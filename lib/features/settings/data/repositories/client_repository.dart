import 'package:cloud_firestore/cloud_firestore.dart';

import '../client.dart';

abstract class ClientRepository {
  Future<List<Client>> getCachedClients({required String organizationId});
  Stream<QuerySnapshot<Map<String, dynamic>>> listenForClientChanges({
    required String organizationId,
    Timestamp? since,
  });

  Future<String> createClient(Client client, String organizationId);
  Future<void> updateClient(Client client, String organizationId);
  Future<void> deleteClient(String clientId, String organizationId);
}
