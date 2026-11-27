// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'inbox_friend_request_res.dart';

part 'inbox_notification_res.g.dart';

@JsonSerializable()
class InboxNotificationRes {
  const InboxNotificationRes({
    required this.id,
    required this.createdAtUtc,
    this.kind,
    this.title,
    this.body,
    this.actorUserId,
    this.data,
    this.readAtUtc,
    this.friendRequest,
  });

  factory InboxNotificationRes.fromJson(Map<String, Object?> json) =>
      _$InboxNotificationResFromJson(json);

  final String id;
  final String? kind;
  final String? title;
  final String? body;
  final String? actorUserId;
  final String? data;
  final DateTime createdAtUtc;
  final DateTime? readAtUtc;
  final InboxFriendRequestRes? friendRequest;

  Map<String, Object?> toJson() => _$InboxNotificationResToJson(this);
}
