import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/database/app_database.dart';
import '../../core/database/database_provider.dart';
import '../../shared/theme/app_colors.dart';

class ClientsScreen extends ConsumerStatefulWidget {
  const ClientsScreen({super.key});

  @override
  ConsumerState<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends ConsumerState<ClientsScreen> {
  String _filter = 'all';

  @override
  Widget build(BuildContext context) {
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
                    'Clients',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Filter chips
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  _FilterChip(label: 'All', value: 'all', selected: _filter == 'all', onTap: () => setState(() => _filter = 'all')),
                  const SizedBox(width: 8),
                  _FilterChip(label: 'Normal', value: 'normal', selected: _filter == 'normal', onTap: () => setState(() => _filter = 'normal')),
                  const SizedBox(width: 8),
                  _FilterChip(label: 'Staff', value: 'staff', selected: _filter == 'staff', onTap: () => setState(() => _filter = 'staff')),
                  const SizedBox(width: 8),
                  _FilterChip(label: 'Company', value: 'company', selected: _filter == 'company', onTap: () => setState(() => _filter = 'company')),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Container(
                decoration: const BoxDecoration(
                  color: AppColors.bg,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: StreamBuilder<List<ClientsTableData>>(
                  stream: db.clientsDao.watchAllClients(),
                  builder: (context, snap) {
                    if (!snap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final all = snap.data!;
                    final clients = _filter == 'all'
                        ? all
                        : all.where((c) => c.clientType == _filter).toList();
                    if (clients.isEmpty) {
                      return Center(
                        child: Text(
                          all.isEmpty
                              ? 'No clients yet.\nTap + to add one.'
                              : 'No ${_filter} clients.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 15,
                          ),
                        ),
                      );
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
                      itemCount: clients.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => _ClientTile(client: clients[i]),
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
          'Add Client',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  static void _showSheet(BuildContext context, {ClientsTableData? client}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ClientSheet(client: client),
    );
  }
}

// ── Filter chip ───────────────────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  final String label;
  final String value;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip({required this.label, required this.value, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.accent : Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

// ── Tile ─────────────────────────────────────────────────────────────────────

class _ClientTile extends ConsumerWidget {
  final ClientsTableData client;
  const _ClientTile({required this.client});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = client.active;
    return GestureDetector(
      onTap: () => _ClientsScreenState._showSheet(context, client: client),
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
                radius: 18,
                backgroundColor: _typeColor(client.clientType).withValues(alpha: 0.12),
                child: Text(
                  client.name[0].toUpperCase(),
                  style: TextStyle(
                    color: _typeColor(client.clientType),
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      client.name,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: active ? AppColors.textPrimary : AppColors.textSecondary,
                        decoration: active ? null : TextDecoration.lineThrough,
                      ),
                    ),
                    Row(
                      children: [
                        _TypeBadge(client.clientType),
                        if (client.company != null && client.company!.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Text(
                            client.company!,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Switch(
                value: active,
                activeThumbColor: AppColors.accent,
                activeTrackColor: AppColors.accent.withValues(alpha: 0.4),
                onChanged: (_) {
                  final db = ref.read(databaseProvider);
                  db.clientsDao.updateClient(
                    ClientsTableCompanion(
                      id: Value(client.id),
                      name: Value(client.name),
                      clientType: Value(client.clientType),
                      company: Value(client.company),
                      active: Value(!active),
                      createdAt: Value(client.createdAt),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'staff':   return AppColors.info;
      case 'company': return AppColors.success;
      default:        return AppColors.accent;
    }
  }
}

class _TypeBadge extends StatelessWidget {
  final String type;
  const _TypeBadge(this.type);

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (type) {
      case 'staff':   color = AppColors.info; break;
      case 'company': color = AppColors.success; break;
      default:        color = AppColors.accent;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        type,
        style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

// ── Add / Edit Sheet ──────────────────────────────────────────────────────────

class _ClientSheet extends ConsumerStatefulWidget {
  final ClientsTableData? client;
  const _ClientSheet({this.client});

  @override
  ConsumerState<_ClientSheet> createState() => _ClientSheetState();
}

class _ClientSheetState extends ConsumerState<_ClientSheet> {
  late final TextEditingController _name;
  late final TextEditingController _company;
  late String _type;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name    = TextEditingController(text: widget.client?.name ?? '');
    _company = TextEditingController(text: widget.client?.company ?? '');
    _type    = widget.client?.clientType ?? 'normal';
  }

  @override
  void dispose() {
    _name.dispose();
    _company.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    setState(() => _saving = true);
    final db      = ref.read(databaseProvider);
    final company = _type == 'company' ? _company.text.trim() : null;
    if (widget.client == null) {
      await db.clientsDao.insertClient(
        ClientsTableCompanion.insert(
          name: name,
          clientType: Value(_type),
          company: Value(company),
          active: const Value(true),
        ),
      );
    } else {
      final c = widget.client!;
      await db.clientsDao.updateClient(
        ClientsTableCompanion(
          id: Value(c.id),
          name: Value(name),
          clientType: Value(_type),
          company: Value(company),
          active: Value(c.active),
          createdAt: Value(c.createdAt),
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
              widget.client == null ? 'Add Client' : 'Edit Client',
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
              autofocus: widget.client == null,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Client Type'),
              items: const [
                DropdownMenuItem(value: 'normal',  child: Text('Normal')),
                DropdownMenuItem(value: 'staff',   child: Text('Staff')),
                DropdownMenuItem(value: 'company', child: Text('Company')),
              ],
              onChanged: (v) => setState(() => _type = v ?? 'normal'),
            ),
            if (_type == 'company') ...[
              const SizedBox(height: 12),
              TextField(
                controller: _company,
                decoration: const InputDecoration(
                  labelText: 'Company Name',
                  hintText: 'e.g. TELECOM, GIZ',
                ),
                textCapitalization: TextCapitalization.words,
              ),
            ],
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
                    : Text(widget.client == null ? 'Add Client' : 'Save Changes'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
