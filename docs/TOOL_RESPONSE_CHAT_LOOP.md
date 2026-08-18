# Tool Response Chat Loop - Stream Contract

This document describes how tool calls and tool results flow through the chat stream, per [OpenAI function calling](https://developers.openai.com/api/docs/guides/function-calling/) and [streaming](https://developers.openai.com/api/docs/guides/function-calling/#streaming) specifications.

## Stream Chunk Types

Consumers of `streamChat()` receive three types of chunks. Handle all three to display the full tool calling flow:

### 1. Content Chunks (Assistant Text)

- `chunk.message?.content` - Incremental text from the model
- `chunk.message?.role` - `LLMRole.assistant`
- `chunk.message?.thinking` - Optional reasoning content (when `think: true`)

### 2. Tool Call Chunks (Model Requests Tools)

- `chunk.message?.toolCalls` - Non-null when the model requests tool execution
- Typically on the final chunk of a round (`chunk.done == true`)
- Each `LLMToolCall` has: `name`, `arguments`, `id` (or synthesized)

### 3. Tool Result Chunks (Tool Execution Output)

- `chunk.message?.role == LLMRole.tool`
- `chunk.message?.content` - The tool's return value
- `chunk.message?.toolCallId` - Links to the tool call (canonical identifier)

Tool result chunks are emitted by the executor after each tool runs, before the next API request. To display "Tool X returned: Y", build a map from tool call chunks (`toolCallId -> toolName` from `message?.toolCalls`) and look up the name when processing tool result chunks.

## Flow Summary

```
User message
    |
    v
[API Request 1] --> Stream: content chunks, then chunk with toolCalls
    |
    v
Executor runs tools --> Stream: tool result chunks (role: tool)
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

## Code Path

- Tool execution: [packages/llm_core/lib/src/tool_executor.dart](../packages/llm_core/lib/src/tool_executor.dart)
- Tool result emission: `StreamToolExecutor.executeTools` yields `LLMChunk` with `role: LLMRole.tool` after each tool runs
- Ollama message format: [packages/llm_ollama/lib/src/message_converter.dart](../packages/llm_ollama/lib/src/message_converter.dart)
- Claude message format: [packages/llm_claude/lib/src/claude_message_converter.dart](../packages/llm_claude/lib/src/claude_message_converter.dart)
- Gemini step format: [packages/llm_gemini/lib/src/gemini_message_converter.dart](../packages/llm_gemini/lib/src/gemini_message_converter.dart)
- llama.cpp call parsing: [packages/llm_llamacpp/lib/src/tool_calls/tool_call_syntax.dart](../packages/llm_llamacpp/lib/src/tool_calls/tool_call_syntax.dart)
