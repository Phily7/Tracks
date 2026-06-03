import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/foundation.dart';
import 'daos/staff_dao.dart';
import 'daos/shifts_dao.dart';
import 'daos/products_dao.dart';
import 'daos/clients_dao.dart';
import 'daos/transactions_dao.dart';
import 'daos/stock_movements_dao.dart';

part 'app_database.g.dart';

// -- Tables ------------------------------------------------------------------

class StaffTable extends Table {
  TextColumn get id => text().clientDefault(() => _uuid())();
  TextColumn get name => text()();
  TextColumn get role => text().withDefault(const Constant(''))();
  BoolColumn get active => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class ProductsTable extends Table {
  TextColumn get id => text().clientDefault(() => _uuid())();
  TextColumn get name => text()();
  IntColumn get bizPrice => integer().withDefault(const Constant(0))();
  IntColumn get staffPrice => integer().withDefault(const Constant(0))();
  IntColumn get telecomPrice => integer().withDefault(const Constant(0))();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class ClientsTable extends Table {
  TextColumn get id => text().clientDefault(() => _uuid())();
  TextColumn get name => text()();
  TextColumn get clientType => text().withDefault(const Constant('normal'))();
  TextColumn get company => text().nullable()();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class ShiftsTable extends Table {
  TextColumn get id => text().clientDefault(() => _uuid())();
  DateTimeColumn get date => dateTime().withDefault(currentDateAndTime)();
  TextColumn get staffId => text().nullable().references(StaffTable, #id)();
  IntColumn get openingCash => integer().withDefault(const Constant(0))();
  IntColumn get openingMomo => integer().withDefault(const Constant(0))();
  IntColumn get closingCash => integer().nullable()();
  IntColumn get closingMomo => integer().nullable()();
  TextColumn get status => text().withDefault(const Constant('open'))();
  TextColumn get location => text().withDefault(const Constant(''))();
  BoolColumn get synced => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class TransactionsTable extends Table {
  TextColumn get id => text().clientDefault(() => _uuid())();
  TextColumn get shiftId => text().references(ShiftsTable, #id)();
  TextColumn get productId => text().references(ProductsTable, #id)();
  TextColumn get clientId => text().nullable().references(ClientsTable, #id)();
  TextColumn get clientType => text().withDefault(const Constant('normal'))();
  TextColumn get paymentMethod => text().withDefault(const Constant('cash'))();
  IntColumn get quantity => integer().withDefault(const Constant(1))();
  IntColumn get unitPrice => integer()();
  IntColumn get totalAmount => integer()();
  TextColumn get entryMode =>
      text().withDefault(const Constant('product_first'))();
  BoolColumn get synced => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class StockMovementsTable extends Table {
  TextColumn get id => text().clientDefault(() => _uuid())();
  TextColumn get shiftId => text().references(ShiftsTable, #id)();
  TextColumn get productId => text().references(ProductsTable, #id)();
  IntColumn get openStock => integer().withDefault(const Constant(0))();
  IntColumn get refillQty => integer().withDefault(const Constant(0))();
  IntColumn get closingStock => integer().nullable()();
  BoolColumn get synced => boolean().withDefault(const Constant(false))();
  DateTimeColumn get recordedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class ExpensesTable extends Table {
  TextColumn get id => text().clientDefault(() => _uuid())();
  TextColumn get shiftId => text().references(ShiftsTable, #id)();
  IntColumn get amount => integer()();
  TextColumn get paymentMethod => text().withDefault(const Constant('cash'))();
  TextColumn get note => text().nullable()();
  BoolColumn get synced => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

// -- Database ----------------------------------------------------------------

@DriftDatabase(
  tables: [
    StaffTable,
    ProductsTable,
    ClientsTable,
    ShiftsTable,
    TransactionsTable,
    StockMovementsTable,
    ExpensesTable,
  ],
  daos: [
    StaffDao,
    ShiftsDao,
    ProductsDao,
    ClientsDao,
    TransactionsDao,
    StockMovementsDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 2;

  static QueryExecutor _openConnection() {
    // if (kIsWeb) {
    //   return DatabaseConnection.delayed(
    //     Future(() async {
    //       final db = await WasmDatabase.open(
    //         databaseName: 'fabfoods_db',
    //         sqlite3Uri: Uri.parse('sqlite3.wasm'),
    //         driftWorkerUri: Uri.parse('drift_worker.dart.js'),
    //       );
    //       return db.resolvedExecutor;
    //     }),
    //   );
    // }
    return driftDatabase(
      name: 'fabfoods_db',
      web: DriftWebOptions(
        sqlite3Wasm: Uri.parse('sqlite3.wasm'),
        driftWorker: Uri.parse('drift_worker.js'),
        onResult: (result) {
          if (result.missingFeatures.isNotEmpty) {
            debugPrint(
              'Using ${result.chosenImplementation} due to unsupported '
              'browser features: ${result.missingFeatures}',
            );
          }
        },
      ),
    );
  }

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.addColumn(shiftsTable, shiftsTable.location);
        await m.addColumn(shiftsTable, shiftsTable.synced);
      }
    },
  );
}

// UUID helper (no extra package needed)
String _uuid() {
  final now = DateTime.now().microsecondsSinceEpoch;
  return 'local-$now-${now.hashCode.abs()}';
}
