import 'package:http/http.dart' as http;

/// Web stand-in for the `dart:io` [WriteGatedHttpClient].
///
/// The VM socket defect it works around does not exist in a browser (the
/// browser owns the sockets), and the `dart:io` types it is built on are
/// unavailable, so constructing it on web is an error. Web callers get a
/// plain [http.Client] from `createLLMHttpClient()` instead.
class WriteGatedHttpClient extends http.BaseClient {
  WriteGatedHttpClient(
    // ignore: avoid_unused_constructor_parameters -- mirrors the io signature
    Object? inner, {
    this.maxConcurrentWrites = 4,
    this.writeTimeout = const Duration(seconds: 30),
  }) {
    throw UnsupportedError(
      'WriteGatedHttpClient requires dart:io and is not available on web.',
    );
  }

  /// See the `dart:io` implementation.
  final int maxConcurrentWrites;

  /// See the `dart:io` implementation.
  final Duration writeTimeout;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    throw UnsupportedError(
      'WriteGatedHttpClient requires dart:io and is not available on web.',
    );
  }
}
