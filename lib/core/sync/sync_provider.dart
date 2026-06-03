import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'sync_service.dart';
import '../database/database_provider.dart';

final syncServiceProvider = Provider<SyncService>((ref) {
  final db = ref.watch(databaseProvider);
  final service = SyncService(db);

  // Start background sync (every 30s)
  service.start(intervalSeconds: 30);

  // Stop when provider is disposed
  ref.onDispose(service.stop);

  return service;
});
