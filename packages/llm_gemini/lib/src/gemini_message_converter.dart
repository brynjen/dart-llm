import 'package:llm_core/llm_core.dart';

/// Converts [LLMMessage] lists and [LLMTool] declarations to the Gemini
/// Interactions API request format.
///
/// Key differences from the legacy `generateContent` format:
/// - Turns live in a top-level `input` array instead of `contents`.
/// - A turn's payload is a list of typed content *blocks*
///   (`{"type": "text", …}`) instead of untyped `parts`.
/// - Tool results are `function_result` blocks instead of `functionResponse`
///   parts.
/// - Tool declarations are flat `{"type": "function", "name": …}` objects
///   instead of being nested under `tools[].functionDeclarations`.
class GeminiMessageConverter {
  /// Separator used to smuggle a thought signature inside a tool-call id.
  ///
  /// The steps-based Interactions API rejects an echoed `function_call` step
  /// unless the model's opaque `thought` signature is echoed with it, but
  /// [LLMMessage] has no channel for signatures. The stream converter appends
  /// the signature to the call id (`callId::sig::signature`); the id
  /// round-trips untouched through [StreamToolExecutor], and
  /// [buildStatelessInput] splits it back apart here.
  static const String signatureSeparator = '::sig::';

  /// Serializes a full conversation into the Interactions API `input` array
  /// (steps-based format).
  ///
  /// ## ⚠️ WIRE SHAPE VERIFIED AGAINST THE LIVE API — CHECK HERE FIRST ON 400
  ///
  /// [LLMChatRepository.streamChat] is stateless: it receives the entire
  /// conversation on every call, so requests are sent with `store: false` and
  /// the whole history serialized here rather than relying on
  /// `previous_interaction_id`.
  ///
  /// The API's earlier role-tagged turn format (`{"role", "content"}`) is now
  /// rejected with "use step_list input format instead of turn_list". The
  /// steps-based `input` is a flat list of typed steps (shapes verified live
  /// 2026-08-17):
  ///
  /// ```json
  /// [
  ///   {"type": "user_input",   "content": [{"type": "text", "text": "…"}]},
  ///   {"type": "thought",      "signature": "…"},
  ///   {"type": "function_call", "id": "…", "name": "…", "arguments": {…}},
  ///   {"type": "function_result", "call_id": "…", "name": "…",
  ///    "result": [{"type": "text", "text": "…"}]},
  ///   {"type": "model_output", "content": [{"type": "text", "text": "…"}]}
  /// ]
  /// ```
  ///
  /// Notes:
  /// - system messages are emitted as leading `user_input` steps — the
  ///   request body has no documented system-instruction field;
  /// - `arguments` must be a JSON **object** (a string is rejected);
  /// - a `function_call` step without its preceding `thought` step (real
  ///   signature required — empty or placeholder signatures are rejected)
  ///   fails with "Request contains an invalid argument", hence
  ///   [signatureSeparator].
  static List<Map<String, dynamic>> buildStatelessInput(
    List<LLMMessage> messages,
  ) {
    final steps = <Map<String, dynamic>>[];

    for (final msg in messages) {
      switch (msg.role) {
        case LLMRole.system:
          if (msg.content != null && msg.content!.isNotEmpty) {
            steps.add(<String, dynamic>{
              'type': 'user_input',
              'content': [_textBlock(msg.content!)],
            });
          }

        case LLMRole.user:
          final content = <Map<String, dynamic>>[];
          for (final image in msg.images ?? const <String>[]) {
            content.add(_imageBlock(image));
          }
          if (msg.content != null && msg.content!.isNotEmpty) {
            content.add(_textBlock(msg.content!));
          }
          // An empty text block is a 400 ("Missing text in content of type
          // text") and a wholly empty input is a 400 ("Request has empty
          // input"), so a degenerate empty message falls back to a single
          // space, which the API accepts.
          steps.add(<String, dynamic>{
            'type': 'user_input',
            'content': content.isEmpty ? [_textBlock(' ')] : content,
          });

        case LLMRole.assistant:
          // Model turns must START with the thought block in thinking models
          // (a model_output ahead of it is a 400), so the signature — when
          // one was captured — is emitted before everything else.
          final toolCalls = msg.toolCalls ?? const <LLMToolCall>[];
          String? lastSignature;
          for (final toolCall in toolCalls) {
            final (_, signature) = _splitSignature(toolCall.id);
            if (signature != null) {
              steps.add(<String, dynamic>{
                'type': 'thought',
                'signature': signature,
              });
              lastSignature = signature;
              break;
            }
          }
          if (msg.content != null && msg.content!.isNotEmpty) {
            steps.add(<String, dynamic>{
              'type': 'model_output',
              'content': [_textBlock(msg.content!)],
            });
          }
          for (final toolCall in toolCalls) {
            Map<String, dynamic> arguments;
            try {
              arguments = toolCall.argumentsJson;
            } catch (_) {
              arguments = <String, dynamic>{};
            }
            final (callId, signature) = _splitSignature(toolCall.id);
            if (signature != null && signature != lastSignature) {
              steps.add(<String, dynamic>{
                'type': 'thought',
                'signature': signature,
              });
              lastSignature = signature;
            }
            steps.add(<String, dynamic>{
              'type': 'function_call',
              if (callId != null && callId.isNotEmpty) 'id': callId,
              'name': toolCall.name,
              'arguments': arguments,
            });
          }

        case LLMRole.tool:
          steps.add(_functionResultStep(msg));
      }
    }

    return steps;
  }

  /// Splits a possibly signature-carrying tool-call id into
  /// `(realId, signature)`.
  static (String?, String?) _splitSignature(String? id) {
    if (id == null) return (null, null);
    final idx = id.indexOf(signatureSeparator);
    if (idx == -1) return (id, null);
    final signature = id.substring(idx + signatureSeparator.length);
    return (id.substring(0, idx), signature.isEmpty ? null : signature);
  }

  /// Converts an [LLMTool] to an Interactions API tool entry.
  ///
  /// The Interactions API takes a flat array of tool objects — unlike
  /// `generateContent`, which wraps declarations in
  /// `tools[0].functionDeclarations`:
  /// ```json
  /// {"type": "function", "name": "…", "description": "…", "parameters": {…}}
  /// ```
  static Map<String, dynamic> toolToFunctionSpec(LLMTool tool) {
    final openAiFormat = tool.toJson;
    final function = openAiFormat['function'] as Map<String, dynamic>? ?? {};
    final parameters = function['parameters'] as Map<String, dynamic>? ?? {};
    return <String, dynamic>{
      'type': 'function',
      'name': function['name'] ?? tool.name,
      'description': function['description'] ?? tool.description,
      'parameters': parameters,
    };
  }

  static Map<String, dynamic> _textBlock(String text) => <String, dynamic>{
    'type': 'text',
    'text': text,
  };

  /// Builds a `function_result` step from a tool-result message.
  ///
  /// [LLMMessage.toolCallId] carries the id of the call being answered
  /// (stripped of any smuggled signature) and [LLMMessage.status] carries the
  /// tool name, matching how [StreamToolExecutor] populates tool messages.
  static Map<String, dynamic> _functionResultStep(LLMMessage msg) {
    final (callId, _) = _splitSignature(msg.toolCallId);
    return <String, dynamic>{
      'type': 'function_result',
      'call_id': callId ?? '',
      'name': msg.status ?? '',
      'result': [_textBlock(msg.content ?? '')],
    };
  }

  /// Builds an image block, sniffing the MIME type from a data URI or from the
  /// leading bytes of a bare base64 payload.
  static Map<String, dynamic> _imageBlock(String imageData) {
    String mimeType = 'image/jpeg';
    String data = imageData;

    if (imageData.startsWith('data:')) {
      final commaIdx = imageData.indexOf(',');
      if (commaIdx != -1) {
        final header = imageData.substring(5, commaIdx);
        final semicolonIdx = header.indexOf(';');
        if (semicolonIdx != -1) {
          mimeType = header.substring(0, semicolonIdx);
        }
        data = imageData.substring(commaIdx + 1);
      }
    } else if (imageData.startsWith('/9j/')) {
      mimeType = 'image/jpeg';
    } else if (imageData.startsWith('iVBORw0KGgo')) {
      mimeType = 'image/png';
    } else if (imageData.startsWith('R0lGOD')) {
      mimeType = 'image/gif';
    } else if (imageData.startsWith('UklGR')) {
      mimeType = 'image/webp';
    }

    return <String, dynamic>{
      'type': 'image',
      'mime_type': mimeType,
      'data': data,
    };
  }
}
