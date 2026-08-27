import 'package:flutter/material.dart';

import '../models/host.dart';
import '../services/host_service.dart';

class LiveScreen extends StatefulWidget {
  const LiveScreen({super.key});

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> {
  final HostService _hostService = HostService();

  List<Host> _liveHosts = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadLiveHosts();
  }

  Future<void> _loadLiveHosts() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final hosts = await _hostService.getLiveHosts();

      if (!mounted) return;

      setState(() {
        _liveHosts = hosts;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _errorMessage = 'Unable to load live hosts.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Live Now'), centerTitle: false),
      body: RefreshIndicator(onRefresh: _loadLiveHosts, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return ListView(
        children: [
          const SizedBox(height: 200),
          Center(
            child: Column(
              children: [
                Text(_errorMessage!),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _loadLiveHosts,
                  child: const Text('Try Again'),
                ),
              ],
            ),
          ),
        ],
      );
    }

    if (_liveHosts.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 200),
          Center(
            child: Column(
              children: [
                Icon(Icons.live_tv_outlined, size: 56, color: Colors.white38),
                SizedBox(height: 16),
                Text(
                  'No hosts are live right now',
                  style: TextStyle(fontSize: 16, color: Colors.white54),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      physics: const AlwaysScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.72,
      ),
      itemCount: _liveHosts.length,
      itemBuilder: (context, index) {
        final host = _liveHosts[index];

        return _LiveHostCard(
          host: host,
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Joining ${host.displayName}...')),
            );
          },
        );
      },
    );
  }
}

class _LiveHostCard extends StatelessWidget {
  final Host host;
  final VoidCallback onTap;

  const _LiveHostCard({required this.host, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Ink(
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1C),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: host.avatarUrl != null && host.avatarUrl!.isNotEmpty
                    ? Image.network(
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
                    : const Center(
                        child: Icon(
                          Icons.person,
                          size: 60,
                          color: Colors.white38,
                        ),
                      ),
              ),
            ),

            Positioned(
              top: 10,
              left: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.redAccent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.circle, size: 8),
                    SizedBox(width: 5),
                    Text(
                      'LIVE',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    host.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (host.username != null && host.username!.isNotEmpty)
                    Text(
                      '@${host.username}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
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
