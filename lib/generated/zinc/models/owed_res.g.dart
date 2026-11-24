// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'owed_res.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

OwedRes _$OwedResFromJson(Map<String, dynamic> json) => OwedRes(
  total: json['total'] as String?,
  currency: json['currency'] as String?,
  items: (json['items'] as List<dynamic>?)
      ?.map((e) => OwedItemRes.fromJson(e as Map<String, dynamic>))
      .toList(),
);

Map<String, dynamic> _$OwedResToJson(OwedRes instance) => <String, dynamic>{
  'total': instance.total,
  'currency': instance.currency,
  'items': instance.items,
};
