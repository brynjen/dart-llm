/// Cancellation tests for `VLLMChatRepository.streamChat`.
///
/// Before `abortableStream`, cancelling a subscription while the converter was
/// parked awaiting the next server-sent event did nothing: the generator was
/// suspended at an `await`, so it was never resumed, the socket stayed open,
/// the server kept generating, and `await cancel()` did not return until the
/// read timeout fired. These pin the fix.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:llm_vllm/llm_vllm.dart';
import 'package:test/test.dart';

/// A client whose response stream never ends on its own, and which honors
/// `abortTrigger` exactly as `IOClient` does: it injects a
/// [http.RequestAbortedException] and closes the stream.
class _SilentClient extends http.BaseClient {
  _SilentClient({this.honorAbort = true});

  final bool honorAbort;
  bool sawAbortable = false;
  bool aborted = false;
  final _body = StreamController<List<int>>();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    sawAbortable = request is http.Abortable;
    if (request case http.Abortable(:final abortTrigger?) when honorAbort) {
      unawaited(
        abortTrigger.whenComplete(() {
          aborted = true;
          if (_body.isClosed) return;
          _body.addError(http.RequestAbortedException(request.url));
          _body.close();
        }),
      );
    }
    // One frame so the turn starts, then silence.
    _body.add(
      utf8.encode(
        'data: ${json.encode({
          'id': 'chatcmpl-1',
          'created': 1700000000,
          'model': 'test-model',
          'choices': [
            {
              'index': 0,
              'delta': {'role': 'assistant', 'content': 'thinking'},
              'finish_reason': null,
            },
          ],
        })}\n\n',
      ),
    );
    return http.StreamedResponse(
      _body.stream,
      200,
      headers: {'content-type': 'text/event-stream'},
    );
  }
}

void main() {
  group('streamChat cancellation', () {
    test('cancel returns promptly while the server is silent', () async {
      final client = _SilentClient();
      final repo = VLLMChatRepository(httpClient: client);
      final received = <String>[];

      final subscription = repo
          .streamChat(
            'test-model',
            messages: [LLMMessage(role: LLMRole.user, content: 'hi')],
          )
          .listen((chunk) {
            final content = chunk.message?.content;
            if (content != null) received.add(content);
          });

      // Let the first frame through so the converter reaches its await.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(received, ['thinking']);

      await subscription.cancel().timeout(
        const Duration(seconds: 2),
        onTimeout: () =>
            fail('cancel() hung; the request was never actually aborted'),
      );

      expect(client.sawAbortable, isTrue, reason: 'request must be abortable');
      expect(client.aborted, isTrue, reason: 'the trigger must have fired');
    });

    test('cancel does not throw', () async {
      final repo = VLLMChatRepository(httpClient: _SilentClient());

      final subscription = repo
          .streamChat(
            'test-model',
            messages: [LLMMessage(role: LLMRole.user, content: 'hi')],
          )
          .listen(null);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // An abort unwinds the converter, and an async generator completes its
      // cancellation future with whatever error unwound it.
      await expectLater(subscription.cancel(), completes);
    });

    test('an unlistened stream issues no request', () async {
      final client = _SilentClient();
      final repo = VLLMChatRepository(httpClient: client);

      repo.streamChat(
        'test-model',
        messages: [LLMMessage(role: LLMRole.user, content: 'hi')],
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(client.sawAbortable, isFalse);
    });

    test('a client that ignores the trigger still tears down', () async {
      // Cancellation degrades rather than hanging forever: a custom client or
      // a mock may not support abortion.
      final client = _SilentClient(honorAbort: false);
      final repo = VLLMChatRepository(httpClient: client);

      final subscription = repo
          .streamChat(
            'test-model',
            messages: [LLMMessage(role: LLMRole.user, content: 'hi')],
          )
          .listen(null);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await expectLater(
        subscription.cancel().timeout(const Duration(seconds: 2)),
        completes,
      );
    });
  });
}
