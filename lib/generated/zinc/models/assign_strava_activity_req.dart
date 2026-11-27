// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'assign_strava_activity_req.g.dart';

@JsonSerializable()
class AssignStravaActivityReq {
  const AssignStravaActivityReq({this.habitId});

  factory AssignStravaActivityReq.fromJson(Map<String, Object?> json) =>
      _$AssignStravaActivityReqFromJson(json);

  final String? habitId;

  Map<String, Object?> toJson() => _$AssignStravaActivityReqToJson(this);
}
