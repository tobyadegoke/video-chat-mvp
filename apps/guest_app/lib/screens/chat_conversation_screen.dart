import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/chat_service.dart';

class ChatConversationScreen extends StatefulWidget {
  final String conversationId;
  final String hostId;
  final String name;
  final String imageUrl;

  const ChatConversationScreen({
    super.key,
    required this.conversationId,
    required this.hostId,
    required this.name,
    required this.imageUrl,
  });

  @override
  State<ChatConversationScreen> createState() => _ChatConversationScreenState();
}

class _ChatConversationScreenState extends State<ChatConversationScreen> {
  final ChatService _chatService = ChatService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final List<_Message> _messages = [];

  RealtimeChannel? _messagesChannel;

  bool _isLoading = true;
  bool _isSending = false;
  bool _showEmojiPicker = false;
  String? _error;

  String? get _currentUserId => Supabase.instance.client.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _subscribeToMessages();
  }

  Future<void> _loadMessages() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final messages = await _chatService.getMessages(widget.conversationId);

      if (!mounted) return;

      setState(() {
        _messages
          ..clear()
          ..addAll(
            messages.map(
              (message) => _Message(
                id: message['id'] as String,
                senderId: message['sender_id'] as String,
                message: message['message'] as String,
                createdAt: DateTime.parse(message['created_at'] as String),
              ),
            ),
          );
        _isLoading = false;
      });

      await _markConversationAsRead();

      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _markConversationAsRead() async {
    try {
      await _chatService.markConversationAsRead(widget.conversationId);
    } catch (_) {
      // Reading messages should not prevent the conversation
      // from functioning if the read-state update fails.
    }
  }

  void _subscribeToMessages() {
    _messagesChannel = _chatService.subscribeToMessages(
      conversationId: widget.conversationId,
      onMessage: (message) async {
        if (!mounted) return;

        final added = _addMessage(message);

        if (!added) return;

        await _markConversationAsRead();

        _scrollToBottom();
      },
    );
  }

  bool _addMessage(Map<String, dynamic> message) {
    final id = message['id'] as String?;

    if (id == null || id.isEmpty) {
      return false;
    }

    final alreadyExists = _messages.any(
      (existingMessage) => existingMessage.id == id,
    );

    if (alreadyExists) {
      return false;
    }

    final createdAtString = message['created_at'] as String?;

    if (createdAtString == null) {
      return false;
    }

    setState(() {
      _messages.add(
        _Message(
          id: id,
          senderId: message['sender_id'] as String,
          message: message['message'] as String,
          createdAt: DateTime.parse(createdAtString),
        ),
      );
    });

    return true;
  }

  String _formatMessageTime(DateTime dateTime) {
    final local = dateTime.toLocal();

    final hour = local.hour == 0
        ? 12
        : local.hour > 12
        ? local.hour - 12
        : local.hour;

    final minute = local.minute.toString().padLeft(2, '0');
    final period = local.hour >= 12 ? 'PM' : 'AM';

    return '$hour:$minute $period';
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();

    if (text.isEmpty || _isSending) {
      return;
    }

    setState(() {
      _isSending = true;
    });

    try {
      final message = await _chatService.sendMessage(
        conversationId: widget.conversationId,
        message: text,
      );

      if (!mounted) return;

      _messageController.clear();

      // Add immediately so the sender does not have to wait
      // for the Realtime event.
      _addMessage(message);

      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not send message: $e')));
    }

    if (!mounted) return;

    setState(() {
      _isSending = false;
    });
  }

  void _toggleEmojiPicker() {
    FocusScope.of(context).unfocus();

    setState(() {
      _showEmojiPicker = !_showEmojiPicker;
    });
  }

  void _openKeyboard() {
    if (_showEmojiPicker) {
      setState(() {
        _showEmojiPicker = false;
      });
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) {
        return;
      }

      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  void _showCallMessage(String type) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$type calling is not connected yet.')),
    );
  }

  @override
  void dispose() {
    if (_messagesChannel != null) {
      _chatService.unsubscribeFromMessages(_messagesChannel!);
    }

    _messageController.dispose();
    _scrollController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundImage: widget.imageUrl.isNotEmpty
                  ? NetworkImage(widget.imageUrl)
                  : null,
              child: widget.imageUrl.isEmpty ? const Icon(Icons.person) : null,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(widget.name, overflow: TextOverflow.ellipsis)),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () => _showCallMessage('Audio'),
            icon: const Icon(Icons.call_outlined),
            tooltip: 'Audio call',
          ),
          IconButton(
            onPressed: () => _showCallMessage('Video'),
            icon: const Icon(Icons.videocam_outlined),
            tooltip: 'Video call',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildMessages()),
          _buildMessageComposer(),
          if (_showEmojiPicker) _buildEmojiPicker(),
        ],
      ),
    );
  }

  Widget _buildMessages() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.white54),
              const SizedBox(height: 12),
              const Text(
                'Could not load messages.',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white60),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadMessages,
                child: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }

    if (_messages.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.chat_bubble_outline, size: 56, color: Colors.white38),
              SizedBox(height: 16),
              Text(
                'No messages yet',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                'Send a message to start the conversation.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white60),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];

        final isMine = message.senderId == _currentUserId;

        return _MessageBubble(
          message: message.message,
          time: _formatMessageTime(message.createdAt),
          isMine: isMine,
        );
      },
    );
  }

  Widget _buildMessageComposer() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton(
              onPressed: _toggleEmojiPicker,
              icon: Icon(
                _showEmojiPicker
                    ? Icons.keyboard_outlined
                    : Icons.emoji_emotions_outlined,
              ),
              tooltip: _showEmojiPicker ? 'Show keyboard' : 'Add emoji',
            ),
            Expanded(
              child: TextField(
                controller: _messageController,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.newline,
                onTap: _openKeyboard,
                decoration: InputDecoration(
                  hintText: 'Message ${widget.name}...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                ),
                onSubmitted: (_) {
                  if (!_isSending) {
                    _sendMessage();
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: _isSending ? null : _sendMessage,
              icon: _isSending
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
              tooltip: 'Send',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmojiPicker() {
    return SizedBox(
      height: 280,
      child: EmojiPicker(
        textEditingController: _messageController,
        config: Config(
          height: 280,
          checkPlatformCompatibility: true,
          emojiViewConfig: EmojiViewConfig(
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            emojiSizeMax: 28,
          ),
        ),
      ),
    );
  }
}

class _Message {
  final String id;
  final String senderId;
  final String message;
  final DateTime createdAt;

  const _Message({
    required this.id,
    required this.senderId,
    required this.message,
    required this.createdAt,
  });
}

class _MessageBubble extends StatelessWidget {
  final String message;
  final String time;
  final bool isMine;

  const _MessageBubble({
    required this.message,
    required this.time,
    required this.isMine,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isMine
              ? Theme.of(context).colorScheme.primary
              : Colors.white12,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isMine ? 18 : 4),
            bottomRight: Radius.circular(isMine ? 4 : 18),
          ),
        ),
        child: Column(
          crossAxisAlignment: isMine
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Text(message, style: const TextStyle(fontSize: 15)),
            const SizedBox(height: 4),
            Text(
              time,
              style: TextStyle(
                fontSize: 10,
                color: isMine ? Colors.white70 : Colors.white54,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
