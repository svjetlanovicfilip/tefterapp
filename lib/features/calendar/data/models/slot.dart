import 'dart:ui';

import 'package:calendar_view/calendar_view.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import '../../../../config/style/colors.dart';

class Slot extends Equatable {
  const Slot({
    required this.startDateTime,
    this.title,
    this.endDateTime,
    this.color,
    this.id,
    this.serviceIds = const [],
    this.employeeIds = const [],
    this.clientId,
    this.clientName,
  });

  factory Slot.fromJson(Map<String, dynamic> json, String id) {
    return Slot(
      id: id,
      title: json['title'],
      color: json['color'],
      startDateTime: (json['startDateTime'] as Timestamp).toDate(),
      endDateTime: (json['endDateTime'] as Timestamp).toDate(),
      serviceIds:
          (json['serviceIds'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      employeeIds:
          (json['employeeIds'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      clientId: json['clientId'],
      clientName: json['clientName'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'color': color,
      'startDateTime': startDateTime,
      'endDateTime': endDateTime,
      'serviceIds': serviceIds,
      'employeeIds': employeeIds,
      'clientId': clientId,
      'clientName': clientName,
    };
  }

  CalendarEventData<Slot> toCalendarEventData() {
    return CalendarEventData(
      date: startDateTime,
      startTime: startDateTime,
      endTime: endDateTime,
      endDate: endDateTime,
      title: title ?? '',
      event: this,
      color: displayColor,
    );
  }

  /// Boja termina; ako nije postavljena ili nije ispravna, koristi se
  /// podrazumijevana.
  Color get displayColor {
    final value = int.tryParse(color ?? '');
    return value != null ? Color(value) : AppColors.amber500;
  }

  Slot copyWith({
    String? id,
    List<String>? serviceIds,
    DateTime? startDateTime,
    DateTime? endDateTime,
    String? color,
    String? title,
    List<String>? employeeIds,
    String? clientId,
    String? clientName,
  }) {
    return Slot(
      id: id ?? this.id,
      title: title ?? this.title,
      startDateTime: startDateTime ?? this.startDateTime,
      endDateTime: endDateTime ?? this.endDateTime,
      color: color ?? this.color,
      serviceIds: serviceIds ?? this.serviceIds,
      employeeIds: employeeIds ?? this.employeeIds,
      clientId: clientId ?? this.clientId,
      clientName: clientName ?? this.clientName,
    );
  }

  @override
  List<Object?> get props => [
    id,
    title,
    startDateTime,
    endDateTime,
    color,
    serviceIds,
    employeeIds,
    clientId,
    clientName,
  ];

  final String? id;
  final String? title;
  final DateTime startDateTime;
  final DateTime? endDateTime;
  final String? color;
  final List<String> serviceIds;
  final List<String> employeeIds;
  final String? clientId;

  /// Ime klijenta u trenutku zakazivanja (denormalizovano). Cloud Function
  /// ga ažurira kad se klijentu promijeni ime.
  final String? clientName;
}
