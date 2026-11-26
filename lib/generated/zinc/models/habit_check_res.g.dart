// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'habit_check_res.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

HabitCheckRes _$HabitCheckResFromJson(Map<String, dynamic> json) =>
    HabitCheckRes(
      habitId: json['habitId'] as String?,
      date: json['date'] as String?,
      status: json['status'] as String?,
    );

Map<String, dynamic> _$HabitCheckResToJson(HabitCheckRes instance) =>
    <String, dynamic>{
      'habitId': instance.habitId,
      'date': instance.date,
      'status': instance.status,
    };
