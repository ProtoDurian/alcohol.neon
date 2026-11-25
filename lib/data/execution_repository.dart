import '../core/problem.dart';
import '../generated/zinc/models/complete_habit_req.dart';
import '../generated/zinc/models/habit_execution_res.dart';
import '../generated/zinc/models/skip_habit_req.dart';
import '../networking/api_client.dart';

/// zinc `/Habit/{userId}` execution endpoints — completing, skipping, and
/// listing a user's habit executions. All authenticated (paths under
/// `/{userId}/`).
class ExecutionRepository {
  final ApiClient _api;
  ExecutionRepository(this._api);

  static const _base = '/api/v1.0/Habit';

  /// Marks a habit version complete for the user
  /// (`POST /Habit/{userId}/{habitVersionId}/executions`).
  Future<Result<HabitExecutionRes>> complete(
    String userId,
    String habitVersionId, {
    CompleteHabitReq? req,
  }) {
    return _api.post(
      '$_base/$userId/$habitVersionId/executions',
      req?.toJson(),
      (j) => HabitExecutionRes.fromJson(j as Map<String, Object?>),
    );
  }

  /// Skips a habit version for the user
  /// (`POST /Habit/{userId}/{habitVersionId}/executions/skip`).
  Future<Result<HabitExecutionRes>> skip(
    String userId,
    String habitVersionId, {
    SkipHabitReq? req,
  }) {
    return _api.post(
      '$_base/$userId/$habitVersionId/executions/skip',
      req?.toJson(),
      (j) => HabitExecutionRes.fromJson(j as Map<String, Object?>),
    );
  }

  /// Builds that may offer Undo before zinc's route ships. Off in every
  /// release; screenshot and preview builds pass
  /// `--dart-define=NEON_UNDO_PREVIEW=true`.
  static const undoPreview = bool.fromEnvironment('NEON_UNDO_PREVIEW');

  /// Takes back today's manual check-in.
  ///
  /// SEAM: zinc's undo route is still being built
  /// (thread T-01a20cac-1b19-70d4-8455-7022a5d5a683). This path is a
  /// placeholder: replace it with the real route, then turn [undoAvailable]
  /// on. Until then nothing calls it outside preview builds.
  Future<Result<void>> undoComplete(String userId, String habitVersionId) {
    return _api.delete('$_base/$userId/$habitVersionId/executions/today');
  }

  /// Whether this build shows Undo at all (the route exists).
  static bool get undoAvailable => undoPreview;

  /// Lists the user's executions (`GET /Habit/{userId}/executions`), optionally
  /// filtered by [date] (`yyyy-MM-dd`) and paged via [limit]/[skip].
  Future<Result<List<HabitExecutionRes>>> onDate(
    String userId, {
    String? date,
    int? limit,
    int? skip,
  }) {
    return _api.get(
      '$_base/$userId/executions',
      (j) => (j as List<dynamic>)
          .map((e) => HabitExecutionRes.fromJson(e as Map<String, Object?>))
          .toList(),
      query: {'Date': date, 'Limit': limit, 'Skip': skip},
    );
  }
}
