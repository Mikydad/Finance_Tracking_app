import 'package:finance_app/core/config.dart';
import 'package:finance_app/core/theme.dart';
import 'package:finance_app/data/remote/capture_api.dart';
import 'package:finance_app/features/capture/paste_sms_screen.dart';
import 'package:finance_app/features/capture/shortcut_setup_screen.dart';
import 'package:finance_app/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class FakeCapture implements CaptureApi {
  IngestResult next = const IngestCreated('tx-1');
  final sent = <(String, String?)>[];
  final keys = <IngestionToken>[];
  final revoked = <String>[];

  @override
  Future<IngestResult> ingest({required String text, String? sender, DateTime? receivedAt}) async {
    sent.add((text, sender));
    return next;
  }

  @override
  Future<String> createToken(String name) async {
    keys.add(IngestionToken(id: 'k${keys.length}', name: name, createdAt: DateTime(2026, 10, 6)));
    return 'fin_abc123';
  }

  @override
  Future<void> revokeToken(String id) async {
    revoked.add(id);
    keys.removeWhere((k) => k.id == id);
  }

  @override
  Future<List<IngestionToken>> tokens() async => [...keys];
}

const backend = AppConfig(supabaseUrl: 'https://example.supabase.co', supabasePublishableKey: 'pk');

Future<void> pump(WidgetTester tester, FakeCapture api, Widget screen) async {
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => screen),
      GoRoute(path: '/transactions/:id', builder: (_, s) => Text('detail ${s.pathParameters['id']}')),
      GoRoute(path: '/add', builder: (_, _) => const Text('add screen')),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        configProvider.overrideWithValue(backend),
        captureApiProvider.overrideWithValue(api),
        syncSchedulerProvider.overrideWithValue(null),
      ],
      child: MaterialApp.router(theme: buildAppTheme(), routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('ingest results are read from the function response', () {
    expect(
      IngestResult.fromJson({'status': 'created', 'transactionId': 't', 'reviewReason': null}),
      isA<IngestCreated>().having((r) => r.needsReview, 'needsReview', false),
    );
    expect(
      IngestResult.fromJson({'status': 'created', 'transactionId': 't', 'reviewReason': 'possible_duplicate'}),
      isA<IngestCreated>().having((r) => r.needsReview, 'needsReview', true),
    );
    expect(
      IngestResult.fromJson({'status': 'ignored', 'reason': 'otp'}),
      isA<IngestIgnored>().having((r) => r.reason, 'reason', 'otp'),
    );
    expect(IngestResult.fromJson({'status': 'unrecognized'}), isA<IngestUnrecognized>());
  });

  testWidgets('paste: pasted SMS is sent with the sender, and the result links to the transaction', (tester) async {
    final api = FakeCapture();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method != 'Clipboard.getData') return null;
      return {'text': ' Dear Customer, your account has been debited with ETB 500.00 '};
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await pump(tester, api, const PasteSmsScreen());

    await tester.tap(find.byKey(const Key('paste')));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Don't know"));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CBE').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('send')));
    await tester.pumpAndSettle();

    expect(api.sent.single, ('Dear Customer, your account has been debited with ETB 500.00', 'CBE'));
    expect(find.text('Added'), findsOneWidget);
    await tester.tap(find.text('View transaction'));
    await tester.pumpAndSettle();
    expect(find.text('detail tx-1'), findsOneWidget);
  });

  testWidgets('paste: skipped and unreadable messages explain why', (tester) async {
    final api = FakeCapture()..next = const IngestIgnored('otp');
    await pump(tester, api, const PasteSmsScreen());
    await tester.enterText(find.byKey(const Key('sms-text')), 'Your OTP is 123456');
    await tester.pump();
    await tester.tap(find.byKey(const Key('send')));
    await tester.pumpAndSettle();
    expect(find.text("That's a one-time code, not a payment."), findsOneWidget);

    api.next = const IngestUnrecognized();
    await tester.tap(find.byKey(const Key('send')));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't read this message"), findsOneWidget);
    await tester.ensureVisible(find.text('Add by hand'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add by hand'));
    await tester.pumpAndSettle();
    expect(find.text('add screen'), findsOneWidget);
  });

  testWidgets('shortcut setup: create a key, see it once, turn it off', (tester) async {
    final api = FakeCapture();
    await pump(tester, api, const ShortcutSetupScreen());
    expect(find.textContaining('https://example.supabase.co/functions/v1/ingest'), findsOneWidget);

    await tester.tap(find.byKey(const Key('create-key')));
    await tester.pumpAndSettle();
    expect(find.text('fin_abc123'), findsOneWidget);
    expect(find.textContaining('not used yet'), findsOneWidget);

    await tester.tap(find.text('Turn off').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Turn off').last);
    await tester.pumpAndSettle();
    expect(api.revoked, ['k0']);
    expect(find.textContaining('not used yet'), findsNothing);
  });
}
