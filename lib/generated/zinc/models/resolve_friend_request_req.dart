// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'resolve_friend_request_req.g.dart';

@JsonSerializable()
class ResolveFriendRequestReq {
  const ResolveFriendRequestReq({required this.decision});

  factory ResolveFriendRequestReq.fromJson(Map<String, Object?> json) =>
      _$ResolveFriendRequestReqFromJson(json);

  final String decision;

  Map<String, Object?> toJson() => _$ResolveFriendRequestReqToJson(this);
}
