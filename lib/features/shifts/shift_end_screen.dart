import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/database/app_database.dart';
import '../../core/database/database_provider.dart';
import '../../shared/theme/app_colors.dart';
import '../../core/sync/sync_provider.dart';

class ShiftEndScreen extends ConsumerStatefulWidget {
  final String shiftId;
  const ShiftEndScreen({super.key, required this.shiftId});

  @override
  ConsumerState<ShiftEndScreen> createState() => _ShiftEndScreenState();
}

class _ShiftEndScreenState extends ConsumerState<ShiftEndScreen> {
  ShiftsTableData? _shift;
  StaffTableData? _staff;
  List<TransactionsTableData> _transactions = [];

  final _cashController = TextEditingController();
  final _momoController = TextEditingController();

  bool _loading = true;
  bool _closing = false;
  bool _closed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _cashController.dispose();
    _momoController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final db = ref.read(databaseProvider);
    _shift = await db.shiftsDao.getShiftById(widget.shiftId);

    if (_shift?.staffId != null) {
      final allStaff = await db.staffDao.getActiveStaff();
      final match = allStaff.where((s) => s.id == _shift!.staffId);
      if (match.isNotEmpty) _staff = match.first;
    }

    final txns = await db.transactionsDao.getTransactionsByShift(
      widget.shiftId,
    );

    if (mounted) {
      setState(() {
        _transactions = txns;
        _cashController.text = _expectedCash(txns).toString();
        _momoController.text = _expectedMomo(txns).toString();
        _loading = false;
      });
    }
  }

  // ── Computed ──────────────────────────────────────────────────────────────

  int _cashSales(List<TransactionsTableData> t) => t
      .where((x) => x.paymentMethod == 'cash')
      .fold(0, (s, x) => s + x.totalAmount);
  int _momoSales(List<TransactionsTableData> t) => t
      .where((x) => x.paymentMethod == 'momo')
      .fold(0, (s, x) => s + x.totalAmount);
  int _visaSales(List<TransactionsTableData> t) => t
      .where((x) => x.paymentMethod == 'visa')
      .fold(0, (s, x) => s + x.totalAmount);
  int _totalSales(List<TransactionsTableData> t) =>
      t.fold(0, (s, x) => s + x.totalAmount);

  int _expectedCash(List<TransactionsTableData> t) =>
      (_shift?.openingCash ?? 0) + _cashSales(t);
  int _expectedMomo(List<TransactionsTableData> t) =>
      (_shift?.openingMomo ?? 0) + _momoSales(t);

  int get _closingCashVal => int.tryParse(_cashController.text) ?? 0;
  int get _closingMomoVal => int.tryParse(_momoController.text) ?? 0;
  int get _cashDiff => _closingCashVal - _expectedCash(_transactions);
  int get _momoDiff => _closingMomoVal - _expectedMomo(_transactions);

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _closeShift() async {
    setState(() {
      _closing = true;
      _error = null;
    });
    try {
      final db = ref.read(databaseProvider);
      await db.shiftsDao.closeShift(
        shiftId: widget.shiftId,
        closingCash: _closingCashVal,
        closingMomo: _closingMomoVal,
      );
      await ref
          .read(syncServiceProvider)
          .syncAll(); // try to sync immediately after closing shift
      if (mounted)
        setState(() {
          _closing = false;
          _closed = true;
        });
    } catch (e) {
      setState(() {
        _closing = false;
        _error = e.toString();
      });
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: AppColors.primary,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }
    if (_closed) return _buildSuccessScreen();

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSummaryCard(),
                    const SizedBox(height: 16),
                    _buildReconciliationCard(),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      _ErrorBanner(message: _error!),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: _closing
                            ? null
                            : (_cashDiff.abs() > 0 || _momoDiff.abs() > 0)
                            ? _showDiscrepancyDialog
                            : _closeShift,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.error,
                        ),
                        icon: _closing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.lock, size: 18),
                        label: Text(_closing ? 'Closing...' : 'Close Shift'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: OutlinedButton(
                        onPressed: () => context.pop(),
                        child: const Text('Back to Sales'),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      color: AppColors.primary,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () => context.pop(),
                child: const Icon(
                  Icons.arrow_back_ios_new,
                  color: Colors.white70,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              const Icon(Icons.lock_outline, color: AppColors.accent, size: 20),
              const SizedBox(width: 8),
              const Text(
                'End Shift',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${_staff?.name ?? 'Staff'}  ·  ${_fmtDate(DateTime.now())}',
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard() {
    final total = _totalSales(_transactions);
    final cash = _cashSales(_transactions);
    final momo = _momoSales(_transactions);
    final visa = _visaSales(_transactions);
    final debt = _transactions
        .where((t) => t.paymentMethod == 'debt')
        .fold(0, (s, t) => s + t.totalAmount);
    final normal = _transactions
        .where((t) => t.clientType == 'normal')
        .fold(0, (s, t) => s + t.totalAmount);
    final staffAmt = _transactions
        .where((t) => t.clientType == 'staff')
        .fold(0, (s, t) => s + t.totalAmount);
    final company = _transactions
        .where((t) => t.clientType == 'company')
        .fold(0, (s, t) => s + t.totalAmount);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Shift Summary',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _fmtRwf(total),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            '${_transactions.length} transaction${_transactions.length == 1 ? '' : 's'}',
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
          const SizedBox(height: 16),
          // Payment breakdown
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _SummaryChip('Cash', cash, AppColors.cash),
              const SizedBox(width: 8),
              _SummaryChip('MoMo', momo, AppColors.momo),
              const SizedBox(width: 8),
              _SummaryChip('Visa', visa, AppColors.visa),
              const SizedBox(width: 8),
              _SummaryChip('Debt', debt, AppColors.debt),
            ],
          ),
          const SizedBox(height: 12),
          // Client breakdown
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                _MiniStat('Normal', normal),
                Container(
                  width: 1,
                  height: 24,
                  color: Colors.white.withValues(alpha: 0.12),
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                ),
                _MiniStat('Staff', staffAmt),
                Container(
                  width: 1,
                  height: 24,
                  color: Colors.white.withValues(alpha: 0.12),
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                ),
                _MiniStat('Company', company),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReconciliationCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE9ECEF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Closing Balances',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Count your drawer and enter the actual amounts.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 20),
          _ReconciliationRow(
            label: 'Cash',
            icon: Icons.payments_outlined,
            color: AppColors.cash,
            opening: _shift?.openingCash ?? 0,
            sales: _cashSales(_transactions),
            expected: _expectedCash(_transactions),
            controller: _cashController,
            diff: _cashDiff,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 20),
          _ReconciliationRow(
            label: 'MoMo',
            icon: Icons.phone_android_outlined,
            color: AppColors.momo,
            opening: _shift?.openingMomo ?? 0,
            sales: _momoSales(_transactions),
            expected: _expectedMomo(_transactions),
            controller: _momoController,
            diff: _momoDiff,
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
    );
  }

  void _showDiscrepancyDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Discrepancy Detected'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Your counts don't match expectations:",
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 12),
            if (_cashDiff != 0) _DiscrepancyLine('Cash', _cashDiff),
            if (_momoDiff != 0) _DiscrepancyLine('MoMo', _momoDiff),
            const SizedBox(height: 12),
            const Text(
              'Close anyway?',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Re-check'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _closeShift();
            },
            child: const Text(
              'Close Anyway',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessScreen() {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle_outline,
                    color: AppColors.success,
                    size: 40,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Shift Closed',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${_staff?.name ?? 'Staff'}  ·  ${_fmtDate(DateTime.now())}',
                  style: const TextStyle(color: Colors.white54, fontSize: 14),
                ),
                const SizedBox(height: 36),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    children: [
                      _SuccessRow(
                        'Total Revenue',
                        _fmtRwf(_totalSales(_transactions)),
                        Colors.white,
                      ),
                      const SizedBox(height: 8),
                      _SuccessRow(
                        'Cash',
                        _fmtRwf(_cashSales(_transactions)),
                        AppColors.cash,
                      ),
                      _SuccessRow(
                        'MoMo',
                        _fmtRwf(_momoSales(_transactions)),
                        AppColors.momo,
                      ),
                      _SuccessRow(
                        'Visa',
                        _fmtRwf(_visaSales(_transactions)),
                        AppColors.visa,
                      ),
                      const Divider(color: Colors.white12, height: 20),
                      _SuccessRow(
                        'Closing Cash',
                        _fmtRwf(_closingCashVal),
                        Colors.white70,
                      ),
                      _SuccessRow(
                        'Closing MoMo',
                        _fmtRwf(_closingMomoVal),
                        Colors.white70,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 36),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () => context.go('/login'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                    ),
                    child: const Text('Back to Start'),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () => context.go('/export'),
                  child: const Text(
                    'Export This Shift',
                    style: TextStyle(color: Colors.white38),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _fmtDate(DateTime d) {
    const m = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    const w = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${w[d.weekday - 1]}, ${d.day} ${m[d.month - 1]} ${d.year}';
  }

  String _fmtRwf(int v) {
    final s = v.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return '$buf RWF';
  }
}

// ═══════════════════════════════════════════════════════════════════════════

class _SummaryChip extends StatelessWidget {
  final String label;
  final int amount;
  final Color color;
  const _SummaryChip(this.label, this.amount, this.color);
  String _k(int v) {
    if (v >= 1000) {
      final k = v / 1000;
      return '${k % 1 == 0 ? k.toInt() : k.toStringAsFixed(1)}k';
    }
    return v.toString();
  }

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          Text(
            _k(amount),
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(color: color.withValues(alpha: 0.8), fontSize: 11),
          ),
        ],
      ),
    ),
  );
}

class _MiniStat extends StatelessWidget {
  final String label;
  final int amount;
  const _MiniStat(this.label, this.amount);
  String _k(int v) {
    if (v >= 1000) {
      final k = v / 1000;
      return '${k % 1 == 0 ? k.toInt() : k.toStringAsFixed(1)}k';
    }
    return v.toString();
  }

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Text(
          _k(amount),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(color: Colors.white38, fontSize: 11),
        ),
      ],
    ),
  );
}

class _ReconciliationRow extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final int opening, sales, expected, diff;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  const _ReconciliationRow({
    required this.label,
    required this.icon,
    required this.color,
    required this.opening,
    required this.sales,
    required this.expected,
    required this.controller,
    required this.diff,
    required this.onChanged,
  });

  String _k(int v) {
    if (v >= 1000) {
      final k = v / 1000;
      return '${k % 1 == 0 ? k.toInt() : k.toStringAsFixed(1)}k';
    }
    return v.toString();
  }

  @override
  Widget build(BuildContext context) {
    final isExact = diff == 0;
    final isOver = diff > 0;
    final diffColor = isExact
        ? AppColors.success
        : isOver
        ? AppColors.info
        : AppColors.error;
    final diffText = isExact
        ? 'Exact ✓'
        : isOver
        ? '+${diff.abs()} over'
        : '${diff.abs()} short';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              _Calc('Opening', _k(opening)),
              const Text(' + ', style: TextStyle(color: AppColors.textHint)),
              _Calc('Sales', _k(sales)),
              const Text(' = ', style: TextStyle(color: AppColors.textHint)),
              _Calc('Expected', _k(expected), bold: true),
            ],
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: onChanged,
          decoration: InputDecoration(
            labelText: 'Actual $label in drawer',
            prefixIcon: Icon(icon, color: color, size: 18),
            suffixText: 'RWF',
            suffixStyle: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: diffColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: diffColor.withValues(alpha: 0.3)),
              ),
              child: Text(
                diffText,
                style: TextStyle(
                  color: diffColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Calc extends StatelessWidget {
  final String label, value;
  final bool bold;
  const _Calc(this.label, this.value, {this.bold = false});
  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
            fontSize: bold ? 14 : 13,
            color: bold ? AppColors.textPrimary : AppColors.textSecondary,
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: AppColors.textHint, fontSize: 10),
        ),
      ],
    ),
  );
}

class _DiscrepancyLine extends StatelessWidget {
  final String label;
  final int diff;
  const _DiscrepancyLine(this.label, this.diff);
  @override
  Widget build(BuildContext context) {
    final isOver = diff > 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(
            '${isOver ? '+' : ''}$diff RWF (${isOver ? 'over' : 'short'})',
            style: TextStyle(
              color: isOver ? AppColors.info : AppColors.error,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SuccessRow extends StatelessWidget {
  final String label, value;
  final Color color;
  const _SuccessRow(this.label, this.value, this.color);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 13),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
      ],
    ),
  );
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.error.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      children: [
        const Icon(Icons.error_outline, color: AppColors.error, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(color: AppColors.error, fontSize: 12),
          ),
        ),
      ],
    ),
  );
}
