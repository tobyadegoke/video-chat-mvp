import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HostChatService {
  HostChatService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static final ValueNotifier<int> unreadTotal = ValueNotifier<int>(0);

  static RealtimeChannel? _inboxMessagesChannel;
  static RealtimeChannel? _inboxConversationsChannel;
  static Timer? _refreshDebounce;
  static bool _refreshInProgress = false;
  static bool _refreshAgain = false;

  String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw StateError('Please sign in again.');
    return id;
  }

  Future<List<Map<String, dynamic>>> getHostConversations() async {
    final userId = _userId;
    final rows = await _client
        .from('conversations')
        .select()
        .eq('host_id', userId)
        .order('updated_at', ascending: false);

    if (rows.isEmpty) return [];

    final guestIds = rows
        .map((row) => row['guest_id'] as String)
        .toSet()
        .toList();

    final guests = await _client
        .from('profiles')
        .select('id, username, display_name, avatar_url, is_online')
        .inFilter('id', guestIds);

    final guestById = {
      for (final guest in guests) guest['id'] as String: guest,
    };

    final results = <Map<String, dynamic>>[];
    for (final row in rows) {
      final conversationId = row['id'] as String;

      final latest = await _client
          .from('messages')
          .select('id, sender_id, message, created_at, read_at')
          .eq('conversation_id', conversationId)
          .order('created_at', ascending: false)
          .limit(1);

      final unread = await _client
          .from('messages')
          .select('id')
          .eq('conversation_id', conversationId)
          .neq('sender_id', userId)
          .isFilter('read_at', null);

      results.add({
        ...Map<String, dynamic>.from(row),
        'guest': guestById[row['guest_id']],
        'latest_message': latest.isEmpty ? null : latest.first,
        'unread_count': unread.length,
      });
    }
    return results;
  }

  Future<int> getUnreadCount() async {
    final userId = _userId;
    final conversations = await _client
        .from('conversations')
        .select('id')
        .eq('host_id', userId);

    if (conversations.isEmpty) return 0;

    final ids = conversations.map((row) => row['id'] as String).toList();
    final unreadRows = await _client
        .from('messages')
        .select('id')
        .inFilter('conversation_id', ids)
        .neq('sender_id', userId)
        .isFilter('read_at', null);

    return unreadRows.length;
  }

  Future<void> refreshUnreadCount() async {
    try {
      unreadTotal.value = await getUnreadCount();
    } catch (error) {
      debugPrint('Unable to refresh unread count: $error');
    }
  }

  Future<void> startInboxRealtime() async {
    final userId = _userId;
    await stopInboxRealtime();
    await refreshUnreadCount();

    _inboxMessagesChannel = _client
        .channel('host_inbox_messages_$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'messages',
          callback: (_) => _scheduleInboxRefresh(),
        )
        .subscribe();

    _inboxConversationsChannel = _client
        .channel('host_inbox_conversations_$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'conversations',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'host_id',
            value: userId,
          ),
          callback: (_) => _scheduleInboxRefresh(),
        )
        .subscribe();
  }

  static void _scheduleInboxRefresh() {
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(
      const Duration(milliseconds: 250),
      () => unawaited(_refreshInboxCountSafely()),
    );
  }

  static Future<void> _refreshInboxCountSafely() async {
    if (_refreshInProgress) {
      _refreshAgain = true;
      return;
    }

    _refreshInProgress = true;
    try {
      do {
        _refreshAgain = false;
        await HostChatService().refreshUnreadCount();
      } while (_refreshAgain);
    } finally {
      _refreshInProgress = false;
    }
  }

  Future<void> stopInboxRealtime() async {
    _refreshDebounce?.cancel();
    _refreshDebounce = null;

    final messages = _inboxMessagesChannel;
    final conversations = _inboxConversationsChannel;
    _inboxMessagesChannel = null;
    _inboxConversationsChannel = null;

    if (messages != null) await _client.removeChannel(messages);
    if (conversations != null) await _client.removeChannel(conversations);
  }

  Future<List<Map<String, dynamic>>> getMessages(
    String conversationId,
  ) async {
    final rows = await _client
        .from('messages')
        .select('id, conversation_id, sender_id, message, created_at, read_at')
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: true);

    return List<Map<String, dynamic>>.from(rows);
  }

  Future<Map<String, dynamic>> sendMessage({
    required String conversationId,
    required String message,
  }) async {
    final text = message.trim();
    if (text.isEmpty) throw ArgumentError('Message cannot be empty.');

    final inserted = await _client
        .from('messages')
        .insert({
          'conversation_id': conversationId,
          'sender_id': _userId,
          'message': text,
        })
        .select()
        .single();

    await _client
        .from('conversations')
        .update({'updated_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', conversationId);

    return Map<String, dynamic>.from(inserted);
  }

  Future<void> markConversationAsRead(String conversationId) async {
    await _client.rpc(
      'mark_conversation_messages_read',
      params: {'p_conversation_id': conversationId},
    );
    await refreshUnreadCount();
  }

  RealtimeChannel subscribeToHostMessages({required void Function() onChange}) {
    return _client
        .channel('host_inbox_screen_messages_$_userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'messages',
          callback: (_) => onChange(),
        )
        .subscribe();
  }

  RealtimeChannel subscribeToHostConversations({
    required void Function() onChange,
  }) {
    return _client
        .channel('host_inbox_screen_conversations_$_userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'conversations',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'host_id',
            value: _userId,
          ),
          callback: (_) => onChange(),
        )
        .subscribe();
  }

  RealtimeChannel subscribeToMessages({
    required String conversationId,
    required void Function(Map<String, dynamic>) onMessage,
  }) {
    return _client
        .channel('host_conversation_messages_$conversationId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: conversationId,
          ),
          callback: (payload) => onMessage(payload.newRecord),
        )
        .subscribe();
  }

  Future<void> unsubscribe(RealtimeChannel channel) async {
    await _client.removeChannel(channel);
  }
}
