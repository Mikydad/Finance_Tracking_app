import 'package:finance_app/features/auth/sign_in_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Records calls instead of talking to Supabase.
class FakeAuth extends GoTrueClient {
  FakeAuth() : super(url: 'http://localhost', autoRefreshToken: false);

  final calls = <String>[];
  bool confirmed = false;

  @override
  Future<AuthResponse> signUp({
    String? email,
    String? phone,
    required String password,
    String? emailRedirectTo,
    Map<String, dynamic>? data,
    String? captchaToken,
    OtpChannel channel = OtpChannel.sms,
  }) async {
    calls.add('signUp $email');
    return AuthResponse(); // no session: confirmation required
  }

  @override
  Future<AuthResponse> signInWithPassword({
    String? email,
    String? phone,
    required String password,
    String? captchaToken,
  }) async {
    calls.add('signIn $email');
    if (!confirmed) throw AuthException('Email not confirmed', code: 'email_not_confirmed', statusCode: '400');
    return AuthResponse();
  }

  @override
  Future<AuthResponse> verifyOTP({
    String? email,
    String? phone,
    String? token,
    required OtpType type,
    String? redirectTo,
    String? captchaToken,
    String? tokenHash,
  }) async {
    calls.add('verify ${type.name} $email $token');
    if (token != '123456') throw AuthException('Token has expired or is invalid', statusCode: '403');
    return AuthResponse();
  }

  @override
  Future<ResendResponse> resend({
    String? email,
    String? phone,
    required OtpType type,
    String? emailRedirectTo,
    String? captchaToken,
  }) async {
    calls.add('resend ${type.name} $email');
    return ResendResponse();
  }

  @override
  Future<void> resetPasswordForEmail(String email, {String? redirectTo, String? captchaToken}) async {
    calls.add('reset $email');
  }

  AuthException? updateError;

  @override
  Future<UserResponse> updateUser(UserAttributes attributes, {String? emailRedirectTo}) async {
    calls.add('update password ${attributes.password}');
    if (updateError != null) throw updateError!;
    return UserResponse.fromJson({'id': 'user-1'});
  }

  @override
  Future<void> signOut({SignOutScope scope = SignOutScope.local}) async {
    calls.add('signOut');
  }
}

void main() {
  Future<FakeAuth> pump(WidgetTester tester) async {
    final auth = FakeAuth();
    await tester.pumpWidget(MaterialApp(home: SignInScreen(auth: auth)));
    return auth;
  }

  testWidgets('creating an account asks for the emailed code and verifies it', (tester) async {
    final auth = await pump(tester);
    await tester.tap(find.text('Create an account'));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('email')), ' miko@example.com ');
    await tester.enterText(find.byKey(const Key('password')), 'long-password');
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pumpAndSettle();

    expect(find.text('Check your email'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('code')), '000000');
    await tester.tap(find.byKey(const Key('verify')));
    await tester.pumpAndSettle();
    expect(find.text('Token has expired or is invalid'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('code')), '123456');
    await tester.tap(find.byKey(const Key('verify')));
    await tester.pumpAndSettle();
    expect(auth.calls, [
      'signUp miko@example.com',
      'verify signup miko@example.com 000000',
      'verify signup miko@example.com 123456',
    ]);
  });

  testWidgets('signing in before confirming sends a new code and asks for it', (tester) async {
    final auth = await pump(tester);
    await tester.enterText(find.byKey(const Key('email')), 'miko@example.com');
    await tester.enterText(find.byKey(const Key('password')), 'long-password');
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pumpAndSettle();

    expect(find.text('Check your email'), findsOneWidget);
    expect(auth.calls, ['signIn miko@example.com', 'resend signup miko@example.com']);
  });

  Future<void> startReset(WidgetTester tester) async {
    await tester.enterText(find.byKey(const Key('email')), ' miko@example.com ');
    await tester.tap(find.text('Forgot password?'));
    await tester.pump();
    expect(find.text('Reset your password'), findsOneWidget);
    await tester.tap(find.byKey(const Key('send-reset-code')));
    await tester.pumpAndSettle();
    expect(find.text('Check your email'), findsOneWidget);
  }

  Future<void> submitReset(WidgetTester tester, {required String code, required String password}) async {
    await tester.enterText(find.byKey(const Key('code')), code);
    await tester.enterText(find.byKey(const Key('new-password')), password);
    await tester.tap(find.byKey(const Key('reset')));
    await tester.pumpAndSettle();
  }

  testWidgets('forgot password: emailed code, then a new password', (tester) async {
    final auth = await pump(tester);
    await startReset(tester);

    await submitReset(tester, code: '123456', password: 'short');
    expect(find.text('Use at least 6 characters.'), findsOneWidget);

    await submitReset(tester, code: '000000', password: 'new-long-password');
    expect(find.text('Token has expired or is invalid'), findsOneWidget);

    await submitReset(tester, code: '123456', password: 'new-long-password');
    expect(auth.calls, [
      'reset miko@example.com',
      'verify recovery miko@example.com 000000',
      'verify recovery miko@example.com 123456',
      'update password new-long-password',
    ]);
  });

  testWidgets('forgot password: asks for the email first', (tester) async {
    final auth = await pump(tester);
    await tester.tap(find.text('Forgot password?'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('send-reset-code')));
    await tester.pumpAndSettle();
    expect(find.text('Enter your email first.'), findsOneWidget);
    expect(auth.calls, isEmpty);
  });

  testWidgets('forgot password: a rejected new password signs out again and explains', (tester) async {
    final auth = await pump(tester);
    auth.updateError = AuthException('Password is known to be weak.', code: 'weak_password', statusCode: '422');
    await startReset(tester);

    await submitReset(tester, code: '123456', password: 'password123');
    expect(auth.calls.last, 'signOut');
    expect(find.text('Reset your password'), findsOneWidget);
    expect(find.textContaining("Your password wasn't changed: Password is known to be weak."), findsOneWidget);
  });

  testWidgets('forgot password: reusing the old password is not an error', (tester) async {
    final auth = await pump(tester);
    auth.updateError = AuthException('New password should be different.', code: 'same_password', statusCode: '422');
    await startReset(tester);

    await submitReset(tester, code: '123456', password: 'old-password');
    expect(auth.calls.last, 'update password old-password');
    expect(find.byKey(const Key('message')), findsNothing);
  });
}
