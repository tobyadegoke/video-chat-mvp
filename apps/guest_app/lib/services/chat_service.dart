import 'package:supabase_flutter/supabase_flutter.dart';

class ChatService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Returns all conversations belonging to the current guest,
  /// including host information, latest message, and unread count.
  Future<List<Map<String, dynamic>>> getGuestConversations() async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      throw Exception('No authenticated user.');
    }

    final conversations = await _supabase
        .from('conversations')
        .select()
        .eq('guest_id', user.id)
        .order('updated_at', ascending: false);

    if (conversations.isEmpty) {
      return [];
    }

    final hostIds = conversations
        .map((conversation) => conversation['host_id'] as String)
        .toSet()
        .toList();

    final hosts = await _supabase
        .from('profiles')
        .select('id, username, display_name, avatar_url, is_online, is_live')
        .inFilter('id', hostIds);

    final hostMap = {for (final host in hosts) host['id'] as String: host};
    final results = <Map<String, dynamic>>[];

    for (final conversation in conversations) {
      final conversationId = conversation['id'] as String;
      final host = hostMap[conversation['host_id']];

      final latestMessages = await _supabase
          .from('messages')
          .select('id, sender_id, message, created_at, read_at')
          .eq('conversation_id', conversationId)
          .order('created_at', ascending: false)
          .limit(1);

      final latestMessage =
          latestMessages.isNotEmpty ? latestMessages.first : null;

      final unreadMessages = await _supabase
          .from('messages')
          .select('id')
          .eq('conversation_id', conversationId)
          .neq('sender_id', user.id)
          .isFilter('read_at', null);

      results.add({
        ...Map<String, dynamic>.from(conversation),
        'host': host,
        'latest_message': latestMessage,
        'unread_count': unreadMessages.length,
      });
    }

    return results;
  }

  /// Subscribe to changes that can affect the guest inbox.
  ///
  /// Conversation changes cover newly created conversations and ordering
  /// changes. Message changes cover previews and unread counts.
  List<RealtimeChannel> subscribeToGuestInbox({
    required void Function() onChange,
  }) {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw StateError('Please sign in again.');
    }

    final conversationsChannel = _supabase
        .channel('guest_inbox_conversations_${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'conversations',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'guest_id',
            value: user.id,
          ),
          callback: (_) => onChange(),
        )
        .subscribe();

    // The messages table is protected by RLS. Refreshing the inbox after
    // message changes recalculates previews and unread counts from the
    // database rather than trying to infer them from partial event payloads.
    final messagesChannel = _supabase
        .channel('guest_inbox_messages_${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'messages',
          callback: (_) => onChange(),
        )
        .subscribe();

    return [conversationsChannel, messagesChannel];
  }

  /// Gets an existing conversation between the current guest and a host,
  /// or creates one if it doesn't exist.
  Future<Map<String, dynamic>> getOrCreateConversation(String hostId) async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      throw Exception('No authenticated user.');
    }

    final existing = await _supabase
        .from('conversations')
        .select()
        .eq('guest_id', user.id)
        .eq('host_id', hostId)
        .maybeSingle();

    if (existing != null) {
      return Map<String, dynamic>.from(existing);
    }

    final conversation = await _supabase
        .from('conversations')
        .insert({'guest_id': user.id, 'host_id': hostId})
        .select()
        .single();

    return Map<String, dynamic>.from(conversation);
  }

  /// Gets all messages in a conversation.
  Future<List<Map<String, dynamic>>> getMessages(String conversationId) async {
    final messages = await _supabase
        .from('messages')
        .select()
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: true);

    return List<Map<String, dynamic>>.from(messages);
  }

  /// Marks messages sent by the other participant as read.
  Future<void> markConversationAsRead(String conversationId) async {
    await _supabase.rpc(
      'mark_conversation_messages_read',
      params: {'p_conversation_id': conversationId},
    );
  }

  /// Sends a message as the currently authenticated user.
  Future<Map<String, dynamic>> sendMessage({
    required String conversationId,
    required String message,
  }) async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      throw Exception('No authenticated user.');
    }

    final trimmedMessage = message.trim();

    if (trimmedMessage.isEmpty) {
      throw Exception('Message cannot be empty.');
    }

    final newMessage = await _supabase
        .from('messages')
        .insert({
          'conversation_id': conversationId,
          'sender_id': user.id,
          'message': trimmedMessage,
        })
        .select()
        .single();

    await _supabase
        .from('conversations')
        .update({'updated_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', conversationId);

    return Map<String, dynamic>.from(newMessage);
  }

  /// Listens for new messages in a conversation.
  RealtimeChannel subscribeToMessages({
    required String conversationId,
    required void Function(Map<String, dynamic> message) onMessage,
  }) {
    return _supabase
        .channel('conversation_messages_$conversationId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: conversationId,
          ),
          callback: (payload) {
            onMessage(payload.newRecord);
          },
        )
        .subscribe();
  }

  /// Stops listening to a conversation.
  Future<void> unsubscribeFromMessages(RealtimeChannel channel) async {
    await _supabase.removeChannel(channel);
  }

  /// Stops listening to guest inbox changes.
  Future<void> unsubscribeFromGuestInbox(
    List<RealtimeChannel> channels,
  ) async {
    for (final channel in channels) {
      await _supabase.removeChannel(channel);
    }
  }
}
