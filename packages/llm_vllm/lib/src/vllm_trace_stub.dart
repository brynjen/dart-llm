/// No-op tracing for platforms without `dart:io` (web).
library;

/// Tracing is never enabled without an environment to read it from.
bool readTraceFlag() => false;

/// Never called, since [readTraceFlag] is always false here.
void writeTraceLine(String line) {}
