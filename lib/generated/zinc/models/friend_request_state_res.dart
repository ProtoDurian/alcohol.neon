// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'friend_request_state_res.g.dart';

@JsonSerializable()
class FriendRequestStateRes {
  const FriendRequestStateRes({
    required this.requestId,
    required this.status,
    required this.createdAtUtc,
    this.resolvedAtUtc,
  });

  factory FriendRequestStateRes.fromJson(Map<String, Object?> json) =>
      _$FriendRequestStateResFromJson(json);

  final String requestId;
  final String status;
  final DateTime createdAtUtc;
  final DateTime? resolvedAtUtc;

  Map<String, Object?> toJson() => _$FriendRequestStateResToJson(this);
}
