import 'package:drift/drift.dart';
import '../app_database.dart';

part 'shifts_dao.g.dart';

@DriftAccessor(tables: [ShiftsTable, StaffTable])
class ShiftsDao extends DatabaseAccessor<AppDatabase> with _$ShiftsDaoMixin {
  ShiftsDao(super.db);

  Future<String> createShift(ShiftsTableCompanion entry) async {
    await into(shiftsTable).insert(entry);
    return entry.id.value;
  }

  Future<ShiftsTableData?> getOpenShift() async {
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    final result = await (select(shiftsTable)
          ..where((s) =>
              s.status.equals('open') &
              s.date.isBiggerOrEqualValue(startOfDay) &
              s.date.isSmallerThanValue(endOfDay)))
        .get();
    return result.isEmpty ? null : result.first;
  }

  Future<void> closeShift({
    required String shiftId,
    required int closingCash,
    required int closingMomo,
  }) =>
      (update(shiftsTable)..where((s) => s.id.equals(shiftId))).write(
        ShiftsTableCompanion(
          status: const Value('closed'),
          closingCash: Value(closingCash),
          closingMomo: Value(closingMomo),
        ),
      );

  Future<ShiftsTableData?> getShiftById(String id) async {
    final result = await (select(shiftsTable)
          ..where((s) => s.id.equals(id)))
        .get();
    return result.isEmpty ? null : result.first;
  }

  Future<List<ShiftsTableData>> getAllShifts() =>
      (select(shiftsTable)
            ..orderBy([(s) => OrderingTerm.desc(s.date)]))
          .get();
}