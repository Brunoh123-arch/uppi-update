import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

class DriversManagementScreen extends StatefulWidget {
  const DriversManagementScreen({super.key});

  @override
  State<DriversManagementScreen> createState() =>
      _DriversManagementScreenState();
}

class _DriversManagementScreenState extends State<DriversManagementScreen> {
  String _searchQuery = '';
  String _statusFilter = 'Todos';
  final List<Map<String, dynamic>> _drivers = [];
  int _page = 0;
  bool _hasMore = true;
  bool _isLoading = false;
  final ScrollController _scrollController = ScrollController();
  Timer? _searchDebounce;

  final List<String> _statusOptions = [
    'Todos',
    'online',
    'active',
    'pendingApproval',
    'blocked',
  ];

  String _statusOptionLabel(String s) {
    switch (s) {
      case 'online':
        return 'Online';
      case 'active':
        return 'Offline';
      case 'pendingApproval':
        return 'Pendente';
      case 'blocked':
        return 'Bloqueado';
      default:
        return 'Todos';
    }
  }

  Color _statusOptionColor(String s) {
    switch (s) {
      case 'online':
        return Colors.greenAccent;
      case 'active':
        return Colors.blueGrey;
      case 'pendingApproval':
        return Colors.orangeAccent;
      case 'blocked':
        return Colors.redAccent;
      default:
        return Colors.white54;
    }
  }

  RealtimeChannel? _profilesChannel;

  @override
  void initState() {
    super.initState();
    _loadMoreDrivers(reset: true);
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
        _loadMoreDrivers();
      }
    });
    _startRealtimeListener();
  }

  void _startRealtimeListener() {
    _profilesChannel = Supabase.instance.client
        .channel('drivers_realtime')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'profiles',
          callback: (payload) {
            final newRecord = payload.newRecord;
            final oldRecord = payload.oldRecord;
            final eventType = payload.eventType;

            if (!mounted) return;

            final record = eventType == PostgresChangeEvent.delete ? oldRecord : newRecord;
            if (record['role'] != 'driver') return;

            setState(() {
              if (eventType == PostgresChangeEvent.insert) {
                if (_matchesFilters(newRecord)) {
                  final exists = _drivers.any((d) => d['id'] == newRecord['id']);
                  if (!exists) {
                    _drivers.insert(0, newRecord);
                  }
                }
              } else if (eventType == PostgresChangeEvent.update) {
                final index = _drivers.indexWhere((d) => d['id'] == newRecord['id']);
                if (index != -1) {
                  if (_matchesFilters(newRecord)) {
                    _drivers[index] = newRecord;
                  } else {
                    _drivers.removeAt(index);
                  }
                } else if (_matchesFilters(newRecord)) {
                  _drivers.insert(0, newRecord);
                }
              } else if (eventType == PostgresChangeEvent.delete) {
                _drivers.removeWhere((d) => d['id'] == oldRecord['id']);
              }
            });
          },
        )
        .subscribe();
  }

  bool _matchesFilters(Map<String, dynamic> record) {
    if (_searchQuery.isNotEmpty) {
      final name = (record['full_name'] ?? '').toString().toLowerCase();
      final phone = (record['phone_number'] ?? '').toString().toLowerCase();
      final email = (record['email'] ?? '').toString().toLowerCase();
      final q = _searchQuery.toLowerCase();
      if (!name.contains(q) && !phone.contains(q) && !email.contains(q)) {
        return false;
      }
    }

    if (_statusFilter != 'Todos') {
      final status = record['status'] as String? ?? 'offline';
      final isApproved = record['is_approved'] == true;

      if (_statusFilter == 'online') {
        if (!isApproved || (status != 'online' && status != 'in_progress')) {
          return false;
        }
      } else if (_statusFilter == 'active') {
        if (!isApproved || (status != 'active' && status != 'offline')) {
          return false;
        }
      } else if (_statusFilter == 'pendingApproval') {
        if (isApproved || status == 'blocked') {
          return false;
        }
      } else if (_statusFilter == 'blocked') {
        if (status != 'blocked') {
          return false;
        }
      }
    }

    return true;
  }

  @override
  void dispose() {
    _profilesChannel?.unsubscribe();
    _scrollController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _loadMoreDrivers({bool reset = false}) async {
    if (_isLoading) return;
    if (reset) {
      _page = 0;
      _hasMore = true;
      _drivers.clear();
    }
    if (!_hasMore) return;

    setState(() => _isLoading = true);

    try {
      const pageSize = 50;
      final from = _page * pageSize;
      final to = from + pageSize - 1;

      var query = Supabase.instance.client
          .from('profiles')
          .select()
          .eq('role', 'driver');

      if (_statusFilter != 'Todos') {
        if (_statusFilter == 'online') {
          query = query.eq('is_approved', true).inFilter('status', ['online', 'in_progress']);
        } else if (_statusFilter == 'active') {
          query = query.eq('is_approved', true).inFilter('status', ['active', 'offline']);
        } else if (_statusFilter == 'pendingApproval') {
          query = query.eq('is_approved', false).neq('status', 'blocked');
        } else if (_statusFilter == 'blocked') {
          query = query.eq('status', 'blocked');
        }
      }

      if (_searchQuery.isNotEmpty) {
        query = query.or('full_name.ilike.%$_searchQuery%,phone_number.ilike.%$_searchQuery%,email.ilike.%$_searchQuery%');
      }

      final data = await query
          .order('created_at', ascending: false)
          .range(from, to);

      if (mounted) {
        setState(() {
          _drivers.addAll(List<Map<String, dynamic>>.from(data));
          _page++;
          _hasMore = data.length == pageSize;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao buscar motoristas: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _onSearchChanged(String query) {
    if (_searchDebounce?.isActive ?? false) _searchDebounce!.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 600), () {
      _searchQuery = query.trim();
      _loadMoreDrivers(reset: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Container(
          height: 80,
          padding: const EdgeInsets.symmetric(horizontal: 32),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: const Border(bottom: BorderSide(color: Colors.white10)),
          ),
          child: Row(
            children: [
              Text(
                'Gestão de Motoristas',
                style: GoogleFonts.outfit(
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 32),
              // Status filter chips
              ..._statusOptions.map((s) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(_statusOptionLabel(s)),
                      selected: _statusFilter == s,
                      selectedColor: _statusOptionColor(s).withValues(alpha: 0.3),
                      labelStyle: TextStyle(
                        color: _statusFilter == s
                            ? _statusOptionColor(s)
                            : Colors.white54,
                        fontWeight: _statusFilter == s
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                      side: BorderSide(
                        color: _statusFilter == s
                            ? _statusOptionColor(s)
                            : Colors.white10,
                      ),
                      onSelected: (_) {
                        setState(() => _statusFilter = s);
                        _loadMoreDrivers(reset: true);
                      },
                    ),
                  )),
              const Spacer(),
              // Search
              SizedBox(
                width: 260,
                height: 42,
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Buscar motorista...',
                    hintStyle: const TextStyle(color: Colors.white38),
                    prefixIcon:
                        const Icon(Icons.search, color: Colors.white38),
                    filled: true,
                    fillColor: Colors.white10,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: EdgeInsets.zero,
                  ),
                  style: const TextStyle(color: Colors.white),
                  onChanged: _onSearchChanged,
                ),
              ),
            ],
          ),
        ),

        // Driver list
        Expanded(
          child: _drivers.isEmpty && !_isLoading
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.drive_eta_outlined,
                          size: 64, color: Colors.white24),
                      const SizedBox(height: 16),
                      Text(
                        _statusFilter != 'Todos'
                            ? 'Nenhum motorista com status "${_statusOptionLabel(_statusFilter)}".'
                            : 'Nenhum motorista encontrado.',
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 16),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(24),
                  itemCount: _drivers.length + (_hasMore ? 1 : 0),
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    if (index == _drivers.length) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16.0),
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }
                    final d = _drivers[index];
                    return _DriverCard(
                      driver: d,
                      onStatusChanged: (newStatus, isApproved) {
                        setState(() {
                          d['status'] = newStatus;
                          d['is_approved'] = isApproved;
                        });
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// Card individual do motorista
// ─────────────────────────────────────────────
class _DriverCard extends StatelessWidget {
  final Map<String, dynamic> driver;
  final Function(String, bool) onStatusChanged;

  const _DriverCard({required this.driver, required this.onStatusChanged});

  Color _statusColor(Map<String, dynamic> d) {
    final status = d['status'] as String? ?? 'offline';
    final isApproved = d['is_approved'] == true;

    if (status == 'blocked') {
      return Colors.redAccent;
    }
    if (!isApproved) {
      return Colors.orangeAccent;
    }
    if (status == 'online' || status == 'in_progress') {
      return Colors.greenAccent;
    }
    return Colors.blueGrey; // offline / active com is_approved
  }

  String _statusLabel(Map<String, dynamic> d) {
    final status = d['status'] as String? ?? 'offline';
    final isApproved = d['is_approved'] == true;

    if (status == 'blocked') {
      return 'BLOQUEADO';
    }
    if (!isApproved) {
      return 'PENDENTE';
    }
    if (status == 'online' || status == 'in_progress') {
      return 'ONLINE';
    }
    return 'OFFLINE'; // active / offline
  }

  @override
  Widget build(BuildContext context) {
    final name = driver['full_name'] ?? 'Sem Nome';
    final phone = driver['phone_number'] ?? '-';
    final email = driver['email'] ?? '-';
    final avatarUrl = driver['avatar_url'] as String?;
    final createdAt = (driver['created_at'] as String?)?.split('T').first ?? '';
    final vehicleModel = driver['vehicle_model'] ?? '-';
    final vehiclePlate = driver['vehicle_plate'] ?? '-';
    final vehicleColor = driver['vehicle_color'] ?? '-';
    final walletBalance =
        (driver['wallet_balance'] as num?)?.toDouble() ?? 0.0;
    final vehicleType = driver['vehicle_type'] as String? ?? 'carro';
    final isMoto = vehicleType == 'moto';
    final vehicleImageUrl = driver['vehicle_image_url'] as String?;

    return Card(
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            // Avatar
            CircleAvatar(
              radius: 30,
              backgroundColor: Colors.white10,
              backgroundImage:
                  avatarUrl != null && avatarUrl.isNotEmpty
                      ? NetworkImage(avatarUrl)
                      : null,
              child: avatarUrl == null || avatarUrl.isEmpty
                  ? const Icon(Icons.person, color: Colors.white38, size: 28)
                  : null,
            ),
            const SizedBox(width: 20),

            // Info
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        name,
                        style: GoogleFonts.outfit(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _statusColor(driver).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _statusColor(driver).withValues(alpha: 0.4),
                          ),
                        ),
                        child: Text(
                          _statusLabel(driver),
                          style: TextStyle(
                            color: _statusColor(driver),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.phone, size: 14, color: Colors.white38),
                      const SizedBox(width: 6),
                      Text(phone,
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 13)),
                      const SizedBox(width: 16),
                      const Icon(Icons.email, size: 14, color: Colors.white38),
                      const SizedBox(width: 6),
                      Text(email,
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 13)),
                      const SizedBox(width: 16),
                      const Icon(Icons.calendar_today,
                          size: 14, color: Colors.white38),
                      const SizedBox(width: 6),
                      Text(createdAt,
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 13)),
                    ],
                  ),
                ],
              ),
            ),

            // Vehicle info
            Expanded(
              flex: 2,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(isMoto ? Icons.motorcycle : Icons.directions_car,
                                size: 14, color: Colors.blueAccent),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                '$vehicleModel - $vehicleColor',
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 13),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.badge,
                                size: 14, color: Colors.blueAccent),
                            const SizedBox(width: 6),
                            Text(
                              vehiclePlate,
                              style: GoogleFonts.outfit(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(isMoto ? Icons.motorcycle : Icons.directions_car,
                                size: 14, color: Colors.orangeAccent),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: (isMoto ? Colors.orange : Colors.blue).withOpacity(0.15),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: (isMoto ? Colors.orange : Colors.blue).withOpacity(0.4),
                                ),
                              ),
                              child: Text(
                                isMoto ? 'MOTO' : 'CARRO',
                                style: TextStyle(
                                  color: isMoto ? Colors.orange : Colors.blue,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.account_balance_wallet,
                                size: 14, color: Colors.greenAccent),
                            const SizedBox(width: 6),
                            Text(
                              'R\$ ${walletBalance.toStringAsFixed(2)}',
                              style: TextStyle(
                                color: walletBalance > 0
                                    ? Colors.greenAccent
                                    : Colors.white54,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (vehicleImageUrl != null && vehicleImageUrl.isNotEmpty) ...[
                    const SizedBox(width: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        vehicleImageUrl,
                        width: 72,
                        height: 72,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            width: 72,
                            height: 72,
                            color: Colors.white10,
                            child: const Icon(Icons.broken_image,
                                color: Colors.white24, size: 24),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Actions — Aprovação fica exclusivamente no KYC
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (driver['status'] == 'blocked')
                  _ActionButton(
                    icon: Icons.lock_open,
                    label: 'Desbloquear',
                    color: Colors.greenAccent,
                    onPressed: () => _changeStatus(
                        context, driver['id'], 'approved', 'desbloquear'),
                  ),
                if (driver['is_approved'] == true && driver['status'] != 'blocked')
                  _ActionButton(
                    icon: Icons.block,
                    label: 'Bloquear',
                    color: Colors.redAccent,
                    onPressed: () => _changeStatus(
                        context, driver['id'], 'blocked', 'bloquear'),
                  ),
                if (driver['is_approved'] != true)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.orangeAccent.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orangeAccent.withOpacity(0.3)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.hourglass_top, size: 14, color: Colors.orangeAccent),
                        SizedBox(width: 6),
                        Text(
                          'Aguardando KYC',
                          style: TextStyle(color: Colors.orangeAccent, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.visibility, color: Colors.blueAccent),
                  tooltip: 'Ver Detalhes',
                  onPressed: () => _showDriverDetails(context, driver),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _changeStatus(
    BuildContext context,
    String driverId,
    String newStatus,
    String actionVerb,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Confirmar: $actionVerb motorista?'),
        content: Text(
          'Alterar status do motorista "${driver['full_name']}" para "${newStatus == 'blocked' ? 'BLOQUEADO' : 'OFFLINE'}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  newStatus == 'blocked' ? Colors.red : Colors.green,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirmar',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      // 1. Update profile status + is_approved flag
      final updateData = <String, dynamic>{'status': newStatus};
      bool nextApproved = driver['is_approved'] == true;
      if (newStatus == 'approved' || newStatus == 'offline') {
        updateData['is_approved'] = true;
        updateData['status'] = 'offline'; // approved drivers start as offline
        nextApproved = true;
      } else if (newStatus == 'blocked') {
        updateData['is_approved'] = false;
        nextApproved = false;
      }
      await Supabase.instance.client
          .from('profiles')
          .update(updateData)
          .eq('id', driverId);

      // 2. Log to admin_audit_log
      final adminId =
          Supabase.instance.client.auth.currentUser?.id ?? 'UNKNOWN';
      await Supabase.instance.client.from('admin_audit_log').insert({
        'admin_id': adminId,
        'action_type': 'driver_status_change',
        'target_user_id': driverId,
        'details': {
          'action': actionVerb,
          'new_status': newStatus,
          'driver_name': driver['full_name'],
        },
      });

      onStatusChanged(updateData['status'], nextApproved);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Motorista status atualizado com sucesso.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showDriverDetails(
      BuildContext context, Map<String, dynamic> driver) {
    showDialog(
      context: context,
      builder: (_) => _DriverDetailDialog(driver: driver),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      icon: Icon(icon, size: 16, color: color),
      label: Text(label, style: TextStyle(color: color, fontSize: 12)),
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: color.withValues(alpha: 0.4)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Dialog de detalhes do motorista
// ─────────────────────────────────────────────
class _DriverDetailDialog extends StatefulWidget {
  final Map<String, dynamic> driver;
  const _DriverDetailDialog({required this.driver});

  @override
  State<_DriverDetailDialog> createState() => _DriverDetailDialogState();
}

class _DriverDetailDialogState extends State<_DriverDetailDialog> {
  late String _vehicleType;
  bool _isLoading = false;
  String? _vehicleImageUrl;
  bool _isUploadingImage = false;

  Map<String, dynamic>? _payoutAccount;
  bool _isLoadingPayout = true;

  double? _commissionPercentage;
  DateTime? _commissionExemptUntil;
  final _commissionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _vehicleType = widget.driver['vehicle_type'] as String? ?? 'carro';
    _vehicleImageUrl = widget.driver['vehicle_image_url'] as String?;
    _commissionPercentage = (widget.driver['commission_percentage'] as num?)?.toDouble();
    final exemptRaw = widget.driver['commission_exempt_until'];
    _commissionExemptUntil = exemptRaw != null ? DateTime.tryParse(exemptRaw.toString()) : null;
    _commissionController.text = _commissionPercentage?.toString() ?? '';
    _fetchPayoutAccount();
  }

  @override
  void dispose() {
    _commissionController.dispose();
    super.dispose();
  }

  Future<void> _updateCommissionPercentage(double? pct) async {
    setState(() {
      _isLoading = true;
    });
    try {
      await Supabase.instance.client
          .from('profiles')
          .update({'commission_percentage': pct})
          .eq('id', widget.driver['id']);

      final adminId = Supabase.instance.client.auth.currentUser?.id ?? 'UNKNOWN';
      await Supabase.instance.client.from('admin_audit_log').insert({
        'admin_id': adminId,
        'action_type': 'driver_commission_percentage_change',
        'target_user_id': widget.driver['id'],
        'details': {
          'commission_percentage': pct,
          'driver_name': widget.driver['full_name'],
        },
      });

      setState(() {
        _commissionPercentage = pct;
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Taxa de comissão atualizada com sucesso.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao atualizar taxa: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _updateCommissionExemptUntil(DateTime? date) async {
    setState(() {
      _isLoading = true;
    });
    try {
      await Supabase.instance.client
          .from('profiles')
          .update({'commission_exempt_until': date?.toIso8601String()})
          .eq('id', widget.driver['id']);

      final adminId = Supabase.instance.client.auth.currentUser?.id ?? 'UNKNOWN';
      await Supabase.instance.client.from('admin_audit_log').insert({
        'admin_id': adminId,
        'action_type': 'driver_commission_exemption_change',
        'target_user_id': widget.driver['id'],
        'details': {
          'commission_exempt_until': date?.toIso8601String(),
          'driver_name': widget.driver['full_name'],
        },
      });

      setState(() {
        _commissionExemptUntil = date;
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Data de isenção atualizada com sucesso.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao atualizar isenção: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _fetchPayoutAccount() async {
    try {
      final res = await Supabase.instance.client
          .from('payout_accounts')
          .select()
          .eq('driver_id', widget.driver['id'])
          .maybeSingle();
      if (mounted) {
        setState(() {
          _payoutAccount = res;
          _isLoadingPayout = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching payout account: $e');
      if (mounted) {
        setState(() {
          _isLoadingPayout = false;
        });
      }
    }
  }

  Future<void> _pickAndUploadVehicleImage() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );

    if (image == null) return;

    setState(() {
      _isUploadingImage = true;
    });

    try {
      final bytes = await image.readAsBytes();
      final driverId = widget.driver['id'];
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final extension = image.name.contains('.') ? image.name.split('.').last.toLowerCase() : 'png';
      final contentType = (extension == 'jpg' || extension == 'jpeg') ? 'image/jpeg' : 'image/png';
      final path = 'vehicle_images/${driverId}_$timestamp.$extension';

      // 1. Upload to Supabase Storage bucket 'avatars'
      await Supabase.instance.client.storage
          .from('avatars')
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              upsert: true,
              contentType: contentType,
            ),
          );

      // 2. Get Public URL
      final publicUrl = Supabase.instance.client.storage
          .from('avatars')
          .getPublicUrl(path);

      // 3. Update database profiles.vehicle_image_url
      await Supabase.instance.client
          .from('profiles')
          .update({'vehicle_image_url': publicUrl})
          .eq('id', driverId);

      // 4. Log audit
      final adminId = Supabase.instance.client.auth.currentUser?.id ?? 'UNKNOWN';
      await Supabase.instance.client.from('admin_audit_log').insert({
        'admin_id': adminId,
        'action_type': 'driver_vehicle_image_change',
        'target_user_id': driverId,
        'details': {
          'vehicle_image_url': publicUrl,
          'driver_name': widget.driver['full_name'],
        },
      });

      setState(() {
        _vehicleImageUrl = publicUrl;
        _isUploadingImage = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Foto do veículo atualizada com sucesso.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isUploadingImage = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao atualizar foto do veículo: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _updateVehicleType(String newType) async {
    setState(() {
      _isLoading = true;
    });

    try {
      final driverId = widget.driver['id'];

      // Update profiles
      await Supabase.instance.client
          .from('profiles')
          .update({'vehicle_type': newType})
          .eq('id', driverId);

      // Update driver_locations
      await Supabase.instance.client
          .from('driver_locations')
          .update({'vehicle_type': newType})
          .eq('driver_id', driverId);

      // Log audit
      final adminId = Supabase.instance.client.auth.currentUser?.id ?? 'UNKNOWN';
      await Supabase.instance.client.from('admin_audit_log').insert({
        'admin_id': adminId,
        'action_type': 'driver_vehicle_type_change',
        'target_user_id': driverId,
        'details': {
          'old_type': _vehicleType,
          'new_type': newType,
          'driver_name': widget.driver['full_name'],
        },
      });

      setState(() {
        _vehicleType = newType;
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Categoria do veículo atualizada com sucesso.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao atualizar categoria: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.driver['full_name'] ?? 'Sem Nome';
    final phone = widget.driver['phone_number'] ?? '-';
    final email = widget.driver['email'] ?? '-';
    final status = widget.driver['status'] ?? 'unknown';
    final avatarUrl = widget.driver['avatar_url'] as String?;
    final createdAt = widget.driver['created_at'] ?? '';
    final vehicleModel = widget.driver['vehicle_model'] ?? '-';
    final vehiclePlate = widget.driver['vehicle_plate'] ?? '-';
    final vehicleColor = widget.driver['vehicle_color'] ?? '-';
    final vehicleYear = widget.driver['vehicle_year'] ?? '-';
    final walletBalance =
        (widget.driver['wallet_balance'] as num?)?.toDouble() ?? 0.0;
    final cpf = widget.driver['cpf'] ?? '-';
    final cnh = widget.driver['cnh_number'] ?? '-';

    return Dialog(
      backgroundColor: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  CircleAvatar(
                    radius: 36,
                    backgroundColor: Colors.white10,
                    backgroundImage:
                        avatarUrl != null && avatarUrl.isNotEmpty
                            ? NetworkImage(avatarUrl)
                            : null,
                    child: avatarUrl == null || avatarUrl.isEmpty
                        ? const Icon(Icons.person,
                            color: Colors.white38, size: 36)
                        : null,
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: GoogleFonts.outfit(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Status: ${status.toUpperCase()}',
                          style: TextStyle(
                            color: status == 'approved'
                                ? Colors.greenAccent
                                : status == 'blocked'
                                    ? Colors.redAccent
                                    : Colors.orangeAccent,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(color: Colors.white10, height: 32),

              // Personal info
              Text('DADOS PESSOAIS',
                  style: _sectionStyle()),
              const SizedBox(height: 12),
              _InfoRow('Telefone', phone),
              _InfoRow('Email', email),
              _InfoRow('CPF', cpf),
              _InfoRow('CNH', cnh),
              _InfoRow('Cadastro', createdAt.toString().split('T').first),

              const Divider(color: Colors.white10, height: 32),

              // Vehicle info
              Text('VEICULO', style: _sectionStyle()),
              const SizedBox(height: 12),
              _InfoRow('Modelo', vehicleModel),
              _InfoRow('Placa', vehiclePlate),
              _InfoRow('Cor', vehicleColor),
              _InfoRow('Ano', vehicleYear.toString()),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 160,
                      child: Text('Categoria',
                          style: TextStyle(color: Colors.white54, fontSize: 14)),
                    ),
                    if (_isLoading)
                      const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.blueAccent),
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.white10,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _vehicleType,
                            dropdownColor: const Color(0xFF1E293B),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                            icon: const Icon(Icons.arrow_drop_down, color: Colors.white54),
                            items: const [
                              DropdownMenuItem(
                                value: 'carro',
                                child: Row(
                                  children: [
                                    Icon(Icons.directions_car, size: 16, color: Colors.blueAccent),
                                    SizedBox(width: 8),
                                    Text('Carro'),
                                  ],
                                ),
                              ),
                              DropdownMenuItem(
                                value: 'moto',
                                child: Row(
                                  children: [
                                    Icon(Icons.motorcycle, size: 16, color: Colors.orangeAccent),
                                    SizedBox(width: 8),
                                    Text('Moto'),
                                  ],
                                ),
                              ),
                            ],
                            onChanged: (val) {
                              if (val != null && val != _vehicleType) {
                                _updateVehicleType(val);
                              }
                            },
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(
                      width: 160,
                      child: Text('Foto do Veículo',
                          style: TextStyle(color: Colors.white54, fontSize: 14)),
                    ),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Stack(
                          children: [
                            Container(
                              width: 280,
                              height: 160,
                              decoration: BoxDecoration(
                                color: Colors.white10,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.white24),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: _vehicleImageUrl != null && _vehicleImageUrl!.isNotEmpty
                                    ? Image.network(
                                        _vehicleImageUrl!,
                                        fit: BoxFit.cover,
                                        errorBuilder: (context, error, stackTrace) {
                                          return const Center(
                                            child: Icon(Icons.broken_image,
                                                color: Colors.white38, size: 48),
                                          );
                                        },
                                      )
                                    : const Center(
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.directions_car,
                                                color: Colors.white24, size: 48),
                                            SizedBox(height: 8),
                                            Text(
                                              'Sem foto do veículo',
                                              style: TextStyle(
                                                  color: Colors.white38, fontSize: 13),
                                            ),
                                          ],
                                        ),
                                      ),
                              ),
                            ),
                            if (_isUploadingImage)
                              Positioned.fill(
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: const Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                ),
                              ),
                            Positioned(
                              bottom: 8,
                              right: 8,
                              child: Material(
                                color: Colors.blueAccent,
                                shape: const CircleBorder(),
                                elevation: 4,
                                child: InkWell(
                                  onTap: _isUploadingImage
                                      ? null
                                      : _pickAndUploadVehicleImage,
                                  customBorder: const CircleBorder(),
                                  child: const Padding(
                                    padding: EdgeInsets.all(8.0),
                                    child: Icon(
                                      Icons.camera_alt,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const Divider(color: Colors.white10, height: 32),

              // Financial
              Text('FINANCEIRO & TRANSFERÊNCIAS (PIX)', style: _sectionStyle()),
              const SizedBox(height: 12),
              _InfoRow(
                'Saldo Carteira',
                'R\$ ${walletBalance.toStringAsFixed(2)}',
              ),
              const SizedBox(height: 12),
              
              // Bloco de Conta Bancária / PIX
              _isLoadingPayout
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(12.0),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : _payoutAccount == null
                      ? Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.amber.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.amber.withOpacity(0.2)),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.warning_amber_rounded, color: Colors.amber),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Nenhuma conta de repasse (PIX) cadastrada para este motorista.',
                                  style: TextStyle(color: Colors.amber, fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        )
                      : Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                const Color(0xFF1E293B),
                                const Color(0xFF0F172A).withOpacity(0.5),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.account_balance_rounded, color: Colors.greenAccent, size: 20),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Dados para Envio do PIX / Repasse',
                                    style: GoogleFonts.outfit(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              _InfoRow('Titular', _payoutAccount!['account_holder_name'] ?? name),
                              _InfoRow('Banco', _payoutAccount!['bank_name'] ?? '-'),
                              _InfoRow('Agência', _payoutAccount!['routing_number'] ?? '-'),
                              _InfoRow('Conta de Repasse', _payoutAccount!['account_number'] ?? '-'),
                              
                              // Exibição do CPF do motorista com ação rápida de cópia
                              if (cpf != '-')
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: Row(
                                    children: [
                                      const SizedBox(
                                        width: 160,
                                        child: Text('CPF do Titular', style: TextStyle(color: Colors.white54, fontSize: 14)),
                                      ),
                                      Expanded(
                                        child: Row(
                                          children: [
                                            Text(
                                              cpf,
                                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                                            ),
                                            const SizedBox(width: 8),
                                            IconButton(
                                              icon: const Icon(Icons.copy, size: 16, color: Colors.blueAccent),
                                              constraints: const BoxConstraints(),
                                              padding: EdgeInsets.zero,
                                              tooltip: 'Copiar CPF',
                                              onPressed: () {
                                                Clipboard.setData(ClipboardData(text: cpf));
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  const SnackBar(
                                                    content: Text('CPF copiado para a área de transferência!'),
                                                    duration: Duration(seconds: 2),
                                                    backgroundColor: Colors.indigoAccent,
                                                  ),
                                                );
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              
                              // Exibição da chave Pix se cadastrada
                              if (_payoutAccount!['account_number'] != null || _payoutAccount!['account_holder_phone'] != null) ...[
                                const Divider(color: Colors.white10, height: 24),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'CHAVE PIX (CONTA)',
                                            style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            _payoutAccount!['account_number'] ?? _payoutAccount!['account_holder_phone'] ?? cpf,
                                            style: GoogleFonts.outfit(
                                              fontWeight: FontWeight.bold,
                                              color: Colors.greenAccent,
                                              fontSize: 15,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                    ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.greenAccent.withOpacity(0.12),
                                        foregroundColor: Colors.greenAccent,
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                        side: BorderSide(color: Colors.greenAccent.withOpacity(0.3)),
                                      ),
                                      icon: const Icon(Icons.copy, size: 16),
                                      label: const Text('COPIAR PIX', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                      onPressed: () {
                                        final pixKey = _payoutAccount!['account_number'] ?? _payoutAccount!['account_holder_phone'] ?? cpf;
                                        Clipboard.setData(ClipboardData(text: pixKey));
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text('Chave PIX ($pixKey) copiada!'),
                                            duration: const Duration(seconds: 2),
                                            backgroundColor: Colors.green.shade800,
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),

              const Divider(color: Colors.white10, height: 32),

              // Commission Settings
              Text('TAXAS & ISENÇÃO DE COMISSÃO', style: _sectionStyle()),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 160,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Comissão Individual (%)',
                              style: TextStyle(color: Colors.white54, fontSize: 14)),
                          SizedBox(height: 2),
                          Text('Se vazio, usa o padrão',
                              style: TextStyle(color: Colors.white24, fontSize: 11)),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Row(
                        children: [
                          SizedBox(
                            width: 120,
                            height: 40,
                            child: TextField(
                              controller: _commissionController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              style: const TextStyle(color: Colors.white, fontSize: 14),
                              decoration: InputDecoration(
                                hintText: 'Padrão (ex: 15)',
                                hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                filled: true,
                                fillColor: Colors.white10,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(color: Colors.white24),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(color: Colors.white24),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(color: Colors.blueAccent),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blueAccent,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            onPressed: () {
                              final text = _commissionController.text.trim();
                              final val = double.tryParse(text);
                              _updateCommissionPercentage(val);
                            },
                            child: const Text('Salvar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 160,
                      child: Text('Isento Até',
                          style: TextStyle(color: Colors.white54, fontSize: 14)),
                    ),
                    Expanded(
                      child: Row(
                        children: [
                          Text(
                            _commissionExemptUntil == null
                                ? 'Sem isenção ativa'
                                : '${_commissionExemptUntil!.day.toString().padLeft(2, '0')}/${_commissionExemptUntil!.month.toString().padLeft(2, '0')}/${_commissionExemptUntil!.year}',
                            style: TextStyle(
                              color: _commissionExemptUntil == null ? Colors.white38 : Colors.greenAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(width: 12),
                          IconButton(
                            icon: const Icon(Icons.calendar_month, color: Colors.blueAccent, size: 20),
                            onPressed: () async {
                              final now = DateTime.now();
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: _commissionExemptUntil ?? now,
                                firstDate: now.subtract(const Duration(days: 365)),
                                lastDate: now.add(const Duration(days: 365 * 5)),
                                builder: (context, child) {
                                  return Theme(
                                    data: Theme.of(context).copyWith(
                                      colorScheme: const ColorScheme.dark(
                                        primary: Colors.blueAccent,
                                        onPrimary: Colors.white,
                                        surface: Color(0xFF1E293B),
                                        onSurface: Colors.white,
                                      ),
                                    ),
                                    child: child!,
                                  );
                                },
                              );
                              if (picked != null) {
                                final endOfDay = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
                                _updateCommissionExemptUntil(endOfDay);
                              }
                            },
                          ),
                          if (_commissionExemptUntil != null)
                            IconButton(
                              icon: const Icon(Icons.clear, color: Colors.redAccent, size: 20),
                              onPressed: () {
                                _updateCommissionExemptUntil(null);
                              },
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const Divider(color: Colors.white10, height: 32),

              // Ride history stats
              Text('HISTORICO DE CORRIDAS', style: _sectionStyle()),
              const SizedBox(height: 12),
              StreamBuilder<List<Map<String, dynamic>>>(
                stream: Supabase.instance.client
                    .from('rides')
                    .stream(primaryKey: ['id'])
                    .eq('driver_id', widget.driver['id']),
                builder: (context,
                    AsyncSnapshot<List<Map<String, dynamic>>> snap) {
                  if (!snap.hasData) {
                    return const Center(
                        child: CircularProgressIndicator());
                  }
                  final rides = snap.data!;
                  final total = rides.length;
                  final completed = rides
                      .where((r) => r['status'] == 'completed' || r['status'] == 'finished')
                      .length;
                  final canceled = rides
                      .where((r) => r['status'] == 'rider_canceled' || r['status'] == 'driver_canceled')
                      .length;
                  double totalFare = 0;
                  for (var r in rides) {
                    if (r['status'] == 'completed' || r['status'] == 'finished') {
                      totalFare +=
                          (r['fare'] as num?)?.toDouble() ?? 0.0;
                    }
                  }
                  final cancelRate = total > 0
                      ? (canceled / total * 100).toStringAsFixed(1)
                      : '0.0';

                  // Calcular corridas completadas em diferentes períodos
                  final now = DateTime.now();
                  final todayStart = DateTime(now.year, now.month, now.day);
                  
                  // Semana começa 7 dias atrás
                  final weekStart = now.subtract(const Duration(days: 7));
                  
                  // Mês começa no dia 1 do mês atual
                  final monthStart = DateTime(now.year, now.month, 1);

                  int completedToday = 0;
                  int completedThisWeek = 0;
                  int completedThisMonth = 0;

                  for (var r in rides) {
                    final status = r['status'] as String?;
                    if (status == 'completed' || status == 'finished') {
                      final createdAtRaw = r['created_at'];
                      if (createdAtRaw != null) {
                        final date = DateTime.tryParse(createdAtRaw.toString());
                        if (date != null) {
                          if (date.isAfter(todayStart)) {
                            completedToday++;
                          }
                          if (date.isAfter(weekStart)) {
                            completedThisWeek++;
                          }
                          if (date.isAfter(monthStart)) {
                            completedThisMonth++;
                          }
                        }
                      }
                    }
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _StatChip('Total', '$total',
                              Colors.blueAccent),
                          const SizedBox(width: 12),
                          _StatChip('Completas', '$completed',
                              Colors.greenAccent),
                          const SizedBox(width: 12),
                          _StatChip('Canceladas', '$canceled',
                              Colors.redAccent),
                          const SizedBox(width: 12),
                          _StatChip(
                            'Taxa Cancel.',
                            '$cancelRate%',
                            double.parse(cancelRate) > 30
                                ? Colors.redAccent
                                : Colors.white54,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'DESEMPENHO POR PERÍODO (COMPLETADAS)',
                        style: TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _StatChip('Hoje', '$completedToday', Colors.tealAccent),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _StatChip('Esta Semana', '$completedThisWeek', Colors.tealAccent),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _StatChip('Este Mês', '$completedThisMonth', Colors.tealAccent),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _InfoRow(
                        'Faturamento Total',
                        'R\$ ${totalFare.toStringAsFixed(2)}',
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  TextStyle _sectionStyle() => const TextStyle(
        color: Colors.white38,
        fontSize: 12,
        fontWeight: FontWeight.bold,
        letterSpacing: 2,
      );
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 160,
            child: Text(label,
                style: const TextStyle(color: Colors.white54, fontSize: 14)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatChip(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(color: Colors.white54, fontSize: 11)),
        ],
      ),
    );
  }
}
