import 'package:http/http.dart' as http;
import 'package:llm_core/src/timeout_config.dart';

import 'package:llm_core/src/http_client_factory_stub.dart'
    if (dart.library.io) 'package:llm_core/src/http_client_factory_io.dart'
    as impl;

/// Creates the HTTP client the LLM backends use by default.
///
/// A bare `http.Client()` on the VM wraps a `dart:io` `HttpClient` with no
/// connect timeout, an unbounded per-host connection pool, and a 15 second
/// idle timeout. That last value is the problem one: it is *longer* than the
/// keep-alive timeout of the servers these packages talk to (uvicorn, which
/// fronts vLLM, defaults to 5 seconds), so a connection the server has already
/// reaped stays in the client pool as a reuse candidate for another ~10
/// seconds. Requests that pick one up can wedge until a timeout unwinds them.
///
/// This factory closes that window and applies [TimeoutConfig.connectionTimeout],
/// which nothing else in the stack was doing.
///
/// On platforms without `dart:io` (web) it returns a plain [http.Client] —
/// there is no connection pool to configure there.
///
/// Pass your own client to any repository to bypass this entirely.
///
/// [maxConnectionsPerHost] bounds how many sockets may be opened to one host
/// at once; further requests queue client-side. Bounding is standards-blessed
/// (RFC 9112 §9.4: a client "ought to limit the number of simultaneous open
/// connections that it maintains to a given server") and gives back-pressure
/// a bare pool cannot.
///
/// [maxConcurrentWrites] bounds how many requests may be in their
/// **connect + request-write** phase at once (see `WriteGatedHttpClient`).
/// It defaults to [kLLMMaxConcurrentWrites] on macOS and iOS and to
/// unlimited elsewhere: the Dart VM's kqueue event handler can lose socket
/// writable events when several connections are opened and written in the
/// same instant, silently stranding requests that are never transmitted at
/// all. Queueing the write phases eliminates the collision without limiting
/// concurrent streaming responses and without adding any fixed delay. Pass
/// `0` to disable the gate. See `docs/concurrent-send-stall.md`
/// for the investigation that pinned this down with kernel evidence on both
/// ends of the wire.
http.Client createLLMHttpClient({
  TimeoutConfig? timeoutConfig,
  int maxConnectionsPerHost = kLLMMaxConnectionsPerHost,
  int? maxConcurrentWrites,
}) => impl.createLLMHttpClient(
  timeoutConfig: timeoutConfig ?? TimeoutConfig.defaultConfig,
  maxConnectionsPerHost: maxConnectionsPerHost,
  maxConcurrentWrites: maxConcurrentWrites,
);

/// Idle timeout applied to pooled connections.
///
/// Deliberately below the keep-alive timeout of the servers these packages
/// talk to, so the *client* is always the side that retires an idle
/// connection. Whoever closes first wins the race; losing it is the bug.
const Duration kLLMIdleTimeout = Duration(seconds: 3);

/// Upper bound on simultaneous connections to one host.
///
/// Unbounded pools are hard to reason about under sustained concurrency and
/// give no back-pressure signal when a server stops keeping up.
const int kLLMMaxConnectionsPerHost = 64;

/// Default bound on concurrent connect+write phases on kqueue platforms
/// (macOS, iOS).
///
/// 4 is the empirically verified value: 16 concurrent 132KB requests wedged
/// 2–5 of 16 every round ungated, and ran 80/80 clean across five rounds
/// with a gate of 4 — the whole 16-burst's write phase completing in ~100ms.
/// Concurrent *responses* are never bounded by the gate; only socket
/// setup/writes queue.
const int kLLMMaxConcurrentWrites = 4;
