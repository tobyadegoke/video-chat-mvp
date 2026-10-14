import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HostAuthScreen extends StatefulWidget {
  const HostAuthScreen({super.key});

  @override
  State<HostAuthScreen> createState() => _HostAuthScreenState();
}

class _HostAuthScreenState extends State<HostAuthScreen> {
  final _supabase = Supabase.instance.client;
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _displayName = TextEditingController();
  final _referralCode = TextEditingController();

  bool _isLogin = true;
  bool _loading = false;
  bool _obscurePassword = true;
  DateTime? _dateOfBirth;

  Future<void> _chooseDateOfBirth() async {
    final today = DateTime.now();
    final latestAllowed = DateTime(today.year - 18, today.month, today.day);

    final selected = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth ?? latestAllowed,
      firstDate: DateTime(1900),
      lastDate: today,
      helpText: 'Select your date of birth',
    );

    if (selected != null && mounted) {
      setState(() => _dateOfBirth = selected);
    }
  }

  String _isoDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  bool _isAtLeast18(DateTime dob) {
    final today = DateTime.now();
    final cutoff = DateTime(today.year - 18, today.month, today.day);
    return !dob.isAfter(cutoff);
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final password = _password.text;
    final displayName = _displayName.text.trim();
    final referralCode = _referralCode.text.trim().toUpperCase();

    if (email.isEmpty || password.isEmpty) {
      _showMessage('Enter your email and password.');
      return;
    }

    if (password.length < 6) {
      _showMessage('Password must contain at least 6 characters.');
      return;
    }

    if (!_isLogin) {
      if (displayName.isEmpty) {
        _showMessage('Enter your display name.');
        return;
      }

      if (referralCode.isEmpty) {
        _showMessage('A host referral code is required.');
        return;
      }

      final dob = _dateOfBirth;
      if (dob == null) {
        _showMessage('Select your date of birth.');
        return;
      }

      if (!_isAtLeast18(dob)) {
        _showMessage('You must be at least 18 to register as a host.');
        return;
      }
    }

    setState(() => _loading = true);

    try {
      if (_isLogin) {
        final response = await _supabase.auth.signInWithPassword(
          email: email,
          password: password,
        );

        if (response.session == null && mounted) {
          _showMessage('No active session was returned.');
        }
      } else {
        final dob = _dateOfBirth!;

        final response = await _supabase.auth.signUp(
          email: email,
          password: password,
          data: {
            'display_name': displayName,
            'account_type': 'host',
            'referral_code': referralCode,
            'date_of_birth': _isoDate(dob),
          },
        );

        if (!mounted) return;

        _showMessage(
          response.session == null
              ? 'Check your email to confirm your account. Then sign in to continue onboarding.'
              : 'Account created. Continue with location onboarding.',
        );
      }
    } on AuthException catch (error) {
      _showMessage(error.message);
    } catch (error) {
      debugPrint('Host authentication failed: ${error.runtimeType}');
      _showMessage('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _displayName.dispose();
    _referralCode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.video_camera_front_rounded,
                    size: 68,
                    color: Colors.redAccent,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    _isLogin ? 'Host sign in' : 'Register as a host',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isLogin
                        ? 'Sign in to continue to your host account.'
                        : 'Create your account using an agent referral code.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  if (!_isLogin) ...[
                    TextField(
                      controller: _displayName,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Display name',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _referralCode,
                      textCapitalization: TextCapitalization.characters,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Host referral code',
                        prefixIcon: Icon(Icons.confirmation_number_outlined),
                      ),
                    ),
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      onPressed: _loading ? null : _chooseDateOfBirth,
                      icon: const Icon(Icons.calendar_month_outlined),
                      label: Text(
                        _dateOfBirth == null
                            ? 'Choose date of birth'
                            : 'Date of birth: ${_isoDate(_dateOfBirth!)}',
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(top: 8, bottom: 12),
                      child: Text(
                        'Hosts must be at least 18 years old. Your date of '
                        'birth is checked by the server.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _password,
                    obscureText: _obscurePassword,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        tooltip: _obscurePassword
                            ? 'Show password'
                            : 'Hide password',
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility
                              : Icons.visibility_off,
                        ),
                      ),
                    ),
                    onSubmitted: (_) {
                      if (!_loading) _submit();
                    },
                  ),
                  const SizedBox(height: 22),
                  FilledButton(
                    onPressed: _loading ? null : _submit,
                    child: _loading
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(_isLogin ? 'Sign in' : 'Create host account'),
                  ),
                  TextButton(
                    onPressed: _loading
                        ? null
                        : () => setState(() => _isLogin = !_isLogin),
                    child: Text(
                      _isLogin
                          ? 'New host? Register with a referral code'
                          : 'Already registered? Sign in',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
