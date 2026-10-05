import 'dart:async';
import 'dart:math';

import 'sync_engine.dart';

/// Decides when to sync: right away on start, shortly after local writes,
/// when the server says something changed, and with growing back-off after a
/// failure (5 s doubling up to 5 min).
class SyncScheduler {
  SyncScheduler(
    this._engine, {
    required this.localChanges,
    this.remoteChanges = const Stream.empty(),
    this.localDelay = const Duration(seconds: 2),
    this.remoteDelay = const Duration(milliseconds: 500),
  });

  final SyncEngine _engine;

  /// Local writes waiting to be pushed.
  final Stream<void> localChanges;

  /// "Something changed on the server" nudges, e.g. from Realtime.
  final Stream<void> remoteChanges;
  final Duration localDelay;
  final Duration remoteDelay;

  final _subs = <StreamSubscription<void>>[];
  Timer? _debounce;
  Timer? _retry;
  int _failures = 0;
  bool _disposed = false;

  /// The last sync error, or null after a successful sync.
  Object? lastError;

  void start() {
    _subs
      ..add(localChanges.listen((_) => _soon(localDelay)))
      ..add(remoteChanges.listen((_) => _soon(remoteDelay)));
    unawaited(syncNow());
  }

  /// Syncs now; returns false (and schedules a retry) if it failed.
  Future<bool> syncNow() async {
    if (_disposed) return false;
    _debounce?.cancel();
    _retry?.cancel();
    try {
      await _engine.sync();
      _failures = 0;
      lastError = null;
      return true;
    } catch (e) {
      lastError = e;
      _failures++;
      if (!_disposed) {
        final seconds = min(5 * pow(2, _failures - 1), 300).toInt();
        _retry = Timer(Duration(seconds: seconds), syncNow);
      }
      return false;
    }
  }

  void _soon(Duration delay) {
    if (_disposed) return;
    _debounce?.cancel();
    _debounce = Timer(delay, syncNow);
  }

  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    _retry?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
  }
}
