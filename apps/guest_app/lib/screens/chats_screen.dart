import 'package:flutter/material.dart';

import 'chat_conversation_screen.dart';

class ChatsScreen extends StatelessWidget {
  const ChatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final chats = [
      {
        'name': 'Maya',
        'message': 'That was really fun 😊',
        'time': '2m',
        'image': 'https://i.pravatar.cc/300?img=47',
        'unread': '2',
      },
      {
        'name': 'Sophia',
        'message': 'Are you joining my live later?',
        'time': '1h',
        'image': 'https://i.pravatar.cc/300?img=32',
        'unread': '0',
      },
      {
        'name': 'Amara',
        'message': 'See you soon!',
        'time': 'Yesterday',
        'image': 'https://i.pravatar.cc/300?img=44',
        'unread': '0',
      },
      {
        'name': 'Nia',
        'message': 'Thanks for stopping by!',
        'time': 'Yesterday',
        'image': 'https://i.pravatar.cc/300?img=45',
        'unread': '1',
      },
    ];

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Chats',
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.search),
                  ),
                ],
              ),
            ),

            Expanded(
              child: ListView.separated(
                itemCount: chats.length,
                separatorBuilder: (_, _) => const Divider(
                  height: 1,
                  indent: 84,
                ),
                itemBuilder: (context, index) {
                  final chat = chats[index];

                  return _ChatTile(
                    name: chat['name']!,
                    message: chat['message']!,
                    time: chat['time']!,
                    imageUrl: chat['image']!,
                    unreadCount: int.parse(chat['unread']!),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatTile extends StatelessWidget {
  final String name;
  final String message;
  final String time;
  final String imageUrl;
  final int unreadCount;

  const _ChatTile({
    required this.name,
    required this.message,
    required this.time,
    required this.imageUrl,
    required this.unreadCount,
  });

  void _openChat(BuildContext context) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => ChatConversationScreen(
        name: name,
        imageUrl: imageUrl,
      ),
    ),
  );
}

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _openChat(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 14,
        ),
        child: Row(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundImage: NetworkImage(imageUrl),
                ),

                if (name == 'Maya' || name == 'Nia')
                  Positioned(
                    right: 2,
                    bottom: 2,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF0F0F0F),
                          width: 2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),

            const SizedBox(width: 14),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: unreadCount > 0
                          ? FontWeight.bold
                          : FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    message,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: unreadCount > 0
                          ? Colors.white
                          : Colors.white60,
                      fontWeight: unreadCount > 0
                          ? FontWeight.w500
                          : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 12),

            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  time,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white54,
                  ),
                ),
                const SizedBox(height: 8),

                if (unreadCount > 0)
                  Container(
                    constraints: const BoxConstraints(
                      minWidth: 20,
                      minHeight: 20,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: Colors.redAccent,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      unreadCount.toString(),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}