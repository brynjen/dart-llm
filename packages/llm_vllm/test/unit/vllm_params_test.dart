import 'package:llm_vllm/llm_vllm.dart';
import 'package:test/test.dart';

void main() {
  group('validateVllmParams', () {
    test('accepts documented vLLM parameters', () {
      expect(
        validateVllmParams({
          'min_p': 0.05,
          'repetition_penalty': 1.05,
          'chat_template_kwargs': {'enable_thinking': false},
          'structured_outputs': {
            'choice': ['a'],
          },
          'vllm_xargs': {'custom': 1},
        }),
        isEmpty,
      );
    });

    test('rejects a typo and suggests the intended parameter', () {
      // vLLM silently drops unknown fields, so without this the penalty would
      // simply never be applied and the response would look fine.
      final errors = validateVllmParams({'repitition_penalty': 1.1});
      expect(errors, hasLength(1));
      expect(errors.single.issue, VllmParamIssue.unknown);
      expect(errors.single.suggestion, 'repetition_penalty');
      expect(errors.single.message, contains('Did you mean'));
      expect(errors.single.message, contains('silently drops'));
    });

    test('suggests nothing when no parameter is close', () {
      final errors = validateVllmParams({'completely_made_up_thing': 1});
      expect(errors.single.suggestion, isNull);
      expect(errors.single.message, contains('vllm_xargs'));
    });

    test('rejects reserved parameters the repository builds itself', () {
      for (final key in reservedVllmParams) {
        final errors = validateVllmParams({key: 'x'});
        expect(errors.single.issue, VllmParamIssue.reserved, reason: key);
      }
    });

    test('rejects guided_* names removed in vLLM 0.12', () {
      final errors = validateVllmParams({
        'guided_choice': ['a', 'b'],
      });
      expect(errors.single.issue, VllmParamIssue.legacyGuided);
      expect(errors.single.message, contains('VLLMStructuredOutputs.choice'));
    });

    test('looks inside a nested extra_body map', () {
      final errors = validateVllmParams({
        'extra_body': {'guided_regex': r'\d+'},
      });
      expect(errors.single.issue, VllmParamIssue.legacyGuided);
      expect(errors.single.path, 'backendOptions.extra_body');
    });

    test('accepts camelCase aliases for snake_case wire names', () {
      expect(
        validateVllmParams({'minP': 0.05, 'repetitionPenalty': 1.1}),
        isEmpty,
      );
      expect(normalizeVllmParam('minP'), 'min_p');
      expect(normalizeVllmParam('already_snake'), 'already_snake');
    });

    test('can validate against a specific server schema', () {
      // A server whose vLLM version predates a parameter should reject it even
      // though the bundled snapshot knows it.
      final errors = validateVllmParams(
        {'min_p': 0.05},
        knownParams: const {'temperature', 'top_p'},
      );
      expect(errors.single.issue, VllmParamIssue.unknown);
    });

    test('reports every problem, not just the first', () {
      final errors = validateVllmParams({
        'model': 'x',
        'guided_json': {},
        'nonsense_param_xyz': 1,
      });
      expect(errors, hasLength(3));
      expect(errors.map((e) => e.issue).toSet(), {
        VllmParamIssue.reserved,
        VllmParamIssue.legacyGuided,
        VllmParamIssue.unknown,
      });
    });
  });

  group('knownVllmChatParams', () {
    test('covers the documented surface of the chat endpoint', () {
      // Snapshot of vLLM 0.27.1's ChatCompletionRequest schema.
      expect(knownVllmChatParams.length, greaterThanOrEqualTo(60));
      for (final key in [
        'temperature',
        'top_k',
        'min_p',
        'repetition_penalty',
        'chat_template_kwargs',
        'structured_outputs',
        'thinking_token_budget',
        'include_reasoning',
        'vllm_xargs',
      ]) {
        expect(knownVllmChatParams, contains(key), reason: key);
      }
    });

    test('every alias target is a real parameter', () {
      for (final target in vllmParamAliases.values) {
        expect(knownVllmChatParams, contains(target), reason: target);
      }
    });
  });

  group('VLLMSamplingOptions', () {
    test('emits only the fields that were set, in wire spelling', () {
      const options = VLLMSamplingOptions(
        minP: 0.05,
        repetitionPenalty: 1.05,
        stopTokenIds: [128001],
      );
      expect(options.toJson(), {
        'min_p': 0.05,
        'repetition_penalty': 1.05,
        'stop_token_ids': [128001],
      });
    });

    test('produces backendOptions that pass validation', () {
      const options = VLLMSamplingOptions(
        minP: 0.05,
        seed: 42,
        ignoreEos: false,
        vllmXargs: {'custom_ext': 3},
      );
      expect(validateVllmParams(options.toBackendOptions()), isEmpty);
    });

    test('an empty instance sends nothing', () {
      expect(const VLLMSamplingOptions().toBackendOptions(), isEmpty);
    });

    test('does not expose n, which the converter would silently drop', () {
      // LLMChunk carries one message and the converter reads choices[0] only,
      // so surfacing `n` would let a caller ask for 4 candidates and get 1.
      expect(const VLLMSamplingOptions().toJson().containsKey('n'), isFalse);
    });

    test('composes with VLLMStructuredOutputs', () {
      final merged = {
        ...const VLLMSamplingOptions(minP: 0.05).toBackendOptions(),
        ...const VLLMStructuredOutputs.choice(['yes', 'no']).toBackendOptions(),
      };
      expect(merged.keys, containsAll(['min_p', 'structured_outputs']));
      expect(validateVllmParams(merged), isEmpty);
    });
  });
}
