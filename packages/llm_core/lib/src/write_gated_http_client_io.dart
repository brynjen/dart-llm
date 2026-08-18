// The send() implementation is adapted from package:http's IOClient
// (https://pub.dev/packages/http, BSD-3-Clause, Copyright 2012 the Dart
// project authors), extended with the write gate and write watchdog.

import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart' show IOStreamedResponse;

/// An `dart:io` HTTP client that bounds how many requests may be in their
/// **connect + request-write** phase at once.
///
/// Exists because of a Dart VM defect on kqueue platforms (macOS, iOS): when
/// several sockets are created and given more body bytes than the first
/// `write()` syscall accepts within the same event-loop window, the VM's
/// event handler can lose the kqueue writable event for some of them. The
/// affected request is never transmitted — the connection is ESTABLISHED on
/// both ends, the client's `Send-Q` is 0, and the server never receives a
/// byte — and no error is ever raised. Verified against a raw `dart:io`
/// [Socket] with kernel counters on both ends; the same traffic from a Linux
/// client is unaffected. See `llm_vllm`'s `BUG-concurrent-send-stall.md` for
/// the investigation, and dart-lang/sdk#30434 for a known, still-open race in
/// the same write-event path.
///
/// The gate is a plain counting semaphore — the same mechanism httpx,
/// aiohttp, and browsers use to bound in-flight connections (RFC 9112 §9.4).
/// A slot is held from just before the connection is acquired until
/// `flush()` reports the request body has been accepted by the kernel, then
/// released — so concurrent *streaming responses* are never limited, only
/// concurrent socket setup/writes. Requests beyond the bound queue and start
/// the moment a slot frees; no timers, no added latency once a write
/// completes. Empirically, a gate of 4 turns 16 concurrent 132KB requests
/// from 2–5 silent wedges per round into 80/80 clean with the whole write
/// phase done in ~100ms.
///
/// As a backstop, each request carries a write watchdog: if connect + body
/// write has not completed within [writeTimeout] (scaled up for large
/// bodies), the request is aborted with a [TimeoutException] instead of
/// wedging silently — turning any residual event loss into a fast,
/// retryable error.
class WriteGatedHttpClient extends http.BaseClient {
  /// Wraps [inner] (a configured `dart:io` [HttpClient]).
  ///
  /// [maxConcurrentWrites] bounds simultaneous connect+write phases.
  /// [writeTimeout] is the base watchdog for one connect+write; it is
  /// extended by one second per 100KB of request body.
  WriteGatedHttpClient(
    HttpClient? inner, {
    this.maxConcurrentWrites = 4,
    this.writeTimeout = const Duration(seconds: 30),
  }) : _inner = inner ?? HttpClient(),
       _gate = _Semaphore(maxConcurrentWrites);

  HttpClient? _inner;

  /// How many requests may be between connection acquisition and completed
  /// body write at the same time.
  final int maxConcurrentWrites;

  /// Base time limit for one connect + request-body write.
  final Duration writeTimeout;

  final _Semaphore _gate;

  Duration _writeDeadlineFor(http.BaseRequest request) {
    final length = request.contentLength;
    if (length == null) return writeTimeout;
    return writeTimeout + Duration(seconds: length ~/ (100 * 1024));
  }

  @override
  Future<IOStreamedResponse> send(http.BaseRequest request) async {
    final client = _inner;
    if (client == null) {
      throw http.ClientException(
        'HTTP request failed. Client is already closed.',
        request.url,
      );
    }

    final stream = request.finalize();

    await _gate.acquire();
    var gateReleased = false;
    void releaseGate() {
      if (!gateReleased) {
        gateReleased = true;
        _gate.release();
      }
    }

    HttpClientRequest? ioRequest;
    var isAborted = false;
    var hasResponse = false;

    // The watchdog cannot rely on HttpClientRequest.abort() alone: abort()
    // fails the *response* future but leaves a pending addStream()/flush()
    // hanging (which is also why the VM defect this class works around is
    // otherwise unrecoverable). So the write phase is raced against a timer
    // and abandoned — abort() is still called as a best-effort teardown of
    // the underlying connection.
    final deadline = _writeDeadlineFor(request);
    final timedOut = Completer<Never>();
    final watchdog = Timer(deadline, () {
      timedOut.completeError(
        TimeoutException(
          'Request write did not complete within the write timeout',
          deadline,
        ),
      );
    });

    // Where IOClient does `stream.pipe(ioRequest)`, the write is split into
    // addStream + flush so there is an observable moment at which the whole
    // body has been handed to the kernel — that is the end of the window
    // the kqueue defect can strand, and where the gate slot frees.
    Future<HttpClientRequest> openAndWrite() async {
      final io = (await client.openUrl(request.method, request.url))
        ..followRedirects = request.followRedirects
        ..maxRedirects = request.maxRedirects
        ..contentLength = (request.contentLength ?? -1)
        ..persistentConnection = request.persistentConnection;
      ioRequest = io;
      request.headers.forEach((name, value) {
        io.headers.set(name, value);
      });

      // SDK request aborting is only effective up until the request is
      // closed, at which point the full response always becomes available:
      //  * a user abort before the response makes the write (and therefore
      //    send) throw the aborted error;
      //  * a user abort after the response arrives but before it is
      //    listened to emits the aborted error on listen;
      //  * a user abort mid-stream injects the error and closes the
      //    response.
      if (request case http.Abortable(:final abortTrigger?)) {
        unawaited(
          abortTrigger.whenComplete(() {
            isAborted = true;
            if (!hasResponse) {
              io.abort(http.RequestAbortedException(request.url));
            }
          }),
        );
      }

      await io.addStream(stream);
      await io.flush();
      return io;
    }

    try {
      final HttpClientRequest written;
      try {
        // Future.any keeps listening to the loser, so a late error from an
        // abandoned write is observed and discarded rather than unhandled.
        written = await Future.any([openAndWrite(), timedOut.future]);
      } on TimeoutException {
        ioRequest?.abort(
          TimeoutException(
            'Request write did not complete within the write timeout',
            deadline,
          ),
        );
        rethrow;
      }
      watchdog.cancel();
      releaseGate();

      final response = await written.close();
      hasResponse = true;

      StreamSubscription<List<int>>? ioResponseSubscription;

      late final StreamController<List<int>> responseController;
      responseController = StreamController(
        onListen: () {
          if (isAborted) {
            responseController
              ..addError(http.RequestAbortedException(request.url))
              ..close();
            return;
          } else if (request case http.Abortable(:final abortTrigger?)) {
            abortTrigger.whenComplete(() {
              if (!responseController.isClosed) {
                responseController
                  ..addError(http.RequestAbortedException(request.url))
                  ..close();
              }
              ioResponseSubscription?.cancel();
            });
          }

          ioResponseSubscription = response.listen(
            responseController.add,
            onDone: () {
              // `responseController.close` triggers the `onCancel` callback;
              // null the subscription so it is not cancelled twice.
              ioResponseSubscription = null;
              unawaited(responseController.close());
            },
            onError: (Object err, StackTrace stackTrace) {
              if (err is HttpException) {
                responseController.addError(
                  http.ClientException(err.message, err.uri),
                  stackTrace,
                );
              } else {
                responseController.addError(err, stackTrace);
              }
            },
          );
        },
        onPause: () => ioResponseSubscription?.pause(),
        onResume: () => ioResponseSubscription?.resume(),
        onCancel: () => ioResponseSubscription?.cancel(),
        sync: true,
      );

      final headers = <String, String>{};
      response.headers.forEach((key, values) {
        headers[key] = values.map((value) => value.trimRight()).join(',');
      });

      return IOStreamedResponse(
        responseController.stream,
        response.statusCode,
        contentLength: response.contentLength == -1
            ? null
            : response.contentLength,
        request: request,
        headers: headers,
        isRedirect: response.isRedirect,
        persistentConnection: response.persistentConnection,
        reasonPhrase: response.reasonPhrase,
        inner: response,
      );
    } on SocketException catch (error) {
      throw _ClientSocketException(error, request.url);
    } on HttpException catch (error) {
      throw http.ClientException(error.message, error.uri);
    } finally {
      watchdog.cancel();
      releaseGate();
    }
  }

  @override
  void close() {
    _inner?.close(force: true);
    _inner = null;
  }
}

/// Thrown as a [http.ClientException] that still implements
/// [SocketException], matching IOClient's behavior so existing catch clauses
/// keep working.
class _ClientSocketException extends http.ClientException
    implements SocketException {
  _ClientSocketException(SocketException e, Uri uri)
    : cause = e,
      super(e.message, uri);

  final SocketException cause;

  @override
  InternetAddress? get address => cause.address;

  @override
  OSError? get osError => cause.osError;

  @override
  int? get port => cause.port;

  @override
  String toString() => 'ClientException with $cause, uri=$uri';
}

class _Semaphore {
  _Semaphore(this._slots);

  int _slots;
  final Queue<Completer<void>> _waiters = Queue();

  Future<void> acquire() {
    if (_slots > 0) {
      _slots--;
      return Future.value();
    }
    final waiter = Completer<void>();
    _waiters.add(waiter);
    return waiter.future;
  }

  void release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeFirst().complete();
    } else {
      _slots++;
    }
  }
}
