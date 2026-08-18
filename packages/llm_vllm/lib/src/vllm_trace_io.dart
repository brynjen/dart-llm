/// `dart:io` tracing sink — see `vllm_trace.dart`.
library;

import 'dart:io' show Platform, stderr;

/// Reads `LLM_VLLM_TRACE` from the environment.
bool readTraceFlag() {
  final v = Platform.environment['LLM_VLLM_TRACE']?.toLowerCase();
  return v == '1' || v == 'true';
}

/// Writes to stderr, so trace output stays out of the program's stdout.
void writeTraceLine(String line) => stderr.writeln(line);
