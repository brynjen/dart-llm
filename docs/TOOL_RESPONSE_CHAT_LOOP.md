# Tool Response Chat Loop - Stream Contract

This document describes how tool calls and tool results flow through the chat stream, per [OpenAI function calling](https://developers.openai.com/api/docs/guides/function-calling/) and [streaming](https://developers.openai.com/api/docs/guides/function-calling/#streaming) specifications.

## Stream Chunk Types

Consumers of `streamChat()` receive these kinds of chunks. Handle all of them to display the full tool calling flow:

### 1. Content Chunks (Assistant Text)

- `chunk.message?.content` - Incremental text from the model
- `chunk.message?.role` - `LLMRole.assistant`
- `chunk.message?.thinking` - Optional reasoning content (when `think: true`)

### 2. Tool Call Progress Chunks (Call Still Streaming)

- `chunk.message?.toolCallDeltas` - Fragments of calls that are still arriving
- The first fragment for an `index` carries the tool `name` (and `id`), so a UI
  can show which tool is running before its arguments finish
- **Never executable**: `argumentsDelta` is one fragment of a JSON document
- Emitted by ChatGPT, vLLM, Claude and Gemini. Ollama and llama.cpp receive each
  call whole, so they emit none — the call arrives on `toolCalls` directly

### 3. Tool Call Chunks (Model Requests Tools)

- `chunk.message?.toolCalls` - Non-null when the model requests tool execution
- Arrives at the end of a round, either on the terminal chunk
  (`chunk.done == true`) or just before it — Claude, Gemini and Ollama deliver
  calls on an earlier chunk
- Each `LLMToolCall` has: `name`, `arguments`, `id` (or synthesized)
- Only calls whose `arguments` decode to a JSON object appear here

### 4. Invalid Tool Call Chunks (Arguments Do Not Decode)

- `chunk.message?.invalidToolCalls` - Set on the same chunk as `toolCalls`
- Each `LLMInvalidToolCall` has: `name`, `arguments` (raw text), `id`, `error`
- **Never executed.** The usual cause is a turn cut off by the output token
  limit (`chunk.finishReason == LLMFinishReason.length`); the other is a model
  writing malformed JSON
- Same shape as LangChain's `invalid_tool_calls` and the Vercel AI SDK's
  `invalid: true` tool calls

### 5. Tool Result Chunks (Tool Execution Output)

- `chunk.message?.role == LLMRole.tool`
- `chunk.message?.content` - The tool's return value
- `chunk.message?.toolCallId` - Links to the tool call (canonical identifier)

Tool result chunks are emitted by the executor after each tool runs, before the next API request. To display "Tool X returned: Y", build a map from tool call chunks (`toolCallId -> toolName` from `message?.toolCalls` and `message?.invalidToolCalls`) and look up the name when processing tool result chunks.

An invalid call also gets a tool result chunk: a tool error saying the call was
not run and why, with a hint to produce a shorter call when the turn hit the
token limit. In the next request the invalid call is echoed with `{}` arguments,
because some servers (vLLM) decode assistant tool-call arguments in history and
reject the request with a `400` otherwise.

With `LLMChatOptions(autoExecuteTools: false)` the executor does not run and no
tool result chunks are emitted; handle `toolCalls` and `invalidToolCalls`
yourself.

## Flow Summary

```
User message
    |
    v
[API Request 1] --> Stream: content chunks, toolCallDeltas,
    |                  then chunk with toolCalls / invalidToolCalls
    v
Executor runs valid calls,
answers invalid ones with a tool error --> Stream: tool result chunks (role: tool)
    |
    v
[API Request 2] with [user, assistant(tool_calls), tool(result), ...]
    |
    v
Stream: content chunks (model's final response)
```

## Backend Differences

The contract above is what consumers see. On the wire each provider spells it
differently, and one backend does not emit tool result chunks at all.

- **OpenAI/ChatGPT:** Tool messages use `tool_call_id`. Stream includes `delta.tool_calls`.
- **vLLM:** Same OpenAI-compatible shape as ChatGPT. Requires the server to be
  started with `--enable-auto-tool-choice` and a matching `--tool-call-parser`;
  without those flags the model never emits a structured tool call.
- **Ollama:** Uses `tool_name` for tool messages. The Ollama message converter derives `tool_name` from `toolCallId` (via preceding assistant's `tool_calls` or synthetic ID parsing) and sends both `tool_name` and `tool_call_id` when possible.
- **Claude:** Tool calls arrive as `tool_use` content blocks. Results go back as
  a **user** message containing `tool_result` blocks keyed by `tool_use_id`;
  consecutive results are merged into one user message.
- **Gemini:** The Interactions API is steps-based. A call is a `function_call`
  step and a result is a `function_result` step. The model's thought signature
  must be echoed back with the call, so it is carried through the `toolCallId`.
- **llama.cpp:** There is no structured tool-call field — calls are parsed out of
  the raw token stream in whatever format the loaded model's family uses. The
  package runs the tool loop internally and **does not emit `role: tool` chunks**,
  so a UI wanting to show tool results must have the tool report them itself
  (see the example app's `CalculatorTool(onInvoke: ...)`). Callers keeping their
  own history must replay `LLMChunkMessage.rawContent` for the assistant turn,
  or the model stops calling tools after the first turn.

### Finish reasons on a tool-calling turn

The OpenAI specification defines `finish_reason` as `tool_calls` "if the model
called a tool" — a classification of what the turn did, not an opaque provider
token. Providers violate this routinely, so the mapping layer repairs it rather
than passing the wrong value through:

- **vLLM** reports `stop` for a named `tool_choice`, streaming and non-streaming
  alike, while returning a complete call.
- **Ollama**'s `done_reason` is `stop` on every turn, and the calls arrive on the
  frame *before* the terminal one.
- **OpenAI** reports `stop` alongside a complete call intermittently.
- **Claude** usually spells it `tool_use`, but a turn mixing text and tool blocks
  can end `end_turn`.
- **Gemini** has no tool-call status at all.
- **llama.cpp** reports no finish reason at all.

One rule covers all of them, and every backend applies it through
`LLMFinishReason.resolve` in `llm_core` rather than re-deriving it:

> A turn that ends while carrying complete, executable tool calls is a tool-call
> turn, whatever the provider spelled — unless the provider's own reason
> contradicts the call being executable.

`length`, `contentFilter` and `refusal` are the contradictions and are never
reclassified.

- **`length`** stays a truncation, but its calls are still returned, split by
  whether their arguments decode: complete calls on `toolCalls`, the cut one on
  `invalidToolCalls`. This is what the OpenAI API itself returns, and how
  LangChain and the Vercel AI SDK surface it.
- **`contentFilter` and `refusal`** withhold the calls: a declined turn must stay
  visibly declined rather than hide a safety outcome behind a call the provider
  did not stand behind.

Adapters correct a provider's known violation of the specification before
resolving. **vLLM** reports `tool_calls` for a turn cut off by `max_tokens`
mid-arguments: its streaming path overwrites the reason once any tool-call delta
went out (vllm-project/vllm#53269, closed as not planned). `llm_vllm` restores
`length` when the **last** call's arguments do not decode. Only the last call
can be cut by the token limit; an earlier undecodable call next to a complete
last one is malformed JSON from the model, and the turn stays `toolCalls`.

**Emission never depends on the finish reason.** Accumulated calls are flushed
when the turn ends — a terminal frame, or the stream closing — so a spelling this
library has not seen, or a proxy cutting the stream off before any terminal frame
arrives, cannot silently drop a call. At an abrupt end of stream there is no
provider signal either way, so a call counts as valid only if its accumulated
arguments are non-empty and decode; the rest are surfaced as invalid.

A new backend inherits this by calling `LLMFinishReason.resolve` at its turn
boundary and `LLMToolCall.partition` on the calls it accumulated. It should not
re-implement either rule.

## Code Path

- Tool execution: [packages/llm_core/lib/src/tool_executor.dart](../packages/llm_core/lib/src/tool_executor.dart)
- Tool result emission: `StreamToolExecutor.executeTools` yields `LLMChunk` with `role: LLMRole.tool` after each tool runs, and for each invalid call
- Valid/invalid split: `LLMToolCall.partition` in [packages/llm_core/lib/src/tool/llm_tool_call.dart](../packages/llm_core/lib/src/tool/llm_tool_call.dart)
- vLLM finish-reason correction: [packages/llm_vllm/lib/src/vllm_stream_converter.dart](../packages/llm_vllm/lib/src/vllm_stream_converter.dart)
- Ollama message format: [packages/llm_ollama/lib/src/message_converter.dart](../packages/llm_ollama/lib/src/message_converter.dart)
- Claude message format: [packages/llm_claude/lib/src/claude_message_converter.dart](../packages/llm_claude/lib/src/claude_message_converter.dart)
- Gemini step format: [packages/llm_gemini/lib/src/gemini_message_converter.dart](../packages/llm_gemini/lib/src/gemini_message_converter.dart)
- llama.cpp call parsing: [packages/llm_llamacpp/lib/src/tool_calls/tool_call_syntax.dart](../packages/llm_llamacpp/lib/src/tool_calls/tool_call_syntax.dart)
