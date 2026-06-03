import 'package:drift/drift.dart';
import '../app_database.dart';

part 'products_dao.g.dart';

@DriftAccessor(tables: [ProductsTable])
class ProductsDao extends DatabaseAccessor<AppDatabase> with _$ProductsDaoMixin {
  ProductsDao(super.db);

  Future<List<ProductsTableData>> getActiveProducts() =>
      (select(productsTable)..where((p) => p.active.equals(true))).get();

  Stream<List<ProductsTableData>> watchActiveProducts() =>
      (select(productsTable)..where((p) => p.active.equals(true))).watch();

  Stream<List<ProductsTableData>> watchAllProducts() =>
      (select(productsTable)..orderBy([(p) => OrderingTerm.asc(p.name)])).watch();

  Future<void> insertProduct(ProductsTableCompanion entry) =>
      into(productsTable).insert(entry);

  Future<bool> updateProduct(ProductsTableCompanion entry) =>
      update(productsTable).replace(entry);
}