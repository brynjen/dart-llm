part of 'persistent_inference_isolate.dart';

String _applyNativeChatTemplate(
  LlamaBindings bindings,
  ffi.Pointer<llama_model> model,
  List<IsolateMessage> messages, {
  List<String> toolSchemasJson = const [],
}) {
  // Retrieve the chat template stored in the GGUF metadata. Despite what the
  // doc-comment on `llama_chat_apply_template` claims, passing nullptr there
  // does NOT consult the model — upstream falls back to a literal "chatml"
  // string, which is wrong for many models (e.g. LFM2.5). We must explicitly
  // fetch the model's template via `llama_model_chat_template` and pass it.
  // The returned pointer is owned by the model and must NOT be freed.
  final templatePtr = bindings.llama_model_chat_template(model, ffi.nullptr);
  final hasTemplate = templatePtr.address != 0;

  String? templateSource;
  if (hasTemplate) {
    try {
      final templateStr = templatePtr.cast<Utf8>().toDartString();
      templateSource = templateStr;
      final preview = templateStr.length > 200
          ? '${templateStr.substring(0, 200)}...'
          : templateStr;
      // ignore: avoid_print
      print(
        '[native_template_applier] Using model chat template (${templateStr.length} chars): $preview',
      );
    } catch (_) {
      // ignore: avoid_print
      print(
        '[native_template_applier] Model returned a chat template pointer but it could not be decoded as UTF-8',
      );
    }
  } else {
    // ignore: avoid_print
    print(
      '[native_template_applier] WARNING: model has no embedded chat template; '
      'falling back to llama.cpp default ("chatml"). Output may be malformed.',
    );
  }

  // The C chat-template API takes only role/content pairs, so a template's
  // `{%- if tools -%}` branch can never fire from here. Write the tool list into
  // the system message ourselves, in the shape this model's template would have
  // produced, so the model sees the format it was fine-tuned on.
  final toolFormat = _detectToolCallFormat(bindings, model, templateSource);
  messages = injectToolDefinitions(
    messages,
    toolSchemasJson,
    format: toolFormat,
  );
  if (toolSchemasJson.isNotEmpty) {
    // ignore: avoid_print
    print(
      '[native_template_applier] Advertised ${toolSchemasJson.length} tool(s) '
      'as ${toolFormat.name}',
    );
  }

  final chatMessages = calloc<llama_chat_message>(messages.length);
  final allocatedPointers = <ffi.Pointer<Utf8>>[];

  try {
    for (var i = 0; i < messages.length; i++) {
      final msg = messages[i];
      final rolePtr = msg.role.toNativeUtf8();
      final contentPtr = msg.content.toNativeUtf8();
      allocatedPointers.add(rolePtr);
      allocatedPointers.add(contentPtr);

      chatMessages[i].role = rolePtr.cast();
      chatMessages[i].content = contentPtr.cast();
    }

    final tmplArg = hasTemplate ? templatePtr : ffi.nullptr;

    final requiredSize = bindings.llama_chat_apply_template(
      tmplArg,
      chatMessages,
      messages.length,
      true,
      ffi.nullptr,
      0,
    );

    if (requiredSize <= 0) {
      // ignore: avoid_print
      print(
        '[native_template_applier] llama_chat_apply_template sizing call '
        'returned $requiredSize; using internal fallback formatter',
      );
      return _fallbackFormatMessages(messages);
    }

    final buffer = calloc<ffi.Char>(requiredSize + 1);
    try {
      final actualSize = bindings.llama_chat_apply_template(
        tmplArg,
        chatMessages,
        messages.length,
        true,
        buffer,
        requiredSize + 1,
      );

      if (actualSize <= 0) {
        // ignore: avoid_print
        print(
          '[native_template_applier] llama_chat_apply_template render call '
          'returned $actualSize; using internal fallback formatter',
        );
        return _fallbackFormatMessages(messages);
      }

      final formatted = buffer.cast<Utf8>().toDartString(length: actualSize);
      final formattedPreview = formatted.length > 200
          ? '${formatted.substring(0, 200)}...'
          : formatted;
      // ignore: avoid_print
      print(
        '[native_template_applier] Formatted prompt (${formatted.length} chars): $formattedPreview',
      );
      return formatted;
    } finally {
      calloc.free(buffer);
    }
  } finally {
    for (final ptr in allocatedPointers) {
      calloc.free(ptr);
    }
    calloc.free(chatMessages);
  }
}

String _fallbackFormatMessages(List<IsolateMessage> messages) {
  final buffer = StringBuffer();
  for (final msg in messages) {
    buffer.writeln('<|im_start|>${msg.role}');
    buffer.writeln(msg.content);
    buffer.writeln('<|im_end|>');
  }
  buffer.write('<|im_start|>assistant\n');
  return buffer.toString();
}
