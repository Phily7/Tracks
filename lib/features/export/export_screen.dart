// ignore_for_file: deprecated_member_use
import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/database/app_database.dart';
import '../../core/database/database_provider.dart';
import '../../shared/theme/app_colors.dart';

class ExportScreen extends ConsumerStatefulWidget {
  const ExportScreen({super.key});

  @override
  ConsumerState<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends ConsumerState<ExportScreen> {
  List<ShiftsTableData> _shifts = [];
  List<ProductsTableData> _products = [];
  ShiftsTableData? _selectedShift;

  bool _loading = true;
  bool _exporting = false;
  String? _lastExported;
  String? _error;

  bool _includeSummary = true;
  bool _includeTransactions = true;
  bool _includeStock = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final db = ref.read(databaseProvider);
    final shifts = await db.shiftsDao.getAllShifts();
    final products = await db.productsDao.getActiveProducts();
    if (mounted) {
      setState(() {
        _shifts = shifts;
        _products = products;
        _selectedShift = shifts.isNotEmpty ? shifts.first : null;
        _loading = false;
      });
    }
  }

  Future<void> _export() async {
    if (_selectedShift == null) {
      setState(() => _error = 'Please select a shift');
      return;
    }
    setState(() {
      _exporting = true;
      _error = null;
    });
    try {
      final db = ref.read(databaseProvider);
      final shift = _selectedShift!;
      final txns = await db.transactionsDao.getTransactionsByShift(shift.id);
      final stock = await db.stockMovementsDao.getMovementsByShift(shift.id);
      final allStaff = await db.staffDao.getActiveStaff();
      final staffName =
          allStaff
              .where((s) => s.id == shift.staffId)
              .map((s) => s.name)
              .firstOrNull ??
          'Unknown';

      final csv = StringBuffer();

      if (_includeSummary) {
        final totalRev = txns.fold(0, (s, t) => s + t.totalAmount);
        final cashRev = txns
            .where((t) => t.paymentMethod == 'cash')
            .fold(0, (s, t) => s + t.totalAmount);
        final momoRev = txns
            .where((t) => t.paymentMethod == 'momo')
            .fold(0, (s, t) => s + t.totalAmount);
        final visaRev = txns
            .where((t) => t.paymentMethod == 'visa')
            .fold(0, (s, t) => s + t.totalAmount);
        final normalRev = txns
            .where((t) => t.clientType == 'normal')
            .fold(0, (s, t) => s + t.totalAmount);
        final staffRev = txns
            .where((t) => t.clientType == 'staff')
            .fold(0, (s, t) => s + t.totalAmount);
        final companyRev = txns
            .where((t) => t.clientType == 'company')
            .fold(0, (s, t) => s + t.totalAmount);
        final debtRev = txns
            .where((t) => t.paymentMethod == 'debt')
            .fold(0, (s, t) => s + t.totalAmount);

        csv.writeln('=== SHIFT SUMMARY ===');
        csv.writeln('Date,${_fmtDate(shift.date)}');
        csv.writeln('Staff,$staffName');
        csv.writeln('Status,${shift.status.toUpperCase()}');
        csv.writeln('Opening Cash,${shift.openingCash}');
        csv.writeln('Opening MoMo,${shift.openingMomo}');
        csv.writeln('Closing Cash,${shift.closingCash ?? "N/A"}');
        csv.writeln('Closing MoMo,${shift.closingMomo ?? "N/A"}');
        csv.writeln('');
        csv.writeln('=== REVENUE BREAKDOWN ===');
        csv.writeln('Total,$totalRev');
        csv.writeln('Cash,$cashRev');
        csv.writeln('MoMo,$momoRev');
        csv.writeln('Visa,$visaRev');
        csv.writeln('Normal Clients,$normalRev');
        csv.writeln('Staff,$staffRev');
        csv.writeln('Company,$companyRev');
        csv.writeln('Debt,$debtRev');
        csv.writeln('=== SALES BY PRODUCT ===');
        csv.writeln('Product,Qty Sold,Unit Price,Total (RWF)');
        for (final p in _products) {
          final pTxns = txns.where((t) => t.productId == p.id).toList();
          if (pTxns.isEmpty) continue;
          final qty = pTxns.fold(0, (s, t) => s + t.quantity);
          final total = pTxns.fold(0, (s, t) => s + t.totalAmount);
          csv.writeln('"${p.name}",$qty,${pTxns.first.unitPrice},$total');
        }
        csv.writeln('');
      }

      if (_includeTransactions) {
        csv.writeln('=== TRANSACTIONS ===');
        csv.writeln('Time,Product,Qty,Unit Price,Total,Payment,Client Type');
        for (final t in txns) {
          final name =
              _products
                  .where((p) => p.id == t.productId)
                  .map((p) => p.name)
                  .firstOrNull ??
              'Unknown';
          csv.writeln(
            '"${_fmtDateTime(t.createdAt)}","$name",${t.quantity},${t.unitPrice},${t.totalAmount},${t.paymentMethod.toUpperCase()},${t.clientType.toUpperCase()}',
          );
        }
        csv.writeln('');
      }

      if (_includeStock) {
        csv.writeln('=== STOCK MOVEMENTS ===');
        csv.writeln(
          'Product,Opening,Refill,Closing,Sold (calc),Txn Count,Variance',
        );
        for (final m in stock) {
          final name =
              _products
                  .where((p) => p.id == m.productId)
                  .map((p) => p.name)
                  .firstOrNull ??
              'Unknown';
          final closing = m.closingStock;
          final sold = closing != null
              ? ((m.openStock + m.refillQty) - closing).clamp(0, 99999)
              : null;
          final txnSold = txns
              .where((t) => t.productId == m.productId)
              .fold(0, (s, t) => s + t.quantity);
          final variance = sold != null ? txnSold - sold : 'N/A';
          csv.writeln(
            '"$name",${m.openStock},${m.refillQty},${closing ?? "N/A"},${sold ?? "N/A"},$txnSold,$variance',
          );
        }
      }

      // Trigger download via package:web
      final fileName =
          'fabfoods_${_fmtDate(shift.date).replaceAll(' ', '_')}_${staffName.toLowerCase()}.csv';

      final blob = html.Blob([csv.toString()], 'text/csv;charset=utf-8;');
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.AnchorElement(href: url)
        ..setAttribute('download', fileName)
        ..click();
      html.Url.revokeObjectUrl(url);

      if (mounted)
        setState(() {
          _exporting = false;
          _lastExported = fileName;
        });
    } catch (e) {
      setState(() {
        _exporting = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: AppColors.primary,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }
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
                    _buildShiftSelector(),
                    const SizedBox(height: 16),
                    if (_selectedShift != null) _buildShiftPreview(),
                    const SizedBox(height: 16),
                    _buildExportOptions(),
                    const SizedBox(height: 24),
                    if (_lastExported != null) _buildSuccessBanner(),
                    if (_error != null) _buildErrorBanner(),
                    const SizedBox(height: 8),
                    _buildDownloadButton(),
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

  Widget _buildHeader() => Container(
    color: AppColors.primary,
    padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
    child: Row(
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
        const Icon(
          Icons.file_download_outlined,
          color: AppColors.accent,
          size: 20,
        ),
        const SizedBox(width: 8),
        const Text(
          'Export Data',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Text(
            'CSV',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _buildShiftSelector() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.grey200),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Label('Select Shift'),
        const SizedBox(height: 10),
        if (_shifts.isEmpty)
          const Text(
            'No shifts found.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          )
        else
          DropdownButtonFormField<ShiftsTableData>(
            value: _selectedShift,
            isExpanded: true,
            decoration: const InputDecoration(
              hintText: 'Choose a shift',
              prefixIcon: Icon(Icons.calendar_today_outlined, size: 17),
            ),
            items: _shifts
                .map(
                  (s) => DropdownMenuItem(
                    value: s,
                    child: Text(
                      '${_fmtDate(s.date)}  ·  ${s.status.toUpperCase()}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: (s) => setState(() {
              _selectedShift = s;
              _lastExported = null;
            }),
          ),
      ],
    ),
  );

  Widget _buildShiftPreview() {
    final shift = _selectedShift!;
    return FutureBuilder<List<TransactionsTableData>>(
      future: ref
          .read(databaseProvider)
          .transactionsDao
          .getTransactionsByShift(shift.id),
      builder: (context, snap) {
        final txns = snap.data ?? [];
        final total = txns.fold(0, (s, t) => s + t.totalAmount);
        final cash = txns
            .where((t) => t.paymentMethod == 'cash')
            .fold(0, (s, t) => s + t.totalAmount);
        final momo = txns
            .where((t) => t.paymentMethod == 'momo')
            .fold(0, (s, t) => s + t.totalAmount);
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Shift Preview',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text(
                    _fmtDate(shift.date),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const Spacer(),
                  _StatusBadge(shift.status),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _PStat('Total', _fmtK(total), Colors.white),
                  const SizedBox(width: 16),
                  _PStat('Cash', _fmtK(cash), AppColors.cash),
                  const SizedBox(width: 16),
                  _PStat('MoMo', _fmtK(momo), AppColors.momo),
                  const Spacer(),
                  _PStat('Txns', '${txns.length}', Colors.white54),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildExportOptions() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.grey200),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Label('Include in Export'),
        const SizedBox(height: 12),
        _Toggle(
          label: 'Summary & Revenue Breakdown',
          subtitle: 'Totals by payment method and client type',
          icon: Icons.bar_chart_outlined,
          value: _includeSummary,
          onChanged: (v) => setState(() => _includeSummary = v),
        ),
        const Divider(height: 20),
        _Toggle(
          label: 'Transaction Log',
          subtitle: 'Every sale with time, product, qty, price',
          icon: Icons.receipt_long_outlined,
          value: _includeTransactions,
          onChanged: (v) => setState(() => _includeTransactions = v),
        ),
        const Divider(height: 20),
        _Toggle(
          label: 'Stock Movements',
          subtitle: 'Opening, refill, closing + variance',
          icon: Icons.inventory_2_outlined,
          value: _includeStock,
          onChanged: (v) => setState(() => _includeStock = v),
        ),
      ],
    ),
  );

  Widget _buildSuccessBanner() => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.success.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppColors.success.withValues(alpha: 0.25)),
    ),
    child: Row(
      children: [
        const Icon(
          Icons.check_circle_outline,
          color: AppColors.success,
          size: 18,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Downloaded!',
                style: TextStyle(
                  color: AppColors.success,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              Text(
                _lastExported!,
                style: const TextStyle(color: AppColors.success, fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _buildErrorBanner() => Container(
    margin: const EdgeInsets.only(bottom: 12),
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
            _error!,
            style: const TextStyle(color: AppColors.error, fontSize: 12),
          ),
        ),
      ],
    ),
  );

  Widget _buildDownloadButton() => SizedBox(
    width: double.infinity,
    height: 52,
    child: ElevatedButton.icon(
      onPressed:
          (_exporting ||
              _selectedShift == null ||
              (!_includeSummary && !_includeTransactions && !_includeStock))
          ? null
          : _export,
      icon: _exporting
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.download_outlined, size: 20),
      label: Text(_exporting ? 'Exporting...' : 'Download CSV'),
    ),
  );

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
    return '${w[d.weekday - 1]} ${d.day} ${m[d.month - 1]} ${d.year}';
  }

  String _fmtDateTime(DateTime d) =>
      '${_fmtDate(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  String _fmtK(int v) {
    if (v >= 1000) {
      final k = v / 1000;
      return '${k % 1 == 0 ? k.toInt() : k.toStringAsFixed(1)}k';
    }
    return v.toString();
  }
}

// ═══════════════════════════════════════════════════════════════════════════

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: AppColors.textSecondary,
      letterSpacing: 0.2,
    ),
  );
}

class _Toggle extends StatelessWidget {
  final String label, subtitle;
  final IconData icon;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _Toggle({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.value,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: value
              ? AppColors.accent.withValues(alpha: 0.1)
              : AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          size: 18,
          color: value ? AppColors.accent : AppColors.grey400,
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: value ? AppColors.textPrimary : AppColors.grey400,
              ),
            ),
            Text(
              subtitle,
              style: const TextStyle(color: AppColors.textHint, fontSize: 11),
            ),
          ],
        ),
      ),
      Switch(value: value, onChanged: onChanged, activeColor: AppColors.accent),
    ],
  );
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge(this.status);
  @override
  Widget build(BuildContext context) {
    final isOpen = status == 'open';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: (isOpen ? AppColors.success : AppColors.grey500).withValues(
          alpha: 0.15,
        ),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          color: isOpen ? AppColors.success : AppColors.grey400,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _PStat extends StatelessWidget {
  final String label, value;
  final Color color;
  const _PStat(this.label, this.value, this.color);
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        value,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 15,
        ),
      ),
      Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10)),
    ],
  );
}
