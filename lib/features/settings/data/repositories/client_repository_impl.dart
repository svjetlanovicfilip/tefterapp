import 'package:cloud_firestore/cloud_firestore.dart';

import '../client.dart';
import '../datasources/client_remote_datasource.dart';
import 'client_repository.dart';

class ClientRepositoryImpl implements ClientRepository {
  ClientRepositoryImpl({required this.clientRemoteDatasource});

  final ClientRemoteDatasource clientRemoteDatasource;

  @override
  Future<List<Client>> getCachedClients({required String organizationId}) =>
      clientRemoteDatasource.getCachedClients(organizationId);

  @override
  Stream<QuerySnapshot<Map<String, dynamic>>> listenForClientChanges({
    required String organizationId,
    Timestamp? since,
  }) => clientRemoteDatasource.listenForClientChanges(
    organizationId,
    since: since,
  );

  @override
  Future<String> createClient(Client client, String organizationId) async {
    final docRef = await clientRemoteDatasource.createClient(
      client,
      organizationId,
    );
    return docRef.id;
  }

  @override
  Future<void> deleteClient(String serviceId, String organizationId) async {
    await clientRemoteDatasource.deleteClient(serviceId, organizationId);
  }

  @override
  Future<void> updateClient(Client client, String organizationId) async {
    await clientRemoteDatasource.updateClient(client, organizationId);
  }
}
