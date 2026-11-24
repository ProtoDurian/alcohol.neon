// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'friend_request_res.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

FriendRequestRes _$FriendRequestResFromJson(Map<String, dynamic> json) =>
    FriendRequestRes(
      requestId: json['requestId'] as String,
      createdAtUtc: DateTime.parse(json['createdAtUtc'] as String),
      userId: json['userId'] as String?,
      username: json['username'] as String?,
    );

Map<String, dynamic> _$FriendRequestResToJson(FriendRequestRes instance) =>
    <String, dynamic>{
      'requestId': instance.requestId,
      'userId': instance.userId,
      'username': instance.username,
      'createdAtUtc': instance.createdAtUtc.toIso8601String(),
    };
