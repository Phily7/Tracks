import 'package:drift/drift.dart';
import '../app_database.dart';

part 'clients_dao.g.dart';

@DriftAccessor(tables: [ClientsTable])
class ClientsDao extends DatabaseAccessor<AppDatabase> with _$ClientsDaoMixin {
  ClientsDao(super.db);

  Future<List<ClientsTableData>> getActiveClients() =>
      (select(clientsTable)..where((c) => c.active.equals(true))).get();

  Stream<List<ClientsTableData>> watchActiveClients() =>
      (select(clientsTable)..where((c) => c.active.equals(true))).watch();

  Stream<List<ClientsTableData>> watchAllClients() =>
      (select(clientsTable)..orderBy([(c) => OrderingTerm.asc(c.name)])).watch();

  Future<void> insertClient(ClientsTableCompanion entry) =>
      into(clientsTable).insert(entry);

  Future<bool> updateClient(ClientsTableCompanion entry) =>
      update(clientsTable).replace(entry);

  Future<void> deactivateClient(String id) =>
      (update(clientsTable)..where((c) => c.id.equals(id)))
          .write(const ClientsTableCompanion(active: Value(false)));
}