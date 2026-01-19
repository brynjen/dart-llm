// ignore_for_file: deprecated_member_use_from_same_package, deprecated_member_use, avoid_print

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
  bool _toolsEnabled = true;
  String? _errorMessage;
  String _currentResponse = '';
  
  // Available tools
  final List<LLMTool> _tools = [CalculatorTool()];

  @override
  void initState() {
    super.initState();
    _initializeModel();
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
      print('[ChatScreen] Creating LlamaCppChatRepository...');
      _chatRepo = LlamaCppChatRepository(
        contextSize: 2048,
        nGpuLayers: 0, // CPU-only with hardware acceleration (KleidiAI, SME2)
      );
      
      print('[ChatScreen] Loading model from: ${widget.modelPath}');
      await _chatRepo!.loadModel(widget.modelPath);
      print('[ChatScreen] Model loaded successfully!');
      
      setState(() {
        _isLoading = false;
      });
      
      // Add welcome message
      _messages.add(_ChatMessage(
        role: _MessageRole.system,
        content: 'Model loaded! Tools are enabled. Try: "What is 15 multiplied by 7?"',
      ));
    } catch (e, stackTrace) {
      print('[ChatScreen] ERROR loading model: $e');
      print('[ChatScreen] Stack trace: $stackTrace');
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load model: $e';
      });
    }
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
      final systemPrompt = _toolsEnabled
          ? '''You are a helpful assistant with access to tools.

Available tools:
- calculator: Performs basic math operations (add, subtract, multiply, divide)

When you need to perform calculations, use the calculator tool by responding with JSON in this format:
{"name": "calculator", "arguments": {"operation": "multiply", "a": 15, "b": 7}}

After receiving the tool result, provide a natural language response to the user.'''
          : 'You are a helpful assistant. Answer questions concisely and accurately.';
      
      final llmMessages = <LLMMessage>[
        LLMMessage(
          role: LLMRole.system,
          content: systemPrompt,
        ),
      ];
      
      // Add conversation history (last 10 messages)
      final historyMessages = _messages
          .where((m) => m.role != _MessageRole.system)
          .toList();
      final recentMessages = historyMessages.length > 10 
          ? historyMessages.sublist(historyMessages.length - 10)
          : historyMessages;
      
      for (final msg in recentMessages) {
        llmMessages.add(LLMMessage(
          role: msg.role == _MessageRole.user ? LLMRole.user : LLMRole.assistant,
          content: msg.content,
        ));
      }

      // Stream the response
      final stream = _chatRepo!.streamChat(
        widget.modelPath,
        messages: llmMessages,
        tools: _toolsEnabled ? _tools : [],
      );

      await for (final chunk in stream) {
        final content = chunk.message?.content ?? '';
        setState(() {
          _currentResponse += content;
        });
        _scrollToBottom();
      }

      // Add the complete response to messages
      setState(() {
        _messages.add(_ChatMessage(
          role: _MessageRole.assistant,
          content: _currentResponse,
        ));
        _currentResponse = '';
        _isGenerating = false;
      });
    } catch (e) {
      setState(() {
        _isGenerating = false;
        _messages.add(_ChatMessage(
          role: _MessageRole.system,
          content: 'Error: $e',
        ));
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
                  content: Text(_toolsEnabled ? 'Tools enabled' : 'Tools disabled'),
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
                    Text(
                      'Loading model...',
                      style: theme.textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'This may take a moment',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
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
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
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
                          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                          border: Border(
                            top: BorderSide(
                              color: theme.colorScheme.outline.withValues(alpha: 0.2),
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
                                    fillColor: theme.colorScheme.surfaceContainerHighest,
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

enum _MessageRole { user, assistant, system }

class _ChatMessage {
  final _MessageRole role;
  final String content;

  _ChatMessage({required this.role, required this.content});
}

class _MessageBubble extends StatelessWidget {
  final _ChatMessage message;
  final bool isStreaming;

  const _MessageBubble({
    required this.message,
    this.isStreaming = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = message.role == _MessageRole.user;
    final isSystem = message.role == _MessageRole.system;

    if (isSystem) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
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
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
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
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
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

