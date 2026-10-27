import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import '../../../../common/constants/routes.dart';
import '../client.dart';

class ClientRemoteDatasource {
  ClientRemoteDatasource({required this.firebaseFirestore});

  final FirebaseFirestore firebaseFirestore;

  CollectionReference<Map<String, dynamic>> _clients(String organizationId) =>
      firebaseFirestore
          .collection(organizationsCollection)
          .doc(organizationId)
          .collection(clientsCollection);

  /// Klijenti iz lokalnog Firestore keša. Ne troši readove.
  Future<List<Client>> getCachedClients(String organizationId) async {
    try {
      final snapshot = await _clients(
        organizationId,
      ).get(const GetOptions(source: Source.cache));

      return snapshot.docs
          .map((doc) => Client.fromJson(doc.data(), doc.id))
          .toList();
    } on Exception catch (_) {
      // Prazan keš (npr. prvo pokretanje) nije greška.
      return [];
    }
  }

  /// Bez [since] sluša sve klijente, a sa [since] samo one izmijenjene od
  /// tog trenutka.
  Stream<QuerySnapshot<Map<String, dynamic>>> listenForClientChanges(
    String organizationId, {
    Timestamp? since,
  }) {
    final clients = _clients(organizationId);
    if (since == null) {
      return clients.snapshots();
    }

    return clients
        .where('updatedAt', isGreaterThanOrEqualTo: since)
        .snapshots();
  }

  Future<DocumentReference<Map<String, dynamic>>> createClient(
    Client client,
    String organizationId,
  ) async {
    final data = client.toJson();
    data['createdAt'] = FieldValue.serverTimestamp();
    data['isActive'] = true;
    data['updatedAt'] = FieldValue.serverTimestamp();

    return firebaseFirestore
        .collection(organizationsCollection)
        .doc(organizationId)
        .collection(clientsCollection)
        .add(data);
  }

  Future<void> updateClient(Client client, String organizationId) async {
    try {
      await firebaseFirestore
          .collection(organizationsCollection)
          .doc(organizationId)
          .collection(clientsCollection)
          .doc(client.id)
          .update({
            // createdAt se nikad ne prepisuje; forma ga ne mora imati, a null
            // bi obrisao datum "Klijent od".
            ...client.toJson()..remove('createdAt'),
            'updatedAt': FieldValue.serverTimestamp(),
          });
    } on Exception catch (e) {
      unawaited(
        FirebaseCrashlytics.instance.recordError(e, StackTrace.current),
      );
      throw Exception(e);
    }
  }

  Future<void> deleteClient(String clientId, String organizationId) async {
    try {
      await firebaseFirestore
          .collection(organizationsCollection)
          .doc(organizationId)
          .collection(clientsCollection)
          .doc(clientId)
          .update(<String, dynamic>{
            'isActive': false,
            'updatedAt': FieldValue.serverTimestamp(),
          });
    } on FirebaseException catch (e) {
      unawaited(
        FirebaseCrashlytics.instance.recordError(e, StackTrace.current),
      );
      throw Exception('${e.code}: ${e.message}');
    } on Exception catch (e) {
      unawaited(
        FirebaseCrashlytics.instance.recordError(e, StackTrace.current),
      );
      throw Exception(e.toString());
    }
  }
}
