import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Email + password sign-in. New accounts are confirmed with the code from
/// the confirmation email, typed into the app, so no web page or deep link
/// is needed. A forgotten password is reset the same way: an emailed code,
/// then a new password. Google and Apple come later.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key, this.auth});

  /// Defaults to the Supabase client's auth; injectable for tests.
  final GoTrueClient? auth;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

enum _Step { signIn, createAccount, enterCode, forgotPassword, resetPassword }

/// Supabase's default minimum (auth.password.minimum_password_length).
const _minPasswordLength = 6;

class _SignInScreenState extends State<SignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  final _newPassword = TextEditingController();
  _Step _step = _Step.signIn;
  bool _busy = false;
  String? _message;

  GoTrueClient get _auth => widget.auth ?? Supabase.instance.client.auth;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _code.dispose();
    _newPassword.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } on AuthException catch (e) {
      if (mounted) setState(() => _message = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signIn() => _run(() async {
    try {
      await _auth.signInWithPassword(email: _email.text.trim(), password: _password.text);
    } on AuthException catch (e) {
      if (e.code != ErrorCode.emailNotConfirmed.code) rethrow;
      // Signed up earlier but never confirmed: send a fresh code.
      await _auth.resend(type: OtpType.signup, email: _email.text.trim());
      _askForCode();
    }
  });

  Future<void> _createAccount() => _run(() async {
    final res = await _auth.signUp(email: _email.text.trim(), password: _password.text);
    // With confirmation turned off in Supabase the user is signed in now.
    if (res.session == null) _askForCode();
  });

  Future<void> _verify() => _run(() async {
    await _auth.verifyOTP(type: OtpType.signup, email: _email.text.trim(), token: _code.text.trim());
    // Signed in; the router takes it from here.
  });

  Future<void> _resend() => _run(() async {
    await _auth.resend(type: OtpType.signup, email: _email.text.trim());
    if (mounted) setState(() => _message = 'We sent a new code.');
  });

  Future<void> _sendResetCode() => _run(() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(() => _message = 'Enter your email first.');
      return;
    }
    await _auth.resetPasswordForEmail(email);
    if (!mounted) return;
    setState(() {
      _step = _Step.resetPassword;
      _code.clear();
      _newPassword.clear();
      _message = null;
    });
  });

  Future<void> _resendResetCode() => _run(() async {
    await _auth.resetPasswordForEmail(_email.text.trim());
    if (mounted) setState(() => _message = 'We sent a new code.');
  });

  Future<void> _resetPassword() => _run(() async {
    final password = _newPassword.text;
    if (password.length < _minPasswordLength) {
      setState(() => _message = 'Use at least $_minPasswordLength characters.');
      return;
    }
    // Read before the first await: a valid code signs the user in, and the
    // router replaces this screen while the password is still being saved.
    final auth = _auth;
    final messenger = ScaffoldMessenger.maybeOf(context);
    await auth.verifyOTP(type: OtpType.recovery, email: _email.text.trim(), token: _code.text.trim());
    try {
      await auth.updateUser(UserAttributes(password: password));
    } on AuthException catch (e) {
      // Typing the old password again is fine: they're signed in with it.
      if (e.code == 'same_password') return;
      // Don't leave them signed in with a password they don't know.
      await auth.signOut();
      final message = "Your password wasn't changed: ${e.message} Ask for a new code and try again.";
      if (mounted) {
        setState(() {
          _step = _Step.forgotPassword;
          _message = message;
        });
      } else {
        messenger?.showSnackBar(SnackBar(content: Text(message)));
      }
    }
  });

  void _goTo(_Step step) => setState(() {
    _step = step;
    _message = null;
  });

  void _askForCode() {
    if (!mounted) return;
    setState(() {
      _step = _Step.enterCode;
      _code.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...switch (_step) {
                  _Step.enterCode => _codeForm(context),
                  _Step.forgotPassword => _forgotForm(context),
                  _Step.resetPassword => _resetForm(context),
                  _Step.signIn || _Step.createAccount => _credentialsForm(context),
                },
                if (_message != null) ...[
                  const SizedBox(height: 12),
                  Text(_message!, key: const Key('message'), textAlign: TextAlign.center),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _credentialsForm(BuildContext context) {
    final creating = _step == _Step.createAccount;
    return [
      Text('Know where your money goes', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 24),
      TextField(
        key: const Key('email'),
        controller: _email,
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.email],
        decoration: const InputDecoration(labelText: 'Email'),
      ),
      const SizedBox(height: 12),
      TextField(
        key: const Key('password'),
        controller: _password,
        obscureText: true,
        autofillHints: [creating ? AutofillHints.newPassword : AutofillHints.password],
        decoration: const InputDecoration(labelText: 'Password'),
      ),
      const SizedBox(height: 24),
      FilledButton(
        key: const Key('submit'),
        onPressed: _busy ? null : (creating ? _createAccount : _signIn),
        child: Text(creating ? 'Create account' : 'Sign in'),
      ),
      if (!creating)
        TextButton(onPressed: _busy ? null : () => _goTo(_Step.forgotPassword), child: const Text('Forgot password?')),
      TextButton(
        onPressed: _busy ? null : () => _goTo(creating ? _Step.signIn : _Step.createAccount),
        child: Text(creating ? 'I already have an account' : 'Create an account'),
      ),
    ];
  }

  List<Widget> _forgotForm(BuildContext context) {
    return [
      Text('Reset your password', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 8),
      const Text("Enter your account's email and we'll send you a code."),
      const SizedBox(height: 24),
      TextField(
        key: const Key('email'),
        controller: _email,
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.email],
        decoration: const InputDecoration(labelText: 'Email'),
        onSubmitted: (_) => _busy ? null : _sendResetCode(),
      ),
      const SizedBox(height: 24),
      FilledButton(
        key: const Key('send-reset-code'),
        onPressed: _busy ? null : _sendResetCode,
        child: const Text('Send code'),
      ),
      TextButton(onPressed: _busy ? null : () => _goTo(_Step.signIn), child: const Text('Back to sign in')),
    ];
  }

  List<Widget> _resetForm(BuildContext context) {
    return [
      Text('Check your email', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 8),
      Text(
        'If ${_email.text.trim()} has an account, we sent it a code. '
        'Enter the code and choose a new password.',
      ),
      const SizedBox(height: 24),
      TextField(
        key: const Key('code'),
        controller: _code,
        keyboardType: TextInputType.number,
        autofillHints: const [AutofillHints.oneTimeCode],
        maxLength: 10,
        decoration: const InputDecoration(labelText: 'Code', counterText: ''),
      ),
      const SizedBox(height: 12),
      TextField(
        key: const Key('new-password'),
        controller: _newPassword,
        obscureText: true,
        autofillHints: const [AutofillHints.newPassword],
        decoration: const InputDecoration(labelText: 'New password'),
        onSubmitted: (_) => _busy ? null : _resetPassword(),
      ),
      const SizedBox(height: 24),
      FilledButton(
        key: const Key('reset'),
        onPressed: _busy ? null : _resetPassword,
        child: const Text('Set new password'),
      ),
      TextButton(onPressed: _busy ? null : _resendResetCode, child: const Text('Send a new code')),
      TextButton(onPressed: _busy ? null : () => _goTo(_Step.signIn), child: const Text('Back to sign in')),
    ];
  }

  List<Widget> _codeForm(BuildContext context) {
    return [
      Text('Check your email', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 8),
      Text('We sent a code to ${_email.text.trim()}. Enter it here to finish creating your account.'),
      const SizedBox(height: 24),
      TextField(
        key: const Key('code'),
        controller: _code,
        keyboardType: TextInputType.number,
        autofillHints: const [AutofillHints.oneTimeCode],
        maxLength: 10,
        decoration: const InputDecoration(labelText: 'Code', counterText: ''),
        onSubmitted: (_) => _busy ? null : _verify(),
      ),
      const SizedBox(height: 24),
      FilledButton(key: const Key('verify'), onPressed: _busy ? null : _verify, child: const Text('Confirm')),
      TextButton(onPressed: _busy ? null : _resend, child: const Text('Send a new code')),
      TextButton(onPressed: _busy ? null : () => _goTo(_Step.signIn), child: const Text('Back to sign in')),
    ];
  }
}
