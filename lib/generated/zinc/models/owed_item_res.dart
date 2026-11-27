// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'owed_item_res.g.dart';

@JsonSerializable()
class OwedItemRes {
  const OwedItemRes({
    required this.habitId,
    this.habitName,
    this.localDate,
    this.amount,
    this.currency,
    this.charityId,
    this.charityName,
    this.state,
    this.reason,
  });

  factory OwedItemRes.fromJson(Map<String, Object?> json) =>
      _$OwedItemResFromJson(json);

  final String habitId;
  final String? habitName;
  final String? localDate;
  final String? amount;
  final String? currency;
  final String? charityId;
  final String? charityName;
  final String? state;
  final String? reason;

  Map<String, Object?> toJson() => _$OwedItemResToJson(this);
}
