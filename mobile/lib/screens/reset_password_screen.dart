// mobile/lib/screens/reset_password_screen.dart
//
// The "set a new password" step of password recovery. Reached two ways:
//   * the member tapped the reset link on their phone -> the email-confirmed
//     function sent them to richfield://auth/recovery?code=… -> supabase_flutter
//     exchanged the code for a session -> AuthService.recoveryPending is set
//     and the router parks them here until a new password is saved;
//   * or they typed the 6-digit code on the Forgot-password screen, which
//     does the same thing without a browser (ForgotPasswordScreen).
// Either way there is already a signed-in session; this screen only calls
// updateUser(password) and then lets the router carry on to Home.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../main.dart' show AppColors, AppRadius, AppSpace, AppText, PrimaryButton;
import '../services/auth_error_mapper.dart';
import '../services/auth_service.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key, required this.authService});

  final AuthService authService;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final password = _password.text;
    if (password.length < 8) {
      setState(() => _error = 'Use at least 8 characters.');
      return;
    }
    if (password != _confirm.text) {
      setState(() => _error = 'The two passwords don\'t match.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.authService.updatePassword(password);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Password updated. You\'re signed in.')),
      );
      context.go('/home');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = AuthErrorMapper.fromAny(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceContainerLow,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceContainerLow,
        elevation: 0,
        foregroundColor: AppColors.onSurface,
        title: Text('New password'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(AppSpace.base),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: AppSpace.md),
              Icon(Icons.lock_reset_outlined, size: 48, color: AppColors.primary),
              SizedBox(height: AppSpace.md),
              Text('Choose a new password', style: AppText.headlineLg(), textAlign: TextAlign.center),
              SizedBox(height: AppSpace.sm),
              Text(
                'Your reset link was verified. Set a new password to finish.',
                style: AppText.bodyMd(color: AppColors.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: AppSpace.lg),
              _field(_password, 'New password', autofocus: true),
              SizedBox(height: AppSpace.sm),
              _field(_confirm, 'Repeat new password'),
              if (_error != null) ...[
                SizedBox(height: AppSpace.sm),
                Text(_error!, style: AppText.bodySm(color: AppColors.error)),
              ],
              SizedBox(height: AppSpace.lg),
              PrimaryButton(
                label: _saving ? 'Saving…' : 'Save password',
                icon: Icons.check,
                onPressed: _saving ? null : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController controller, String label, {bool autofocus = false}) {
    return TextField(
      controller: controller,
      obscureText: _obscure,
      autofocus: autofocus,
      autofillHints: const [AutofillHints.newPassword],
      onSubmitted: (_) => _save(),
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: AppColors.surfaceContainerLowest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          borderSide: BorderSide.none,
        ),
        suffixIcon: IconButton(
          icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18),
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
      ),
    );
  }
}
