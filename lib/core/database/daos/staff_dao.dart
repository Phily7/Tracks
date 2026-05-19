import 'package:drift/drift.dart';
import '../app_database.dart';

part 'staff_dao.g.dart';

@DriftAccessor(tables: [StaffTable])
class StaffDao extends DatabaseAccessor<AppDatabase> with _$StaffDaoMixin {
  StaffDao(super.db);

  Future<List<StaffTableData>> getActiveStaff() =>
      (select(staffTable)..where((s) => s.active.equals(true))).get();

  Stream<List<StaffTableData>> watchActiveStaff() =>
      (select(staffTable)..where((s) => s.active.equals(true))).watch();

  Future<void> insertStaff(StaffTableCompanion entry) =>
      into(staffTable).insert(entry);

  Future<bool> updateStaff(StaffTableCompanion entry) =>
      update(staffTable).replace(entry);

  Future<void> deactivateStaff(String id) =>
      (update(staffTable)..where((s) => s.id.equals(id)))
          .write(const StaffTableCompanion(active: Value(false)));
}