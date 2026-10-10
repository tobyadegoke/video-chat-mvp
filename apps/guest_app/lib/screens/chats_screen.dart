import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/chat_service.dart';
import 'chat_conversation_screen.dart';

class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  final ChatService _chatService = ChatService();

  List<Map<String, dynamic>> _conversations = [];
  List<RealtimeChannel> _inboxChannels = [];
  Timer? _refreshDebounce;
  bool _isLoading = true;
  bool _refreshInProgress = false;
  bool _refreshAgain = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadConversations();
    _subscribeToInbox();
  }

  void _subscribeToInbox() {
    try {
      _inboxChannels = _chatService.subscribeToGuestInbox(
        onChange: _scheduleInboxRefresh,
      );
    } catch (error) {
      // Initial loading still works if Realtime cannot be started.
      debugPrint('Unable to subscribe to guest inbox updates: $error');
    }
  }

  void _scheduleInboxRefresh() {
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) {
        _refreshConversationsInBackground();
      }
    });
  }

  Future<void> _refreshConversationsInBackground() async {
    if (_refreshInProgress) {
      _refreshAgain = true;
      return;
    }

    _refreshInProgress = true;
    try {
      do {
        _refreshAgain = false;
        await _loadConversations(showLoading: false);
      } while (_refreshAgain && mounted);
    } finally {
      _refreshInProgress = false;
    }
  }

  Future<void> _loadConversations({bool showLoading = true}) async {
    if (!mounted) return;

    if (showLoading) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final conversations = await _chatService.getGuestConversations();
      if (!mounted) return;

      setState(() {
        _conversations = conversations;
        _isLoading = false;
        _errorMessage = null;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _errorMessage = error.toString();
        _isLoading = false;
      });
    }
  }

  String _formatMessageTime(String? timestamp) {
    if (timestamp == null || timestamp.isEmpty) return '';

    final dateTime = DateTime.tryParse(timestamp);
    if (dateTime == null) return '';

    final local = dateTime.toLocal();
    final now = DateTime.now();

    if (local.year == now.year &&
        local.month == now.month &&
        local.day == now.day) {
      final hour = local.hour == 0
          ? 12
          : local.hour > 12
              ? local.hour - 12
              : local.hour;
      final minute = local.minute.toString().padLeft(2, '0');
      final period = local.hour >= 12 ? 'PM' : 'AM';
      return '$hour:$minute $period';
    }

    if (local.year == now.year) {
      return '${local.month}/${local.day}';
    }

    return '${local.month}/${local.day}/${local.year}';
  }

  Future<void> _openConversation(
    Map<String, dynamic> conversation,
  ) async {
    final host = conversation['host'] as Map<String, dynamic>?;
    if (host == null) return;

    final conversationId = conversation['id'] as String;
    final hostId = conversation['host_id'] as String;
    final displayName = host['display_name'] as String?;
    final name = displayName?.trim().isNotEmpty == true
        ? displayName!
        : 'Host';
    final imageUrl = host['avatar_url'] as String? ?? '';

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatConversationScreen(
          conversationId: conversationId,
          hostId: hostId,
          name: name,
          imageUrl: imageUrl,
        ),
      ),
    );

    if (!mounted) return;
    await _loadConversations(showLoading: false);
  }

  @override
  void dispose() {
    _refreshDebounce?.cancel();
    unawaited(_chatService.unsubscribeFromGuestInbox(_inboxChannels));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chats')),
      body: RefreshIndicator(
        onRefresh: () => _loadConversations(),
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: 300,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 48,
                      color: Colors.white54,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Could not load chats.',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white60),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => _loadConversations(),
                      child: const Text('Try Again'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    if (_conversations.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(
            height: 300,
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.chat_bubble_outline,
                      size: 56,
                      color: Colors.white38,
                    ),
                    SizedBox(height: 16),
                    Text(
                      'No chats yet',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Start a conversation with a host to see it here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white60),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _conversations.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 88),
      itemBuilder: (context, index) =>
          _buildConversationTile(_conversations[index]),
    );
  }

  Widget _buildConversationTile(Map<String, dynamic> conversation) {
    final host = conversation['host'] as Map<String, dynamic>?;
    if (host == null) return const SizedBox.shrink();

    final displayName = host['display_name'] as String?;
    final name = displayName?.trim().isNotEmpty == true
        ? displayName!
        : 'Host';
    final username = host['username'] as String?;
    final imageUrl = host['avatar_url'] as String? ?? '';
    final isOnline = host['is_online'] == true;
    final latestMessage =
        conversation['latest_message'] as Map<String, dynamic>?;

    final latestText = latestMessage?['message'] as String?;
    final messageText =
        latestText?.trim().isNotEmpty == true ? latestText! : 'No messages yet';
    final messageTime = _formatMessageTime(
      latestMessage?['created_at'] as String?,
    );
    final unreadCount = (conversation['unread_count'] as int?) ?? 0;

    return ListTile(
      onTap: () => _openConversation(conversation),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Stack(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundImage:
                imageUrl.isNotEmpty ? NetworkImage(imageUrl) : null,
            child: imageUrl.isEmpty ? const Icon(Icons.person) : null,
          ),
          if (isOnline)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.green,
                  border: Border.all(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    width: 2,
                  ),
                ),
              ),
            ),
        ],
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              name,
              style: TextStyle(
                fontWeight:
                    unreadCount > 0 ? FontWeight.bold : FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (messageTime.isNotEmpty)
            Text(
              messageTime,
              style: TextStyle(
                fontSize: 11,
                color: unreadCount > 0
                    ? const Color(0xFFFF6B6B)
                    : Colors.white54,
                fontWeight:
                    unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
              ),
            ),
        ],
      ),
      subtitle: Row(
        children: [
          Expanded(
            child: Text(
              username != null && username.isNotEmpty
                  ? '@$username · $messageText'
                  : messageText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: unreadCount > 0 ? Colors.white : Colors.white60,
                fontWeight:
                    unreadCount > 0 ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
          if (unreadCount > 0) ...[
            const SizedBox(width: 8),
            Container(
              constraints: const BoxConstraints(
                minWidth: 24,
                minHeight: 24,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: 7,
                vertical: 3,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFD50000),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.9),
                  width: 1,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                unreadCount > 99 ? '99+' : '$unreadCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  height: 1,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
