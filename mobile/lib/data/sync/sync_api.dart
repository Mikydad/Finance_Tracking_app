import 'package:supabase_flutter/supabase_flutter.dart';

/// One changed row from `sync_pull`, in the server's column names.
class RemoteChange {
  const RemoteChange(this.table, this.row);

  final String table;
  final Map<String, dynamic> row;
}

class PullPage {
  const PullPage({required this.changes, required this.cursor, required this.hasMore});

  factory PullPage.fromJson(Map<String, dynamic> json) => PullPage(
    changes: [
      for (final c in json['changes'] as List)
        RemoteChange(c['table'] as String, Map<String, dynamic>.from(c['row'] as Map)),
    ],
    cursor: (json['cursor'] as num).toInt(),
    hasMore: json['has_more'] as bool,
  );

  final List<RemoteChange> changes;
  final int cursor;
  final bool hasMore;
}

/// The server's answer for one pushed op, in the order the ops were sent.
class PushResult {
  const PushResult({required this.ok, this.error});

  factory PushResult.fromJson(Map<String, dynamic> json) =>
      PushResult(ok: json['ok'] as bool, error: json['error'] as String?);

  final bool ok;
  final String? error;
}

/// The two sync RPCs. Throws on network or auth failures; a rejected op is
/// reported in its [PushResult] instead.
abstract class SyncApi {
  Future<PullPage> pull(int since, int limit);

  /// [ops] are `{table, op, row}` maps, as `sync_push` expects.
  Future<List<PushResult>> push(List<Map<String, Object?>> ops);
}

class SupabaseSyncApi implements SyncApi {
  SupabaseSyncApi(this._client);

  final SupabaseClient _client;

  @override
  Future<PullPage> pull(int since, int limit) async {
    final res = await _client.rpc('sync_pull', params: {'p_since': since, 'p_limit': limit});
    return PullPage.fromJson(Map<String, dynamic>.from(res as Map));
  }

  @override
  Future<List<PushResult>> push(List<Map<String, Object?>> ops) async {
    final res = await _client.rpc('sync_push', params: {'p_ops': ops});
    return [for (final r in (res as Map)['results'] as List) PushResult.fromJson(Map<String, dynamic>.from(r as Map))];
  }
}
