import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:llm_core/llm_core.dart';
import 'package:llm_vllm/src/dto/vllm_model.dart';
import 'package:llm_vllm/src/vllm_base_url.dart';

/// Repository for vLLM model/server operations.
class VLLMRepository {
  VLLMRepository({
    this.baseUrl = 'http://localhost:8000',
    this.apiKey,
    http.Client? httpClient,
  }) : httpClient = httpClient ?? http.Client(),
       _ownsHttpClient = httpClient == null;

  /// The base URL of the vLLM server.
  final String baseUrl;

  /// Optional API key for vLLM servers started with `--api-key`.
  final String? apiKey;

  /// The HTTP client to use for requests.
  final http.Client httpClient;

  final bool _ownsHttpClient;

  /// Releases the HTTP client, but only if this repository created it.
  ///
  /// A client passed in by the caller stays open — its owner disposes it.
  void close() {
    if (_ownsHttpClient) httpClient.close();
  }

  /// List models served by vLLM.
  ///
  /// GET /v1/models
  Future<List<VLLMModel>> models() async {
    final response = await _sendRequest('GET', vllmEndpoint(baseUrl, 'models'));
    // A proxy or misconfigured endpoint can answer 200 with a non-JSON or
    // differently-shaped body; surface that as an API error rather than a
    // raw TypeError from the cast.
    try {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return VLLMModelsResponse.fromJson(json).data;
    } on FormatException catch (e) {
      throw LLMApiException(
        'Malformed vLLM models response: ${e.message}',
        statusCode: response.statusCode,
        responseBody: response.body,
      );
    } on TypeError {
      throw LLMApiException(
        'Malformed vLLM models response',
        statusCode: response.statusCode,
        responseBody: response.body,
      );
    }
  }

  /// Whether the server was started with tool-calling enabled.
  ///
  /// Tool calling needs `--enable-auto-tool-choice` **and** a
  /// `--tool-call-parser`. Without them any request carrying `tools` fails with
  /// a `400`, so checking first turns a confusing runtime failure into a
  /// configuration check.
  ///
  /// Probes with a one-token request; returns `false` if the server rejects it
  /// and `false` on any transport failure, so a probe never breaks a caller.
  ///
  /// Note this reports whether the *server* accepts tool requests. It cannot
  /// tell you whether the configured parser matches the model's output format
  /// — a mismatched parser accepts the request and then yields no tool calls.
  Future<bool> supportsToolCalling(String model) async {
    try {
      final response = await httpClient.post(
        vllmEndpoint(baseUrl, 'chat/completions'),
        headers: _jsonHeaders,
        body: json.encode({
          'model': model,
          'messages': [
            {'role': 'user', 'content': 'hi'},
          ],
          'max_tokens': 1,
          'tools': [
            {
              'type': 'function',
              'function': {
                'name': 'probe',
                'parameters': {'type': 'object', 'properties': {}},
              },
            },
          ],
        }),
      );
      if (response.statusCode == 200) return true;
      // vLLM names the missing flags in the error body.
      return !response.body.contains('tool-call-parser');
    } catch (_) {
      return false;
    }
  }

  /// Whether the server was started with `--reasoning-parser`.
  ///
  /// Without it the model still thinks, but the reasoning arrives inline as
  /// `<think>` tags rather than in a separate `reasoning` field, and
  /// `thinking_token_budget` is rejected with a `400`.
  ///
  /// `VLLMChatRepository` handles both cases transparently — it splits inline
  /// `<think>` tags when no parser is present — so this is informational, or a
  /// guard before setting a thinking budget.
  Future<bool> supportsReasoningParser(String model) async {
    try {
      final response = await httpClient.post(
        vllmEndpoint(baseUrl, 'chat/completions'),
        headers: _jsonHeaders,
        body: json.encode({
          'model': model,
          'messages': [
            {'role': 'user', 'content': 'hi'},
          ],
          'max_tokens': 1,
          // Rejected with a message naming --reasoning-parser when absent.
          'thinking_token_budget': 1,
        }),
      );
      if (response.statusCode == 200) return true;
      return !response.body.contains('reasoning');
    } catch (_) {
      return false;
    }
  }

  /// Probes what this deployment actually offers for [model].
  ///
  /// `VLLMChatRepository.capabilitiesForModel` reports what the *backend*
  /// implements, which on vLLM is not the same thing: tool calling depends on
  /// server flags, and vision and embeddings depend on which model was loaded.
  /// Pass the result to `VLLMChatRepository(capabilities: ...)` so capability
  /// checks reflect the connected server.
  ///
  /// Each probe degrades to `false` on failure, so an unreachable server
  /// reports a conservative result instead of throwing.
  ///
  /// ```dart
  /// final probe = VLLMRepository(baseUrl: baseUrl);
  /// final repo = VLLMChatRepository(
  ///   baseUrl: baseUrl,
  ///   capabilities: await probe.resolveCapabilities('Qwen/Qwen3-0.6B'),
  /// );
  /// ```
  Future<LLMCapabilities> resolveCapabilities(String model) async {
    final results = await Future.wait([
      supportsToolCalling(model),
      supportsReasoningParser(model),
      supportsEmbeddings(model),
    ]);
    return LLMCapabilities(
      // Every vLLM chat deployment streams and honors response_format.
      streaming: true,
      structuredOutput: true,
      tools: results[0],
      thinking: results[1],
      embeddings: results[2],
      // Vision depends on the loaded model's modality, which the server does
      // not report. Left false rather than guessed; set it explicitly if you
      // are serving a multimodal model.
      vision: false,
    );
  }

  /// Whether this deployment serves embeddings for [model].
  ///
  /// vLLM runs one model per process, so a chat model's `/v1/embeddings`
  /// endpoint exists but rejects requests.
  Future<bool> supportsEmbeddings(String model) async {
    try {
      final response = await httpClient.post(
        vllmEndpoint(baseUrl, 'embeddings'),
        headers: _jsonHeaders,
        body: json.encode({'model': model, 'input': 'probe'}),
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// The request parameters this server actually accepts.
  ///
  /// Reads the `ChatCompletionRequest` schema from the server's
  /// `/openapi.json`. Pass the result to
  /// `LLMChatOptions.backendOptions` validation to catch parameters that were
  /// added or removed in the server's vLLM version rather than relying on the
  /// [knownVllmChatParams] snapshot — this is what would have caught the
  /// `guided_*` parameters disappearing in vLLM 0.12.
  ///
  /// Returns `null` if the schema cannot be read, so callers can fall back to
  /// the built-in snapshot.
  Future<Set<String>?> fetchSupportedParams() async {
    try {
      final root = normalizeVllmBaseUrl(baseUrl);
      final response = await httpClient.get(
        Uri.parse('$root/openapi.json'),
        headers: {'accept': 'application/json'},
      );
      if (response.statusCode != 200) return null;
      final schemas =
          (jsonDecode(response.body) as Map<String, dynamic>)['components']
              as Map<String, dynamic>?;
      final props =
          ((schemas?['schemas']
                      as Map<String, dynamic>?)?['ChatCompletionRequest']
                  as Map<String, dynamic>?)?['properties']
              as Map<String, dynamic>?;
      if (props == null || props.isEmpty) return null;
      return props.keys.toSet();
    } catch (_) {
      return null;
    }
  }

  Map<String, String> get _jsonHeaders => {
    'content-type': 'application/json',
    'accept': 'application/json',
    if (apiKey != null && apiKey!.isNotEmpty) 'authorization': 'Bearer $apiKey',
  };

  Future<http.Response> _sendRequest(
    String method,
    Uri uri, {
    Map<String, dynamic>? body,
  }) async {
    final headers = {
      'content-type': 'application/json',
      'accept': 'application/json',
      if (apiKey != null && apiKey!.isNotEmpty)
        'authorization': 'Bearer $apiKey',
    };

    final response = method.toUpperCase() == 'POST'
        ? await httpClient.post(
            uri,
            headers: headers,
            body: body != null ? json.encode(body) : null,
          )
        : await httpClient.get(uri, headers: headers);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw LLMApiException(
        'vLLM API error',
        statusCode: response.statusCode,
        responseBody: response.body,
      );
    }

    return response;
  }
}
