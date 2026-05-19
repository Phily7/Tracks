import 'package:drift/drift.dart';
import '../app_database.dart';

part 'transactions_dao.g.dart';

@DriftAccessor(tables: [TransactionsTable])
class TransactionsDao extends DatabaseAccessor<AppDatabase>
    with _$TransactionsDaoMixin {
  TransactionsDao(super.db);

  Future<void> insertTransaction(TransactionsTableCompanion entry) =>
      into(transactionsTable).insert(entry);

  Future<List<TransactionsTableData>> getTransactionsByShift(String shiftId) =>
      (select(transactionsTable)
            ..where((t) => t.shiftId.equals(shiftId))
            ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
          .get();

  Stream<List<TransactionsTableData>> watchTransactionsByShift(String shiftId) =>
      (select(transactionsTable)
            ..where((t) => t.shiftId.equals(shiftId))
            ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
          .watch();

  Future<void> deleteTransaction(String id) =>
      (delete(transactionsTable)..where((t) => t.id.equals(id))).go();
}