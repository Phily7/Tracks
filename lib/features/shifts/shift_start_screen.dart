import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/database/app_database.dart';
import '../../core/database/database_provider.dart';
import '../../shared/theme/app_colors.dart';

class ShiftStartScreen extends ConsumerStatefulWidget {
  const ShiftStartScreen({super.key});

  @override
  ConsumerState<ShiftStartScreen> createState() => _ShiftStartScreenState();
}

class _ShiftStartScreenState extends ConsumerState<ShiftStartScreen> {
  StaffTableData? _selectedStaff;
  final _cashController = TextEditingController(text: '0');
  final _momoController = TextEditingController(text: '0');
  List<StaffTableData> _staffList = [];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadStaff();
  }

  @override
  void dispose() {
    _cashController.dispose();
    _momoController.dispose();
    super.dispose();
  }


Future<void> _loadStaff() async {
  try {
    final db = ref.read(databaseProvider);
    var staff = await db.staffDao.getActiveStaff();

    if (staff.isEmpty) {
      try {
        await _seedDefaultStaff(db);
        staff = await db.staffDao.getActiveStaff();
      } catch (_) {}
    }

    if (staff.isEmpty) {
      setState(() { _staffList = _hardcodedStaff(); _loading = false; });
      return;
    }

    setState(() { _staffList = staff; _loading = false; });
  } catch (e) {
    setState(() { _staffList = _hardcodedStaff(); _loading = false; _error = null; });
  }
}

Future<void> _seedDefaultStaff(AppDatabase db) async {
  for (final name in ['Samantha', 'Magnifique']) {
    await db.staffDao.insertStaff(
      StaffTableCompanion.insert(
        id: Value('staff-${name.toLowerCase()}'),
        name: name,
      ),
    );
  }
}

List<StaffTableData> _hardcodedStaff() {
  return [
    StaffTableData(
      id: 'staff-samantha',
      name: 'Samantha',
      role: 'barista',
      active: true,
      createdAt: DateTime.now(),
    ),
    StaffTableData(
      id: 'staff-magnifique',
      name: 'Magnifique',
      role: 'barista',
      active: true,
      createdAt: DateTime.now(),
    ),
  ];
}


  Future<void> _startShift() async {
    if (_selectedStaff == null) {
      setState(() => _error = 'Please select who is working today');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      final db = ref.read(databaseProvider);
      final existing = await db.shiftsDao.getOpenShift();
      if (existing != null && mounted) {
        setState(() => _saving = false);
        _showAlreadyOpenDialog(existing);
        return;
      }
      final shiftId = 'shift-${DateTime.now().millisecondsSinceEpoch}';
      await db.shiftsDao.createShift(
        ShiftsTableCompanion.insert(
          id: Value(shiftId),
          staffId: Value(_selectedStaff!.id),
          openingCash: Value(int.tryParse(_cashController.text) ?? 0),
          openingMomo: Value(int.tryParse(_momoController.text) ?? 0),
        ),
      );
      if (mounted) context.go('/shift/active', extra: shiftId);
    } catch (e) {
      setState(() { _saving = false; _error = e.toString(); });
    }
  }

  void _showAlreadyOpenDialog(ShiftsTableData shift) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Shift Already Open'),
        content: const Text('There is already an open shift today. Resume it or close it first.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              context.go('/shift/active', extra: shift.id);
            },
            child: const Text('Resume Shift'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.restaurant, color: Colors.white, size: 22),
                    ),
                    const SizedBox(width: 12),
                    const Text('FabFoods',
                        style: TextStyle(color: Colors.white, fontSize: 20,
                            fontWeight: FontWeight.w700)),
                  ]),
                  const SizedBox(height: 32),
                  const Text('Start Shift',
                      style: TextStyle(color: Colors.white, fontSize: 28,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text(
                    _formatDate(DateTime.now()),
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6), fontSize: 15),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            // White card
            Expanded(
              child: Container(
                decoration: const BoxDecoration(
                  color: AppColors.bg,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 8),
                            const Text('Who is working today?',
                                style: TextStyle(fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary)),
                            const SizedBox(height: 12),
                            ..._staffList.map((staff) => _StaffCard(
                                  staff: staff,
                                  selected: _selectedStaff?.id == staff.id,
                                  onTap: () => setState(() => _selectedStaff = staff),
                                )),
                            const SizedBox(height: 28),
                            const Text('Opening Balances',
                                style: TextStyle(fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary)),
                            const SizedBox(height: 4),
                            const Text('Count the cash and MoMo before starting.',
                                style: TextStyle(fontSize: 13,
                                    color: AppColors.textSecondary)),
                            const SizedBox(height: 16),
                            _BalanceField(
                              label: 'Cash on Hand (RWF)',
                              controller: _cashController,
                              color: AppColors.cash,
                              icon: Icons.payments_outlined,
                            ),
                            const SizedBox(height: 12),
                            _BalanceField(
                              label: 'MoMo Balance (RWF)',
                              controller: _momoController,
                              color: AppColors.momo,
                              icon: Icons.phone_android_outlined,
                            ),
                            if (_error != null) ...[
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppColors.error.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(children: [
                                  const Icon(Icons.error_outline,
                                      color: AppColors.error, size: 18),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(_error!,
                                      style: const TextStyle(
                                          color: AppColors.error, fontSize: 13))),
                                ]),
                              ),
                            ],
                            const SizedBox(height: 32),
                            SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: ElevatedButton(
                                onPressed: _saving ? null : _startShift,
                                child: _saving
                                    ? const SizedBox(width: 20, height: 20,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2, color: Colors.white))
                                    : const Text('Start Shift'),
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime d) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun',
                    'Jul','Aug','Sep','Oct','Nov','Dec'];
    const days = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    return '${days[d.weekday - 1]}, ${d.day} ${months[d.month - 1]} ${d.year}';
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _StaffCard extends StatelessWidget {
  final StaffTableData staff;
  final bool selected;
  final VoidCallback onTap;
  const _StaffCard({required this.staff, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.accent.withValues(alpha: 0.08)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.accent : const Color(0xFFE9ECEF),
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: selected ? AppColors.accent : AppColors.surfaceAlt,
            child: Text(
              staff.name[0].toUpperCase(),
              style: TextStyle(
                color: selected ? Colors.white : AppColors.textSecondary,
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
                Text(staff.name,
                    style: const TextStyle(fontWeight: FontWeight.w600,
                        fontSize: 15, color: AppColors.textPrimary)),
                Text(staff.role,
                    style: const TextStyle(fontSize: 12,
                        color: AppColors.textSecondary)),
              ],
            ),
          ),
          if (selected)
            const Icon(Icons.check_circle, color: AppColors.accent, size: 22),
        ]),
      ),
    );
  }
}

class _BalanceField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final Color color;
  final IconData icon;
  const _BalanceField({
    required this.label,
    required this.controller,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: color, size: 20),
        suffixText: 'RWF',
        suffixStyle: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}