import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/database/app_database.dart';
import '../../core/database/database_provider.dart';
import '../../shared/theme/app_colors.dart';

class StaffScreen extends ConsumerWidget {
  const StaffScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 24, 24, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Text(
                    'Shift Workers',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: Container(
                decoration: const BoxDecoration(
                  color: AppColors.bg,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: StreamBuilder<List<StaffTableData>>(
                  stream: db.staffDao.watchAllStaff(),
                  builder: (context, snap) {
                    if (!snap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final staff = snap.data!;
                    if (staff.isEmpty) {
                      return const Center(
                        child: Text(
                          'No staff yet.\nTap + to add someone.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 15),
                        ),
                      );
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
                      itemCount: staff.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => _StaffTile(staff: staff[i]),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showSheet(context),
        backgroundColor: AppColors.accent,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text(
          'Add Worker',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  static void _showSheet(BuildContext context, {StaffTableData? staff}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _StaffSheet(staff: staff),
    );
  }
}

// ── Tile ─────────────────────────────────────────────────────────────────────

class _StaffTile extends ConsumerWidget {
  final StaffTableData staff;
  const _StaffTile({required this.staff});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = staff.active;
    return GestureDetector(
      onTap: () => StaffScreen._showSheet(context, staff: staff),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: active ? 1.0 : 0.5,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: active ? const Color(0xFFE9ECEF) : AppColors.grey300,
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: active ? AppColors.accent.withValues(alpha: 0.12) : AppColors.surfaceAlt,
                child: Text(
                  staff.name[0].toUpperCase(),
                  style: TextStyle(
                    color: active ? AppColors.accent : AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      staff.name,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: active ? AppColors.textPrimary : AppColors.textSecondary,
                        decoration: active ? null : TextDecoration.lineThrough,
                      ),
                    ),
                    if (staff.role.isNotEmpty)
                      Text(
                        staff.role,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              Switch(
                value: active,
                activeThumbColor: AppColors.accent,
                activeTrackColor: AppColors.accent.withValues(alpha: 0.4),
                onChanged: (_) => ref.read(databaseProvider).staffDao.updateStaff(
                  StaffTableCompanion(
                    id: Value(staff.id),
                    name: Value(staff.name),
                    role: Value(staff.role),
                    active: Value(!active),
                    createdAt: Value(staff.createdAt),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Add / Edit Sheet ──────────────────────────────────────────────────────────

class _StaffSheet extends ConsumerStatefulWidget {
  final StaffTableData? staff;
  const _StaffSheet({this.staff});

  @override
  ConsumerState<_StaffSheet> createState() => _StaffSheetState();
}

class _StaffSheetState extends ConsumerState<_StaffSheet> {
  late final TextEditingController _name;
  late final TextEditingController _role;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.staff?.name ?? '');
    _role = TextEditingController(text: widget.staff?.role ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _role.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    setState(() => _saving = true);
    final db = ref.read(databaseProvider);
    if (widget.staff == null) {
      await db.staffDao.insertStaff(
        StaffTableCompanion.insert(
          name: name,
          role: Value(_role.text.trim()),
          active: const Value(true),
        ),
      );
    } else {
      final s = widget.staff!;
      await db.staffDao.updateStaff(
        StaffTableCompanion(
          id: Value(s.id),
          name: Value(name),
          role: Value(_role.text.trim()),
          active: Value(s.active),
          createdAt: Value(s.createdAt),
        ),
      );
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.grey300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              widget.staff == null ? 'Add Worker' : 'Edit Worker',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name'),
              textCapitalization: TextCapitalization.words,
              autofocus: widget.staff == null,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _role,
              decoration: const InputDecoration(
                labelText: 'Role (optional)',
                hintText: 'e.g. barista',
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(widget.staff == null ? 'Add Worker' : 'Save Changes'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
