// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'strava_activity_res.g.dart';

@JsonSerializable()
class StravaActivityRes {
  const StravaActivityRes({
    required this.startUtc,
    required this.manual,
    required this.pinned,
    required this.locked,
    this.id,
    this.name,
    this.sportType,
    this.habitId,
  });

  factory StravaActivityRes.fromJson(Map<String, Object?> json) =>
      _$StravaActivityResFromJson(json);

  final String? id;
  final String? name;
  final String? sportType;
  final DateTime startUtc;
  final bool manual;
  final String? habitId;
  final bool pinned;
  final bool locked;

  Map<String, Object?> toJson() => _$StravaActivityResToJson(this);
}
