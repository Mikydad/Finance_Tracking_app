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
  Future<AuthResponse> signInWithPassword({String? email, String? phone, required String password, String? captchaToken}) async {
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
}
