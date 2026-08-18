/// Opt-in lifecycle tracing for diagnosing stalled requests.
///
/// Enabled by setting `LLM_VLLM_TRACE=1` (or `true`) in the environment. Off,
/// every call is a single boolean check and no allocation.
///
/// Exists because a stalled request is otherwise indistinguishable from a slow
/// one: the process sits idle with an open socket and no error is ever raised.
/// Tracing the boundaries — request built, headers received, first byte, each
/// chunk, stream done — tells you *which* await never returned.
library;

import 'package:llm_vllm/src/vllm_trace_stub.dart'
    if (dart.library.io) 'package:llm_vllm/src/vllm_trace_io.dart';

/// Whether tracing is enabled. Read once at startup.
final bool vllmTraceEnabled = readTraceFlag();

int _seq = 0;

/// Allocates a monotonic id so concurrent requests can be told apart.
int vllmNextRequestId() => ++_seq;

final Stopwatch _since = Stopwatch()..start();

/// Emits one trace line. [id] correlates lines belonging to one request.
void vllmTrace(int id, String event, [String? detail]) {
  if (!vllmTraceEnabled) return;
  final ms = _since.elapsedMilliseconds;
  writeTraceLine(
    '[vllm-trace ${ms.toString().padLeft(8)}ms req=$id] $event'
    '${detail == null ? '' : ' — $detail'}',
  );
}
