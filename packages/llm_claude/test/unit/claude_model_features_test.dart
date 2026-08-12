import 'package:llm_claude/llm_claude.dart';
import 'package:test/test.dart';

void main() {
  group('claudeRequestShapeFor', () {
    test('current models use the modern shape', () {
      for (final model in [
        'claude-opus-5',
        'claude-opus-4-8',
        'claude-opus-4-7',
        'claude-sonnet-5',
        'claude-fable-5',
        'claude-mythos-5',
      ]) {
        expect(
          claudeRequestShapeFor(model),
          ClaudeRequestShape.modern,
          reason: '$model should use adaptive thinking and reject sampling',
        );
      }
    });

    test('the 4.6 family is transitional', () {
      expect(
        claudeRequestShapeFor('claude-opus-4-6'),
        ClaudeRequestShape.transitional,
      );
      expect(
        claudeRequestShapeFor('claude-sonnet-4-6'),
        ClaudeRequestShape.transitional,
      );
    });

    test('pre-4.6 models are legacy, including dated snapshots', () {
      for (final model in [
        'claude-opus-4-5',
        'claude-sonnet-4-5',
        'claude-haiku-4-5',
        'claude-haiku-4-5-20251001',
        'claude-opus-4-1',
        'claude-3-5-sonnet-20241022',
      ]) {
        expect(
          claudeRequestShapeFor(model),
          ClaudeRequestShape.legacy,
          reason: '$model predates adaptive thinking',
        );
      }
    });

    test('unknown model ids default to modern', () {
      // Every model from Opus 4.7 onward uses the modern shape, so a model
      // released after this library should work without a code change.
      expect(
        claudeRequestShapeFor('claude-something-not-yet-released'),
        ClaudeRequestShape.modern,
      );
    });

    test('handles Bedrock-prefixed ids', () {
      expect(
        claudeRequestShapeFor('anthropic.claude-opus-5'),
        ClaudeRequestShape.modern,
      );
      expect(
        claudeRequestShapeFor('anthropic.claude-haiku-4-5'),
        ClaudeRequestShape.legacy,
      );
    });
  });

  group('capability helpers', () {
    test('sampling parameters are rejected only on modern models', () {
      expect(claudeRejectsSamplingParams('claude-opus-5'), isTrue);
      expect(claudeRejectsSamplingParams('claude-sonnet-4-6'), isFalse);
      expect(claudeRejectsSamplingParams('claude-haiku-4-5'), isFalse);
    });

    test('adaptive thinking is unavailable on legacy models', () {
      expect(claudeSupportsAdaptiveThinking('claude-opus-5'), isTrue);
      expect(claudeSupportsAdaptiveThinking('claude-opus-4-6'), isTrue);
      expect(claudeSupportsAdaptiveThinking('claude-haiku-4-5'), isFalse);
    });

    test('structured outputs are unavailable on legacy models', () {
      expect(claudeSupportsStructuredOutputs('claude-opus-5'), isTrue);
      expect(claudeSupportsStructuredOutputs('claude-haiku-4-5'), isFalse);
    });
  });
}
