import 'dart:async';

/// Wraps a generated stream so that cancelling it aborts the work behind it.
///
/// ## Why this exists
///
/// Every backend's `streamChat` is an `async*` generator, and cancelling the
/// subscription to one does **not** reliably stop it. From the Dart VM's
/// `_AsyncStarStreamController.onCancel`:
///
/// ```dart
/// // Only resume the generator if it is suspended at a yield.
/// // Cancellation does not affect an async generator that is
/// // suspended at an await.
/// ```
///
/// During a long generation the converter is parked at an `await`, waiting for
/// the next server-sent event — not at a `yield`. So a cancel arriving then
/// runs no `finally`, closes no socket and stops no work: the request keeps
/// generating server-side and its tokens are delivered to a controller with no
/// listener and dropped. Worse, `await subscription.cancel()` returns a future
/// that only completes when the generator eventually terminates, so the caller
/// hangs until the read timeout fires — and if the generator unwinds with an
/// error, that error completes the *cancellation* future, so `cancel()` throws.
///
/// A [StreamController] has no such rule: its `onCancel` runs immediately.
/// Putting one in front of the generator gives cancellation somewhere to land,
/// and [build] receives a future that completes at that moment — hand it to
/// `http.AbortableRequest` and the socket closes, which unparks the generator
/// and lets every `finally` in the chain run.
///
/// ```dart
/// @override
/// Stream<LLMChunk> streamChat(String model, {...}) => abortableStream(
///   (abortTrigger) => _streamChat(model, ..., abortTrigger: abortTrigger),
/// );
/// ```
///
/// [build] is called once, on first listen, so an unlistened stream still
/// sends nothing. The returned stream is single-subscription, and the trigger
/// never completes with an error, as `http.Abortable` requires.
///
/// `cancel()` completes promptly and never throws. It means "stop, and the
/// request has been told to abort" — not "every frame of the generator has
/// finished unwinding", which cannot be awaited without reintroducing the hang
/// described above.
Stream<T> abortableStream<T>(
  Stream<T> Function(Future<void> abortTrigger) build,
) {
  final abort = Completer<void>();
  // Cancelled in `onCancel` below, which the analyzer cannot see from here.
  // ignore: cancel_subscriptions
  StreamSubscription<T>? inner;
  late final StreamController<T> controller;

  controller = StreamController<T>(
    onListen: () {
      // Building here rather than eagerly preserves the existing contract that
      // a `streamChat` nobody listens to issues no request.
      final Stream<T> source;
      try {
        source = build(abort.future);
      } catch (error, stackTrace) {
        controller
          ..addError(error, stackTrace)
          ..close();
        return;
      }
      inner = source.listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );
    },
    // Forwarded, or back-pressure stops reaching the socket and the converter
    // starts buffering the whole response in memory.
    onPause: () => inner?.pause(),
    onResume: () => inner?.resume(),
    onCancel: () {
      // Firing the trigger is what actually stops the work: it aborts the
      // request, which closes the socket, which unparks the generator.
      if (!abort.isCompleted) abort.complete();

      final subscription = inner;
      inner = null;
      if (subscription == null) return null;

      // Deliberately **not** awaited. Cancelling the inner subscription is the
      // very operation that hangs on a generator parked at an `await` — the
      // defect this wrapper exists to fix — so awaiting it here would hand the
      // caller back the same hang through the front door. The trigger above
      // has already been fired, so the generator unwinds on its own once the
      // abort lands, and this call is only there to release the subscription.
      //
      // The error is swallowed for the same reason it would be rethrown
      // otherwise: cancelling an async generator completes the cancellation
      // future with whatever error unwound it, and a deliberate stop has two
      // routine ones — the converter's read `TimeoutException`, and
      // `ToolLoopIncompleteException` when a cancelled tool loop ends without a
      // final assistant answer. Neither is a failure the caller asked about.
      unawaited(subscription.cancel().catchError((Object _) {}));
      return null;
    },
  );

  return controller.stream;
}
