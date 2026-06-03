import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../database/app_database.dart';

/// Syncs local Drift records to Supabase in the background.
/// - Write-local-first: every record is saved to Drift immediately.
/// - This service pushes unsynced records to Supabase whenever called.
/// - Uses upsert so retries are safe (idempotent).
class SyncService {
  final AppDatabase _db;
  final SupabaseClient _supabase = Supabase.instance.client;

  Timer? _timer;
  bool _syncing = false;

  SyncService(this._db);

  // ── Start / Stop ──────────────────────────────────────────────────────────

  /// Start background sync every [intervalSeconds] seconds.
  void start({int intervalSeconds = 30}) {
    _timer?.cancel();
    _timer = Timer.periodic(
      Duration(seconds: intervalSeconds),
      (_) => syncAll(),
    );
    // Sync immediately on start
    syncAll();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  // ── Main sync entry point ─────────────────────────────────────────────────

  Future<void> syncAll() async {
    if (_syncing) return; // Prevent concurrent syncs
    _syncing = true;
    try {
      await _syncShifts();
      await _syncTransactions();
      await _syncStockMovements();
    } catch (e) {
      debugPrint('[SyncService] Error: $e');
    } finally {
      _syncing = false;
    }
  }

  // ── Sync shifts ───────────────────────────────────────────────────────────

  Future<void> _syncShifts() async {
    final unsynced = await _db.shiftsDao.getUnsyncedShifts();
    if (unsynced.isEmpty) return;

    for (final shift in unsynced) {
      try {
        await _supabase.from('shifts').upsert({
          'id': shift.id,
          'date': shift.date.toIso8601String(),
          'staff_id': shift.staffId,
          'location': shift.location,
          'opening_cash': shift.openingCash,
          'opening_momo': shift.openingMomo,
          'closing_cash': shift.closingCash,
          'closing_momo': shift.closingMomo,
          'status': shift.status,
          'created_at': shift.createdAt.toIso8601String(),
        });
        await _db.shiftsDao.markSynced(shift.id);
        debugPrint('[SyncService] Shift synced: ${shift.id}');
      } catch (e) {
        debugPrint('[SyncService] Shift sync failed: ${shift.id} — $e');
        // Continue with next record, will retry on next cycle
      }
    }
  }

  // ── Sync transactions ─────────────────────────────────────────────────────

  Future<void> _syncTransactions() async {
    final unsynced = await _db.transactionsDao.getUnsyncedTransactions();
    if (unsynced.isEmpty) return;

    for (final txn in unsynced) {
      try {
        await _supabase.from('transactions').upsert({
          'id': txn.id,
          'shift_id': txn.shiftId,
          'product_id': txn.productId,
          'client_id': txn.clientId,
          'client_type': txn.clientType,
          'payment_method': txn.paymentMethod,
          'quantity': txn.quantity,
          'unit_price': txn.unitPrice,
          'total_amount': txn.totalAmount,
          'entry_mode': txn.entryMode,
          'created_at': txn.createdAt.toIso8601String(),
        });
        await _db.transactionsDao.markSynced(txn.id);
        debugPrint('[SyncService] Transaction synced: ${txn.id}');
      } catch (e) {
        debugPrint('[SyncService] Transaction sync failed: ${txn.id} — $e');
      }
    }
  }

  // ── Sync stock movements ──────────────────────────────────────────────────

  Future<void> _syncStockMovements() async {
    final unsynced = await _db.stockMovementsDao.getUnsyncedMovements();
    if (unsynced.isEmpty) return;

    for (final m in unsynced) {
      try {
        await _supabase.from('stock_movements').upsert({
          'id': m.id,
          'shift_id': m.shiftId,
          'product_id': m.productId,
          'open_stock': m.openStock,
          'refill_qty': m.refillQty,
          'closing_stock': m.closingStock,
          'recorded_at': m.recordedAt.toIso8601String(),
        });
        await _db.stockMovementsDao.markSynced(m.id);
        debugPrint('[SyncService] Stock movement synced: ${m.id}');
      } catch (e) {
        debugPrint('[SyncService] Stock sync failed: ${m.id} — $e');
      }
    }
  }
}
