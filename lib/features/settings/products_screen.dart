import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/database/app_database.dart';
import '../../core/database/database_provider.dart';
import '../../shared/theme/app_colors.dart';

class ProductsScreen extends ConsumerWidget {
  const ProductsScreen({super.key});

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
                    'Products',
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
                child: StreamBuilder<List<ProductsTableData>>(
                  stream: db.productsDao.watchAllProducts(),
                  builder: (context, snap) {
                    if (!snap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final products = snap.data!;
                    if (products.isEmpty) {
                      return const Center(
                        child: Text(
                          'No products yet.\nTap + to add one.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 15),
                        ),
                      );
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
                      itemCount: products.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => _ProductTile(product: products[i]),
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
          'Add Product',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  static void _showSheet(BuildContext context, {ProductsTableData? product}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ProductSheet(product: product),
    );
  }
}

// ── Tile ─────────────────────────────────────────────────────────────────────

class _ProductTile extends ConsumerWidget {
  final ProductsTableData product;
  const _ProductTile({required this.product});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = product.active;
    return GestureDetector(
      onTap: () => ProductsScreen._showSheet(context, product: product),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: active ? 1.0 : 0.5,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: active ? const Color(0xFFE9ECEF) : AppColors.grey300,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: active ? AppColors.textPrimary : AppColors.textSecondary,
                        decoration: active ? null : TextDecoration.lineThrough,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _PriceChip('Biz', product.bizPrice, AppColors.accent),
                        const SizedBox(width: 6),
                        _PriceChip('Staff', product.staffPrice, AppColors.info),
                        const SizedBox(width: 6),
                        _PriceChip('Tel', product.telecomPrice, AppColors.success),
                      ],
                    ),
                  ],
                ),
              ),
              Switch(
                value: active,
                activeThumbColor: AppColors.accent,
                activeTrackColor: AppColors.accent.withValues(alpha: 0.4),
                onChanged: (_) => ref.read(databaseProvider).productsDao.updateProduct(
                  ProductsTableCompanion(
                    id: Value(product.id),
                    name: Value(product.name),
                    bizPrice: Value(product.bizPrice),
                    staffPrice: Value(product.staffPrice),
                    telecomPrice: Value(product.telecomPrice),
                    active: Value(!active),
                    createdAt: Value(product.createdAt),
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

class _PriceChip extends StatelessWidget {
  final String label;
  final int price;
  final Color color;
  const _PriceChip(this.label, this.price, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$label: ${_fmt(price)}',
        style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }

  String _fmt(int n) {
    if (n == 0) return '—';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(n % 1000 == 0 ? 0 : 1)}k';
    return n.toString();
  }
}

// ── Add / Edit Sheet ──────────────────────────────────────────────────────────

class _ProductSheet extends ConsumerStatefulWidget {
  final ProductsTableData? product;
  const _ProductSheet({this.product});

  @override
  ConsumerState<_ProductSheet> createState() => _ProductSheetState();
}

class _ProductSheetState extends ConsumerState<_ProductSheet> {
  late final TextEditingController _name;
  late final TextEditingController _biz;
  late final TextEditingController _staff;
  late final TextEditingController _telecom;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _name    = TextEditingController(text: p?.name ?? '');
    _biz     = TextEditingController(text: p != null ? p.bizPrice.toString() : '0');
    _staff   = TextEditingController(text: p != null ? p.staffPrice.toString() : '0');
    _telecom = TextEditingController(text: p != null ? p.telecomPrice.toString() : '0');
  }

  @override
  void dispose() {
    _name.dispose();
    _biz.dispose();
    _staff.dispose();
    _telecom.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    setState(() => _saving = true);
    final db  = ref.read(databaseProvider);
    final biz     = int.tryParse(_biz.text) ?? 0;
    final staff   = int.tryParse(_staff.text) ?? 0;
    final telecom = int.tryParse(_telecom.text) ?? 0;
    if (widget.product == null) {
      await db.productsDao.insertProduct(
        ProductsTableCompanion.insert(
          name: name,
          bizPrice: Value(biz),
          staffPrice: Value(staff),
          telecomPrice: Value(telecom),
        ),
      );
    } else {
      final p = widget.product!;
      await db.productsDao.updateProduct(
        ProductsTableCompanion(
          id: Value(p.id),
          name: Value(name),
          bizPrice: Value(biz),
          staffPrice: Value(staff),
          telecomPrice: Value(telecom),
          active: Value(p.active),
          createdAt: Value(p.createdAt),
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
              widget.product == null ? 'Add Product' : 'Edit Product',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Product Name'),
              textCapitalization: TextCapitalization.words,
              autofocus: widget.product == null,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _PriceField(
                    label: 'Biz Price',
                    controller: _biz,
                    color: AppColors.accent,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _PriceField(
                    label: 'Staff Price',
                    controller: _staff,
                    color: AppColors.info,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _PriceField(
                    label: 'Telecom',
                    controller: _telecom,
                    color: AppColors.success,
                  ),
                ),
              ],
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
                    : Text(
                        widget.product == null ? 'Add Product' : 'Save Changes',
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PriceField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final Color color;
  const _PriceField({required this.label, required this.controller, required this.color});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: color, fontSize: 12),
        suffixText: 'RWF',
        suffixStyle: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}
