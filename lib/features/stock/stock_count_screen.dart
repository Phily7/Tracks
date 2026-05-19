import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/database/app_database.dart';
import '../../core/database/database_provider.dart';
import '../../shared/theme/app_colors.dart';

class StockCountScreen extends ConsumerStatefulWidget {
  final String shiftId;
  const StockCountScreen({super.key, required this.shiftId});

  @override
  ConsumerState<StockCountScreen> createState() => _StockCountScreenState();
}

class _StockCountScreenState extends ConsumerState<StockCountScreen>
    with SingleTickerProviderStateMixin {
  List<ProductsTableData> _products = [];
  List<StockMovementsTableData> _movements = [];
  List<TransactionsTableData> _transactions = [];

  // productId → controllers
  final Map<String, TextEditingController> _openCtrl = {};
  final Map<String, TextEditingController> _refillCtrl = {};
  final Map<String, TextEditingController> _closingCtrl = {};

  late TabController _tabCtrl;
  bool _loading = true;
  bool _saving = false;
  String? _saved;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _init();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    for (final c in _openCtrl.values) c.dispose();
    for (final c in _refillCtrl.values) c.dispose();
    for (final c in _closingCtrl.values) c.dispose();
    super.dispose();
  }

  // ── Init ──────────────────────────────────────────────────────────────────

  Future<void> _init() async {
    final db = ref.read(databaseProvider);
    final products = await db.productsDao.getActiveProducts();
    final movements = await db.stockMovementsDao.getMovementsByShift(
      widget.shiftId,
    );
    final txns = await db.transactionsDao.getTransactionsByShift(
      widget.shiftId,
    );

    for (final p in products) {
      final m = movements.where((x) => x.productId == p.id).firstOrNull;
      _openCtrl[p.id] = TextEditingController(
        text: m?.openStock.toString() ?? '',
      );
      _refillCtrl[p.id] = TextEditingController(
        text: m?.refillQty.toString() ?? '',
      );
      _closingCtrl[p.id] = TextEditingController(
        text: m?.closingStock?.toString() ?? '',
      );

      // Auto fill tentative closing if not yet
      if (m?.closingStock == null && _openCtrl[p.id]!.text.isNotEmpty) {
        final open = int.tryParse(_openCtrl[p.id]!.text) ?? 0;
        final refill = int.tryParse(_refillCtrl[p.id]!.text) ?? 0;
        final sold = txns
            .where((t) => t.productId == p.id)
            .fold(0, (s, t) => s + t.quantity);
        final tentative = (open + refill - sold).clamp(0, 99999);
        _closingCtrl[p.id]!.text = tentative.toString();
      }
    }

    if (mounted) {
      setState(() {
        _products = products;
        _movements = movements;
        _transactions = txns;
        _loading = false;
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => _saveAll());
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  StockMovementsTableData? _movementFor(String productId) =>
      _movements.where((m) => m.productId == productId).firstOrNull;

  int? _soldQty(String productId) {
    final m = _movementFor(productId);
    if (m == null) return null;
    final closing = int.tryParse(_closingCtrl[productId]?.text ?? '');
    if (closing == null) return null;
    final open = int.tryParse(_openCtrl[productId]?.text ?? '') ?? m.openStock;
    final refill =
        int.tryParse(_refillCtrl[productId]?.text ?? '') ?? m.refillQty;
    return ((open + refill) - closing).clamp(0, 99999);
  }

  int _txnSold(String productId) => _transactions
      .where((t) => t.productId == productId)
      .fold(0, (s, t) => s + t.quantity);

  // ── Save single product ───────────────────────────────────────────────────

  Future<void> _saveProduct(ProductsTableData p) async {
    final open = int.tryParse(_openCtrl[p.id]?.text ?? '');
    if (open == null) {
      setState(() => _error = 'Enter opening stock for ${p.name}');
      return;
    }
    final refill = int.tryParse(_refillCtrl[p.id]?.text ?? '') ?? 0;
    final closing = int.tryParse(_closingCtrl[p.id]?.text ?? '');

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final db = ref.read(databaseProvider);
      final existing = _movementFor(p.id);
      if (existing != null) {
        await db.stockMovementsDao.updateMovement(
          StockMovementsTableCompanion(
            id: Value(existing.id),
            shiftId: Value(widget.shiftId),
            productId: Value(p.id),
            openStock: Value(open),
            refillQty: Value(refill),
            closingStock: Value(closing),
          ),
        );
      } else {
        await db.stockMovementsDao.insertMovement(
          StockMovementsTableCompanion.insert(
            shiftId: widget.shiftId,
            productId: p.id,
            openStock: Value(open),
            refillQty: Value(refill),
            closingStock: Value(closing),
          ),
        );
      }
      final movements = await db.stockMovementsDao.getMovementsByShift(
        widget.shiftId,
      );
      if (mounted) {
        setState(() {
          _movements = movements;
          _saving = false;
          _saved = p.name;
        });
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) setState(() => _saved = null);
        });
      }
    } catch (e) {
      setState(() {
        _saving = false;
        _error = e.toString();
      });
    }
  }

  // ── Save all ──────────────────────────────────────────────────────────────

  Future<void> _saveAll() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final db = ref.read(databaseProvider);
      for (final p in _products) {
        final open = int.tryParse(_openCtrl[p.id]?.text ?? '');
        if (open == null) continue;
        final refill = int.tryParse(_refillCtrl[p.id]?.text ?? '') ?? 0;
        final closing = int.tryParse(_closingCtrl[p.id]?.text ?? '');
        final existing = _movementFor(p.id);
        if (existing != null) {
          await db.stockMovementsDao.updateMovement(
            StockMovementsTableCompanion(
              id: Value(existing.id),
              shiftId: Value(widget.shiftId),
              productId: Value(p.id),
              openStock: Value(open),
              refillQty: Value(refill),
              closingStock: Value(closing),
            ),
          );
        } else {
          await db.stockMovementsDao.insertMovement(
            StockMovementsTableCompanion.insert(
              shiftId: widget.shiftId,
              productId: p.id,
              openStock: Value(open),
              refillQty: Value(refill),
              closingStock: Value(closing),
            ),
          );
        }
      }
      final movements = await db.stockMovementsDao.getMovementsByShift(
        widget.shiftId,
      );
      if (mounted) {
        setState(() {
          _movements = movements;
          _saving = false;
          _saved = 'All products';
        });
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) setState(() => _saved = null);
        });
      }
    } catch (e) {
      setState(() {
        _saving = false;
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
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildTabBar(),
            Expanded(
              child: TabBarView(
                controller: _tabCtrl,
                children: [_buildCountTab(), _buildSummaryTab()],
              ),
            ),
            _buildBottomBar(),
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
          onTap: () => context.go('/shift/active', extra: widget.shiftId),
          child: const Icon(
            Icons.arrow_back_ios_new,
            color: Colors.white70,
            size: 18,
          ),
        ),
        const SizedBox(width: 12),
        const Icon(
          Icons.inventory_2_outlined,
          color: AppColors.accent,
          size: 20,
        ),
        const SizedBox(width: 8),
        const Text(
          'Stock Count',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const Spacer(),
        if (_saved != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check, color: AppColors.success, size: 13),
                SizedBox(width: 4),
                Text(
                  'Saved',
                  style: TextStyle(
                    color: AppColors.success,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );

  // ── Tab bar ───────────────────────────────────────────────────────────────

  Widget _buildTabBar() => Container(
    color: AppColors.grey800,
    child: TabBar(
      controller: _tabCtrl,
      indicatorColor: AppColors.accent,
      indicatorWeight: 2.5,
      labelColor: AppColors.accent,
      unselectedLabelColor: AppColors.grey400,
      labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
      tabs: [
        Tab(text: 'Count  (${_products.length})'),
        Tab(text: 'Summary  (${_movements.length} logged)'),
      ],
    ),
  );

  // ── Count tab ─────────────────────────────────────────────────────────────

  Widget _buildCountTab() => ListView.separated(
    padding: const EdgeInsets.all(14),
    itemCount: _products.length,
    separatorBuilder: (_, __) => const SizedBox(height: 10),
    itemBuilder: (_, i) => _StockRow(
      product: _products[i],
      movement: _movementFor(_products[i].id),
      txnSold: _txnSold(_products[i].id),
      openCtrl: _openCtrl[_products[i].id]!,
      refillCtrl: _refillCtrl[_products[i].id]!,
      closingCtrl: _closingCtrl[_products[i].id]!,
      onSave: () => _saveProduct(_products[i]),
      saving: _saving,
    ),
  );

  // ── Summary tab ───────────────────────────────────────────────────────────

  Widget _buildSummaryTab() {
    if (_movements.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inventory_2_outlined,
              color: AppColors.grey400,
              size: 36,
            ),
            SizedBox(height: 10),
            Text(
              'No stock logged yet',
              style: TextStyle(
                color: AppColors.grey500,
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Enter opening stock on the Count tab',
              style: TextStyle(color: AppColors.grey400, fontSize: 12),
            ),
          ],
        ),
      );
    }

    int totalSold = 0;
    for (final p in _products) {
      totalSold += _soldQty(p.id) ?? 0;
    }
    final withClosing = _movements.where((m) => m.closingStock != null).length;

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Row(
          children: [
            _StatCard('Logged', '${_movements.length}', AppColors.accent),
            const SizedBox(width: 10),
            _StatCard('Closing done', '$withClosing', AppColors.info),
            const SizedBox(width: 10),
            _StatCard('Units sold', '$totalSold', AppColors.success),
          ],
        ),
        const SizedBox(height: 16),
        ..._movements.map((m) {
          final product = _products
              .where((p) => p.id == m.productId)
              .firstOrNull;
          if (product == null) return const SizedBox.shrink();
          final closing = m.closingStock;
          final sold = closing != null
              ? ((m.openStock + m.refillQty) - closing).clamp(0, 99999)
              : null;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.grey200),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    product.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                _Badge('Open: ${m.openStock}', AppColors.grey600),
                if (m.refillQty > 0) ...[
                  const SizedBox(width: 5),
                  _Badge('+${m.refillQty} refill', AppColors.info),
                ],
                const SizedBox(width: 5),
                if (closing != null) ...[
                  _Badge('Close: $closing', AppColors.grey600),
                  const SizedBox(width: 5),
                  _Badge('Sold: $sold', AppColors.accent),
                ] else
                  _Badge('No closing', AppColors.grey400),
              ],
            ),
          );
        }),
      ],
    );
  }

  // ── Bottom bar ────────────────────────────────────────────────────────────

  Widget _buildBottomBar() => Container(
    decoration: const BoxDecoration(
      color: AppColors.surface,
      border: Border(top: BorderSide(color: AppColors.grey200)),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                const Icon(
                  Icons.error_outline,
                  color: AppColors.error,
                  size: 14,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _error!,
                    style: const TextStyle(
                      color: AppColors.error,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () =>
                    context.go('/shift/active', extra: widget.shiftId),
                child: const Text('Back to Sales'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _saving ? null : _saveAll,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save_outlined, size: 17),
                label: Text(_saving ? 'Saving...' : 'Save All'),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// Sub-widgets
// ═══════════════════════════════════════════════════════════════════════════

class _StockRow extends StatelessWidget {
  final ProductsTableData product;
  final StockMovementsTableData? movement;
  final int txnSold;
  final TextEditingController openCtrl, refillCtrl, closingCtrl;
  final VoidCallback onSave;
  final bool saving;
  const _StockRow({
    required this.product,
    required this.movement,
    required this.openCtrl,
    required this.refillCtrl,
    required this.closingCtrl,
    required this.onSave,
    required this.saving,
    required this.txnSold,
  });

  @override
  Widget build(BuildContext context) {
    final hasOpen = openCtrl.text.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: movement != null
              ? AppColors.accent.withValues(alpha: 0.35)
              : AppColors.grey200,
          width: movement != null ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  product.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Text(
                '${product.bizPrice} RWF',
                style: const TextStyle(color: AppColors.grey500, fontSize: 12),
              ),
              if (movement != null) ...[
                const SizedBox(width: 8),
                const Icon(
                  Icons.check_circle,
                  color: AppColors.success,
                  size: 14,
                ),
              ],
            ],
          ),

          if (txnSold > 0) ...[
            const SizedBox(height: 4),
            _SoldBadge('$txnSold sold via txns'),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              // Opening
              Expanded(
                child: _QtyField(
                  label: 'Opening',
                  ctrl: openCtrl,
                  color: AppColors.grey700,
                ),
              ),
              const SizedBox(width: 8),
              // Refill
              Expanded(
                child: _QtyField(
                  label: 'Refill',
                  ctrl: refillCtrl,
                  color: AppColors.info,
                  enabled: hasOpen,
                ),
              ),
              const SizedBox(width: 8),
              // Closing
              Expanded(
                child: _QtyField(
                  label: 'Closing',
                  ctrl: closingCtrl,
                  color: AppColors.grey500,
                  enabled: hasOpen,
                ),
              ),
              const SizedBox(width: 8),
              // Save
              SizedBox(
                height: 46,
                child: ElevatedButton(
                  onPressed: saving ? null : onSave,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    backgroundColor: movement != null
                        ? AppColors.grey700
                        : AppColors.accent,
                  ),
                  child: Text(
                    movement != null ? 'Upd' : 'Save',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QtyField extends StatelessWidget {
  final String label;
  final TextEditingController ctrl;
  final Color color;
  final bool enabled;
  const _QtyField({
    required this.label,
    required this.ctrl,
    required this.color,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) => TextField(
    controller: ctrl,
    enabled: enabled,
    keyboardType: TextInputType.number,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: color),
    decoration: InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: color, fontSize: 11),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.grey200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: color, width: 2),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.grey100),
      ),
      filled: true,
      fillColor: enabled ? AppColors.surfaceAlt : AppColors.grey50,
    ),
  );
}

class _StatCard extends StatelessWidget {
  final String label, value;
  final Color color;
  const _StatCard(this.label, this.value, this.color);
  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 10,
            ),
          ),
        ],
      ),
    ),
  );
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color;
  const _Badge(this.text, this.color);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Text(
      text,
      style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600),
    ),
  );
}

class _SoldBadge extends StatelessWidget {
  final String text;
  const _SoldBadge(this.text);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: AppColors.accent.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Text(
      text,
      style: const TextStyle(
        color: AppColors.accent,
        fontSize: 10,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}
