import 'dart:convert';

import 'package:http/http.dart' as http;

import 'dto/ollama_model.dart';

/// Repository for managing Ollama models and server operations.
///
/// Provides functionality for listing, pulling, and inspecting models.
///
/// Example:
/// ```dart
/// final repo = OllamaRepository(baseUrl: 'http://localhost:11434');
/// final models = await repo.models();
/// for (final model in models) {
///   print(model.name);
/// }
/// ```
class OllamaRepository {
  OllamaRepository({
    this.baseUrl = "http://localhost:11434",
    http.Client? httpClient,
  }) : httpClient = httpClient ?? http.Client();

  /// The base URL of the Ollama server.
  final String baseUrl;

  /// The HTTP client to use for requests.
  final http.Client httpClient;

  /// List all locally available models.
  ///
  /// GET /api/tags
  Future<List<OllamaModel>> models() async {
    final response = await _sendRequest('GET', Uri.parse('$baseUrl/api/tags'));
    final json = jsonDecode(response.body);

    // The response has a "models" key that contains the array of models
    final List<dynamic> modelsJson = json['models'] ?? [];
    return modelsJson.map((model) => OllamaModel.fromJson(model)).toList();
  }

  /// Show information about a specific model.
  ///
  /// POST /api/show
  Future<OllamaModelInfo> showModel(String modelName) async {
    final response = await _sendRequest(
      'POST',
      Uri.parse('$baseUrl/api/show'),
      body: {'model': modelName},
    );
    final json = jsonDecode(response.body);
    return OllamaModelInfo.fromJson(json);
  }

  /// Pull a model from the Ollama library.
  ///
  /// POST /api/pull
  ///
  /// Returns a stream of progress updates.
  Stream<OllamaPullProgress> pullModel(String modelName) async* {
    final request = http.StreamedRequest(
      'POST',
      Uri.parse('$baseUrl/api/pull'),
    );
    request.headers['content-type'] = 'application/json';
    final bodyBytes = utf8.encode(json.encode({'model': modelName}));
    request.headers['content-length'] = bodyBytes.length.toString();
    request.sink.add(bodyBytes);
    request.sink.close();

    final response = await httpClient.send(request);

    if (response.statusCode != 200) {
      throw Exception('Failed to pull model: ${response.statusCode}');
    }

    await for (final chunk in response.stream.transform(utf8.decoder)) {
      // Split by newlines to handle multiple JSON objects in one chunk
      final lines = chunk.split('\n').where((line) => line.trim().isNotEmpty);
      for (final line in lines) {
        try {
          final jsonData = jsonDecode(line);
          yield OllamaPullProgress.fromJson(jsonData);
        } catch (e) {
          // Skip malformed JSON lines
          continue;
        }
      }
    }
  }

  /// Get the version of Ollama.
  ///
  /// GET /api/version
  Future<OllamaVersion> version() async {
    final response = await _sendRequest(
      'GET',
      Uri.parse('$baseUrl/api/version'),
    );
    final json = jsonDecode(response.body);
    return OllamaVersion.fromJson(json);
  }

  Future<http.Response> _sendRequest(
    String method,
    Uri uri, {
    Map<String, dynamic>? body,
  }) async {
    final headers = {'content-type': 'application/json'};

    final response = method.toUpperCase() == 'POST'
        ? await httpClient.post(
            uri,
            headers: headers,
            body: body != null ? json.encode(body) : null,
          )
        : await httpClient.get(uri, headers: headers);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Request failed with status ${response.statusCode}');
    }

    return response;
  }
}
