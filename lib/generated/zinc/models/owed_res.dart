// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'owed_item_res.dart';

part 'owed_res.g.dart';

@JsonSerializable()
class OwedRes {
  const OwedRes({
    this.total,
    this.currency,
    this.items,
  });
  
  factory OwedRes.fromJson(Map<String, Object?> json) => _$OwedResFromJson(json);
  
  final String? total;
  final String? currency;
  final List<OwedItemRes>? items;

  Map<String, Object?> toJson() => _$OwedResToJson(this);
}
