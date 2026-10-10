import 'package:flutter/material.dart';

import '../models/host.dart';
import '../services/chat_service.dart';
import '../services/host_service.dart';
import 'chat_conversation_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.onSeeAllLive});

  final VoidCallback? onSeeAllLive;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final HostService _hostService = HostService();

  List<Host> _hosts = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadHosts();
  }

  Future<void> _loadHosts() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final hosts = await _hostService.getAllHosts();

      if (!mounted) return;

      setState(() {
        _hosts = hosts;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _errorMessage = 'Unable to load hosts.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_errorMessage != null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_errorMessage!),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _loadHosts,
                child: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }

    final liveHosts = _hosts.where((host) => host.isLive).toList();

    final recommendedHosts = _hosts.where((host) => !host.isLive).toList();

    final featuredHost = liveHosts.isNotEmpty ? liveHosts.first : null;

    final starOfWeek = _hosts.isNotEmpty ? _hosts.first : null;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadHosts,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
            children: [
              // HEADER
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Good evening,',
                        style: TextStyle(fontSize: 16, color: Colors.white60),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Tobi 👋',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.notifications_none),
                  ),
                ],
              ),

              const SizedBox(height: 28),

              // FEATURED HOST
              const Text(
                'Featured Host',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 12),

              if (featuredHost != null)
                _FeaturedHostCard(host: featuredHost)
              else
                const _EmptySection(
                  message: 'No hosts are live right now',
                  height: 180,
                ),

              const SizedBox(height: 32),

              // STAR OF THE WEEK
              const Text(
                '⭐ Star of the Week',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 12),

              if (starOfWeek != null)
                _StarOfWeekCard(host: starOfWeek)
              else
                const _EmptySection(
                  message: 'No hosts available yet',
                  height: 120,
                ),

              const SizedBox(height: 32),

              // LIVE NOW
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '🔴 Live Now',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  TextButton(
                    onPressed: widget.onSeeAllLive,
                    child: const Text('See all'),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              if (liveHosts.isEmpty)
                const _EmptySection(
                  message: 'No hosts are live right now',
                  height: 190,
                )
              else
                SizedBox(
                  height: 190,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: liveHosts.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 12),
                    itemBuilder: (context, index) {
                      return _LiveHostCard(host: liveHosts[index]);
                    },
                  ),
                ),

              const SizedBox(height: 32),

              // RECOMMENDED
              const Text(
                'Recommended for You',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 12),

              if (recommendedHosts.isEmpty)
                const _EmptySection(
                  message: 'No more hosts to recommend yet',
                  height: 210,
                )
              else
                SizedBox(
                  height: 210,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: recommendedHosts.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 12),
                    itemBuilder: (context, index) {
                      return _RecommendedHostCard(
                        host: recommendedHosts[index],
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptySection extends StatelessWidget {
  final String message;
  final double height;

  const _EmptySection({required this.message, required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1C),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Center(
        child: Text(message, style: const TextStyle(color: Colors.white54)),
      ),
    );
  }
}

class _FeaturedHostCard extends StatelessWidget {
  final Host host;

  const _FeaturedHostCard({required this.host});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 260,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: const Color(0xFF1C1C1C),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (host.avatarUrl != null && host.avatarUrl!.isNotEmpty)
              Image.network(
                host.avatarUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) {
                  return const Center(
                    child: Icon(Icons.person, size: 80, color: Colors.white38),
                  );
                },
              )
            else
              const Center(
                child: Icon(Icons.person, size: 80, color: Colors.white38),
              ),

            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.85),
                  ],
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          host.displayName,
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (host.isLive)
                        const Icon(
                          Icons.circle,
                          color: Colors.redAccent,
                          size: 12,
                        ),
                    ],
                  ),

                  const SizedBox(height: 4),

                  Text(
                    host.bio ?? 'Live on the platform',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70),
                  ),

                  const SizedBox(height: 16),

                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Joining ${host.displayName}...'),
                          ),
                        );
                      },
                      icon: const Icon(Icons.videocam),
                      label: const Text('Join Live'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StarOfWeekCard extends StatelessWidget {
  final Host host;

  const _StarOfWeekCard({required this.host});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 120,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: const Color(0xFF1C1C1C),
      ),
      child: Row(
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 40,
                backgroundColor: const Color(0xFF2A2A2A),
                backgroundImage:
                    host.avatarUrl != null && host.avatarUrl!.isNotEmpty
                    ? NetworkImage(host.avatarUrl!)
                    : null,
                child: host.avatarUrl == null || host.avatarUrl!.isEmpty
                    ? const Icon(Icons.person, size: 40)
                    : null,
              ),
              const Positioned(
                right: 0,
                bottom: 0,
                child: CircleAvatar(
                  radius: 14,
                  backgroundColor: Colors.amber,
                  child: Icon(Icons.star, size: 16, color: Colors.black),
                ),
              ),
            ],
          ),

          const SizedBox(width: 16),

          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  host.displayName,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Most loved host this week',
                  style: TextStyle(color: Colors.white60),
                ),
              ],
            ),
          ),

          const Icon(Icons.emoji_events, color: Colors.amber, size: 32),
        ],
      ),
    );
  }
}

class _LiveHostCard extends StatelessWidget {
  final Host host;

  const _LiveHostCard({required this.host});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 140,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (host.avatarUrl != null && host.avatarUrl!.isNotEmpty)
                    Image.network(
                      host.avatarUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) {
                        return const Center(
                          child: Icon(
                            Icons.person,
                            size: 60,
                            color: Colors.white38,
                          ),
                        );
                      },
                    )
                  else
                    const Center(
                      child: Icon(
                        Icons.person,
                        size: 60,
                        color: Colors.white38,
                      ),
                    ),

                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'LIVE',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 8),

          Text(
            host.displayName,
            style: const TextStyle(fontWeight: FontWeight.bold),
            overflow: TextOverflow.ellipsis,
          ),

          Text(
            host.username != null && host.username!.isNotEmpty
                ? '@${host.username}'
                : 'Live now',
            style: const TextStyle(fontSize: 12, color: Colors.white60),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _RecommendedHostCard extends StatelessWidget {
  final Host host;

  const _RecommendedHostCard({required this.host});

  Future<void> _openChat(BuildContext context) async {
    try {
      final conversation = await ChatService().getOrCreateConversation(host.id);

      if (!context.mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatConversationScreen(
            conversationId: conversation['id'] as String,
            hostId: host.id,
            name: host.displayName,
            imageUrl: host.avatarUrl ?? '',
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not start chat: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 145,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: host.avatarUrl != null && host.avatarUrl!.isNotEmpty
                  ? Image.network(
                      host.avatarUrl!,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) {
                        return const Center(
                          child: Icon(
                            Icons.person,
                            size: 60,
                            color: Colors.white38,
                          ),
                        );
                      },
                    )
                  : const Center(
                      child: Icon(
                        Icons.person,
                        size: 60,
                        color: Colors.white38,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            host.displayName,
            style: const TextStyle(fontWeight: FontWeight.bold),
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            host.username != null && host.username!.isNotEmpty
                ? '@${host.username}'
                : 'Host',
            style: const TextStyle(fontSize: 12, color: Colors.white60),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            height: 34,
            child: OutlinedButton.icon(
              onPressed: () => _openChat(context),
              icon: const Icon(Icons.chat_bubble_outline, size: 15),
              label: const Text('Chat', style: TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
