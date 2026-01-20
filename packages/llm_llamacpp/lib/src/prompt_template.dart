import 'package:llm_core/llm_core.dart';

/// Abstract base class for prompt templates.
///
/// Prompt templates convert a list of LLM messages into the format
/// expected by a specific model.
abstract class PromptTemplate {
  /// The name of this template.
  String get name;

  /// Formats the messages into a prompt string.
  String format(List<LLMMessage> messages);

  /// Returns the stop tokens for this template.
  List<String> get stopTokens;
}

/// ChatML template used by many models (Qwen, OpenHermes, etc.)
class ChatMLTemplate extends PromptTemplate {
  @override
  String get name => 'chatml';

  @override
  String format(List<LLMMessage> messages) {
    final buffer = StringBuffer();

    for (final message in messages) {
      final role = switch (message.role) {
        LLMRole.system => 'system',
        LLMRole.user => 'user',
        LLMRole.assistant => 'assistant',
        LLMRole.tool => 'tool',
      };
      buffer.writeln('<|im_start|>$role');
      buffer.writeln(message.content ?? '');
      buffer.writeln('<|im_end|>');
    }

    // Add start of assistant response
    buffer.write('<|im_start|>assistant\n');

    return buffer.toString();
  }

  @override
  List<String> get stopTokens => ['<|im_end|>', '<|im_start|>'];
}

/// Llama 2 chat template.
class Llama2Template extends PromptTemplate {
  @override
  String get name => 'llama2';

  @override
  String format(List<LLMMessage> messages) {
    final buffer = StringBuffer();

    String? systemPrompt;
    final conversationMessages = <LLMMessage>[];

    // Separate system prompt from conversation
    for (final message in messages) {
      if (message.role == LLMRole.system) {
        systemPrompt = message.content;
      } else {
        conversationMessages.add(message);
      }
    }

    // Format conversation with system prompt in first turn
    for (var i = 0; i < conversationMessages.length; i++) {
      final message = conversationMessages[i];

      if (message.role == LLMRole.user) {
        buffer.write('<s>[INST] ');
        if (i == 0 && systemPrompt != null) {
          buffer.write('<<SYS>>\n$systemPrompt\n<</SYS>>\n\n');
        }
        buffer.write('${message.content ?? ''} [/INST]');
      } else if (message.role == LLMRole.assistant) {
        buffer.write(' ${message.content ?? ''} </s>');
      }
    }

    return buffer.toString();
  }

  @override
  List<String> get stopTokens => ['</s>', '[INST]'];
}

/// Llama 3 chat template.
class Llama3Template extends PromptTemplate {
  @override
  String get name => 'llama3';

  @override
  String format(List<LLMMessage> messages) {
    final buffer = StringBuffer();
    buffer.write('<|begin_of_text|>');

    for (final message in messages) {
      final role = switch (message.role) {
        LLMRole.system => 'system',
        LLMRole.user => 'user',
        LLMRole.assistant => 'assistant',
        LLMRole.tool => 'ipython',
      };

      buffer.write('<|start_header_id|>$role<|end_header_id|>\n\n');
      buffer.write(message.content ?? '');
      buffer.write('<|eot_id|>');
    }

    // Add start of assistant response
    buffer.write('<|start_header_id|>assistant<|end_header_id|>\n\n');

    return buffer.toString();
  }

  @override
  List<String> get stopTokens => [
    '<|eot_id|>',
    '<|end_of_text|>',
    '<|start_header_id|>',
  ];
}

/// Alpaca template.
class AlpacaTemplate extends PromptTemplate {
  @override
  String get name => 'alpaca';

  @override
  String format(List<LLMMessage> messages) {
    final buffer = StringBuffer();

    String? systemPrompt;
    String? userInput;

    for (final message in messages) {
      switch (message.role) {
        case LLMRole.system:
          systemPrompt = message.content;
          break;
        case LLMRole.user:
          userInput = message.content;
          break;
        case LLMRole.assistant:
          // Include previous assistant responses
          if (userInput != null) {
            if (systemPrompt != null) {
              buffer.writeln(systemPrompt);
              buffer.writeln();
            }
            buffer.writeln('### Instruction:');
            buffer.writeln(userInput);
            buffer.writeln();
            buffer.writeln('### Response:');
            buffer.writeln(message.content ?? '');
            buffer.writeln();
            userInput = null;
          }
          break;
        case LLMRole.tool:
          // Alpaca doesn't have native tool support
          break;
      }
    }

    // Add final instruction if not responded to
    if (userInput != null) {
      if (systemPrompt != null) {
        buffer.writeln(systemPrompt);
        buffer.writeln();
      }
      buffer.writeln('### Instruction:');
      buffer.writeln(userInput);
      buffer.writeln();
      buffer.writeln('### Response:');
    }

    return buffer.toString();
  }

  @override
  List<String> get stopTokens => ['### Instruction:', '###'];
}

/// Vicuna template.
class VicunaTemplate extends PromptTemplate {
  @override
  String get name => 'vicuna';

  @override
  String format(List<LLMMessage> messages) {
    final buffer = StringBuffer();

    for (final message in messages) {
      switch (message.role) {
        case LLMRole.system:
          buffer.writeln(message.content ?? '');
          buffer.writeln();
          break;
        case LLMRole.user:
          buffer.write('USER: ${message.content ?? ''}\n');
          break;
        case LLMRole.assistant:
          buffer.write('ASSISTANT: ${message.content ?? ''}</s>\n');
          break;
        case LLMRole.tool:
          // Vicuna doesn't have native tool support
          break;
      }
    }

    buffer.write('ASSISTANT:');
    return buffer.toString();
  }

  @override
  List<String> get stopTokens => ['</s>', 'USER:'];
}

/// Phi-3 template.
class Phi3Template extends PromptTemplate {
  @override
  String get name => 'phi3';

  @override
  String format(List<LLMMessage> messages) {
    final buffer = StringBuffer();

    for (final message in messages) {
      final role = switch (message.role) {
        LLMRole.system => 'system',
        LLMRole.user => 'user',
        LLMRole.assistant => 'assistant',
        LLMRole.tool => 'user', // Phi-3 doesn't have native tool role
      };

      buffer.write('<|$role|>\n');
      buffer.write(message.content ?? '');
      buffer.write('<|end|>\n');
    }

    buffer.write('<|assistant|>\n');
    return buffer.toString();
  }

  @override
  List<String> get stopTokens => ['<|end|>', '<|user|>', '<|assistant|>'];
}

/// Raw template that just concatenates messages.
class RawTemplate extends PromptTemplate {
  @override
  String get name => 'raw';

  @override
  String format(List<LLMMessage> messages) {
    return messages.map((m) => m.content ?? '').join('\n');
  }

  @override
  List<String> get stopTokens => [];
}

/// Gets the appropriate template for a model name.
PromptTemplate getTemplateForModel(String modelName) {
  final lowerName = modelName.toLowerCase();

  if (lowerName.contains('llama-3') || lowerName.contains('llama3')) {
    return Llama3Template();
  } else if (lowerName.contains('llama-2') || lowerName.contains('llama2')) {
    return Llama2Template();
  } else if (lowerName.contains('chatml') ||
      lowerName.contains('qwen') ||
      lowerName.contains('openhermes') ||
      lowerName.contains('mistral')) {
    return ChatMLTemplate();
  } else if (lowerName.contains('alpaca')) {
    return AlpacaTemplate();
  } else if (lowerName.contains('vicuna')) {
    return VicunaTemplate();
  } else if (lowerName.contains('phi-3') || lowerName.contains('phi3')) {
    return Phi3Template();
  }

  // Default to ChatML as it's widely compatible
  return ChatMLTemplate();
}
