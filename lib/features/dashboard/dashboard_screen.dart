import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/database/app_database.dart';
import '../../core/database/database_provider.dart';
import '../../shared/theme/app_colors.dart';

// ── Time range enum ───────────────────────────────────────────────────────────
enum DashRange { day, week, month, quarter, year, all }

extension DashRangeExt on DashRange {
  String get label => switch (this) {
    DashRange.day => 'Day',
    DashRange.week => 'Week',
    DashRange.month => 'Month',
    DashRange.quarter => 'Quarter',
    DashRange.year => 'Year',
    DashRange.all => 'All',
  };
}

// ── Data model ────────────────────────────────────────────────────────────────
class DashData {
  final List<TransactionsTableData> txns;
  final List<ShiftsTableData> shifts;
  final List<ProductsTableData> products;
  final List<StaffTableData> staff;
  final List<StockMovementsTableData> stock;
  const DashData({
    required this.txns,
    required this.shifts,
    required this.products,
    required this.staff,
    required this.stock,
  });

  int get totalRevenue => txns.fold(0, (s, t) => s + t.totalAmount);
  int get cashRevenue => txns
      .where((t) => t.paymentMethod == 'cash')
      .fold(0, (s, t) => s + t.totalAmount);
  int get momoRevenue => txns
      .where((t) => t.paymentMethod == 'momo')
      .fold(0, (s, t) => s + t.totalAmount);
  int get visaRevenue => txns
      .where((t) => t.paymentMethod == 'visa')
      .fold(0, (s, t) => s + t.totalAmount);
  int get normalRevenue => txns
      .where((t) => t.clientType == 'normal')
      .fold(0, (s, t) => s + t.totalAmount);
  int get staffRevenue => txns
      .where((t) => t.clientType == 'staff')
      .fold(0, (s, t) => s + t.totalAmount);
  int get companyRevenue => txns
      .where((t) => t.clientType == 'company')
      .fold(0, (s, t) => s + t.totalAmount);

  int get debtRevenue => txns
      .where((t) => t.paymentMethod == 'debt')
      .fold(0, (s, t) => s + t.totalAmount);
  int get txnCount => txns.length;
  int get shiftCount => shifts.length;
  double get avgPerShift => shiftCount == 0 ? 0 : totalRevenue / shiftCount;
}

// ── Screen ────────────────────────────────────────────────────────────────────
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});
  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen>
    with SingleTickerProviderStateMixin {
  // ── State ─────────────────────────────────────────────────────────────────
  DashRange _range = DashRange.week;
  DateTime _anchor = DateTime.now(); // the "current" period centre
  ShiftsTableData? _singleShift; // null = all shifts in range

  DashData? _data;
  List<ShiftsTableData> _allShifts = [];
  bool _loading = true;
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(
      length: 6,
      vsync: this,
      initialIndex: DashRange.values.indexOf(_range),
    );
    _tabCtrl.addListener(() {
      if (!_tabCtrl.indexIsChanging) return;
      setState(() {
        _range = DashRange.values[_tabCtrl.index];
        _singleShift = null;
        _anchor = DateTime.now();
      });
      _load();
    });
    _load();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  // ── Date range helpers ────────────────────────────────────────────────────

  (DateTime, DateTime) get _bounds {
    final a = _anchor;
    return switch (_range) {
      DashRange.day => (
        DateTime(a.year, a.month, a.day),
        DateTime(a.year, a.month, a.day, 23, 59, 59),
      ),
      DashRange.week => () {
        final mon = a.subtract(Duration(days: a.weekday - 1));
        final start = DateTime(mon.year, mon.month, mon.day);
        return (
          start,
          start.add(
            const Duration(days: 6, hours: 23, minutes: 59, seconds: 59),
          ),
        );
      }(),
      DashRange.month => (
        DateTime(a.year, a.month, 1),
        DateTime(a.year, a.month + 1, 0, 23, 59, 59),
      ),
      DashRange.quarter => () {
        final q = ((a.month - 1) ~/ 3) * 3 + 1;
        return (DateTime(a.year, q, 1), DateTime(a.year, q + 3, 0, 23, 59, 59));
      }(),
      DashRange.year => (
        DateTime(a.year, 1, 1),
        DateTime(a.year, 12, 31, 23, 59, 59),
      ),
      DashRange.all => (DateTime(2020), DateTime(2099)),
    };
  }

  String get _periodLabel {
    final (s, e) = _bounds;
    return switch (_range) {
      DashRange.day => _fmtDate(s),
      DashRange.week => '${_fmtShort(s)} – ${_fmtShort(e)}',
      DashRange.month => _monthYear(s),
      DashRange.quarter => 'Q${((s.month - 1) ~/ 3) + 1} ${s.year}',
      DashRange.year => '${s.year}',
      DashRange.all => 'All Time',
    };
  }

  void _prev() {
    setState(() {
      _singleShift = null;
      _anchor = _shiftAnchor(-1);
    });
    _load();
  }

  void _next() {
    setState(() {
      _singleShift = null;
      _anchor = _shiftAnchor(1);
    });
    _load();
  }

  DateTime _shiftAnchor(int dir) {
    final a = _anchor;
    return switch (_range) {
      DashRange.day => a.add(Duration(days: dir)),
      DashRange.week => a.add(Duration(days: 7 * dir)),
      DashRange.month => DateTime(a.year, a.month + dir, 1),
      DashRange.quarter => DateTime(a.year, a.month + 3 * dir, 1),
      DashRange.year => DateTime(a.year + dir, 1, 1),
      DashRange.all => a,
    };
  }

  // ── Data loading ──────────────────────────────────────────────────────────

  Future<void> _load() async {
    setState(() => _loading = true);
    final db = ref.read(databaseProvider);
    final (start, end) = _bounds;

    final allShifts = await db.shiftsDao.getAllShifts();
    final allProducts = await db.productsDao.getActiveProducts();
    final allStaff = await db.staffDao.getActiveStaff();

    // Filter shifts to range
    final rangeShifts = _range == DashRange.all
        ? allShifts
        : allShifts
              .where(
                (s) =>
                    s.date.isAfter(
                      start.subtract(const Duration(seconds: 1)),
                    ) &&
                    s.date.isBefore(end.add(const Duration(seconds: 1))),
              )
              .toList();

    // If single shift selected, use only that
    final targetShifts = _singleShift != null ? [_singleShift!] : rangeShifts;

    // Load transactions for target shifts
    List<TransactionsTableData> txns = [];
    List<StockMovementsTableData> stock = [];
    for (final s in targetShifts) {
      txns.addAll(await db.transactionsDao.getTransactionsByShift(s.id));
      stock.addAll(await db.stockMovementsDao.getMovementsByShift(s.id));
    }

    if (mounted) {
      setState(() {
        _allShifts = rangeShifts;
        _data = DashData(
          txns: txns,
          shifts: targetShifts,
          products: allProducts,
          staff: allStaff,
          stock: stock,
        );
        _loading = false;
      });
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildRangeTabs(),
            _buildPeriodNav(),
            if (_allShifts.isNotEmpty && _range != DashRange.all)
              _buildShiftChips(),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppColors.accent),
                    )
                  : _data == null || _data!.txns.isEmpty
                  ? _buildEmpty()
                  : _buildCharts(),
            ),
          ],
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

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
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: AppColors.accent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.restaurant, color: Colors.white, size: 17),
        ),
        const SizedBox(width: 10),
        const Text(
          'FabFoods',
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        const Spacer(),
        const Icon(Icons.analytics_outlined, color: AppColors.accent, size: 20),
        const SizedBox(width: 6),
        const Text(
          'Dashboard',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: 16),
        GestureDetector(
          onTap: () => context.go('/login'),
          child: const Icon(
            Icons.logout_outlined,
            color: Colors.white38,
            size: 18,
          ),
        ),
      ],
    ),
  );

  // ── Range tabs ────────────────────────────────────────────────────────────

  Widget _buildRangeTabs() => Container(
    color: AppColors.grey800,
    child: TabBar(
      controller: _tabCtrl,
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      indicatorColor: AppColors.accent,
      indicatorWeight: 2.5,
      labelColor: AppColors.accent,
      unselectedLabelColor: AppColors.grey400,
      labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
      tabs: DashRange.values.map((r) => Tab(text: r.label)).toList(),
    ),
  );

  // ── Period nav ────────────────────────────────────────────────────────────

  Widget _buildPeriodNav() => Container(
    color: AppColors.grey700,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Row(
      children: [
        if (_range != DashRange.all)
          GestureDetector(
            onTap: _prev,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.grey600,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(
                Icons.chevron_left,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            _periodLabel,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ),
        const SizedBox(width: 12),
        if (_range != DashRange.all)
          GestureDetector(
            onTap: _next,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.grey600,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(
                Icons.chevron_right,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
      ],
    ),
  );

  // ── Shift chips ───────────────────────────────────────────────────────────

  Widget _buildShiftChips() => Container(
    color: AppColors.grey800,
    height: 40,
    child: ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      children: [
        _ShiftChip(
          label: 'All Shifts (${_allShifts.length})',
          active: _singleShift == null,
          onTap: () {
            setState(() => _singleShift = null);
            _load();
          },
        ),
        ..._allShifts.map(
          (s) => _ShiftChip(
            label: _fmtShort(s.date),
            active: _singleShift?.id == s.id,
            onTap: () {
              setState(() => _singleShift = s);
              _load();
            },
          ),
        ),
      ],
    ),
  );

  // ── Empty state ───────────────────────────────────────────────────────────

  Widget _buildEmpty() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.bar_chart_outlined,
          color: AppColors.grey400,
          size: 48,
        ),
        const SizedBox(height: 12),
        const Text(
          'No data for this period',
          style: TextStyle(
            color: AppColors.grey500,
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _singleShift != null
              ? 'No transactions in this shift'
              : 'Try a different range or navigate to another period',
          style: const TextStyle(color: AppColors.grey400, fontSize: 12),
        ),
      ],
    ),
  );

  // ── Charts ────────────────────────────────────────────────────────────────

  Widget _buildCharts() {
    final d = _data!;
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        _buildKpiRow(d),
        const SizedBox(height: 16),
        _buildRevenueChart(d),
        const SizedBox(height: 16),
        _buildPaymentChart(d),
        const SizedBox(height: 16),
        _buildClientChart(d),
        const SizedBox(height: 16),
        _buildTopProducts(d),
        const SizedBox(height: 16),
        _buildStaffChart(d),
        if (d.stock.isNotEmpty) ...[
          const SizedBox(height: 16),
          _buildStockVariance(d),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  // ── KPI row ───────────────────────────────────────────────────────────────

  Widget _buildKpiRow(DashData d) => Row(
    children: [
      _KpiCard(
        'Revenue',
        _fmtRwf(d.totalRevenue),
        AppColors.accent,
        Icons.trending_up_outlined,
      ),
      const SizedBox(width: 8),
      _KpiCard(
        'Shifts',
        '${d.shiftCount}',
        AppColors.info,
        Icons.access_time_outlined,
      ),
      const SizedBox(width: 8),
      _KpiCard(
        'Sales',
        '${d.txnCount}',
        AppColors.success,
        Icons.receipt_long_outlined,
      ),
      const SizedBox(width: 8),
      _KpiCard(
        'Avg/Shift',
        _fmtK(d.avgPerShift.toInt()),
        AppColors.grey500,
        Icons.show_chart_outlined,
      ),
    ],
  );

  // ── Revenue trend (line chart) ────────────────────────────────────────────

  Widget _buildRevenueChart(DashData d) {
    // Group transactions by shift date
    final Map<String, int> byDate = {};
    for (final t in d.txns) {
      final key = _fmtShort(t.createdAt);
      byDate[key] = (byDate[key] ?? 0) + t.totalAmount;
    }
    if (byDate.isEmpty) return const SizedBox.shrink();
    final keys = byDate.keys.toList();
    final values = byDate.values.toList();
    final maxY = (values.reduce((a, b) => a > b ? a : b) * 1.2).toDouble();

    final spots = List.generate(
      keys.length,
      (i) => FlSpot(i.toDouble(), values[i].toDouble()),
    );

    return _ChartCard(
      title: 'Revenue Trend',
      subtitle: '${keys.length} data point${keys.length == 1 ? '' : 's'}',
      icon: Icons.show_chart,
      child: SizedBox(
        height: 180,
        child: LineChart(
          LineChartData(
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: maxY / 4,
              getDrawingHorizontalLine: (_) =>
                  FlLine(color: AppColors.grey200, strokeWidth: 1),
            ),
            titlesData: FlTitlesData(
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 44,
                  getTitlesWidget: (v, _) => Text(
                    _fmtK(v.toInt()),
                    style: const TextStyle(
                      color: AppColors.grey400,
                      fontSize: 9,
                    ),
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  interval: keys.length > 7
                      ? (keys.length / 6).ceilToDouble()
                      : 1,
                  getTitlesWidget: (v, _) {
                    final i = v.toInt();
                    if (i < 0 || i >= keys.length)
                      return const SizedBox.shrink();
                    return Text(
                      keys[i],
                      style: const TextStyle(
                        color: AppColors.grey400,
                        fontSize: 8,
                      ),
                    );
                  },
                ),
              ),
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
            ),
            borderData: FlBorderData(show: false),
            minX: 0,
            maxX: (keys.length - 1).toDouble(),
            minY: 0,
            maxY: maxY,
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                isCurved: true,
                color: AppColors.accent,
                barWidth: 2.5,
                dotData: FlDotData(
                  show: true,
                  getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                    radius: 3,
                    color: AppColors.accent,
                    strokeWidth: 1.5,
                    strokeColor: Colors.white,
                  ),
                ),
                belowBarData: BarAreaData(
                  show: true,
                  color: AppColors.accent.withValues(alpha: 0.08),
                ),
              ),
            ],
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipItems: (spots) => spots
                    .map(
                      (s) => LineTooltipItem(
                        '${keys[s.x.toInt()]}\n${_fmtRwf(s.y.toInt())}',
                        const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Payment method (bar chart) ────────────────────────────────────────────

  Widget _buildPaymentChart(DashData d) {
    final vals = [d.cashRevenue, d.momoRevenue, d.visaRevenue, d.debtRevenue];
    final labels = ['Cash', 'MoMo', 'Visa', 'Debt'];
    final colors = [
      AppColors.cash,
      AppColors.momo,
      AppColors.visa,
      AppColors.debt,
    ];
    final maxY = vals.isEmpty
        ? 1.0
        : (vals.reduce((a, b) => a > b ? a : b) * 1.25).toDouble();

    return _ChartCard(
      title: 'Payment Methods',
      subtitle: 'Revenue by payment type',
      icon: Icons.payments_outlined,
      child: SizedBox(
        height: 160,
        child: BarChart(
          BarChartData(
            alignment: BarChartAlignment.spaceAround,
            maxY: maxY == 0 ? 1 : maxY,
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipItem: (group, _, rod, __) => BarTooltipItem(
                  '${labels[group.x]}\n${_fmtRwf(rod.toY.toInt())}',
                  const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            titlesData: FlTitlesData(
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (v, _) => Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      labels[v.toInt()],
                      style: const TextStyle(
                        color: AppColors.grey500,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 44,
                  getTitlesWidget: (v, _) => Text(
                    _fmtK(v.toInt()),
                    style: const TextStyle(
                      color: AppColors.grey400,
                      fontSize: 9,
                    ),
                  ),
                ),
              ),
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
            ),
            borderData: FlBorderData(show: false),
            gridData: FlGridData(
              drawVerticalLine: false,
              getDrawingHorizontalLine: (_) =>
                  FlLine(color: AppColors.grey200, strokeWidth: 1),
            ),
            barGroups: List.generate(
              3,
              (i) => BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: vals[i].toDouble(),
                    color: colors[i],
                    width: 36,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(6),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Client type (bar chart) ───────────────────────────────────────────────

  Widget _buildClientChart(DashData d) {
    final vals = [d.normalRevenue, d.staffRevenue, d.companyRevenue];
    final labels = ['Normal', 'Staff', 'Company'];
    final colors = [AppColors.accent, AppColors.info, AppColors.grey600];
    final maxY = vals.isEmpty
        ? 1.0
        : (vals.reduce((a, b) => a > b ? a : b) * 1.25).toDouble();

    return _ChartCard(
      title: 'Client Breakdown',
      subtitle: 'Revenue by client type',
      icon: Icons.people_outline,
      child: SizedBox(
        height: 160,
        child: BarChart(
          BarChartData(
            alignment: BarChartAlignment.spaceAround,
            maxY: maxY == 0 ? 1 : maxY,
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipItem: (group, _, rod, __) => BarTooltipItem(
                  '${labels[group.x]}\n${_fmtRwf(rod.toY.toInt())}',
                  const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            titlesData: FlTitlesData(
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (v, _) => Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      labels[v.toInt()],
                      style: const TextStyle(
                        color: AppColors.grey500,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 44,
                  getTitlesWidget: (v, _) => Text(
                    _fmtK(v.toInt()),
                    style: const TextStyle(
                      color: AppColors.grey400,
                      fontSize: 9,
                    ),
                  ),
                ),
              ),
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
            ),
            borderData: FlBorderData(show: false),
            gridData: FlGridData(
              drawVerticalLine: false,
              getDrawingHorizontalLine: (_) =>
                  FlLine(color: AppColors.grey200, strokeWidth: 1),
            ),
            barGroups: List.generate(
              4,
              (i) => BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: vals[i].toDouble(),
                    color: colors[i],
                    width: 36,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(6),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Top products (horizontal bar chart) ───────────────────────────────────

  Widget _buildTopProducts(DashData d) {
    final Map<String, int> byProduct = {};
    for (final t in d.txns) {
      byProduct[t.productId] = (byProduct[t.productId] ?? 0) + t.totalAmount;
    }
    final sorted = byProduct.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = sorted.take(8).toList();
    if (top.isEmpty) return const SizedBox.shrink();

    final maxVal = top.first.value.toDouble();

    return _ChartCard(
      title: 'Top Products',
      subtitle: 'By revenue — top ${top.length}',
      icon: Icons.fastfood_outlined,
      child: Column(
        children: top.asMap().entries.map((entry) {
          final i = entry.key;
          final e = entry.value;
          final name =
              d.products
                  .where((p) => p.id == e.key)
                  .map((p) => p.name)
                  .firstOrNull ??
              'Unknown';
          final pct = maxVal == 0 ? 0.0 : e.value / maxVal;
          final colors = [
            AppColors.accent,
            AppColors.info,
            AppColors.success,
            AppColors.momo,
            AppColors.grey600,
            AppColors.grey500,
            AppColors.grey400,
            AppColors.grey300,
          ];

          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                SizedBox(
                  width: 16,
                  child: Text(
                    '${i + 1}',
                    style: const TextStyle(
                      color: AppColors.grey400,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            _fmtRwf(e.value),
                            style: TextStyle(
                              color: colors[i % colors.length],
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: pct,
                          minHeight: 5,
                          backgroundColor: AppColors.grey100,
                          valueColor: AlwaysStoppedAnimation(
                            colors[i % colors.length],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Staff performance ─────────────────────────────────────────────────────

  Widget _buildStaffChart(DashData d) {
    final Map<String, int> byStaff = {};
    for (final s in d.shifts) {
      final staffId = s.staffId ?? 'unknown';

      // Group by shift's staff
      final rev = d.txns
          .where(
            (t) => d.shifts
                .where((sh) => sh.staffId == staffId && sh.id == t.shiftId)
                .isNotEmpty,
          )
          .fold(0, (sum, t) => sum + t.totalAmount);
      if (rev > 0) byStaff[staffId] = (byStaff[staffId] ?? 0) + rev;
    }

    if (byStaff.isEmpty) return const SizedBox.shrink();

    final entries = byStaff.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final maxVal = entries.first.value.toDouble();

    return _ChartCard(
      title: 'Staff Performance',
      subtitle: 'Revenue per staff member',
      icon: Icons.person_outline,
      child: Column(
        children: entries.map((e) {
          final name =
              d.staff
                  .where((s) => s.id == e.key)
                  .map((s) => s.name)
                  .firstOrNull ??
              'Unknown';
          final pct = maxVal == 0 ? 0.0 : e.value / maxVal;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: AppColors.accent.withValues(alpha: 0.15),
                  child: Text(
                    name[0].toUpperCase(),
                    style: const TextStyle(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            _fmtRwf(e.value),
                            style: const TextStyle(
                              color: AppColors.accent,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: pct,
                          minHeight: 6,
                          backgroundColor: AppColors.grey100,
                          valueColor: const AlwaysStoppedAnimation(
                            AppColors.accent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Stock vs Sales variance ───────────────────────────────────────────────

  Widget _buildStockVariance(DashData d) {
    final rows = d.stock.map((m) {
      final name =
          d.products
              .where((p) => p.id == m.productId)
              .map((p) => p.name)
              .firstOrNull ??
          'Unknown';
      final closing = m.closingStock;
      final stockSold = closing != null
          ? ((m.openStock + m.refillQty) - closing).clamp(0, 99999)
          : null;
      final txnSold = d.txns
          .where((t) => t.productId == m.productId)
          .fold(0, (s, t) => s + t.quantity);
      final variance = stockSold != null ? txnSold - stockSold : null;
      return (name, txnSold, stockSold, variance);
    }).toList();

    return _ChartCard(
      title: 'Stock vs Transactions',
      subtitle: 'Variance: txn count minus stock count',
      icon: Icons.inventory_2_outlined,
      child: Column(
        children: [
          Row(
            children: const [
              Expanded(
                flex: 3,
                child: Text(
                  'Product',
                  style: TextStyle(
                    color: AppColors.grey400,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  'Txn',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.grey400,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  'Stock',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.grey400,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  'Var.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.grey400,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 10),
          ...rows.map((r) {
            final (name, txn, stock, variance) = r;
            final varColor = variance == null
                ? AppColors.grey400
                : variance == 0
                ? AppColors.success
                : variance > 0
                ? AppColors.info
                : AppColors.error;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(
                      name,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '$txn',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      stock != null ? '$stock' : '–',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      variance != null
                          ? (variance > 0 ? '+$variance' : '$variance')
                          : '–',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: varColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ── Formatters ────────────────────────────────────────────────────────────

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

  String _fmtShort(DateTime d) {
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
    return '${d.day} ${m[d.month - 1]}';
  }

  String _monthYear(DateTime d) {
    const m = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${m[d.month - 1]} ${d.year}';
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

  String _fmtK(int v) {
    if (v >= 1000) {
      final k = v / 1000;
      return '${k % 1 == 0 ? k.toInt() : k.toStringAsFixed(1)}k';
    }
    return v.toString();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Sub-widgets
// ═══════════════════════════════════════════════════════════════════════════

class _ChartCard extends StatelessWidget {
  final String title, subtitle;
  final IconData icon;
  final Widget child;
  const _ChartCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.grey200),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: AppColors.accent),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
            ),
            const Spacer(),
            Text(
              subtitle,
              style: const TextStyle(color: AppColors.textHint, fontSize: 11),
            ),
          ],
        ),
        const SizedBox(height: 16),
        child,
      ],
    ),
  );
}

class _KpiCard extends StatelessWidget {
  final String label, value;
  final Color color;
  final IconData icon;
  const _KpiCard(this.label, this.value, this.color, this.icon);

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.grey200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(color: AppColors.textHint, fontSize: 10),
          ),
        ],
      ),
    ),
  );
}

class _ShiftChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _ShiftChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: active ? AppColors.accent : AppColors.grey700,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: active ? Colors.white : AppColors.grey400,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}
