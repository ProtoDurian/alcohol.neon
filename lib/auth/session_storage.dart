// The SDK exports LogtoClient's storageProvider parameter but not its type.
// ignore: implementation_imports
import 'package:logto_dart_sdk/src/modules/logto_storage_strategy.dart';

// ignore: implementation_imports
export 'package:logto_dart_sdk/src/modules/logto_storage_strategy.dart'
    show LogtoStorageStrategy;

/// The Logto SDK's token storage, which can drop the saved session at once.
///
/// The SDK's `signOut` deletes its saved tokens only after the network call
/// that revokes them (and on Android before the end-session page). An app
/// closed during that call kept the session, so it opened signed in again.
/// [detach] deletes the saved tokens first and keeps them in memory, so the
/// SDK's sign-out can still revoke them.
class SessionStorage implements LogtoStorageStrategy {
  SessionStorage([LogtoStorageStrategy? saved])
    : _saved = saved ?? SecureStorageStrategy();

  final LogtoStorageStrategy _saved;

  /// The SDK's storage keys (token_storage.dart, not exported).
  static const keys = [
    'logto_access_token',
    'logto_refresh_token',
    'logto_id_token',
  ];

  /// The session's tokens while detached; writes stay here too, so a token
  /// refresh that lands after sign-out never saves the old session again.
  Map<String, String?>? _held;

  /// Deletes the saved session now; this run keeps it in memory.
  Future<void> detach() async {
    if (_held != null) return;
    final held = _held = {};
    for (final key in keys) {
      final value = await _saved.read(key: key);
      held.putIfAbsent(key, () => value);
      await _saved.delete(key: key);
    }
  }

  /// Saves tokens again (a new sign-in is starting).
  void attach() => _held = null;

  @override
  Future<String?> read({required String key}) async {
    final held = _held;
    if (held != null && held.containsKey(key)) return held[key];
    return _saved.read(key: key);
  }

  @override
  Future<void> write({required String key, required String? value}) async {
    final held = _held;
    if (held != null) {
      held[key] = value;
      return;
    }
    await _saved.write(key: key, value: value);
  }

  @override
  Future<void> delete({required String key}) async {
    _held?[key] = null;
    await _saved.delete(key: key);
  }
}
