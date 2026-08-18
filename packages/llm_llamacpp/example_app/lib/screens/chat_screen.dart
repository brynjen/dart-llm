// ignore_for_file: deprecated_member_use_from_same_package, deprecated_member_use, avoid_print

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:llm_llamacpp/llm_llamacpp.dart';

import '../tools/calculator_tool.dart';

class ChatScreen extends StatefulWidget {
  final String modelPath;

  const ChatScreen({super.key, required this.modelPath});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<_ChatMessage> _messages = [];

  LlamaCppChatRepository? _chatRepo;
  bool _isLoading = true;
  bool _isGenerating = false;
  // Default tools OFF: the tools-on system prompt asks the model for JSON,
  // and the current ToolCallStreamHandler buffers everything between `{` and
  // a balanced `}`. For long prose answers that contain a stray `{` (or for
  // models that never emit balanced JSON) this prevents any streaming chunk
  // from reaching the UI. Toggle the build/build_outlined icon to enable.
  bool _toolsEnabled = false;
  bool _gpuEnabled = false;
  String? _errorMessage;
  String _currentResponse = '';

  // Number of layers to offload to GPU when GPU is enabled. 99 effectively
  // means "all layers"; llama.cpp will silently clamp to the model's depth.
  static const int _gpuLayersWhenEnabled = 99;

  // Available tools. Built in initState because the calculator reports its
  // invocations back to this State so they can be rendered.
  late final List<LLMTool> _tools;

  /// Tool-call bubbles that are waiting for their result, oldest first.
  final List<_ChatMessage> _pendingToolCalls = [];

  /// The raw text of the assistant turn that issued the pending tool calls.
  String? _pendingRawAssistantTurn;

  @override
  void initState() {
    super.initState();
    _tools = [CalculatorTool(onInvoke: _onToolInvoked)];
    _initializeModel();
  }

  /// Attaches a tool's result to the bubble that requested it.
  ///
  /// Calls execute in order, so the oldest bubble still awaiting a result for
  /// this tool is the right one.
  void _onToolInvoked(Map<String, dynamic> args, String result) {
    final index = _pendingToolCalls.indexWhere(
      (m) => m.toolName == 'calculator' && m.toolResult == null,
    );
    if (index < 0) return;
    final bubble = _pendingToolCalls.removeAt(index);
    if (!mounted) return;
    setState(() {
      bubble.toolResult = result;
      // The bubble doubles as the history record: the raw assistant turn that
      // issued the call, and the result that came back.
      bubble.rawContent = _pendingRawAssistantTurn;
    });
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _chatRepo?.dispose();
    super.dispose();
  }

  Future<void> _initializeModel() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Dispose any previous repo so the persistent inference isolate is told
      // to drop the old context. The repo itself is cheap; the model is only
      // loaded on the next streamChat call.
      _chatRepo?.dispose();
      final nGpuLayers = _gpuEnabled ? _gpuLayersWhenEnabled : 0;
      print(
        '[ChatScreen] Creating LlamaCppChatRepository '
        '(nGpuLayers=$nGpuLayers, gpuEnabled=$_gpuEnabled)...',
      );
      // Use withModelPath for Android compatibility - the model will be loaded
      // in the inference isolate, not the main isolate. This avoids FFI issues
      // that occur when llama.cpp is called from multiple Dart isolates.
      // If GPU offload fails at runtime (e.g. Vulkan driver missing on this
      // device), llama.cpp will fall back to CPU automatically.
      _chatRepo = LlamaCppChatRepository.withModelPath(
        widget.modelPath,
        contextSize: 2048,
        nGpuLayers: nGpuLayers,
      );
      print('[ChatScreen] Repository ready (model will load on first chat)');

      setState(() {
        _isLoading = false;
      });

      final toolsHint = _toolsEnabled
          ? 'Tools enabled (calculator). Try: "What is 15 multiplied by 7?"'
          : 'Tools disabled. Toggle the wrench icon to enable tool calling.';
      _messages.add(
        _ChatMessage(
          role: _MessageRole.system,
          content: _gpuEnabled
              ? 'Model loaded with GPU offload requested ($_gpuLayersWhenEnabled layers). '
                    'On Android arm64-v8a this uses the Vulkan backend if libggml-vulkan.so '
                    'is bundled and the device driver supports it; otherwise it silently '
                    'falls back to CPU.\n$toolsHint'
              : 'Model loaded (CPU only). $toolsHint',
        ),
      );
    } catch (e, stackTrace) {
      print('[ChatScreen] ERROR loading model: $e');
      print('[ChatScreen] Stack trace: $stackTrace');
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load model: $e';
      });
    }
  }

  Future<void> _toggleGpu() async {
    if (_isGenerating || _isLoading) return;
    setState(() {
      _gpuEnabled = !_gpuEnabled;
      _messages.clear();
    });
    await _initializeModel();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _isGenerating || _chatRepo == null) return;

    _inputController.clear();

    setState(() {
      _messages.add(_ChatMessage(role: _MessageRole.user, content: text));
      _isGenerating = true;
      _currentResponse = '';
    });
    _scrollToBottom();

    try {
      // Build message history for the model
      // No tool syntax in the prompt: llm_llamacpp advertises the tools it was
      // given in whatever format the loaded model's chat template expects, and
      // parses the calls back out. Hand-writing a JSON example here used to
      // fight the model's own trained format.
      const systemPrompt =
          'You are a helpful assistant. Answer questions concisely and accurately. Numbers should never be formatted.';

      final llmMessages = <LLMMessage>[
        LLMMessage(role: LLMRole.system, content: systemPrompt),
      ];

      // Add conversation history (last 10 messages)
      final historyMessages = _messages
          .where((m) => m.role != _MessageRole.system)
          .toList();
      // Keep a bounded window, but never start it inside a tool exchange. A
      // blind tail slice can begin at a tool-call bubble or its result, which
      // renders as a `tool` turn with no assistant call before it — a shape the
      // model never saw in training. A tool turn now costs several entries
      // (narration, call, answer), so this is reached quickly in real use.
      var recentMessages = historyMessages.length > 12
          ? historyMessages.sublist(historyMessages.length - 12)
          : historyMessages;
      final firstUser = recentMessages.indexWhere(
        (m) => m.role == _MessageRole.user,
      );
      recentMessages = firstUser <= 0
          ? recentMessages
          : recentMessages.sublist(firstUser);

      // Rebuild the shape LiquidAI documents for tool use:
      //   system(tools) -> user -> assistant(with call) -> tool(result) -> assistant
      // A tool-call bubble expands into two messages, because the model has to
      // see both that it made the call and what came back. Dropping them makes
      // the history show an assistant announcing a tool and then answering
      // without calling one, which the model copies on the next turn and stops
      // calling tools at all.
      for (final msg in recentMessages) {
        switch (msg.role) {
          case _MessageRole.user:
            llmMessages.add(
              LLMMessage(role: LLMRole.user, content: msg.content),
            );
          case _MessageRole.assistant:
            if (!msg.displayOnly) {
              llmMessages.add(
                LLMMessage(role: LLMRole.assistant, content: msg.content),
              );
            }
          case _MessageRole.toolCall:
            final raw = msg.rawContent;
            if (raw != null && raw.isNotEmpty) {
              llmMessages.add(
                LLMMessage(role: LLMRole.assistant, content: raw),
              );
            }
            final result = msg.toolResult;
            if (result != null) {
              llmMessages.add(
                LLMMessage(
                  role: LLMRole.tool,
                  content: result,
                  toolCallId: msg.toolCallId,
                ),
              );
            }
          case _MessageRole.system:
            break;
        }
      }

      // Stream the response
      final stream = _chatRepo!.streamChat(
        widget.modelPath,
        messages: llmMessages,
        tools: _toolsEnabled ? _tools : [],
      );

      await for (final chunk in stream) {
        final content = chunk.message?.content ?? '';
        final toolCalls = chunk.message?.toolCalls;

        setState(() {
          _currentResponse += content;

          if (toolCalls != null && toolCalls.isNotEmpty) {
            // The model is about to call a tool. Close off whatever it said
            // first, so the transcript reads text -> call -> text rather than
            // collapsing both turns into one bubble.
            if (_currentResponse.trim().isNotEmpty) {
              _messages.add(
                _ChatMessage(
                  role: _MessageRole.assistant,
                  content: _currentResponse.trim(),
                  displayOnly: true,
                ),
              );
            }
            _currentResponse = '';

            // Keep the turn as the model wrote it — markup included — so the
            // next request can replay a faithful history.
            _pendingRawAssistantTurn = chunk.message?.rawContent;

            for (final call in toolCalls) {
              final bubble = _ChatMessage(
                role: _MessageRole.toolCall,
                content: '',
                toolName: call.name,
                toolArguments: call.arguments,
                toolCallId: call.id,
              );
              _messages.add(bubble);
              _pendingToolCalls.add(bubble);
            }
          }
        });
        _scrollToBottom();
      }

      // Add whatever text is left over as the final answer.
      setState(() {
        if (_currentResponse.trim().isNotEmpty) {
          _messages.add(
            _ChatMessage(
              role: _MessageRole.assistant,
              content: _currentResponse.trim(),
            ),
          );
        }
        _currentResponse = '';
        _isGenerating = false;
        _pendingToolCalls.clear();
      });
    } catch (e, stackTrace) {
      print('[ChatScreen] ERROR during chat: $e');
      print('[ChatScreen] Stack trace: $stackTrace');
      setState(() {
        _isGenerating = false;
        _messages.add(
          _ChatMessage(role: _MessageRole.system, content: 'Error: $e'),
        );
      });
    }
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          // GPU toggle (CPU vs GPU offload). On Android arm64-v8a with a
          // Vulkan-capable driver this routes inference through libggml-vulkan.so.
          IconButton(
            icon: Icon(
              _gpuEnabled ? Icons.bolt : Icons.bolt_outlined,
              color: _gpuEnabled ? theme.colorScheme.primary : null,
            ),
            onPressed: (_isLoading || _isGenerating) ? null : _toggleGpu,
            tooltip: _gpuEnabled
                ? 'Disable GPU (use CPU)'
                : 'Enable GPU offload (Vulkan on Android arm64)',
          ),
          // Tools toggle
          IconButton(
            icon: Icon(
              _toolsEnabled ? Icons.build : Icons.build_outlined,
              color: _toolsEnabled ? theme.colorScheme.primary : null,
            ),
            onPressed: () {
              setState(() {
                _toolsEnabled = !_toolsEnabled;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    _toolsEnabled ? 'Tools enabled' : 'Tools disabled',
                  ),
                  duration: const Duration(seconds: 1),
                ),
              );
            },
            tooltip: _toolsEnabled ? 'Disable tools' : 'Enable tools',
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () {
              setState(() {
                _messages.clear();
              });
            },
            tooltip: 'Clear chat',
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              theme.colorScheme.surface,
              theme.colorScheme.surfaceContainerLowest,
            ],
          ),
        ),
        child: _isLoading
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text('Loading model...', style: theme.textTheme.bodyLarge),
                    const SizedBox(height: 8),
                    Text(
                      'This may take a moment',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.6,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            : _errorMessage != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 64,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Failed to load model',
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _errorMessage!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.7,
                          ),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('Go Back'),
                      ),
                    ],
                  ),
                ),
              )
            : Column(
                children: [
                  // Messages list
                  Expanded(
                    child: ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: _messages.length + (_isGenerating ? 1 : 0),
                      itemBuilder: (context, index) {
                        // Show streaming response
                        if (index == _messages.length && _isGenerating) {
                          return _MessageBubble(
                            message: _ChatMessage(
                              role: _MessageRole.assistant,
                              content: _currentResponse.isEmpty
                                  ? '...'
                                  : _currentResponse,
                            ),
                            isStreaming: true,
                          );
                        }
                        return _MessageBubble(message: _messages[index]);
                      },
                    ),
                  ),

                  // Input area
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.5),
                      border: Border(
                        top: BorderSide(
                          color: theme.colorScheme.outline.withValues(
                            alpha: 0.2,
                          ),
                        ),
                      ),
                    ),
                    child: SafeArea(
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _inputController,
                              decoration: InputDecoration(
                                hintText: 'Type a message...',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(24),
                                  borderSide: BorderSide.none,
                                ),
                                filled: true,
                                fillColor:
                                    theme.colorScheme.surfaceContainerHighest,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 12,
                                ),
                              ),
                              textInputAction: TextInputAction.send,
                              onSubmitted: (_) => _sendMessage(),
                              enabled: !_isGenerating,
                            ),
                          ),
                          const SizedBox(width: 12),
                          IconButton.filled(
                            onPressed: _isGenerating ? null : _sendMessage,
                            icon: _isGenerating
                                ? SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: theme.colorScheme.onPrimary,
                                    ),
                                  )
                                : const Icon(Icons.send),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

enum _MessageRole { user, assistant, system, toolCall }

class _ChatMessage {
  _ChatMessage({
    required this.role,
    required this.content,
    this.toolName,
    this.toolArguments,
    this.toolCallId,
    this.displayOnly = false,
  });

  final _MessageRole role;
  final String content;

  /// Set for [_MessageRole.toolCall]: the tool the model asked for.
  final String? toolName;

  /// The raw JSON arguments the model supplied.
  final String? toolArguments;

  /// Id of the call, so the tool result can name what it answers.
  ///
  /// `Validation.validateMessages` in llm_core rejects a tool message without
  /// one, so replaying a tool exchange requires keeping it.
  final String? toolCallId;

  /// Rendered in the transcript but withheld from the history sent to the model.
  ///
  /// Set on the text an assistant emitted before a tool call: the tool-call
  /// bubble's [rawContent] already contains that text along with the call
  /// markup, so sending both would repeat it.
  final bool displayOnly;

  /// Filled in once the tool has run. Mutable, and not a constructor argument,
  /// because llm_llamacpp yields the call before it executes it: the bubble is
  /// created first and the result lands a moment later.
  String? toolResult;

  /// For an assistant turn that called a tool: the turn as the model wrote it,
  /// including the tool-call markup. Sent back as history instead of [content].
  ///
  /// LiquidAI documents the required shape as
  /// system(tools) -> user -> assistant(with call) -> tool(result) -> assistant.
  /// Replaying only the visible text breaks that: the model then sees itself
  /// announce a tool and answer without calling one, and stops calling tools on
  /// later turns.
  String? rawContent;
}

class _MessageBubble extends StatelessWidget {
  final _ChatMessage message;
  final bool isStreaming;

  const _MessageBubble({required this.message, this.isStreaming = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = message.role == _MessageRole.user;
    final isSystem = message.role == _MessageRole.system;

    if (message.role == _MessageRole.toolCall) {
      return _ToolCallBubble(message: message);
    }

    if (isSystem) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.5,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              message.content,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Icon(
                Icons.smart_toy,
                size: 18,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isUser
                    ? theme.colorScheme.primary
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isUser ? 18 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 18),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Flexible(
                    child: Text(
                      message.content,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: isUser
                            ? theme.colorScheme.onPrimary
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  if (isStreaming) ...[
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.5,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 16,
              backgroundColor: theme.colorScheme.secondaryContainer,
              child: Icon(
                Icons.person,
                size: 18,
                color: theme.colorScheme.secondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Shows a tool call the model made, and its result once the tool has run.
///
/// Styled like a "thinking" aside rather than a chat message: the model asking
/// for a calculation is part of how it reached the answer, not something it said
/// to the user.
class _ToolCallBubble extends StatelessWidget {
  const _ToolCallBubble({required this.message});

  final _ChatMessage message;

  /// Renders the raw JSON arguments as `key: value` pairs.
  ///
  /// Raw JSON wraps mid-key on a phone-width bubble, which is hard to read.
  /// Falls back to the original string if the model sent something unparseable.
  static String _formatArgs(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return raw;
      return decoded.entries.map((e) => '${e.key}: ${e.value}').join(', ');
    } catch (_) {
      return raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subdued = theme.colorScheme.onSurface.withValues(alpha: 0.6);
    final mono = theme.textTheme.bodySmall?.copyWith(
      fontFamily: 'monospace',
      color: subdued,
      height: 1.4,
    );
    final pending = message.toolResult == null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(width: 40),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.35,
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.colorScheme.outline.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        pending ? Icons.hourglass_top : Icons.build,
                        size: 14,
                        color: subdued,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        pending ? 'Calling tool' : 'Tool call',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: subdued,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${message.toolName}(${_formatArgs(message.toolArguments)})',
                    style: mono,
                  ),
                  if (message.toolResult != null) ...[
                    const SizedBox(height: 4),
                    Text('\u2192 ${message.toolResult}', style: mono),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
