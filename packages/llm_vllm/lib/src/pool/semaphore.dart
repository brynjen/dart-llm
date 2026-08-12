import 'dart:async';

/// A counting semaphore for limiting concurrent access to a resource.
///
/// Callers that [acquire] when all permits are taken will wait until
/// a permit becomes available via [release].
class Semaphore {
  Semaphore(this.maxCount)
    : assert(maxCount > 0, 'maxCount must be positive'),
      _available = maxCount;

  /// The maximum number of concurrent permits.
  final int maxCount;

  int _available;

  final _waiters = <Completer<void>>[];

  /// Number of immediately available permits.
  int get available => _available;

  /// Number of callers waiting to acquire a permit.
  int get waiting => _waiters.length;

  /// Acquires a permit, waiting indefinitely if none are available.
  Future<void> acquire() async {
    if (_available > 0) {
      _available--;
      return;
    }
    final completer = Completer<void>();
    _waiters.add(completer);
    await completer.future;
    // Slot was passed directly by release() — no decrement needed here.
  }

  /// Acquires a permit, throwing [VLLMQueueTimeoutException] if [timeout]
  /// elapses before one becomes available.
  Future<void> acquireWithTimeout(Duration timeout) async {
    if (_available > 0) {
      _available--;
      return;
    }
    final completer = Completer<void>();
    _waiters.add(completer);
    try {
      await completer.future.timeout(timeout);
    } on TimeoutException {
      _waiters.remove(completer);
      throw VLLMQueueTimeoutException(
        'Timed out waiting for a free slot after $timeout',
      );
    }
    // Slot passed directly by release().
  }

  /// Releases a permit, unblocking the next waiter if any.
  void release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeAt(0).complete();
      // Pass the slot directly to the next waiter — don't change _available.
    } else {
      _available++;
    }
  }
}

/// Thrown when a [Semaphore.acquireWithTimeout] call times out.
class VLLMQueueTimeoutException implements Exception {
  const VLLMQueueTimeoutException(this.message);
  final String message;
  @override
  String toString() => 'VLLMQueueTimeoutException: $message';
}
