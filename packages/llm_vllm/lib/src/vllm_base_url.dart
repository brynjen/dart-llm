/// Normalization for user-supplied vLLM base URLs.
///
/// vLLM serves its OpenAI-compatible API under `/v1`. Users reasonably supply
/// the base URL in any of these forms:
///
/// ```
/// http://localhost:8000
/// http://localhost:8000/
/// http://localhost:8000/v1
/// http://localhost:8000/v1/
/// ```
///
/// All four must resolve to the same endpoint. Naive concatenation of
/// `'$baseUrl/v1/chat/completions'` turns the last two into
/// `/v1/v1/chat/completions`, which a vLLM server answers with a 404.
library;

/// Strips a trailing slash and a trailing `/v1` segment from [baseUrl] so that
/// endpoint paths can be appended without duplicating the API version.
///
/// Returns the origin-and-prefix portion only; callers append the full
/// `/v1/...` path themselves via [vllmEndpoint].
String normalizeVllmBaseUrl(String baseUrl) {
  var normalized = baseUrl.trim();
  while (normalized.endsWith('/')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  if (normalized.endsWith('/v1')) {
    normalized = normalized.substring(0, normalized.length - 3);
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
  }
  return normalized;
}

/// Builds the absolute URI for a vLLM API [path] against [baseUrl].
///
/// [path] is given without the `/v1` prefix, e.g. `'chat/completions'`.
Uri vllmEndpoint(String baseUrl, String path) {
  final root = normalizeVllmBaseUrl(baseUrl);
  final suffix = path.startsWith('/') ? path.substring(1) : path;
  return Uri.parse('$root/v1/$suffix');
}

/// Builds the request headers for a vLLM API call.
///
/// [extraHeaders] is spread first so the protocol headers and `authorization`
/// always win: a caller may add headers but can neither break the wire format
/// nor override the configured credentials.
Map<String, String> vllmHeaders({
  required String accept,
  String? apiKey,
  Map<String, String>? extraHeaders,
}) => {
  ...?extraHeaders,
  'content-type': 'application/json',
  'accept': accept,
  if (apiKey != null && apiKey.isNotEmpty) 'authorization': 'Bearer $apiKey',
};
