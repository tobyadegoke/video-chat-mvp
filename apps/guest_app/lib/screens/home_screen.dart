import 'dart:async';

import 'package:flutter/material.dart';

import '../models/host.dart';
import '../services/chat_service.dart';
import '../services/host_service.dart';
import 'chat_conversation_screen.dart';

const _appName = 'Video Platform'; // Replace when the final app name is decided.
const _continents = <String>[
  'All Continents',
  'Africa',
  'Asia',
  'Europe',
  'North America',
  'South America',
];

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.onSeeAllLive});

  final VoidCallback? onSeeAllLive;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final HostService _hostService = HostService();
  Timer? _refreshTimer;
  List<Host> _hosts = [];
  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _errorMessage;
  String _continent = 'All Continents';
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadHosts();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) unawaited(_loadHosts(silent: true));
    });
  }

  Future<void> _loadHosts({bool silent = false}) async {
    if (_isRefreshing) return;
    _isRefreshing = true;
    if (!silent && mounted) {
      setState(() {
        _isLoading = _hosts.isEmpty;
        _errorMessage = null;
      });
    }
    try {
      final hosts = await _hostService.getAllHosts();
      hosts.sort((a, b) {
        if (a.isOnline != b.isOnline) return a.isOnline ? -1 : 1;
        if (a.isLive != b.isLive) return a.isLive ? -1 : 1;
        return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
      });
      if (!mounted) return;
      setState(() {
        _hosts = hosts;
        _isLoading = false;
        _errorMessage = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Unable to load hosts. Please try again.';
      });
    } finally {
      _isRefreshing = false;
    }
  }

  List<Host> get _filteredHosts {
    return _hosts.where((host) {
      final continentMatches = _continent == 'All Continents' ||
          host.continent == _continent;
      final queryMatches = host.displayName.toLowerCase().contains(
        _searchQuery.trim().toLowerCase(),
      );
      return continentMatches && queryMatches;
    }).toList();
  }

  Future<void> _openSearch() async {
    final query = await showSearch<String?>(
      context: context,
      delegate: _HostSearchDelegate(),
    );
    if (!mounted || query == null) return;
    setState(() => _searchQuery = query);
  }

  void _showNotifications() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Notifications are coming soon.')),
    );
  }

  Future<void> _openChat(Host host) async {
    try {
      final conversation = await ChatService().getOrCreateConversation(host.id);
      if (!mounted) return;
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
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start chat: $error')),
      );
    }
  }

  void _startCall(Host host) {
    // Call navigation is intentionally not wired until the call flow is ready.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Calling ${host.displayName} will be available with the call feature.')),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hosts = _filteredHosts;
    final onlineCount = hosts.where((host) => host.isOnline).length;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadHosts,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _appName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.6,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Search hosts',
                    onPressed: _openSearch,
                    icon: const Icon(Icons.search_rounded),
                  ),
                  IconButton(
                    tooltip: 'Notifications',
                    onPressed: _showNotifications,
                    icon: const Icon(Icons.notifications_none_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 26),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Discover hosts',
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Text(
                      '$onlineCount online',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 42,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _continents.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final continent = _continents[index];
                    final selected = _continent == continent;
                    return ChoiceChip(
                      avatar: continent == 'All Continents'
                          ? const Icon(Icons.public_rounded, size: 17)
                          : null,
                      label: Text(continent),
                      selected: selected,
                      onSelected: (_) => setState(() => _continent = continent),
                      showCheckmark: false,
                    );
                  },
                ),
              ),
              if (_searchQuery.isNotEmpty) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: InputChip(
                    label: Text('Search: $_searchQuery'),
                    onDeleted: () => setState(() => _searchQuery = ''),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.only(top: 80),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_errorMessage != null && _hosts.isEmpty)
                _MessagePanel(
                  icon: Icons.cloud_off_rounded,
                  message: _errorMessage!,
                  action: TextButton(onPressed: _loadHosts, child: const Text('Try again')),
                )
              else if (hosts.isEmpty)
                _MessagePanel(
                  icon: Icons.people_outline_rounded,
                  message: _continent == 'All Continents'
                      ? 'No hosts found yet.'
                      : 'No hosts found in $_continent.',
                  action: TextButton(onPressed: () => setState(() => _continent = 'All Continents'), child: const Text('Clear filter')),
                )
              else
                LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth >= 760
                        ? 3
                        : constraints.maxWidth >= 480
                            ? 2
                            : 2;
                    return GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: hosts.length,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        mainAxisExtent: 218,
                      ),
                      itemBuilder: (context, index) {
                        final host = hosts[index];
                        return _HostCard(
                          host: host,
                          onMessage: () => _openChat(host),
                          onCall: () => _startCall(host),
                        );
                      },
                    );
                  },
                ),
              if (_errorMessage != null && _hosts.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_errorMessage!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HostCard extends StatelessWidget {
  const _HostCard({required this.host, required this.onMessage, required this.onCall});

  final Host host;
  final VoidCallback onMessage;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final avatar = host.avatarUrl;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: .45)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 34,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  backgroundImage: avatar != null && avatar.trim().isNotEmpty
                      ? NetworkImage(avatar)
                      : null,
                  child: avatar == null || avatar.trim().isEmpty
                      ? const Icon(Icons.person_rounded, size: 34)
                      : null,
                ),
                if (host.isOnline)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                        border: Border.all(color: theme.colorScheme.surface, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 9),
            Text(
              host.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 5),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.circle, size: 7, color: host.isOnline ? Colors.green : theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    host.isOnline ? 'Online' : 'Offline',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
            if (host.continent != null && host.continent!.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(
                host.continent!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
            const Spacer(),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onMessage,
                    icon: const Icon(Icons.chat_bubble_outline_rounded, size: 16),
                    label: const Text('Message'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onCall,
                    icon: const Icon(Icons.call_outlined, size: 16),
                    label: const Text('Call'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      visualDensity: VisualDensity.compact,
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

class _MessagePanel extends StatelessWidget {
  const _MessagePanel({required this.icon, required this.message, this.action});
  final IconData icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 52),
      child: Column(
        children: [
          Icon(icon, size: 46, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
          ?action,
        ],
      ),
    );
  }
}

class _HostSearchDelegate extends SearchDelegate<String?> {
  @override
  String get searchFieldLabel => 'Search hosts by display name';

  @override
  List<Widget>? buildActions(BuildContext context) => [
    IconButton(onPressed: () => query = '', icon: const Icon(Icons.clear_rounded)),
  ];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
    onPressed: () => close(context, null),
    icon: const Icon(Icons.arrow_back_rounded),
  );

  @override
  Widget buildResults(BuildContext context) => Center(
    child: FilledButton(onPressed: () => close(context, query.trim()), child: const Text('Apply search')),
  );

  @override
  Widget buildSuggestions(BuildContext context) => const Padding(
    padding: EdgeInsets.all(24),
    child: Text('Enter a host display name, then select Search.'),
  );
}
