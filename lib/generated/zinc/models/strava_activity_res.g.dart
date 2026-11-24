// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'strava_activity_res.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

StravaActivityRes _$StravaActivityResFromJson(Map<String, dynamic> json) =>
    StravaActivityRes(
      startUtc: DateTime.parse(json['startUtc'] as String),
      manual: json['manual'] as bool,
      pinned: json['pinned'] as bool,
      locked: json['locked'] as bool,
      id: json['id'] as String?,
      name: json['name'] as String?,
      sportType: json['sportType'] as String?,
      habitId: json['habitId'] as String?,
    );

Map<String, dynamic> _$StravaActivityResToJson(StravaActivityRes instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'sportType': instance.sportType,
      'startUtc': instance.startUtc.toIso8601String(),
      'manual': instance.manual,
      'habitId': instance.habitId,
      'pinned': instance.pinned,
      'locked': instance.locked,
    };
