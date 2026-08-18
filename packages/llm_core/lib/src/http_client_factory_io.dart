import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:llm_core/src/http_client_factory.dart'
    show kLLMIdleTimeout, kLLMMaxConcurrentWrites;
import 'package:llm_core/src/timeout_config.dart';
import 'package:llm_core/src/write_gated_http_client_io.dart';

/// `dart:io` implementation — see `http_client_factory.dart` for the rationale.
///
/// On kqueue platforms (macOS, iOS) the pool is wrapped in
/// [WriteGatedHttpClient], which bounds concurrent connect+write phases to
/// [kLLMMaxConcurrentWrites] — the queue-based workaround for the VM's
/// lost-writable-event defect. Linux is verified unaffected and gets a plain
/// [IOClient].
http.Client createLLMHttpClient({
  required TimeoutConfig timeoutConfig,
  required int maxConnectionsPerHost,
  int? maxConcurrentWrites,
}) {
  final inner = HttpClient()
    ..connectionTimeout = timeoutConfig.connectionTimeout
    ..idleTimeout = kLLMIdleTimeout
    ..maxConnectionsPerHost = maxConnectionsPerHost;
  final gate =
      maxConcurrentWrites ??
      ((Platform.isMacOS || Platform.isIOS) ? kLLMMaxConcurrentWrites : 0);
  if (gate <= 0) {
    return IOClient(inner);
  }
  return WriteGatedHttpClient(inner, maxConcurrentWrites: gate);
}
