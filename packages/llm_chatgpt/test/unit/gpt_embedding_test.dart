import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:llm_chatgpt/llm_chatgpt.dart';
import 'package:test/test.dart';

void main() {
  _embeddingInputShapeTests();

  group('ChatGPTEmbeddingsResponse', () {
    test('fromJson and toJson roundtrip', () {
      final json = {
        'model': 'text-embedding-3-small',
        'object': 'list',
        'usage': {'prompt_tokens': 5, 'total_tokens': 5},
        'data': [
          {
            'object': 'embedding',
            'index': 0,
            'embedding': [0.1, 0.2, 0.3],
          },
          {
            'object': 'embedding',
            'index': 1,
            'embedding': [0.4, 0.5, 0.6],
          },
        ],
      };

      final response = ChatGPTEmbeddingsResponse.fromJson(json);
      final reconstructed = response.toJson();

      expect(response.model, 'text-embedding-3-small');
      expect(response.object, 'list');
      expect(response.data.length, 2);
      expect(response.usage.promptTokens, 5);
      expect(response.usage.totalTokens, 5);

      expect(reconstructed['model'], 'text-embedding-3-small');
      expect(reconstructed['object'], 'list');
    });

    test('fromJson with single embedding', () {
      final json = {
        'model': 'text-embedding-3-small',
        'object': 'list',
        'usage': {'prompt_tokens': 5, 'total_tokens': 5},
        'data': [
          {
            'object': 'embedding',
            'index': 0,
            'embedding': [0.1, 0.2, 0.3],
          },
        ],
      };

      final response = ChatGPTEmbeddingsResponse.fromJson(json);

      expect(response.data.length, 1);
      expect(response.data[0].embedding, [0.1, 0.2, 0.3]);
    });
  });

  group('ChatGPTEmbedding', () {
    test('fromJson and toJson', () {
      final json = {
        'object': 'embedding',
        'index': 0,
        'embedding': [0.1, 0.2, 0.3, 0.4, 0.5],
      };

      final embedding = ChatGPTEmbedding.fromJson(json);
      final reconstructed = embedding.toJson();

      expect(embedding.object, 'embedding');
      expect(embedding.index, 0);
      expect(embedding.embedding, [0.1, 0.2, 0.3, 0.4, 0.5]);
      expect(reconstructed['object'], 'embedding');
      expect(reconstructed['index'], 0);
    });

    test('fromJson with large embedding vector', () {
      final largeVector = List.generate(1536, (i) => i * 0.001);
      final json = {
        'object': 'embedding',
        'index': 0,
        'embedding': largeVector,
      };

      final embedding = ChatGPTEmbedding.fromJson(json);

      expect(embedding.embedding.length, 1536);
    });
  });

  group('ChatGPTEmbeddingsUsage', () {
    test('fromJson and toJson', () {
      final json = {'prompt_tokens': 10, 'total_tokens': 10};

      final usage = ChatGPTEmbeddingsUsage.fromJson(json);
      final reconstructed = usage.toJson();

      expect(usage.promptTokens, 10);
      expect(usage.totalTokens, 10);
      expect(reconstructed['prompt_tokens'], 10);
      expect(reconstructed['total_tokens'], 10);
    });
  });

  group('ChatGPTLLMEmbedding extension', () {
    test('toLLMEmbedding converts correctly', () {
      final response = ChatGPTEmbeddingsResponse(
        model: 'text-embedding-3-small',
        usage: ChatGPTEmbeddingsUsage(promptTokens: 5, totalTokens: 5),
        data: [
          ChatGPTEmbedding(index: 0, embedding: [0.1, 0.2, 0.3]),
          ChatGPTEmbedding(index: 1, embedding: [0.4, 0.5, 0.6]),
        ],
      );

      final llmEmbeddings = response.toLLMEmbedding;

      expect(llmEmbeddings.length, 2);
      expect(llmEmbeddings[0].model, 'text-embedding-3-small');
      expect(llmEmbeddings[0].embedding, [0.1, 0.2, 0.3]);
      expect(llmEmbeddings[0].promptEvalCount, 5);
      expect(llmEmbeddings[1].embedding, [0.4, 0.5, 0.6]);
    });
  });
}

/// Captures the JSON body of a non-streaming request and replies with a
/// canned embeddings response.
class _BodyCapturingClient extends http.BaseClient {
  final List<Map<String, dynamic>> bodies = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    bodies.add(
      json.decode((request as http.Request).body) as Map<String, dynamic>,
    );
    final payload = json.encode({
      'model': 'text-embedding-3-small',
      'object': 'list',
      'usage': {'prompt_tokens': 1, 'total_tokens': 1},
      'data': [
        {
          'object': 'embedding',
          'index': 0,
          'embedding': [0.1, 0.2],
        },
      ],
    });
    return http.StreamedResponse(
      Stream.value(utf8.encode(payload)),
      200,
      request: request,
    );
  }
}

void _embeddingInputShapeTests() {
  Future<Map<String, dynamic>> capture(List<String> messages) async {
    final client = _BodyCapturingClient();
    final repo = ChatGPTChatRepository(apiKey: 'k', httpClient: client);
    await repo.embed(model: 'text-embedding-3-small', messages: messages);
    return client.bodies.single;
  }

  group('embeddings request shape', () {
    test('a single input is sent as a bare string', () async {
      // OpenAI embeds a bare `""` but rejects an array containing one
      // ("Invalid 'input[0]': input cannot be an empty string"), so the bare
      // form is the only representation of an empty input. Sending every
      // single-element request that way is also the shape OpenAI's own
      // examples use.
      expect((await capture(['hello']))['input'], 'hello');
      expect((await capture([]))['input'], isEmpty);
    });

    test('an empty single input stays representable', () async {
      expect((await capture(['']))['input'], '');
    });

    test('multiple inputs are still sent as an array', () async {
      expect((await capture(['a', 'b']))['input'], ['a', 'b']);
    });
  });
}
