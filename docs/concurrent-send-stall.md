# Bug: concurrent streaming requests stall through a shared HTTP client

**Status:** RESOLVED. Four client-side defects fixed, and the headline
`send()` stall root-caused to the **Dart VM's macOS socket event handler**
losing kqueue writable events under a burst of simultaneous large writes —
the request bytes never leave the client process. An earlier revision of this
document blamed vLLM's HTTP front end; kernel counters on both ends of the
wire later disproved that (see below). Fixed in `llm_core` by bounding
concurrent connect+write phases (`WriteGatedHttpClient`, a counting semaphore
released when the request body reaches the kernel — default 4 slots on
macOS/iOS, no timers involved).
**Found:** 2026-08-17, `llm_vllm` 0.3.0 + `llm_core` 0.3.0
**Fixed in:** `llm_core` (`lib/src/http_client_utils.dart`,
`lib/src/http_client_factory.dart`, `lib/src/write_gated_http_client_io.dart`),
`llm_vllm` and `llm_ollama` stream converters

> The defective code was in **`llm_core`**. `llm_vllm` is where it was found
> and where the reproduction harnesses live
> (`packages/llm_vllm/example/concurrency_stall_repro.dart`,
> `dart_io_stall_probe.dart`, `raw_socket_burst_probe.dart`). Every backend
> calling `sendStreamingRequest` was affected.

---

## Symptom

A process making sustained concurrent requests through one long-lived
repository periodically stops making progress. While wedged it looks exactly
like the GPU box died:

- host GPU drops to idle wattage;
- `vllm:num_requests_running` = 0, `num_requests_waiting` = 0;
- `vllm:request_success_total{finished_reason="error"|"abort"}` = 0 — the
  server reports no failures at all;
- the client process sits at 0% CPU and never raises an error;
- `netstat` shows far more ESTABLISHED sockets than there are in-flight
  requests.

The variable is **cumulative requests through one long-lived client**, not load:
the same batch completes cleanly from a fresh process, and 16 parallel `curl`
invocations (one process per request, no shared client) never reproduce it.

## Reproduction

`example/concurrency_stall_repro.dart`. It needs only a running vLLM server.

```bash
cd packages/llm_vllm
LLM_VLLM_TRACE=1 dart run example/concurrency_stall_repro.dart \
  --host http://192.168.0.74:8000 \
  --model Qwen/Qwen3.8-27B-FP8 \
  --concurrency 8 --prompt-ktokens 8 --batches 40 \
  --read-timeout-seconds 120
```

### Measuring it is half the problem

The stall is **self-healing**: a timeout eventually fires, `RetryUtil` retries,
and the retry succeeds immediately. Counting errors therefore finds nothing —
every harness run reported `err=0`. Two further traps, both hit during this
investigation:

- **Comparing against the batch median hides it.** When a stall wedges a whole
  batch, that batch's own median moves with it and the batch scores as normal.
  The harness now judges every request against the **run** median.
- **A watchdog alone is useless**, because the run recovers long before any
  sensible watchdog would fire.

Confirmed baseline, unfixed code, 320 requests at concurrency 8 / 8k prompts:

```
batch 24/40  wall=11s  p50=10.8s  p90=11.2s  max=11.5s
batch 25/40  wall=74s  p50=73.8s  p90=74.2s  max=74.4s   <- all 8 wedged
batch 26/40  wall=11s  p50=11.0s  p90=11.3s  max=11.4s
```

Client-side sockets to the server during that batch: **27 ESTABLISHED for 8
in-flight requests**, falling back to 8 once it cleared.

After the fixes, the same harness against the same server, 480 requests through
one shared repository:

```
summary client=default sent=480 completed=480 errors=0
run median=11.3s p90=11.8s p99=12.4s max=12.5s
PASS: no stalls in 480 requests
```

That is a real improvement at this size, but **it was not proof the stall was
gone** — see
[the send() stall itself](#the-send-stall-itself-a-dart-vm-defect-on-macos)
below, where the same code still stalled at 32k / concurrency 16 until the
send-pacing fix landed.

---

## What was actually wrong

Four distinct defects, found in this order.

### 1. A stream read timeout killed the process instead of failing the request

`VLLMStreamConverter` (and `OllamaStreamConverter`) passed the read timeout as:

```dart
.timeout(readTimeout, onTimeout: (sink) {
  throw TimeoutException(...);   // WRONG
})
```

`onTimeout` is invoked from a **timer**, outside the stream's error path. A
throw there does not enter the stream — it escapes as an unhandled exception
and takes the isolate down. Observed live: a 32k-prompt run at concurrency 16
died with

```
Unhandled exception:
TimeoutException after 0:01:00.000000: Stream read timed out ...
#2  Stream.timeout.<anonymous closure> (dart:async/stream.dart:2067:14)
#3  Timer._createTimer.<anonymous closure> (dart:async-patch/timer_patch.dart:18:15)
```

The fix pushes the error into the sink instead:

```dart
onTimeout: (sink) {
  sink.addError(TimeoutException(...));
  sink.close();
}
```

For any long-lived agent loop this was strictly worse than the stall it was
meant to guard: an unrecoverable process death on a slow response.

### 2. `applyTimeoutToSend` defaulted to `false`

`sendStreamingRequest` returned a completely **untimed** `httpClient.send()`
unless the caller opted in. `llm_vllm` opted in — which is the only reason its
stall self-healed. `llm_claude`, `llm_gemini` and `llm_ollama` did not, so for
them the same stall was **permanent**. The default is now `true`.

### 3. `StreamedRequest` for an in-memory body

```dart
final request = http.StreamedRequest(method, uri);
if (body != null) {
  request.headers['content-length'] = body.length.toString();
  request.sink.add(body);
}
unawaited(request.sink.close());
```

The original report blamed the unawaited `close()` for stranding the body. That
is **not** the mechanism: `StreamedRequest` wraps a non-broadcast
`StreamController(sync: true)`, and both the `add` and the `close` happen before
`IOClient.send()` calls `finalize()`, so both sit in the controller's pending
queue and are delivered when `stream.pipe(ioRequest)` subscribes. Whether the
`close()` future completes is irrelevant.

It was still wrong, for a different reason. `IOClient.send` does
`ioRequest.contentLength = request.contentLength ?? -1` — and a
`StreamedRequest` reports `null`, so dart:io negotiates **chunked** encoding,
which the hand-set `content-length` header then silently undoes. Every caller
passes a fully-materialised `List<int>`; there is nothing to stream. Now:

```dart
final request = http.Request(method, uri);
request.headers.addAll(headers);
if (body != null) request.bodyBytes = body;
```

`package:http` reports the content length, dart:io writes the body as part of
`send()`, and no encoding is negotiated and retracted.

Worth doing on its own merits, but it does **not** remove the stall: the 32k /
concurrency 16 runs below wedge with `http.Request` in place.

### 4. An unbounded, badly-tuned connection pool

Every repository built a bare `http.Client()`, giving a `dart:io` `HttpClient`
with:

- `connectionTimeout == null` — `TimeoutConfig.connectionTimeout` existed but
  was never applied anywhere;
- `maxConnectionsPerHost == null` — unbounded, which is how 8 in-flight
  requests produced 27 sockets;
- `idleTimeout == 15s` — **longer than the server's keep-alive**. uvicorn, which
  fronts vLLM, defaults to 5s. A connection the server has already reaped stays
  in the client pool as a reuse candidate for another ~10s, and dart:io creates
  the response completer only *after* the request body is written
  (`_HttpClientConnection.send`, `http_impl.dart`), so a connection that dies in
  that window has no error path at all — exactly the "socket open, both sides
  idle, no exception" signature.

`llm_core` now exposes `createLLMHttpClient()` (conditional import, so web still
gets a plain client), used as the default by every repository:

```dart
IOClient(HttpClient()
  ..connectionTimeout = timeoutConfig.connectionTimeout
  ..idleTimeout = const Duration(seconds: 3)   // below the server's keep-alive
  ..maxConnectionsPerHost = 64)
```

Passing your own `httpClient` bypasses it, as before.

### Also: retries were silent

`RetryUtil.executeWithRetry` logged nothing. A request that wedged for a full
timeout and then succeeded on retry showed up as latency and nothing else,
which is why this went unexplained for so long. It now warns on every retry via
`RetryUtil.logger` and accepts an `onRetry` callback.

---

## The `send()` stall itself: a Dart VM defect on macOS

None of the four client-side fixes removes the original symptom at 32k prompts
/ concurrency 16. From a **verified-idle server** (`num_requests_running` and
`num_requests_waiting` both 0), first batch, `--client shipped`:

```
16 request.build
16 send.begin
15 send.headers      <- one request never got headers
```

and with a 300s read timeout, the classic recovery:

```
       19ms  req=7  send.begin        <- first attempt
   301031ms  req=7  send.begin        <- retry, after the 300s timeout fired
   301103ms  req=7  send.headers 200  <- succeeds in 62ms
```

An earlier revision of this document concluded from vLLM's metrics ledger that
the server "accepts the connection and never reads it" and blamed vLLM's HTTP
front end. That inference was **wrong**, and the correction is instructive:
everything the application layer could see — on both machines — was identical
for "server never reads" and "client never writes". Only kernel counters can
tell those apart.

### The kernel evidence: the bytes never leave the client

With uvicorn trace logging on the server (`--uvicorn-log-level trace`), one
16-burst from macOS produced **16/16 `HTTP connection made`** lines — every
connection was accepted *and registered by uvicorn* — but only 11/16
`Received request`. For the five missing requests, taken **while wedged**:

- server-side `ss -tmi` on those exact sockets: `Recv-Q 0`, **`segs_in: 2`**
  — the server kernel saw the TCP handshake and then *nothing*, ever (one
  socket got a single ~202-byte segment: the request headers, never the body);
- client-side `netstat`: `Send-Q 0` on all 16 sockets.

`Send-Q 0` on the client plus `segs_in 2` on the server is unfakeable: the
Dart process **never handed the request bytes to its own kernel**. The wedge
is entirely inside the client; there was never anything for vLLM to read. The
earlier ledger observations (fds held, engine idle, fd leak on unread FIN) are
all downstream consequences of an idle-but-open accepted connection, plus
uvicorn's real-but-secondary quirk of arming no timeout until a response
completes.

### Isolated to the VM's socket write path, macOS only

- **Raw `dart:io` `Socket`, no HttpClient:** 16 simultaneous
  `Socket.connect` + one `add(headers)` + `add(132KB)` + `flush()` — all 16
  connect in ~40ms, but **3 of 16 never complete `flush()`**: the write path
  stalled before the kernel. Whole HTTP stack exonerated.
- **Same burst from Linux** (Dart 3.13.0 in a container on the server box,
  epoll event handler): **32/32 clean**, headers in 54–453ms. The defect is
  specific to the macOS (kqueue) event handler; production paths running on
  Linux are unaffected.
- **Concurrency 8, 132KB bodies:** still wedges 1–2 of 8 — it never needed 16.
- **16 connections, 33KB bodies (8k prompts):** never wedges. A 33KB body
  fits in the first `write()` syscall, so no kqueue writable event is needed;
  132KB does not, and the fd then waits on a writable event that sometimes
  never arrives. This is why the 8k/8 soak always passed while 32k/16 always
  failed — the earlier revision misread that as "load-dependent server bug".
- **15ms stagger between connects, 16 × 132KB:** **48/48 clean** across three
  rounds. Spreading socket creation out of the same event-loop window fully
  prevents the loss.
- **Semaphore of 4 on the connect+write phase, 16 × 132KB:** **80/80 clean**
  across five rounds, the whole burst's write phase completing in ~100ms —
  the same protection as the stagger with no clock in the loop (a gate of 2
  also passed 48/48; an ungated control in the same session wedged again).
- Why per-process `curl` never reproduced it: one process per request means
  one socket per event loop — no simultaneous registrations to collide. (The
  earlier `Expect: 100-continue` explanation was a red herring.)

No matching report exists in dart-lang/sdk, but the neighborhood is
well-charted:

- [dart-lang/sdk#30434](https://github.com/dart-lang/sdk/issues/30434) — a
  *duplicated* write event during connect in the same delivery path, open
  since 2017; this defect is the mirror image (a *lost* one).
- [dart-lang/sdk#24417](https://github.com/dart-lang/sdk/issues/24417) — a
  `!di->tracked_by_kqueue()` assertion firing in exactly the
  `EV_DELETE`/re-`EV_ADD` bookkeeping; the Dart team analyzed it, wrote they
  could not see how it was possible, and closed it stale.
- `runtime/bin/eventhandler_macos.cc` registers sockets edge-triggered
  (`EV_ADD | EV_CLEAR`) and re-issues a full `EV_DELETE`/`EV_ADD` of both
  filters on every mask change (unchanged since 2017), so a readiness edge
  that fires into a deleted registration is simply gone — and
  `_SocketStreamConsumer` waits on that event with **no timeout**.

How the mainstream runtimes avoid this class of bug entirely (all verified
from source): CPython's selectors and libuv register kqueue **level-
triggered** (no `EV_CLEAR`), so a dropped notification self-heals at the next
poll — Python/asyncio cannot lose this race. Go and Rust's mio do use
`EV_CLEAR`, but register **once per fd for its lifetime** (no delete/re-add
churn) and treat events as mere wake-up hints: writes are eager syscalls that
park only on `EAGAIN` and retry on every wake. Dart is alone in combining
edge-triggering, per-mask-change re-registration, and a write path that
waits indefinitely for the event to arrive. Even Go's conservative usage has
hit never-delivered kqueue events on macOS
([golang/go#54529](https://github.com/golang/go/issues/54529), unresolved,
suspected in the kernel) — macOS kqueue has a long rap sheet (libevent ships
a runtime "detected broken kqueue" check).

There is **no event-level recovery available from Dart user code**: the
event mask is sent to the native handler exactly once per socket (`flagsSent`
latch in `socket_patch.dart`), and `RawSocket.writeEventsEnabled` only flips
Dart-side dispatch booleans — it never re-arms the kqueue filter.

### The fix: gate the connect+write phase

`llm_core` now ships `WriteGatedHttpClient`: a counting semaphore bounds how
many requests may be between *connection acquisition* and *request body
handed to the kernel* (`flush()` complete) at the same time. Excess requests
queue and start the instant a slot frees — no timers, no fixed delays, and
concurrent streaming *responses* are never limited because slots free at
flush, not at response. `createLLMHttpClient()` applies it **by default on
macOS and iOS** with `kLLMMaxConcurrentWrites` (4, the empirically verified
bound); Linux and web get none. Each gated request also carries a write
watchdog (default 30s, scaled for large bodies): if connect+write has not
completed by then, the request is aborted with a `TimeoutException` — any
residual event loss becomes a fast, retryable error instead of a silent
wedge. (The watchdog must *race* the write rather than rely on
`HttpClientRequest.abort()`, which fails the response future but leaves a
pending `flush()` hanging.)

Bounded admission is how every surveyed production stack handles this
class of problem — LiteLLM holds an `asyncio.Semaphore` per deployment
across each whole request, aiohttp parks excess connects in per-host waiter
queues, httpx/httpcore queue requests FIFO against `max_connections`, and
none of them delay sends on a clock. Releasing at body-flush rather than at
response completion makes this gate strictly *looser* than all of those.

Retained defense-in-depth, both verified against the live server:

- the send timeout + retry (defect 2) — turns any wedged request into a
  delayed success rather than a hang;
- **bounding in-flight connections** (`maxConnectionsPerHost`, RFC 9112 §9.4)
  — `= 4` also made the 16-burst complete 16/16 in every round, at the cost
  of capping concurrent streams; the write gate achieves the same without
  the cap.

### Measurement traps

Ways this investigation produced wrong answers before producing right ones:

- **The application layer cannot distinguish "peer never reads" from "we never
  wrote".** Every app-level probe (traces, metrics, logs) on both machines was
  consistent with both stories. The tie-breakers were kernel counters:
  `Send-Q` on the client, `segs_in`/`bytes_received` (`ss -tmi`) on the
  server, taken **while wedged**.
- **Killing a run leaves work on the server.** vLLM kept executing requests from
  a `pkill`ed harness; a following run then queued behind them and looked
  wedged. Always drain to `num_requests_running == num_requests_waiting == 0`
  before measuring.
- **A smaller config is not a weaker version of the same test.** 8k prompts at
  concurrency 8 ran 480 requests clean; 32k at concurrency 16 wedged on the
  first batch. The difference turned out to be *mechanistic* (body size vs
  first-write capacity), not a matter of degree.

## Regression coverage

- `packages/llm_core/test/unit/http_client_utils_test.dart` — drives a real
  `HttpServer`: asserts the whole body arrives with a matching `content-length`
  and no chunked encoding, and that a server which accepts but never answers
  produces a `TimeoutException` **with default arguments**. Both timeout tests
  fail against the pre-fix code.
- `packages/llm_core/test/unit/write_gated_http_client_test.dart` — drives a
  real `HttpServer` plus a never-reading raw socket: asserts slots release on
  body flush (not on response), a stalled write is aborted by the watchdog
  and frees its slot for the queued request, round-trips stay intact, and
  the gated default applies exactly on kqueue platforms.
- `example/concurrency_stall_repro.dart` — soak harness; fails when any request
  exceeds 4x the run median.
- `example/raw_socket_burst_probe.dart` — the minimal repro: N raw sockets,
  one large write each, reports which ones never complete `flush()`. Run it
  with a stagger argument of 0 vs 15 to see the defect and the fix.

## Environment

- Dart SDK 3.12.2, macOS client → Ubuntu server over LAN (Linux control:
  Dart 3.13.0, same burst clean)
- vLLM 0.27.1, `Qwen/Qwen3.8-27B-FP8`, `max_model_len` 204 800,
  `max_num_seqs` 16, prefix caching off
- `package:http` 1.6.0
