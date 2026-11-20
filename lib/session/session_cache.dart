import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../generated/zinc/models/configuration_principal_res.dart';
import '../generated/zinc/models/habit_overview_response.dart';

/// What the last launch saw: the user's configuration and Today's overview.
class SessionSnapshot {
  final ConfigurationPrincipalRes config;
  final HabitOverviewResponse overview;
  final DateTime savedAt;
  const SessionSnapshot(this.config, this.overview, this.savedAt);
}

/// Saves the configuration and Today's overview to an app-private JSON file so
/// the next launch can show Today at once and refresh it in the background.
/// Keyed by user id, so a different account never shows. A Today saved on an
/// earlier day (up to [maxAge]) is shown dimmed until the fresh one lands.
/// Best-effort: any I/O or decode failure behaves like an empty cache.
class SessionCache {
  final Future<Directory> Function() _dir;
  const SessionCache({Future<Directory> Function()? dir})
    : _dir = dir ?? getApplicationSupportDirectory;

  Future<File> _file() async =>
      File('${(await _dir()).path}/session_cache.json');

  Future<Map<String, dynamic>?> _read() async {
    try {
      final f = await _file();
      if (!await f.exists()) return null;
      return jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  // One write at a time, app-wide: config and overview are saved about one
  // frame apart on every launch, and two read-change-write passes that
  // overlap each keep only their own half, so the next launch had no Today.
  static Future<void> _queue = Future.value();

  Future<void> _write(String userId, String key, Object value) {
    final next = _queue.then((_) => _writeNow(userId, key, value));
    _queue = next;
    return next;
  }

  Future<void> _writeNow(String userId, String key, Object value) async {
    try {
      final old = await _read();
      final m = old != null && old['userId'] == userId
          ? old
          : <String, dynamic>{'userId': userId};
      m[key] = value;
      if (key == 'overview') m['savedAt'] = DateTime.now().toIso8601String();
      // Write a new file and swap it in, so a reader never sees half a file.
      final f = await _file();
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(jsonEncode(m), flush: true);
      await tmp.rename(f.path);
    } catch (_) {
      // Only costs the next launch its instant Today.
    }
  }

  /// The snapshot for [userId] if it is complete and at most [maxAge] old.
  /// A snapshot from an earlier day is still returned: the app shows it
  /// dimmed as "Updating" instead of a loader (see [SessionSnapshot.savedAt]).
  static const maxAge = Duration(days: 7);

  Future<SessionSnapshot?> load(String userId, {DateTime? now}) async {
    final m = await _read();
    if (m == null || m['userId'] != userId) return null;
    try {
      final savedAt = DateTime.parse(m['savedAt'] as String).toLocal();
      final today = (now ?? DateTime.now()).toLocal();
      if (today.difference(savedAt) > maxAge) return null;
      return SessionSnapshot(
        ConfigurationPrincipalRes.fromJson(
          (m['config'] as Map).cast<String, Object?>(),
        ),
        HabitOverviewResponse.fromJson(
          (m['overview'] as Map).cast<String, Object?>(),
        ),
        savedAt,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> saveConfig(String userId, ConfigurationPrincipalRes config) =>
      _write(userId, 'config', config);

  Future<void> saveOverview(String userId, HabitOverviewResponse overview) =>
      _write(userId, 'overview', overview);

  /// Called on sign-out so the next account starts clean.
  Future<void> clear() async {
    try {
      final f = await _file();
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
