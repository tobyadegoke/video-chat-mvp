import 'package:flutter/material.dart';

import '../services/available_host_service.dart';

class ShuffleScreen extends StatefulWidget {
  const ShuffleScreen({super.key});

  @override
  State<ShuffleScreen> createState() => _ShuffleScreenState();
}

class _ShuffleScreenState extends State<ShuffleScreen> {
  final AvailableHostService _hostService = AvailableHostService();

  AvailableHost? _selectedHost;

  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _findHost() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final hosts = await _hostService.getAvailableHosts();

      if (!mounted) return;

      if (hosts.isEmpty) {
        setState(() {
          _isLoading = false;
          _selectedHost = null;
          _errorMessage = 'No hosts are available right now.';
        });

        return;
      }

      // For now, select the first available host.
      // We'll add random matching after confirming Supabase works.
      setState(() {
        _selectedHost = hosts.first;
        _isLoading = false;
      });
    } catch (error) {
      debugPrint('AVAILABLE HOST ERROR: $error');

      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _errorMessage = 'Unable to find a host. Please try again.';
      });
    }
  }

  void _startCall() {
    if (_selectedHost == null) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Starting a call with ${_selectedHost!.displayName}...'),
      ),
    );

    // LiveKit call navigation will go here later.
  }

  void _goBack() {
    setState(() {
      _selectedHost = null;
      _errorMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: _selectedHost != null
              ? _buildHostFoundState(_selectedHost!)
              : _buildFindHostState(),
        ),
      ),
    );
  }

  Widget _buildFindHostState() {
    return Padding(
      key: const ValueKey('find-host'),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.shuffle_rounded, size: 80, color: Colors.redAccent),

          const SizedBox(height: 24),

          const Text(
            'Meet Someone New',
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 12),

          const Text(
            'We’ll connect you with an available host.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.white60),
          ),

          const SizedBox(height: 24),

          if (_errorMessage != null)
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.redAccent),
            ),

          const SizedBox(height: 16),

          SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton.icon(
              onPressed: _isLoading ? null : _findHost,
              icon: _isLoading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.shuffle),
              label: Text(
                _isLoading ? 'Finding Host...' : 'Find a Host',
                style: const TextStyle(fontSize: 17),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHostFoundState(AvailableHost host) {
    return Padding(
      key: ValueKey(host.id),
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 32),

          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              onPressed: _goBack,
              icon: const Icon(Icons.arrow_back),
            ),
          ),

          const Spacer(),

          const Text(
            'You matched with',
            style: TextStyle(color: Colors.white60, fontSize: 16),
          ),

          const SizedBox(height: 16),

          CircleAvatar(
            radius: 90,
            backgroundColor: const Color(0xFF1C1C1C),
            backgroundImage:
                host.avatarUrl != null && host.avatarUrl!.isNotEmpty
                ? NetworkImage(host.avatarUrl!)
                : null,
            child: host.avatarUrl == null || host.avatarUrl!.isEmpty
                ? const Icon(Icons.person, size: 90, color: Colors.white38)
                : null,
          ),

          const SizedBox(height: 24),

          Text(
            host.displayName,
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 8),

          if (host.username.isNotEmpty)
            Text(
              '@${host.username}',
              style: const TextStyle(fontSize: 15, color: Colors.white38),
            ),

          const SizedBox(height: 12),

          Text(
            host.bio ?? 'Available to chat',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, color: Colors.white60),
          ),

          const Spacer(),

          SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton.icon(
              onPressed: _startCall,
              icon: const Icon(Icons.videocam),
              label: const Text('Start Call', style: TextStyle(fontSize: 17)),
            ),
          ),

          const SizedBox(height: 12),

          SizedBox(
            width: double.infinity,
            height: 56,
            child: OutlinedButton.icon(
              onPressed: _isLoading ? null : _findHost,
              icon: const Icon(Icons.shuffle),
              label: const Text(
                'Shuffle Again',
                style: TextStyle(fontSize: 17),
              ),
            ),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
