import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/host_profile_service.dart';
import 'host_profile_edit_screen.dart';

const _surface = Color(0xFF141821);
const _border = Color(0xFF2B3240);
const _muted = Color(0xFF9299A8);
const _accent = Color(0xFF9B8AFB);
const _danger = Color(0xFFFF858E);

class HostProfileScreen extends StatefulWidget {
  const HostProfileScreen({super.key, this.service});
  final HostProfileService? service;
  @override
  State<HostProfileScreen> createState() => _HostProfileScreenState();
}

class _HostProfileScreenState extends State<HostProfileScreen> {
  late final HostProfileService _service =
      widget.service ?? HostProfileService();
  Map<String, dynamic>? _profile;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final value = await _service.loadProfile();
      if (!mounted) return;
      setState(() {
        _profile = value;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst(
          RegExp(r'^(Exception|Bad state|Invalid argument): '),
          '',
        );
        _loading = false;
      });
    }
  }

  Future<void> _edit() async {
    final p = _profile;
    if (p == null) return;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => HostProfileEditScreen(profile: p, service: _service),
      ),
    );
    if (changed == true) await _loadProfile();
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text(
          'You will need to sign in again to access your host account.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not log out: $e')));
    }
  }

  void _open(ProfileDestination d) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => HostProfileDestinationScreen(destination: d),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null || _profile == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.person_off_outlined, size: 42),
              const SizedBox(height: 12),
              Text(
                _error ?? 'Your profile could not be loaded.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _loadProfile,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }

    final p = _profile!;
    final name = (p['display_name'] as String?)?.trim();
    final username = (p['username'] as String?)?.trim();
    final avatar = (p['avatar_url'] as String?)?.trim();
    final bio = (p['bio'] as String?)?.trim();

    return SafeArea(
      top: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 36),
            children: [
              Text(
                'My Profile',
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              const Text(
                'Your creator account and preferences.',
                style: TextStyle(color: _muted),
              ),
              const SizedBox(height: 22),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: _border),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 38,
                          backgroundColor: const Color(0xFF29243D),
                          backgroundImage: avatar != null && avatar.isNotEmpty
                              ? NetworkImage(avatar)
                              : null,
                          child: avatar == null || avatar.isEmpty
                              ? const Icon(Icons.person, size: 36)
                              : null,
                        ),
                        const SizedBox(width: 15),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name == null || name.isEmpty
                                    ? 'Your creator profile'
                                    : name,
                                style: const TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                username == null || username.isEmpty
                                    ? 'Username not set'
                                    : '@$username',
                                style: const TextStyle(
                                  color: _muted,
                                  fontSize: 13,
                                ),
                              ),
                              if (bio != null && bio.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  bio,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFFB9BECA),
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Edit profile',
                          onPressed: _edit,
                          icon: const Icon(Icons.edit_outlined, color: _accent),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _edit,
                        icon: const Icon(Icons.manage_accounts_outlined),
                        label: const Text('Edit profile'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              const _SectionLabel('CREATOR ACCOUNT'),
              const SizedBox(height: 8),
              _MenuTile(
                icon: Icons.account_balance_wallet_outlined,
                color: const Color(0xFFFFC66D),
                title: 'Account & earnings',
                subtitle: 'Earnings report, balance and payouts',
                onTap: () => _open(ProfileDestination.account),
              ),
              const SizedBox(height: 16),
              const _SectionLabel('PREFERENCES & SUPPORT'),
              const SizedBox(height: 8),
              _MenuTile(
                icon: Icons.settings_outlined,
                title: 'Settings',
                subtitle: 'Account preferences and security',
                onTap: () => _open(ProfileDestination.settings),
              ),
              _MenuTile(
                icon: Icons.notifications_none_rounded,
                title: 'Notifications',
                subtitle: 'Manage alerts and updates',
                onTap: () => _open(ProfileDestination.notifications),
              ),
              _MenuTile(
                icon: Icons.shield_outlined,
                title: 'Privacy & safety',
                subtitle: 'Privacy information and account safety',
                onTap: () => _open(ProfileDestination.privacy),
              ),
              _MenuTile(
                icon: Icons.support_agent_rounded,
                title: 'Help & support',
                subtitle: 'Get help or report a problem',
                onTap: () => _open(ProfileDestination.support),
              ),
              _MenuTile(
                icon: Icons.policy_outlined,
                title: 'Legal',
                subtitle: 'Terms and privacy policy',
                onTap: () => _open(ProfileDestination.legal),
              ),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _border),
                ),
                child: ListTile(
                  leading: const Icon(Icons.logout_rounded, color: _danger),
                  title: const Text(
                    'Log out',
                    style: TextStyle(
                      color: _danger,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: const Text('Sign out of your host account'),
                  trailing: const Icon(
                    Icons.chevron_right_rounded,
                    color: _muted,
                  ),
                  onTap: _logout,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      color: _muted,
      fontSize: 11,
      letterSpacing: 1.2,
      fontWeight: FontWeight.w800,
    ),
  );
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.color = _accent,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 4),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: Color(0xFF222733))),
    ),
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: color.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Icon(icon, color: color, size: 22),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: _muted, fontSize: 12),
      ),
      trailing: const Icon(Icons.chevron_right_rounded, color: _muted),
      onTap: onTap,
    ),
  );
}

enum ProfileDestination {
  account,
  settings,
  notifications,
  privacy,
  support,
  legal,
}

class HostProfileDestinationScreen extends StatelessWidget {
  const HostProfileDestinationScreen({super.key, required this.destination});

  final ProfileDestination destination;

  @override
  Widget build(BuildContext context) {
    // Keep the existing build implementation.
    final data = switch (destination) {
      ProfileDestination.account => (
        'Account & earnings',
        Icons.account_balance_wallet_outlined,
        'Your creator finances will appear here.',
        <(IconData, String, String)>[
          (
            Icons.bar_chart_rounded,
            'Earnings report',
            'Earnings history and breakdowns will be connected when the earnings backend is available.',
          ),
          (
            Icons.payments_outlined,
            'Payout methods',
            'Secure payout onboarding and payout history are not connected yet.',
          ),
          (
            Icons.account_balance_outlined,
            'Available balance',
            'Your verified balance will appear when the earnings ledger is implemented.',
          ),
        ],
      ),
      ProfileDestination.settings => (
        'Settings',
        Icons.settings_outlined,
        'Manage your host account preferences.',
        <(IconData, String, String)>[
          (
            Icons.lock_outline,
            'Account security',
            'Security settings will be added with the account-management workflow.',
          ),
          (
            Icons.tune_rounded,
            'App preferences',
            'Additional preferences will be available here as they are implemented.',
          ),
        ],
      ),
      ProfileDestination.notifications => (
        'Notifications',
        Icons.notifications_none_rounded,
        'Choose how you stay informed.',
        <(IconData, String, String)>[
          (
            Icons.notifications_active_outlined,
            'Notification preferences',
            'Notification controls are not connected yet.',
          ),
        ],
      ),
      ProfileDestination.privacy => (
        'Privacy & safety',
        Icons.shield_outlined,
        'Information about protecting your account.',
        <(IconData, String, String)>[
          (
            Icons.privacy_tip_outlined,
            'Privacy controls',
            'Privacy controls will be added alongside platform privacy and safety features.',
          ),
          (
            Icons.block_outlined,
            'Blocked users and reports',
            'These controls will appear when moderation features are available.',
          ),
        ],
      ),
      ProfileDestination.support => (
        'Help & support',
        Icons.support_agent_rounded,
        'Find help with your host account.',
        <(IconData, String, String)>[
          (
            Icons.help_outline_rounded,
            'Frequently asked questions',
            'Help articles are not connected yet.',
          ),
          (
            Icons.bug_report_outlined,
            'Report a problem',
            'Support ticket submission will be added with the support workflow.',
          ),
        ],
      ),
      ProfileDestination.legal => (
        'Legal',
        Icons.policy_outlined,
        'Policies for using the platform.',
        <(IconData, String, String)>[
          (
            Icons.description_outlined,
            'Terms of service',
            'The approved terms-of-service link has not been configured yet.',
          ),
          (
            Icons.privacy_tip_outlined,
            'Privacy policy',
            'The approved privacy-policy link has not been configured yet.',
          ),
        ],
      ),
    };
    return Scaffold(
      appBar: AppBar(title: Text(data.$1)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: _accent.withValues(alpha: .14),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Icon(data.$2, color: _accent, size: 26),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      data.$3,
                      style: const TextStyle(
                        color: Color(0xFFB9BECA),
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            for (final item in data.$4)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _border),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(item.$1, color: _accent, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.$2,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            item.$3,
                            style: const TextStyle(
                              color: _muted,
                              height: 1.4,
                              fontSize: 12,
                            ),
                          ),
                        ],
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
