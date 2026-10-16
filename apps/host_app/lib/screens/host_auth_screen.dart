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
  int _step = 0;
  DateTime? _dateOfBirth;

  static const _stepTitles = [
    'Account details',
    'Login credentials',
    'Age eligibility',
  ];

  String _isoDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  bool _isAtLeast18(DateTime dob) {
    final today = DateTime.now();
    final cutoff = DateTime(today.year - 18, today.month, today.day);
    return !dob.isAfter(cutoff);
  }

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

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  bool _validateCurrentStep() {
    if (_step == 0) {
      if (_displayName.text.trim().isEmpty) {
        _showMessage('Enter your display name.');
        return false;
      }

      if (_referralCode.text.trim().isEmpty) {
        _showMessage('A host referral code is required.');
        return false;
      }
    }

    if (_step == 1) {
      final email = _email.text.trim();

      if (email.isEmpty || !email.contains('@')) {
        _showMessage('Enter a valid email address.');
        return false;
      }

      if (_password.text.length < 6) {
        _showMessage('Password must contain at least 6 characters.');
        return false;
      }
    }

    return true;
  }

  void _nextStep() {
    if (!_validateCurrentStep()) return;
    FocusScope.of(context).unfocus();
    setState(() => _step++);
  }

  Future<void> _submitLogin() async {
    final email = _email.text.trim();
    final password = _password.text;

    if (email.isEmpty || password.isEmpty) {
      _showMessage('Enter your email and password.');
      return;
    }

    setState(() => _loading = true);

    try {
      final response = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (response.session == null && mounted) {
        _showMessage('No active session was returned. Please try again.');
      }
    } on AuthException catch (error) {
      _showMessage(error.message);
    } catch (error) {
      debugPrint('Host sign-in failed: ${error.runtimeType}');
      _showMessage('Unable to sign in right now. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createAccount() async {
    final dob = _dateOfBirth;

    if (dob == null) {
      _showMessage('Select your date of birth.');
      return;
    }

    if (!_isAtLeast18(dob)) {
      _showMessage('You must be at least 18 to register as a host.');
      return;
    }

    setState(() => _loading = true);
    FocusScope.of(context).unfocus();

    try {
      final response = await _supabase.auth.signUp(
        email: _email.text.trim(),
        password: _password.text,
        data: {
          'display_name': _displayName.text.trim(),
          'account_type': 'host',
          'referral_code': _referralCode.text.trim().toUpperCase(),
          'date_of_birth': _isoDate(dob),
        },
      );

      if (!mounted) return;

      if (response.session == null) {
        _showMessage(
          'Check your email to confirm your account. Then sign in to '
          'continue host setup and verify your location.',
        );
      } else {
        _showMessage(
          'Account created. Continue by verifying your device location.',
        );
      }
    } on AuthException catch (error) {
      _showMessage(error.message);
    } catch (error) {
      debugPrint('Host registration failed: ${error.runtimeType}');
      _showMessage('Unable to create your account. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _switchMode() {
    setState(() {
      _isLogin = !_isLogin;
      _step = 0;
    });
  }

  Widget _buildRegistrationStep() {
    switch (_step) {
      case 0:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _displayName,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Display name',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _referralCode,
              textCapitalization: TextCapitalization.characters,
              autocorrect: false,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Host referral code',
                prefixIcon: Icon(Icons.confirmation_number_outlined),
              ),
              onSubmitted: (_) => _nextStep(),
            ),
            const SizedBox(height: 12),
            const Text(
              'A valid agent referral code is required to register as a host.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        );

      case 1:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.email_outlined),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _password,
              obscureText: _obscurePassword,
              autocorrect: false,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                  icon: Icon(
                    _obscurePassword ? Icons.visibility : Icons.visibility_off,
                  ),
                ),
              ),
              onSubmitted: (_) => _nextStep(),
            ),
            const SizedBox(height: 12),
            const Text(
              'Use at least 6 characters. Keep your password private.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        );

      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.verified_user_outlined, size: 48),
            const SizedBox(height: 16),
            const Text(
              'Hosts must be at least 18 years old.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _loading ? null : _chooseDateOfBirth,
              icon: const Icon(Icons.calendar_month_outlined),
              label: Text(
                _dateOfBirth == null
                    ? 'Choose date of birth'
                    : 'Date of birth: ${_isoDate(_dateOfBirth!)}',
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Your date of birth is checked by the server. Your account '
              'will not be created if the age requirement is not met.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12),
            ),
          ],
        );
    }
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
    final title = _isLogin ? 'Host sign in' : _stepTitles[_step];

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
                    title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isLogin
                        ? 'Sign in to continue to your host account.'
                        : 'Host registration · Step ${_step + 1} of 3',
                    textAlign: TextAlign.center,
                  ),
                  if (!_isLogin) ...[
                    const SizedBox(height: 20),
                    LinearProgressIndicator(value: (_step + 1) / 3),
                    const SizedBox(height: 24),
                    _buildRegistrationStep(),
                    const SizedBox(height: 24),
                    if (_step > 0)
                      OutlinedButton(
                        onPressed: _loading
                            ? null
                            : () => setState(() => _step--),
                        child: const Text('Back'),
                      ),
                    const SizedBox(height: 10),
                    FilledButton(
                      onPressed: _loading
                          ? null
                          : _step < 2
                          ? _nextStep
                          : _createAccount,
                      child: _loading
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              _step < 2 ? 'Continue' : 'Create host account',
                            ),
                    ),
                  ] else ...[
                    const SizedBox(height: 24),
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                    ),
                    const SizedBox(height: 16),
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
                        if (!_loading) _submitLogin();
                      },
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _loading ? null : _submitLogin,
                      child: _loading
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Sign in'),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _loading ? null : _switchMode,
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
