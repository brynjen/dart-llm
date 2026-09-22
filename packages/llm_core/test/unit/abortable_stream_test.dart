import 'dart:async';

import 'package:llm_core/llm_core.dart';
import 'package:test/test.dart';

void main() {
  group('abortableStream', () {
    test('does not build until someone listens', () {
      var built = 0;

      final stream = abortableStream<int>((_) {
        built++;
        return Stream.value(1);
      });

      expect(built, 0, reason: 'an unlistened stream must send nothing');

      stream.listen(null).cancel();
      expect(built, 1);
    });

    test('forwards events, errors and done', () async {
      final events = abortableStream<int>(
        (_) => Stream.fromIterable([1, 2, 3]),
      );

      expect(await events.toList(), [1, 2, 3]);
    });

    test('a synchronous failure in build surfaces as a stream error', () {
      final stream = abortableStream<int>((_) => throw StateError('nope'));

      expect(stream.toList(), throwsA(isA<StateError>()));
    });

    test('cancelling completes the abort trigger', () async {
      var aborted = false;

      final subscription = abortableStream<int>((abortTrigger) {
        unawaited(abortTrigger.then((_) => aborted = true));
        return const Stream<int>.empty();
      }).listen(null);

      await subscription.cancel();

      expect(aborted, isTrue);
    });

    // The regression test for the whole feature. Without the controller in
    // front, a generator parked at an `await` never resumes on cancel, so this
    // would hang until the source happened to produce something.
    test('cancel completes while the generator is parked at an await', () async {
      final blocked = Completer<void>();
      var abortFired = false;

      Stream<int> generator(Future<void> abortTrigger) async* {
        unawaited(abortTrigger.then((_) => abortFired = true));
        yield 1;
        // Stands in for awaiting the next server-sent event on a long, quiet
        // generation. Nothing completes this unless the request is aborted.
        await blocked.future;
        yield 2;
      }

      final received = <int>[];
      final subscription = abortableStream<int>(generator).listen(received.add);

      // Let the first event through so the generator reaches the await.
      await Future<void>.delayed(Duration.zero);
      expect(received, [1]);

      await subscription.cancel().timeout(
        const Duration(seconds: 2),
        onTimeout: () => fail('cancel() hung on a parked generator'),
      );

      expect(abortFired, isTrue, reason: 'the request should be aborted');

      // Unblocking afterwards must not deliver anything to a cancelled stream.
      blocked.complete();
      await Future<void>.delayed(Duration.zero);
      expect(received, [1]);
    });

    test('an error raised during teardown does not escape cancel()', () async {
      Stream<int> generator(Future<void> abortTrigger) async* {
        try {
          yield 1;
          await Completer<void>().future;
        } finally {
          // Mirrors the converter's read timeout and the tool loop's
          // ToolLoopIncompleteException, both of which can unwind a cancelled
          // generator and would otherwise complete the cancellation future
          // with an error.
          throw StateError('teardown blew up');
        }
      }

      final subscription = abortableStream<int>(generator).listen(null);
      await Future<void>.delayed(Duration.zero);

      await expectLater(subscription.cancel(), completes);
    });

    test('pause and resume reach the source', () async {
      var paused = false;

      final controller = StreamController<int>(
        onPause: () => paused = true,
        onResume: () => paused = false,
      );
      addTearDown(controller.close);

      final subscription = abortableStream<int>(
        (_) => controller.stream,
      ).listen(null);

      subscription.pause();
      await Future<void>.delayed(Duration.zero);
      expect(paused, isTrue, reason: 'back-pressure must reach the socket');

      subscription.resume();
      await Future<void>.delayed(Duration.zero);
      expect(paused, isFalse);

      await subscription.cancel();
    });
  });
}
