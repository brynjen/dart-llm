import 'package:http/http.dart' as http;
import 'package:llm_core/src/timeout_config.dart';

/// Fallback for platforms without `dart:io` (web).
///
/// There is no client-side connection pool to configure there — the browser
/// owns it — so this is a plain [http.Client]. [maxConcurrentWrites] is
/// ignored: the VM socket defect it guards against does not exist in a
/// browser.
http.Client createLLMHttpClient({
  required TimeoutConfig timeoutConfig,
  required int maxConnectionsPerHost,
  int? maxConcurrentWrites,
}) => http.Client();
