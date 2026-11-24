// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'inbox_friend_request_res.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

InboxFriendRequestRes _$InboxFriendRequestResFromJson(
  Map<String, dynamic> json,
) => InboxFriendRequestRes(
  status: json['status'] as String,
  requestId: json['requestId'] as String?,
  resolvedAtUtc: json['resolvedAtUtc'] == null
      ? null
      : DateTime.parse(json['resolvedAtUtc'] as String),
);

Map<String, dynamic> _$InboxFriendRequestResToJson(
  InboxFriendRequestRes instance,
) => <String, dynamic>{
  'requestId': instance.requestId,
  'status': instance.status,
  'resolvedAtUtc': instance.resolvedAtUtc?.toIso8601String(),
};
