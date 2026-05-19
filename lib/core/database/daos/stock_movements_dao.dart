import 'package:drift/drift.dart';
import '../app_database.dart';

part 'stock_movements_dao.g.dart';

@DriftAccessor(tables: [StockMovementsTable])
class StockMovementsDao extends DatabaseAccessor<AppDatabase>
    with _$StockMovementsDaoMixin {
  StockMovementsDao(super.db);

  Future<List<StockMovementsTableData>> getMovementsByShift(String shiftId) =>
      (select(stockMovementsTable)
            ..where((s) => s.shiftId.equals(shiftId)))
          .get();

  Future<void> insertMovement(StockMovementsTableCompanion entry) =>
      into(stockMovementsTable).insert(entry);

  Future<bool> updateMovement(StockMovementsTableCompanion entry) =>
      update(stockMovementsTable).replace(entry);

  Future<StockMovementsTableData?> getMovement(
      String shiftId, String productId) async {
    final result = await (select(stockMovementsTable)
          ..where((s) =>
              s.shiftId.equals(shiftId) & s.productId.equals(productId)))
        .get();
    return result.isEmpty ? null : result.first;
  }
}