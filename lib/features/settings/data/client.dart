import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

class Client extends Equatable {
  const Client({
    required this.name,
    required this.phoneNumber,
    required this.isActive,
    this.id,
    this.description,
    this.createdAt,
    this.updatedAt,
  });

  factory Client.fromJson(Map<String, dynamic> json, String clientId) {
    return Client(
      name: (json['name'] ?? '') as String,
      phoneNumber: (json['phoneNumber'] ?? '') as String,
      id: clientId,
      description: json['description'] as String?,
      createdAt: json['createdAt'] as Timestamp?,
      updatedAt: json['updatedAt'] as Timestamp?,
      isActive: json['isActive'] as bool,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'phoneNumber': phoneNumber,
      'description': description,
      'isActive': isActive,
      'createdAt': createdAt,
      // 'id' ne moraš čuvati u dokumentu, id ti je doc.id
      // 'updatedAt' postavlja datasource preko serverTimestamp-a
    };
  }

  final String name;
  final String phoneNumber;
  final String? id;
  final String? description;
  final Timestamp? createdAt;

  /// Vrijeme posljednje izmjene, koristi se za delta-sync klijenata.
  final Timestamp? updatedAt;
  final bool isActive;

  @override
  List<Object?> get props => [
    name,
    phoneNumber,
    id,
    description,
    createdAt,
    updatedAt,
    isActive,
  ];
}
