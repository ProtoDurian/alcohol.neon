import '../core/problem.dart';
import '../generated/zinc/models/owed_res.dart';
import '../networking/api_client.dart';

/// zinc `/Penalty` endpoints (zinc ≥ 1.47).
class PenaltyRepository {
  final ApiClient _api;
  PenaltyRepository(this._api);

  static const _base = '/api/v1.0/Penalty';

  /// What the user owes, oldest first (`GET /Penalty/{userId}/owed`).
  Future<Result<OwedRes>> owed(String userId) {
    return _api.get(
      '$_base/$userId/owed',
      (j) => OwedRes.fromJson(j as Map<String, Object?>),
    );
  }
}
