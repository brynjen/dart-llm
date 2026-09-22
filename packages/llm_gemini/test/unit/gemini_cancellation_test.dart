/// Cancellation guard for `GeminiChatRepository.streamChat`.
///
/// Cancelling a subscription while the converter is parked awaiting the next
/// event must abort the request rather than leave it running server-side. The
/// mechanism lives in `abortableStream` and `sendStreamingRequest`; this pins
/// that this backend is wired into it.
library;

import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:llm_gemini/llm_gemini.dart';
import 'package:test/test.dart';

/// Sends nothing and never ends, unless the abort trigger fires.
class _SilentClient extends http.BaseClient {
  bool sawAbortable = false;
  bool aborted = false;
  final _body = StreamController<List<int>>();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    sawAbortable = request is http.Abortable;
    if (request case http.Abortable(:final abortTrigger?)) {
      unawaited(
        abortTrigger.whenComplete(() {
          aborted = true;
          if (_body.isClosed) return;
          _body.addError(http.RequestAbortedException(request.url));
          _body.close();
        }),
      );
    }
    return http.StreamedResponse(
      _body.stream,
      200,
      headers: {'content-type': 'text/event-stream'},
    );
  }
}

void main() {
  group('streamChat cancellation', () {
    test('cancel aborts the in-flight request and returns promptly', () async {
      final client = _SilentClient();
      final repo = GeminiChatRepository(apiKey: 'k', httpClient: client);

      final subscription = repo
          .streamChat(
            'gemini-3.5-flash-lite',
            messages: [LLMMessage(role: LLMRole.user, content: 'hi')],
          )
          .listen(null, onError: (Object _) {});
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(client.sawAbortable, isTrue, reason: 'request must be abortable');

      await subscription.cancel().timeout(
        const Duration(seconds: 2),
        onTimeout: () =>
            fail('cancel() hung; the request was never actually aborted'),
      );

      expect(client.aborted, isTrue, reason: 'the trigger must have fired');
    });

    test('an unlistened stream issues no request', () async {
      final client = _SilentClient();
      final repo = GeminiChatRepository(apiKey: 'k', httpClient: client);

      repo.streamChat(
        'gemini-3.5-flash-lite',
        messages: [LLMMessage(role: LLMRole.user, content: 'hi')],
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(client.sawAbortable, isFalse);
    });
  });
}
