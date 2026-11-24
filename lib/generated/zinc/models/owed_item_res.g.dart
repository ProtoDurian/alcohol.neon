// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'owed_item_res.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

OwedItemRes _$OwedItemResFromJson(Map<String, dynamic> json) => OwedItemRes(
  habitId: json['habitId'] as String,
  habitName: json['habitName'] as String?,
  localDate: json['localDate'] as String?,
  amount: json['amount'] as String?,
  currency: json['currency'] as String?,
  charityId: json['charityId'] as String?,
  charityName: json['charityName'] as String?,
  state: json['state'] as String?,
  reason: json['reason'] as String?,
);

Map<String, dynamic> _$OwedItemResToJson(OwedItemRes instance) =>
    <String, dynamic>{
      'habitId': instance.habitId,
      'habitName': instance.habitName,
      'localDate': instance.localDate,
      'amount': instance.amount,
      'currency': instance.currency,
      'charityId': instance.charityId,
      'charityName': instance.charityName,
      'state': instance.state,
      'reason': instance.reason,
    };
