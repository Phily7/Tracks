import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/database/app_database.dart';
import '../../core/database/database_provider.dart';
import '../../shared/theme/app_colors.dart';
//import 'package:dropdown_search/dropdown_search.dart';

class SaleEntryScreen extends ConsumerStatefulWidget {
  final String shiftId;
  const SaleEntryScreen({super.key, required this.shiftId});

  @override
  ConsumerState<SaleEntryScreen> createState() => _SaleEntryScreenState();
}

class _SaleEntryScreenState extends ConsumerState<SaleEntryScreen> {
  // ── Data ─────────────────────────────────────────────────────────────────
  List<ProductsTableData> _products = [];
  List<ClientsTableData> _clients = [];
  ShiftsTableData? _shift;
  StaffTableData? _staff;
  List<StaffTableData> _staffList = [];
  List<TransactionsTableData> _transactions = [];

  // ── Form state ────────────────────────────────────────────────────────────
  ProductsTableData? _selectedProduct;
  ClientsTableData? _selectedClient;
  StaffTableData? _selectedStaffClient;
  String _clientType = 'normal'; // 'normal' | 'staff' | 'company'
  int _quantity = 1;
  String _paymentMethod = 'cash';
  String _entryMode = 'product_first';

  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  // ── Initialisation ────────────────────────────────────────────────────────

  Future<void> _init() async {
    final db = ref.read(databaseProvider);

    // Load shift
    _shift = await db.shiftsDao.getShiftById(widget.shiftId);

    // Load staff name for header
    if (_shift?.staffId != null) {
      final allStaff = await db.staffDao.getActiveStaff();
      final match = allStaff.where((s) => s.id == _shift!.staffId);
      if (match.isNotEmpty) _staff = match.first;
      _staffList = allStaff;
    }

    // Products – seed if empty
    var products = await db.productsDao.getActiveProducts();
    if (products.isEmpty) {
      await _seedProducts(db);
      products = await db.productsDao.getActiveProducts();
    }

    // Clients – seed if empty
    var clients = await db.clientsDao.getActiveClients();
    if (clients.isEmpty) {
      await _seedClients(db);
      clients = await db.clientsDao.getActiveClients();
    }

    // Transactions (initial load + live stream)
    final txns = await db.transactionsDao.getTransactionsByShift(
      widget.shiftId,
    );

    if (mounted) {
      setState(() {
        _products = products;
        _clients = clients;
        _transactions = txns;
        _loading = false;
      });
    }

    db.transactionsDao.watchTransactionsByShift(widget.shiftId).listen((list) {
      if (mounted) setState(() => _transactions = list);
    });
  }

  Future<void> _seedProducts(AppDatabase db) async {
    const items = [
      ('Soda', 700, 700, 700),
      ('Inyange Juice', 1000, 1000, 1000),
      ('Water-small', 800, 700, 700),
      ('Plastic Soda', 1300, 1200, 1300),
      ('Vanilla Cake', 500, 500, 500),
      ('Meat Balls', 400, 400, 400),
      ('Chapati', 300, 300, 300),
      ('Banana Cake', 500, 500, 500),
      ('Veg Samosa', 400, 400, 400),
      ('Meat Samosa', 400, 400, 400),
      ('Rolex', 1500, 1500, 1500),
      ('Crepes', 400, 400, 400),
      ('Eggs', 300, 300, 300),
      ('Bread', 500, 500, 500),
      ('Yoghuts', 1000, 1000, 1000),
      ('Donuts', 500, 500, 500),
      ('Croissant', 800, 800, 800),
      ('Small Pizza', 500, 500, 500),
      ('Ice cups (Take away)', 500, 500, 500),
      ('Coffee Cup (Take away)', 500, 500, 500),
    ];
    for (final (name, biz, staff, telecom) in items) {
      await db.productsDao.insertProduct(
        ProductsTableCompanion.insert(
          name: name,
          bizPrice: Value(biz),
          staffPrice: Value(staff),
          telecomPrice: Value(telecom),
        ),
      );
    }
  }

  Future<void> _seedClients(AppDatabase db) async {
    const companies = [
      ('TELECOM', 'company', 'TELECOM'),
      ('GIZ', 'company', 'GIZ'),
      ('ICT Chamber', 'company', 'ICT Chamber'),
    ];
    for (final (name, type, company) in companies) {
      await db.clientsDao.insertClient(
        ClientsTableCompanion.insert(
          name: name,
          clientType: Value(type),
          company: Value(company),
        ),
      );
    }

    //Staff clients (consume at staff prices, often on debt)
    const staffClients = [
      'Alex',
      'Beula',
      'Lambert',
      'Kessy',
      'Hocklin',
      'Fred',
      'Emile',
      'Manzi',
      'Cedric',
      'Gisele',
      'Gael',
      'Kanyana',
      'Winnie',
      'Yeetah',
      'Seleman',
      'Danny Bizimana',
      'Heritier',
      'Christian Hezagira',
      'Mounira M.',
      'Albert',
      'Josue',
      'Charbel',
      'Philemon',
      'Irene',
      'Kawaida',
      'Patrick Mugisha',
      'Savio',
      'Husna',
      'Wivine',
      'Christophe',
      'Phinah',
      'Christella',
      'Chouchou',
      'Magnifique Ishimwe',
      'Frank',
      'Steven Mugabo',
      'Perfect',
      'Olivier Ntezi',
      'Jacques Rutalindwa',
      'Ziadi',
      'Gift',
      'Issa',
      'Shelda',
      'Samantha',
      'Magnific Barista',
      'Judith',
      'Magalie',
      'Robert',
      'Cele',
      'Kabodi',
      'Tam Tam',
      'Shumbusho',
    ];
    for (final name in staffClients) {
      await db.clientsDao.insertClient(
        ClientsTableCompanion.insert(
          name: name,
          clientType: const Value('staff'),
        ),
      );
    }
  }

  // ── Computed ──────────────────────────────────────────────────────────────

  int get _unitPrice {
    if (_selectedProduct == null) return 0;
    return switch (_clientType) {
      'staff' => _selectedProduct!.staffPrice,
      'company' => _selectedProduct!.telecomPrice,
      _ => _selectedProduct!.bizPrice,
    };
  }

  int get _totalAmount => _unitPrice * _quantity;

  int get _totalRevenue => _transactions.fold(0, (s, t) => s + t.totalAmount);
  int get _cashRevenue => _transactions
      .where((t) => t.paymentMethod == 'cash')
      .fold(0, (s, t) => s + t.totalAmount);
  int get _momoRevenue => _transactions
      .where((t) => t.paymentMethod == 'momo')
      .fold(0, (s, t) => s + t.totalAmount);

  int get _debtRevenue => _transactions
      .where((t) => t.paymentMethod == 'debt')
      .fold(0, (s, t) => s + t.totalAmount);

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _saveSale() async {
    if (_selectedProduct == null) {
      setState(() => _error = 'Please select a product');
      return;
    }
    if (_clientType == 'company' && _selectedClient == null) {
      setState(() => _error = 'Please select a company');
      return;
    }
    // final clientId = _selectedClient?.id ?? _selectedStaffClient?.id; // for now, we are using a single _selectedClient for both staff and company clients, so we can simplify this
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final db = ref.read(databaseProvider);
      await db.transactionsDao.insertTransaction(
        TransactionsTableCompanion.insert(
          shiftId: widget.shiftId,
          productId: _selectedProduct!.id,
          unitPrice: _unitPrice,
          totalAmount: _totalAmount,
          clientId: Value(_selectedClient?.id ?? _selectedStaffClient?.id),
          clientType: Value(_clientType),
          paymentMethod: Value(_paymentMethod),
          quantity: Value(_quantity),
          entryMode: Value(_entryMode),
        ),
      );
      setState(() {
        _selectedProduct = null;
        _selectedClient = null;
        _clientType = 'normal';
        _quantity = 1;
        _paymentMethod = 'cash';
        _saving = false;
      });
    } catch (e) {
      setState(() {
        _saving = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _deleteTransaction(String id) async {
    final db = ref.read(databaseProvider);
    await db.transactionsDao.deleteTransaction(id);
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
            _buildStatsBar(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildModeToggle(),
                    const SizedBox(height: 16),
                    _buildEntryCard(),
                    const SizedBox(height: 24),
                    _buildTransactionLog(),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
            _buildBottomNav(),
          ],
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Container(
      color: AppColors.primary,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.accent,
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(Icons.restaurant, color: Colors.white, size: 18),
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
          if (_staff != null) ...[
            const Icon(Icons.person_outline, color: Colors.white54, size: 15),
            const SizedBox(width: 4),
            Text(
              _staff!.name,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Stats bar ─────────────────────────────────────────────────────────────

  Widget _buildStatsBar() {
    return Container(
      color: AppColors.primaryLight,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          _Stat(
            label: 'Total',
            value: _fmtK(_totalRevenue),
            valueColor: Colors.white,
            labelColor: Colors.white60,
            valueFontSize: 17,
          ),
          const SizedBox(width: 20),
          _Stat(
            label: 'Cash',
            value: _fmtK(_cashRevenue),
            valueColor: AppColors.cash,
            labelColor: Colors.white54,
          ),
          const SizedBox(width: 16),
          _Stat(
            label: 'MoMo',
            value: _fmtK(_momoRevenue),
            valueColor: AppColors.momo,
            labelColor: Colors.white54,
          ),

          const SizedBox(width: 16),
          _Stat(
            label: 'Debt',
            value: _fmtK(_debtRevenue),
            valueColor: AppColors.debt,
            labelColor: Colors.white54,
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => context.push('/dashboard'),
            child: Row(
              children: [
                Text(
                  '${_transactions.length} sale${_transactions.length == 1 ? '' : 'S'}',
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
                const SizedBox(width: 6),
                const Icon(
                  Icons.analytics_outlined,
                  color: AppColors.accent,
                  size: 16,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Mode toggle ───────────────────────────────────────────────────────────

  Widget _buildModeToggle() {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: const Color(0xFFE9ECEF)),
      ),
      child: Row(
        children: [
          _ModeTab(
            label: 'Product First',
            icon: Icons.fastfood_outlined,
            active: _entryMode == 'product_first',
            onTap: () => setState(() => _entryMode = 'product_first'),
          ),
          _ModeTab(
            label: 'Client First',
            icon: Icons.person_search_outlined,
            active: _entryMode == 'client_first',
            onTap: () => setState(() => _entryMode = 'client_first'),
          ),
        ],
      ),
    );
  }

  // ── Entry card ────────────────────────────────────────────────────────────

  Widget _buildEntryCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE9ECEF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Product ──
          _FieldLabel('Product'),
          const SizedBox(height: 8),
          DropdownButtonFormField<ProductsTableData>(
            initialValue: _selectedProduct,
            isExpanded: true,
            decoration: const InputDecoration(
              hintText: 'Select a product',
              prefixIcon: Icon(Icons.fastfood_outlined, size: 18),
            ),
            items: _products
                .map(
                  (p) => DropdownMenuItem(
                    value: p,
                    child: Text(
                      '${p.name}  ·  ${p.bizPrice} RWF',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: (p) => setState(() {
              _selectedProduct = p;
              _error = null;
            }),
          ),
          const SizedBox(height: 16),

          // ── Quantity ──
          _FieldLabel('Quantity'),
          const SizedBox(height: 8),
          _QuantityRow(
            value: _quantity,
            onChanged: (v) => setState(() => _quantity = v),
          ),
          const SizedBox(height: 16),

          // ── Client type ──
          // ── Client type ──
          _FieldLabel('Client Type'),
          const SizedBox(height: 8),
          _TypeRow(
            value: _clientType,
            onChanged: (v) => setState(() {
              _clientType = v;
              if (v != 'company') _selectedClient = null;
              if (v != 'staff') _selectedStaffClient = null;
            }),
          ),

          // Company dropdown
          if (_clientType == 'company') ...[
            const SizedBox(height: 10),
            _SearchableClientDropdown(
              hint: 'Select company...',
              icon: Icons.business_outlined,
              clients: _clients
                  .where((c) => c.clientType == 'company')
                  .toList(),
              selected: _selectedClient,
              onChanged: (c) => setState(() => _selectedClient = c),
            ),
          ],

          // Staff dropdown
          if (_clientType == 'staff') ...[
            const SizedBox(height: 10),
            _SearchableClientDropdown(
              hint: 'Search staff member...',
              icon: Icons.badge_outlined,
              clients: _clients.where((c) => c.clientType == 'staff').toList(),
              selected: _selectedClient,
              onChanged: (c) => setState(() => _selectedClient = c),
            ),
          ],

          // ── Payment ──
          _FieldLabel('Payment Method'),
          const SizedBox(height: 8),
          _PaymentRow(
            value: _paymentMethod,
            onChanged: (v) => setState(() => _paymentMethod = v),
          ),
          const SizedBox(height: 16),

          // ── Price preview ──
          if (_selectedProduct != null)
            _PricePreview(
              unitPrice: _unitPrice,
              quantity: _quantity,
              total: _totalAmount,
            ),

          // ── Error ──
          if (_error != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: AppColors.error,
                    size: 15,
                  ),
                  const SizedBox(width: 8),
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
          ],
          const SizedBox(height: 16),

          // ── Save button ──
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _saving ? null : _saveSale,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.add_circle_outline, size: 20),
              label: Text(_saving ? 'Saving...' : 'Record Sale'),
            ),
          ),
        ],
      ),
    );
  }

  // ── Transaction log ───────────────────────────────────────────────────────

  Widget _buildTransactionLog() {
    if (_transactions.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 28),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE9ECEF)),
        ),
        child: const Column(
          children: [
            Icon(
              Icons.receipt_long_outlined,
              color: AppColors.textHint,
              size: 30,
            ),
            SizedBox(height: 8),
            Text(
              'No sales yet',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: 2),
            Text(
              'Record your first sale above',
              style: TextStyle(color: AppColors.textHint, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              "Today's Sales",
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: AppColors.textPrimary,
              ),
            ),
            const Spacer(),
            Text(
              '${_transactions.length} items',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ..._transactions.map((txn) {
          final productName =
              _products
                  .where((p) => p.id == txn.productId)
                  .map((p) => p.name)
                  .firstOrNull ??
              'Unknown';
          return _TxnRow(
            txn: txn,
            productName: productName,
            onDelete: () => _showDeleteDialog(txn.id, productName),
          );
        }),
      ],
    );
  }

  void _showDeleteDialog(String id, String productName) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Sale?'),
        content: Text('Remove "$productName" from this shift?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteTransaction(id);
            },
            child: const Text(
              'Delete',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }

  // ── Bottom nav ────────────────────────────────────────────────────────────

  Widget _buildBottomNav() {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: Color(0xFFE9ECEF))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          _NavBtn(
            icon: Icons.inventory_2_outlined,
            label: 'Stock',
            onTap: () => context.push('/stock', extra: widget.shiftId),
          ),
          const Spacer(),
          SizedBox(
            height: 44,
            child: ElevatedButton.icon(
              onPressed: () =>
                  context.push('/shift/end', extra: widget.shiftId),
              icon: const Icon(Icons.lock_outline, size: 17),
              label: const Text('End Shift'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                padding: const EdgeInsets.symmetric(horizontal: 20),
              ),
            ),
          ),
          const Spacer(),
          _NavBtn(
            icon: Icons.file_download_outlined,
            label: 'Export',
            onTap: () => context.push('/export'),
          ),
        ],
      ),
    );
  }

  // ── Formatters ────────────────────────────────────────────────────────────

  String _fmtK(int amount) {
    if (amount == 0) return '0';
    if (amount >= 1000) {
      final k = amount / 1000;
      return '${k % 1 == 0 ? k.toInt() : k.toStringAsFixed(1)}k';
    }
    return amount.toString();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Sub-widgets
// ═══════════════════════════════════════════════════════════════════════════

class _Stat extends StatelessWidget {
  final String label, value;
  final Color valueColor, labelColor;
  final double valueFontSize;
  const _Stat({
    required this.label,
    required this.value,
    required this.valueColor,
    required this.labelColor,
    this.valueFontSize = 14,
  });
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: TextStyle(color: labelColor, fontSize: 10)),
      Text(
        value,
        style: TextStyle(
          color: valueColor,
          fontWeight: FontWeight.w800,
          fontSize: valueFontSize,
        ),
      ),
    ],
  );
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);
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

class _ModeTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  const _ModeTab({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: active ? AppColors.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 15,
              color: active ? Colors.white : AppColors.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: active ? Colors.white : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _QuantityRow extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  const _QuantityRow({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _QtyBtn(
          icon: Icons.remove,
          enabled: value > 1,
          onTap: () => onChanged(value - 1),
        ),
        const SizedBox(width: 14),
        Text(
          '$value',
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(width: 14),
        _QtyBtn(
          icon: Icons.add,
          enabled: true,
          onTap: () => onChanged(value + 1),
        ),
        const Spacer(),
        for (final q in [5, 10, 20])
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: GestureDetector(
              onTap: () => onChanged(q),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: value == q
                      ? AppColors.accent.withValues(alpha: 0.1)
                      : AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: value == q
                        ? AppColors.accent
                        : const Color(0xFFE9ECEF),
                    width: value == q ? 1.5 : 1,
                  ),
                ),
                child: Text(
                  '$q',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: value == q
                        ? AppColors.accent
                        : AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _QtyBtn extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  const _QtyBtn({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: enabled ? onTap : null,
    child: Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE9ECEF)),
      ),
      child: Icon(
        icon,
        size: 16,
        color: enabled ? AppColors.textPrimary : AppColors.textHint,
      ),
    ),
  );
}

class _TypeRow extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const _TypeRow({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      _TypeChip(
        label: 'Normal',
        id: 'normal',
        current: value,
        onTap: () => onChanged('normal'),
      ),
      const SizedBox(width: 8),
      _TypeChip(
        label: 'Staff',
        id: 'staff',
        current: value,
        onTap: () => onChanged('staff'),
      ),
      const SizedBox(width: 8),
      _TypeChip(
        label: 'Company',
        id: 'company',
        current: value,
        onTap: () => onChanged('company'),
      ),
    ],
  );
}

class _TypeChip extends StatelessWidget {
  final String label, id, current;
  final VoidCallback onTap;
  const _TypeChip({
    required this.label,
    required this.id,
    required this.current,
    required this.onTap,
  });
  bool get active => id == current;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: active ? AppColors.accent : AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: active ? AppColors.accent : const Color(0xFFE9ECEF),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: active ? Colors.white : AppColors.textSecondary,
        ),
      ),
    ),
  );
}

class _PaymentRow extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const _PaymentRow({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      _PayChip(
        id: 'cash',
        label: 'Cash',
        icon: Icons.payments_outlined,
        color: AppColors.cash,
        current: value,
        onTap: () => onChanged('cash'),
      ),
      _PayChip(
        id: 'momo',
        label: 'MoMo',
        icon: Icons.phone_android_outlined,
        color: AppColors.momo,
        current: value,
        onTap: () => onChanged('momo'),
      ),
      _PayChip(
        id: 'visa',
        label: 'Visa',
        icon: Icons.credit_card_outlined,
        color: AppColors.visa,
        current: value,
        onTap: () => onChanged('visa'),
      ),
      _PayChip(
        id: 'debt',
        label: 'Debt',
        icon: Icons.receipt_outlined,
        color: AppColors.debt,
        current: value,
        onTap: () => onChanged('debt'),
      ),
    ],
  );
}

class _PayChip extends StatelessWidget {
  final String id, label, current;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _PayChip({
    required this.id,
    required this.label,
    required this.current,
    required this.icon,
    required this.color,
    required this.onTap,
  });
  bool get active => id == current;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: active ? color.withValues(alpha: 0.1) : AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: active ? color : const Color(0xFFE9ECEF),
          width: active ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: active ? color : AppColors.textSecondary),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: active ? color : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    ),
  );
}

class _PricePreview extends StatelessWidget {
  final int unitPrice, quantity, total;
  const _PricePreview({
    required this.unitPrice,
    required this.quantity,
    required this.total,
  });

  String _fmt(int v) {
    final s = v.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: AppColors.accent.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AppColors.accent.withValues(alpha: 0.18)),
    ),
    child: Row(
      children: [
        Text(
          '$unitPrice × $quantity =',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const Spacer(),
        Text(
          '${_fmt(total)} RWF',
          style: const TextStyle(
            color: AppColors.accent,
            fontWeight: FontWeight.w800,
            fontSize: 19,
          ),
        ),
      ],
    ),
  );
}

class _TxnRow extends StatelessWidget {
  final TransactionsTableData txn;
  final String productName;
  final VoidCallback onDelete;
  const _TxnRow({
    required this.txn,
    required this.productName,
    required this.onDelete,
  });

  Color get _payColor => switch (txn.paymentMethod) {
    'momo' => AppColors.momo,
    'visa' => AppColors.visa,
    _ => AppColors.cash,
  };

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFFE9ECEF)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                productName,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 3),
              Row(
                children: [
                  Text(
                    '${txn.quantity}× ${txn.unitPrice} RWF',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(width: 6),
                  _Badge(txn.paymentMethod.toUpperCase(), _payColor),
                  const SizedBox(width: 4),
                  _Badge(txn.clientType.toUpperCase(), AppColors.textSecondary),
                ],
              ),
            ],
          ),
        ),
        Text(
          '${txn.totalAmount} RWF',
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: onDelete,
          child: const Icon(
            Icons.delete_outline,
            color: AppColors.error,
            size: 18,
          ),
        ),
      ],
    ),
  );
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color;
  const _Badge(this.text, this.color);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      text,
      style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w700),
    ),
  );
}

class _NavBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _NavBtn({required this.icon, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: AppColors.textSecondary, size: 22),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    ),
  );
}

class _SearchableClientDropdown extends StatefulWidget {
  final String hint;
  final IconData icon;
  final List<ClientsTableData> clients;
  final ClientsTableData? selected;
  final ValueChanged<ClientsTableData?> onChanged;
  const _SearchableClientDropdown({
    required this.hint,
    required this.icon,
    required this.clients,
    required this.selected,
    required this.onChanged,
  });
  @override
  State<_SearchableClientDropdown> createState() =>
      _SearchableClientDropdownState();
}

class _SearchableClientDropdownState extends State<_SearchableClientDropdown> {
  final _searchCtrl = TextEditingController();
  List<ClientsTableData> _filtered = [];
  bool _open = false;
  final _layerLink = LayerLink();
  OverlayEntry? _overlay;

  @override
  void initState() {
    super.initState();
    _filtered = widget.clients;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _overlay?.remove();
    super.dispose();
  }

  void _filter(String q) {
    setState(() {
      _filtered = q.isEmpty
          ? widget.clients
          : widget.clients
                .where((c) => c.name.toLowerCase().contains(q.toLowerCase()))
                .toList();
    });
    _overlay?.markNeedsBuild();
  }

  void _toggle() {
    if (_open) {
      _close();
    } else {
      _openOverlay();
    }
  }

  void _openOverlay() {
    _overlay = OverlayEntry(builder: (_) => _buildOverlay());
    Overlay.of(context).insert(_overlay!);
    setState(() => _open = true);
  }

  void _close() {
    _overlay?.remove();
    _overlay = null;
    _searchCtrl.clear();
    _filtered = widget.clients;
    setState(() => _open = false);
  }

  void _select(ClientsTableData c) {
    widget.onChanged(c);
    _close();
  }

  Widget _buildOverlay() => Positioned(
    width: 300,
    child: CompositedTransformFollower(
      link: _layerLink,
      showWhenUnlinked: false,
      offset: const Offset(0, 48),
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          constraints: const BoxConstraints(maxHeight: 280),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.grey200),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: TextField(
                  controller: _searchCtrl,
                  autofocus: true,
                  onChanged: _filter,
                  decoration: InputDecoration(
                    hintText: 'Type to search...',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _filtered.length,
                  itemBuilder: (_, i) {
                    final c = _filtered[i];
                    final selected = c.id == widget.selected?.id;
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        widget.icon,
                        size: 16,
                        color: selected ? AppColors.accent : AppColors.grey500,
                      ),
                      title: Text(
                        c.name,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w400,
                          color: selected
                              ? AppColors.accent
                              : AppColors.textPrimary,
                        ),
                      ),
                      onTap: () => _select(c),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: GestureDetector(
        onTap: _toggle,
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _open ? AppColors.accent : AppColors.grey200,
              width: _open ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(widget.icon, size: 18, color: AppColors.grey500),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.selected?.name ?? widget.hint,
                  style: TextStyle(
                    color: widget.selected != null
                        ? AppColors.textPrimary
                        : AppColors.textHint,
                    fontSize: 14,
                  ),
                ),
              ),
              Icon(
                _open ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                color: AppColors.grey500,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
