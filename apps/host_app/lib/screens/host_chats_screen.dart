import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/host_chat_service.dart';

const _chatAccent = Color(0xFF9B8AFB);
const _chatMuted = Color(0xFF9299A8);

/// Body widget for the Host app's Chats destination.
class HostChatsScreen extends StatefulWidget {
  const HostChatsScreen({super.key});

  @override
  State<HostChatsScreen> createState() => _HostChatsScreenState();
}

class _HostChatsScreenState extends State<HostChatsScreen> {
  final HostChatService _service = HostChatService();
  List<Map<String, dynamic>> _conversations = [];
  RealtimeChannel? _messagesChannel;
  RealtimeChannel? _conversationsChannel;
  bool _loading = true;
  bool _loadingConversations = false;
  bool _reloadRequested = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _messagesChannel = _service.subscribeToHostMessages(
      onChange: _requestReload,
    );
    _conversationsChannel = _service.subscribeToHostConversations(
      onChange: _requestReload,
    );
    unawaited(_load());
  }

  void _requestReload() {
    if (!mounted) return;
    if (_loadingConversations) {
      _reloadRequested = true;
      return;
    }
    unawaited(_load());
  }

  Future<void> _load() async {
    if (_loadingConversations) {
      _reloadRequested = true;
      return;
    }

    _loadingConversations = true;
    if (mounted) {
      setState(() {
        _error = null;
        if (_conversations.isEmpty) _loading = true;
      });
    }

    try {
      final rows = await _service.getHostConversations();
      if (!mounted) return;
      setState(() {
        _conversations = rows;
        _loading = false;
        _error = null;
      });
      await _service.refreshUnreadCount();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    } finally {
      _loadingConversations = false;
      if (mounted && _reloadRequested) {
        _reloadRequested = false;
        unawaited(_load());
      }
    }
  }

  @override
  void dispose() {
    final messages = _messagesChannel;
    final conversations = _conversationsChannel;
    if (messages != null) unawaited(_service.unsubscribe(messages));
    if (conversations != null) unawaited(_service.unsubscribe(conversations));
    super.dispose();
  }

  String _timeLabel(String? raw) {
    if (raw == null) return '';
    final date = DateTime.tryParse(raw)?.toLocal();
    if (date == null) return '';
    final now = DateTime.now();
    if (date.year == now.year &&
        date.month == now.month &&
        date.day == now.day) {
      final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
      return '$hour:${date.minute.toString().padLeft(2, '0')} ${date.hour >= 12 ? 'PM' : 'AM'}';
    }
    return '${date.month}/${date.day}';
  }

  Future<void> _open(Map<String, dynamic> row) async {
    final guest = row['guest'] as Map<String, dynamic>?;
    if (guest == null) {
      _showMessage(
        'The guest profile for this conversation could not be loaded.',
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HostChatConversationScreen(
          conversationId: row['id'] as String,
          guestId: row['guest_id'] as String,
          name: ((guest['display_name'] as String?)?.trim().isNotEmpty ?? false)
              ? (guest['display_name'] as String).trim()
              : ((guest['username'] as String?)?.trim().isNotEmpty ?? false)
              ? '@${(guest['username'] as String).trim()}'
              : 'Guest',
          avatarUrl: guest['avatar_url'] as String? ?? '',
        ),
      ),
    );
    if (mounted) {
      await _load();
      await _service.refreshUnreadCount();
    }
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 100),
            const Icon(Icons.error_outline, size: 44, color: _chatMuted),
            const SizedBox(height: 12),
            const Center(child: Text('Could not load chats')),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: _chatMuted),
              ),
            ),
            Center(
              child: FilledButton(
                onPressed: _load,
                child: const Text('Try again'),
              ),
            ),
          ],
        ),
      );
    }
    if (_conversations.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 100),
            Icon(Icons.forum_outlined, size: 58, color: _chatMuted),
            SizedBox(height: 16),
            Center(
              child: Text(
                'No chats yet',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
            SizedBox(height: 8),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'When a guest messages you, the conversation will appear here.',
                textAlign: TextAlign.center,
                style: TextStyle(color: _chatMuted),
              ),
            ),
            SizedBox(height: 30),
            Center(
              child: Text(
                'Pull down to refresh',
                style: TextStyle(color: _chatMuted, fontSize: 12),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _conversations.length,
        separatorBuilder: (_, _) => const Divider(height: 1, indent: 84),
        itemBuilder: (context, index) {
          final row = _conversations[index];
          final guest = row['guest'] as Map<String, dynamic>?;
          if (guest == null) return const SizedBox.shrink();
          final display = (guest['display_name'] as String?)?.trim();
          final username = (guest['username'] as String?)?.trim();
          final name = (display?.isNotEmpty ?? false)
              ? display!
              : (username?.isNotEmpty ?? false)
              ? '@$username'
              : 'Guest';
          final avatar = guest['avatar_url'] as String? ?? '';
          final latest = row['latest_message'] as Map<String, dynamic>?;
          final preview = (latest?['message'] as String?)?.trim();
          final unread = (row['unread_count'] as int?) ?? 0;
          final online = guest['is_online'] == true;
          return ListTile(
            onTap: () => _open(row),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 7,
            ),
            leading: Stack(
              children: [
                CircleAvatar(
                  radius: 27,
                  backgroundImage: avatar.isNotEmpty
                      ? NetworkImage(avatar)
                      : null,
                  child: avatar.isEmpty
                      ? const Icon(Icons.person_outline)
                      : null,
                ),
                if (online)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 13,
                      height: 13,
                      decoration: BoxDecoration(
                        color: const Color(0xFF61D9B4),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Theme.of(context).scaffoldBackgroundColor,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            title: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                (preview?.isNotEmpty ?? false) ? preview! : 'No messages yet',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: unread > 0 ? Colors.white : _chatMuted),
              ),
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _timeLabel(latest?['created_at'] as String?),
                  style: const TextStyle(fontSize: 11, color: _chatMuted),
                ),
                if (unread > 0) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: const BoxDecoration(
                      color: _chatAccent,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      unread > 99 ? '99+' : '$unread',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.black,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class HostChatConversationScreen extends StatefulWidget {
  const HostChatConversationScreen({
    super.key,
    required this.conversationId,
    required this.guestId,
    required this.name,
    required this.avatarUrl,
  });

  final String conversationId;
  final String guestId;
  final String name;
  final String avatarUrl;

  @override
  State<HostChatConversationScreen> createState() =>
      _HostChatConversationScreenState();
}

class _HostChatConversationScreenState
    extends State<HostChatConversationScreen> {
  final HostChatService _service = HostChatService();
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<Map<String, dynamic>> _messages = [];
  RealtimeChannel? _channel;
  bool _loading = true;
  bool _sending = false;
  String? _error;

  String? get _userId => Supabase.instance.client.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _channel = _service.subscribeToMessages(
      conversationId: widget.conversationId,
      onMessage: (row) async {
        if (!mounted || !_addMessage(row)) return;
        await _markRead();
        _scrollToBottom();
      },
    );
  }

  Future<void> _loadMessages() async {
    try {
      final rows = await _service.getMessages(widget.conversationId);
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(rows);
        _loading = false;
        _error = null;
      });
      await _markRead();
      _scrollToBottom();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _markRead() async {
    try {
      await _service.markConversationAsRead(widget.conversationId);
    } catch (error) {
      debugPrint('Unable to mark conversation read: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not mark messages as read: $error')),
      );
    }
  }

  bool _addMessage(Map<String, dynamic> incoming) {
    final id = incoming['id'] as String?;
    if (id == null || _messages.any((row) => row['id'] == id)) return false;
    setState(() => _messages.add(Map<String, dynamic>.from(incoming)));
    return true;
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final row = await _service.sendMessage(
        conversationId: widget.conversationId,
        message: text,
      );
      if (!mounted) return;
      _controller.clear();
      _addMessage(row);
      _scrollToBottom();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not send message: $error')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  String _time(String? raw) {
    final date = raw == null ? null : DateTime.tryParse(raw)?.toLocal();
    if (date == null) return '';
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    return '$hour:${date.minute.toString().padLeft(2, '0')} ${date.hour >= 12 ? 'PM' : 'AM'}';
  }

  @override
  void dispose() {
    final channel = _channel;
    if (channel != null) _service.unsubscribe(channel);
    _controller.dispose();
    _scroll.dispose();
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
              backgroundImage: widget.avatarUrl.isNotEmpty
                  ? NetworkImage(widget.avatarUrl)
                  : null,
              child: widget.avatarUrl.isEmpty
                  ? const Icon(Icons.person_outline)
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: _buildMessageList()),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'Message ${widget.name}…',
                        filled: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded),
                    tooltip: 'Send message',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageList() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 44, color: _chatMuted),
              const SizedBox(height: 12),
              const Text('Could not load messages'),
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: _chatMuted),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _loadMessages,
                child: const Text('Try again'),
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
              Icon(Icons.chat_bubble_outline, size: 52, color: _chatMuted),
              SizedBox(height: 12),
              Text(
                'No messages yet',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 6),
              Text(
                'Send the first message to start chatting.',
                textAlign: TextAlign.center,
                style: TextStyle(color: _chatMuted),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.all(16),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final row = _messages[index];
        final mine = row['sender_id'] == _userId;
        final text = row['message'] as String? ?? '';
        final timestamp = _time(row['created_at'] as String?);
        return Align(
          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * .78,
            ),
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: mine ? _chatAccent : const Color(0xFF252B37),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18),
                topRight: const Radius.circular(18),
                bottomLeft: Radius.circular(mine ? 18 : 4),
                bottomRight: Radius.circular(mine ? 4 : 18),
              ),
            ),
            child: Column(
              crossAxisAlignment: mine
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: TextStyle(
                    color: mine ? const Color(0xFF100D20) : Colors.white,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  timestamp,
                  style: TextStyle(
                    color: mine ? const Color(0xFF3A3456) : _chatMuted,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
