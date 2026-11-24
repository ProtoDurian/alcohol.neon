// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'inbox_friend_request_res.g.dart';

@JsonSerializable()
class InboxFriendRequestRes {
  const InboxFriendRequestRes({
    required this.status,
    this.requestId,
    this.resolvedAtUtc,
  });
  
  factory InboxFriendRequestRes.fromJson(Map<String, Object?> json) => _$InboxFriendRequestResFromJson(json);
  
  final String? requestId;
  final String status;
  final DateTime? resolvedAtUtc;

  Map<String, Object?> toJson() => _$InboxFriendRequestResToJson(this);
}
