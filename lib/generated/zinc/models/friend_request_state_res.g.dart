// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'friend_request_state_res.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

FriendRequestStateRes _$FriendRequestStateResFromJson(
  Map<String, dynamic> json,
) => FriendRequestStateRes(
  requestId: json['requestId'] as String,
  status: json['status'] as String,
  createdAtUtc: DateTime.parse(json['createdAtUtc'] as String),
  resolvedAtUtc: json['resolvedAtUtc'] == null
      ? null
      : DateTime.parse(json['resolvedAtUtc'] as String),
);

Map<String, dynamic> _$FriendRequestStateResToJson(
  FriendRequestStateRes instance,
) => <String, dynamic>{
  'requestId': instance.requestId,
  'status': instance.status,
  'createdAtUtc': instance.createdAtUtc.toIso8601String(),
  'resolvedAtUtc': instance.resolvedAtUtc?.toIso8601String(),
};
