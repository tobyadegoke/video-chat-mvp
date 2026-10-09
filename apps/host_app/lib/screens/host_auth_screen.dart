import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Host login and referral-based signup.
/// The database validates the referral code and assigns the host role.
/// Never send a client-selected `role` value.
class HostAuthScreen extends StatefulWidget {
  const HostAuthScreen({super.key});

  @override
  State<HostAuthScreen> createState() => _HostAuthScreenState();
}

class _HostAuthScreenState extends State<HostAuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _referralCodeController = TextEditingController();

  bool _isLogin = true;
  bool _isLoading = false;
  bool _obscurePassword = true;

  SupabaseClient get _supabase => Supabase.instance.client;

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final displayName = _displayNameController.text.trim();
    final referralCode = _referralCodeController.text.trim().toUpperCase();

    if (email.isEmpty || password.isEmpty) {
      _showMessage('Please enter your email and password.');
      return;
    }

    if (!_isLogin && displayName.isEmpty) {
      _showMessage('Please enter your display name.');
      return;
    }

    if (!_isLogin && referralCode.isEmpty) {
      _showMessage('A host referral code is required.');
      return;
    }

    if (!_isLogin && password.length < 6) {
      _showMessage('Password must contain at least 6 characters.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (_isLogin) {
        await _supabase.auth.signInWithPassword(
          email: email,
          password: password,
        );
        if (!mounted) return;
        _showMessage('Signed in successfully.');
      } else {
        final response = await _supabase.auth.signUp(
          email: email,
          password: password,
          data: {
            'display_name': displayName,
            'account_type': 'host',
            'referral_code': referralCode,
          },
        );

        if (!mounted) return;
        _showMessage(
          response.session == null
              ? 'Account request accepted. Check your email to verify your account.'
              : 'Host account created successfully.',
        );
      }
      // The app-level auth/session listener should route signed-in users onward.
    } on AuthException catch (error) {
      _showMessage(error.message);
    } catch (_) {
      _showMessage('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _displayNameController.dispose();
    _referralCodeController.dispose();
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
                    size: 72,
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
                        ? 'Sign in to manage your host account.'
                        : 'Create a host account using your referral code.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  if (!_isLogin) ...[
                    TextField(
                      controller: _displayNameController,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Display name',
                        prefixIcon: Icon(Icons.person_outline),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _referralCodeController,
                      textCapitalization: TextCapitalization.characters,
                      autocorrect: false,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Host referral code',
                        prefixIcon: Icon(Icons.confirmation_number_outlined),
                        border: OutlineInputBorder(),
                        helperText: 'Paste Agent Referral Code here to create a host account.',
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.email_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    enableSuggestions: false,
                    autocorrect: false,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _isLoading ? null : _submit(),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      border: const OutlineInputBorder(),
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
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 54,
                    child: FilledButton(
                      onPressed: _isLoading ? null : _submit,
                      child: _isLoading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_isLogin ? 'Sign In' : 'Create Host Account'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _isLoading
                        ? null
                        : () => setState(() => _isLogin = !_isLogin),
                    child: Text(
                      _isLogin
                          ? 'Need a host account? Register with a referral code'
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
