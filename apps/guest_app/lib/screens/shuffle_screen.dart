import 'dart:math';

import 'package:flutter/material.dart';

import '../data/mock_hosts.dart';

class ShuffleScreen extends StatefulWidget {
  const ShuffleScreen({super.key});

  @override
  State<ShuffleScreen> createState() => _ShuffleScreenState();
}

class _ShuffleScreenState extends State<ShuffleScreen> {
  final Random _random = Random();

  Host? _selectedHost;

  void _findHost() {
    final availableHosts = mockHosts
        .where((host) => host.isOnline && !host.isLive)
        .toList();

    if (availableHosts.isEmpty) {
      return;
    }

    setState(() {
      _selectedHost =
          availableHosts[_random.nextInt(availableHosts.length)];
    });
  }

  void _startCall() {
    if (_selectedHost == null) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Starting a call with ${_selectedHost!.name}...',
        ),
      ),
    );

    // LiveKit call navigation will go here later.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: _selectedHost == null
              ? _buildFindHostState()
              : _buildHostFoundState(_selectedHost!),
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
          const Icon(
            Icons.shuffle_rounded,
            size: 80,
            color: Colors.redAccent,
          ),

          const SizedBox(height: 24),

          const Text(
            'Meet Someone New',
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 12),

          const Text(
            'We’ll connect you with an available host.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: Colors.white60,
            ),
          ),

          const SizedBox(height: 40),

          SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton.icon(
              onPressed: _findHost,
              icon: const Icon(Icons.shuffle),
              label: const Text(
                'Find a Host',
                style: TextStyle(fontSize: 17),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHostFoundState(Host host) {
    return Padding(
      key: ValueKey(host.id),
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 32),

          const Text(
            'You matched with',
            style: TextStyle(
              color: Colors.white60,
              fontSize: 16,
            ),
          ),

          const SizedBox(height: 16),

          CircleAvatar(
            radius: 90,
            backgroundImage: NetworkImage(host.imageUrl),
          ),

          const SizedBox(height: 24),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                host.name,
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 10),
              const Icon(
                Icons.circle,
                color: Colors.green,
                size: 14,
              ),
            ],
          ),

          const SizedBox(height: 8),

          Text(
            host.category,
            style: const TextStyle(
              fontSize: 16,
              color: Colors.white60,
            ),
          ),

          const Spacer(),

          SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton.icon(
              onPressed: _startCall,
              icon: const Icon(Icons.videocam),
              label: const Text(
                'Start Call',
                style: TextStyle(fontSize: 17),
              ),
            ),
          ),

          const SizedBox(height: 12),

          SizedBox(
            width: double.infinity,
            height: 56,
            child: OutlinedButton.icon(
              onPressed: _findHost,
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