# llm_vllm

[![pub.dev](https://img.shields.io/pub/v/llm_vllm)](https://pub.dev/packages/llm_vllm)

vLLM OpenAI-compatible backend implementation for LLM interactions in Dart.

## Features

- Streaming chat responses via `/v1/chat/completions`
- Optional bearer auth for servers started with `--api-key`
- Tool/function calling
- Vision payloads through OpenAI-compatible message content
- Embeddings via `/v1/embeddings`
- Model listing via `/v1/models`
- Thinking/reasoning stream support when enabled by the served model
- Structured output through OpenAI-compatible `response_format`
- Multi-instance `VLLMPool` for routing, concurrency limits, and health checks

## Installation

```yaml
dependencies:
  llm_vllm: ^0.2.0
```

## Prerequisites

Start a vLLM OpenAI-compatible server. For local development this commonly uses
port 8000:

```bash
vllm serve Qwen/Qwen3-0.6B
```

## Usage

### Basic Chat

```dart
import 'package:llm_vllm/llm_vllm.dart';

final repo = VLLMChatRepository(baseUrl: 'http://localhost:8000');

final stream = repo.streamChat('Qwen/Qwen3-0.6B', messages: [
  LLMMessage(role: LLMRole.user, content: 'Hello!'),
]);

await for (final chunk in stream) {
  print(chunk.message?.content ?? '');
}
```

### Authenticated Server

```dart
final repo = VLLMChatRepository(
  baseUrl: 'http://localhost:8000',
  apiKey: 'your-vllm-api-key',
);
```

### Tool Calling

```dart
final stream = repo.streamChat(
  'Qwen/Qwen3-0.6B',
  messages: messages,
  tools: [MyTool()],
);
```

Automatic tool execution is enabled by default. Disable it to run a manual tool
loop:

```dart
final stream = repo.streamChat(
  'Qwen/Qwen3-0.6B',
  messages: messages,
  tools: [MyTool()],
  options: const LLMChatOptions(autoExecuteTools: false),
);
```

### Structured Output

```dart
final stream = repo.streamChat(
  'Qwen/Qwen3-0.6B',
  messages: [LLMMessage(role: LLMRole.user, content: 'Return a person object.')],
  options: const LLMChatOptions(
    responseFormat: JsonSchemaFormat(
      name: 'Person',
      schema: {
        'type': 'object',
        'properties': {
          'name': {'type': 'string'},
          'age': {'type': 'integer'},
        },
        'required': ['name', 'age'],
      },
    ),
  ),
);
```

### Embeddings

```dart
final embeddings = await repo.embed(
  model: 'BAAI/bge-small-en-v1.5',
  messages: ['Hello world', 'Goodbye world'],
);
```

### Model Listing

```dart
final vllmRepo = VLLMRepository(baseUrl: 'http://localhost:8000');
final models = await vllmRepo.models();
```

### vLLM-Specific Options

vLLM accepts **64 request parameters**. Rather than typing all of them — a
treadmill that breaks on every vLLM release — `llm_vllm` uses three layers:

| Layer | Use for | Example |
|---|---|---|
| `LLMChatOptions` | Portable settings every backend supports | `temperature`, `topP`, `maxOutputTokens` |
| Typed helpers | The vLLM-only knobs people actually reach for | `VLLMSamplingOptions`, `VLLMStructuredOutputs` |
| `backendOptions` | The long tail, validated against vLLM's schema | `cache_salt`, `priority`, `mm_processor_kwargs` |

```dart
final stream = repo.streamChat(
  'Qwen/Qwen3-0.6B',
  messages: messages,
  options: LLMChatOptions(
    // Layer 1 — portable across backends
    temperature: 0.2,
    maxOutputTokens: 256,
    backendOptions: {
      // Layer 2 — typed and IDE-discoverable
      ...const VLLMSamplingOptions(
        minP: 0.05,
        repetitionPenalty: 1.05,
        seed: 42,
      ).toBackendOptions(),
      // Layer 3 — long tail, still validated
      'priority': 1,
    },
  ),
);
```

> **vLLM silently ignores unknown request fields.** It returns `200` and drops
> them rather than reporting an error, so a misspelled parameter is
> indistinguishable from a working one — `repitition_penalty` yields a
> perfectly normal response in which the penalty was never applied.

Because of that, `backendOptions` keys are validated before the request is
sent. An unrecognized key throws with the closest match:

```
vLLM does not recognize "repitition_penalty" and silently drops unknown
fields, so this would have no effect. Did you mean "repetition_penalty"?
```

camelCase spellings are accepted and normalized (`minP` → `min_p`), matching
`llm_ollama`. `extra_body` is an OpenAI **Python SDK** wrapper, not a wire
field — vLLM never reads it, so its contents are flattened onto the request
body rather than dropped.

A few keys get special treatment:

- **`chat_template_kwargs`** merges key-by-key with the map the repository
  builds for reasoning control, so setting unrelated template kwargs never
  discards `enable_thinking`. Your entries win on conflict — an explicit
  `enable_thinking` here overrides the `think:` flag.
- **`tool_choice`** accepts `auto`/`none`/`required`, a bare tool name (which
  is wrapped into the OpenAI named-function form), or the full object.
  `none` and `auto` are valid without tools; `required` or a named tool
  without tools is rejected client-side, since vLLM would answer 400.
- **`n`** must be `1`. The streaming pipeline surfaces only the first choice,
  so additional candidates would cost tokens and be discarded; issue separate
  requests instead.

For parameters added by a custom vLLM extension, use `vllm_xargs` — vLLM's own
escape hatch, which is a declared field and so is never dropped:

```dart
backendOptions: const VLLMSamplingOptions(
  vllmXargs: {'my_extension_param': 3},
).toBackendOptions(),
```

#### Validating against your server's schema

The bundled parameter list is a snapshot of vLLM 0.27.1. To validate against
the version you actually run — which also catches parameters added or removed
between releases — read the schema from the server:

```dart
final probe = VLLMRepository(baseUrl: 'http://localhost:8000');
final repo = VLLMChatRepository(
  baseUrl: 'http://localhost:8000',
  supportedParams: await probe.fetchSupportedParams(),
);
```

`fetchSupportedParams()` returns `null` if the schema cannot be read, in which
case the built-in snapshot is used.

### Capabilities

`VLLMChatRepository.capabilitiesForModel` reports what **`llm_vllm` implements**,
not what the connected server offers — vLLM runs one model per process, so tool
calling depends on server flags and vision and embeddings depend on the loaded
model. Probe the deployment and pass the result in:

```dart
final probe = VLLMRepository(baseUrl: baseUrl);
final repo = VLLMChatRepository(
  baseUrl: baseUrl,
  capabilities: await probe.resolveCapabilities('Qwen/Qwen3-0.6B'),
);
```

`resolveCapabilities` cannot detect vision (the server does not report model
modality), so it reports `false`; set it explicitly when serving a multimodal
model.

Both probes wire through the builder as well:

```dart
final probe = VLLMRepository(baseUrl: baseUrl);
final repo = VLLMChatRepository.builder()
    .baseUrl(baseUrl)
    .capabilities(await probe.resolveCapabilities('Qwen/Qwen3-0.6B'))
    .supportedParams(await probe.fetchSupportedParams() ?? knownVllmChatParams)
    .build();
probe.close();
```

### Retries and timeouts

Retries are **on by default** — three attempts on `429`/`5xx`, because a vLLM
server answers `503` while it is still loading weights. Opt out with
`RetryConfig(maxAttempts: 0)`.

Retries cover *establishing* the request. Once the server has started
streaming, a dropped connection ends the stream with an error and is **not**
retried — the tokens already delivered are yours, and re-sending would restart
generation and duplicate them. For long generations, accumulate chunks and
re-issue with the partial output appended to the conversation.

Two timeouts apply to a stream:

| Setting | Measures |
|---|---|
| `TimeoutConfig.readTimeout` | The gap *between* chunks — catches a stalled stream |
| `TimeoutConfig.totalTimeout` | Total elapsed time — catches a stream that trickles forever |

### Embeddings batching

`batchEmbed` splits large inputs into batches of 32, preserving order:

```dart
await repo.batchEmbed(
  model: 'BAAI/bge-small-en-v1.5',
  messages: manyTexts,
  options: const {'batch_size': 64}, // or 0 to send everything at once
);
```

### Checking server configuration

Tool calling and reasoning depend on how the server was **started**, not on the
request. `VLLMRepository` probes for both, mirroring `llm_ollama`'s
`supportsStructuredOutput`:

```dart
final probe = VLLMRepository(baseUrl: 'http://localhost:8000');
await probe.supportsToolCalling('Qwen/Qwen3-0.6B');     // needs --tool-call-parser
await probe.supportsReasoningParser('Qwen/Qwen3-0.6B'); // needs --reasoning-parser
```

Both return `false` rather than throwing when the server is unreachable, so a
probe never breaks a caller.

If you skip the probe, the raw `400` is still translated into an actionable
error naming the missing flag, rather than vLLM's terse original message.

> `supportsToolCalling` reports whether the server *accepts* tool requests. It
> cannot tell you whether the configured parser matches the model's output
> format — a mismatched parser accepts the request and then returns no tool
> calls at all.

### Guided decoding

For JSON and JSON Schema, use `LLMChatOptions.responseFormat` — it maps to the
OpenAI-compatible `response_format` field. For the vLLM-only constraint modes,
use `VLLMStructuredOutputs`:

```dart
final stream = repo.streamChat(
  'Qwen/Qwen3-0.6B',
  messages: messages,
  options: LLMChatOptions(
    backendOptions:
        const VLLMStructuredOutputs.choice(['positive', 'negative'])
            .toBackendOptions(),
  ),
);
```

Also available: `.json(schema)`, `.regex(pattern)`, `.grammar(ebnf)`, and
`.structuralTag(tag)`.

vLLM 0.12 replaced the `guided_*` parameters with `structured_outputs`. The old
names are **not rejected by the server** — they are ignored, yielding
unconstrained output with a `200` status. `llm_vllm` throws an `ArgumentError`
if it sees one (including nested inside `extra_body`) rather than letting the
constraint silently disappear.

### Reasoning

`think: true` / `think: false` maps to `chat_template_kwargs.enable_thinking`,
which is how vLLM's chat templates gate reasoning for Qwen3-family models. The
flag is sent in both directions, because Qwen3 thinks by default and would
otherwise ignore `think: false`.

Reasoning text is read from the server's `reasoning` field (aliases:
`reasoning_content`, `thinking`). If the server was started **without**
`--reasoning-parser`, the model emits raw `<think>` tags inline instead;
`llm_vllm` detects and splits those into `chunk.message.thinking` so the
behavior is the same either way.

#### Thinking budget and effort

With `think: true`, `reasoningBudget` maps to vLLM's top-level
`thinking_token_budget` (vLLM ≥ 0.19), which is **hard-enforced server-side**:
a logits processor forces the end-of-thinking tokens once the budget is spent.
It requires the server to run with `--reasoning-parser`; without it the server
answers `400`, which surfaces as a `ThinkingNotSupportedException` naming the
missing flag.

```dart
options: const LLMChatOptions(think: true, reasoningBudget: 512),
```

When no budget is set, `reasoningEffort` maps to vLLM's native
`reasoning_effort` (a soft knob that needs no reasoning parser). vLLM accepts
`low`/`medium`/`high`, so the portable scale clamps:

| `ReasoningEffort` | wire value |
|---|---|
| `none` | `chat_template_kwargs.enable_thinking: false` (no `reasoning_effort`) |
| `minimal`, `low` | `low` |
| `medium` | `medium` |
| `high`, `xhigh`, `max` | `high` |

If both knobs are set, the budget wins (vLLM is budget-native). Explicit
`backendOptions['thinking_token_budget']` / `['reasoning_effort']` override
both. Reasoning-token usage is surfaced as `LLMUsage.reasoningTokens` when the
server reports `completion_tokens_details.reasoning_tokens`.

Known upstream caveats: the budget is not enforced when MTP speculative
decoding is enabled (vllm#39573), and a tight budget can truncate tool-call
arguments on Qwen3.5+ (vllm#44676).

To enable tool calling and native reasoning parsing, start vLLM with:

```bash
vllm serve Qwen/Qwen3-0.6B \
  --enable-auto-tool-choice \
  --tool-call-parser qwen3_xml \
  --reasoning-parser qwen3
```

Without `--enable-auto-tool-choice` and `--tool-call-parser`, any request
carrying `tools` fails with a `400`.

### Base URL

The base URL may be given with or without the `/v1` suffix and with or without
a trailing slash — all four spellings resolve to the same endpoint:

```dart
VLLMChatRepository(baseUrl: 'http://localhost:8000');     // ✓
VLLMChatRepository(baseUrl: 'http://localhost:8000/');    // ✓
VLLMChatRepository(baseUrl: 'http://localhost:8000/v1');  // ✓
VLLMChatRepository(baseUrl: 'http://localhost:8000/v1/'); // ✓
```

## Pool

```dart
final pool = VLLMPool(
  instances: [
    VLLMInstanceConfig(
      baseUrl: 'http://gpu1:8000',
      maxConcurrent: 3,
      preferredModels: ['Qwen/Qwen3-0.6B'],
    ),
    VLLMInstanceConfig(
      baseUrl: 'http://gpu2:8000',
      maxConcurrent: 1,
      exclusiveModels: ['large-model'],
    ),
  ],
  modelConfigs: [
    VLLMModelConfig(pattern: 'large-model', maxConcurrent: 1),
  ],
  healthCheck: const HealthCheckConfig(),
);
```

`VLLMPool` is a drop-in `LLMChatRepository` with routing, per-instance
concurrency limits, optional per-model limits, queue limits, and `/v1/models`
health checks.

Instance-scoped settings (`rateLimiter`, `supportedParams`, `capabilities`,
`httpClient`) go on each `VLLMInstanceConfig`; request-scoped features
(`responseCache`, `metrics`) go on the pool itself, so the cache is shared
across instances and requests are counted once.
`pool.capabilitiesForModel(model)` reports the OR-fold of what the healthy,
eligible instances offer.

## Resource cleanup

Every repository owns an HTTP client unless you pass one in; whoever creates
the client closes it.

```dart
final repo = VLLMChatRepository(baseUrl: baseUrl);
// ... use it ...
repo.close();          // closes the owned client and the rate limiter

final probe = VLLMRepository(baseUrl: baseUrl);
// ... probe ...
probe.close();

final pool = VLLMPool(instances: [...]);
// ... use it ...
pool.dispose();        // stops health checks, closes owned per-instance
                       // clients and the state-change stream
```

A client you supply — to a repository or via
`VLLMInstanceConfig.httpClient` — is never closed by `close()`/`dispose()`.

## Testing

```bash
dart test --exclude-tags integration

VLLM_BASE_URL=http://localhost:8000 \
VLLM_CHAT_MODEL=Qwen/Qwen3-0.6B \
dart test --tags integration
```

Model-dependent live tests are gated so a chat-only server can still run the
general suite:

- `VLLM_ENABLE_TOOL_TESTS=true` for servers launched with vLLM tool calling
  support.
- `VLLM_ENABLE_REASONING_TESTS=true` for models/deployments that emit thinking
  or reasoning content.
- `VLLM_ENABLE_EMBEDDING_TESTS=true` with `VLLM_EMBEDDING_MODEL` and, when
  needed, `VLLM_EMBEDDING_BASE_URL` for `/v1/embeddings`.

For a small, purpose-built tool-calling lane, `Salesforce/xLAM-1b-fc-r` is a
good first download. Serve it with vLLM auto tool choice enabled and point the
tool integration tests at that server:

```bash
vllm serve Salesforce/xLAM-1b-fc-r \
  --host 0.0.0.0 \
  --port 8633 \
  --enable-auto-tool-choice \
  --tool-call-parser xlam \
  --chat-template examples/tool_chat_template_xlam_qwen.jinja

VLLM_BASE_URL=http://localhost:8633 \
VLLM_CHAT_MODEL=Salesforce/xLAM-1b-fc-r \
VLLM_ENABLE_TOOL_TESTS=true \
dart test test/integration/tool_calling_test.dart --tags integration
```
