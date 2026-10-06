import 'package:supabase_flutter/supabase_flutter.dart';

/// What the `ingest` function did with a message.
sealed class IngestResult {
  const IngestResult();

  factory IngestResult.fromJson(Map<String, dynamic> json) => switch (json['status']) {
    'created' => IngestCreated(json['transactionId'] as String, needsReview: json['reviewReason'] != null),
    'duplicate' => IngestDuplicate(json['transactionId'] as String?),
    'enriched' => IngestEnriched(json['transactionId'] as String),
    'ignored' => IngestIgnored(json['reason'] as String? ?? 'not_a_transaction'),
    _ => const IngestUnrecognized(),
  };
}

class IngestCreated extends IngestResult {
  const IngestCreated(this.transactionId, {this.needsReview = false});
  final String transactionId;
  final bool needsReview;
}

class IngestDuplicate extends IngestResult {
  const IngestDuplicate(this.transactionId);
  final String? transactionId;
}

class IngestEnriched extends IngestResult {
  const IngestEnriched(this.transactionId);
  final String transactionId;
}

class IngestIgnored extends IngestResult {
  const IngestIgnored(this.reason);

  /// otp, credit_line_drawdown, bonus, promo, security_notice, ...
  final String reason;
}

class IngestUnrecognized extends IngestResult {
  const IngestUnrecognized();
}

/// A key the iPhone Shortcut uses to send SMS to `ingest` without signing in.
/// The secret itself is only shown once, when created.
class IngestionToken {
  const IngestionToken({required this.id, required this.name, required this.createdAt, this.lastUsedAt});

  factory IngestionToken.fromJson(Map<String, dynamic> json) => IngestionToken(
    id: json['id'] as String,
    name: json['name'] as String,
    createdAt: DateTime.parse(json['created_at'] as String),
    lastUsedAt: json['last_used_at'] == null ? null : DateTime.parse(json['last_used_at'] as String),
  );

  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime? lastUsedAt;
}

/// Server calls for capturing bank SMS: send one message, and manage the
/// Shortcut's keys.
abstract class CaptureApi {
  Future<IngestResult> ingest({required String text, String? sender, DateTime? receivedAt});

  /// Active (not revoked) keys, newest first.
  Future<List<IngestionToken>> tokens();

  /// Returns the new key's secret (`fin_...`). It can't be read again later.
  Future<String> createToken(String name);

  Future<void> revokeToken(String id);
}

class SupabaseCaptureApi implements CaptureApi {
  SupabaseCaptureApi(this._client);

  final SupabaseClient _client;

  @override
  Future<IngestResult> ingest({required String text, String? sender, DateTime? receivedAt}) async {
    final res = await _client.functions.invoke(
      'ingest',
      body: {
        'text': text,
        'sender': ?sender,
        'receivedAt': (receivedAt ?? DateTime.now()).toUtc().toIso8601String(),
        'channel': 'paste',
      },
    );
    return IngestResult.fromJson(Map<String, dynamic>.from(res.data as Map));
  }

  @override
  Future<List<IngestionToken>> tokens() async {
    final rows = await _client
        .from('ingestion_tokens')
        .select('id, name, last_used_at, created_at')
        .isFilter('revoked_at', null)
        .order('created_at', ascending: false);
    return [for (final r in rows) IngestionToken.fromJson(r)];
  }

  @override
  Future<String> createToken(String name) async {
    final rows = await _client.rpc('create_ingestion_token', params: {'p_name': name}) as List;
    return (rows.single as Map)['token'] as String;
  }

  @override
  Future<void> revokeToken(String id) =>
      _client.from('ingestion_tokens').update({'revoked_at': DateTime.now().toUtc().toIso8601String()}).eq('id', id);
}
