import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

/// Tela God Mode: Gestão completa de carteiras dos usuários e
/// endereços favoritos dos passageiros. Permite visualização,
/// ajustes de saldo na tabela wallets, e remoção de favoritos.
class UserWalletsScreen extends StatefulWidget {
  const UserWalletsScreen({super.key});

  @override
  State<UserWalletsScreen> createState() => _UserWalletsScreenState();
}

class _UserWalletsScreenState extends State<UserWalletsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(32, 20, 32, 0),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: const Border(bottom: BorderSide(color: Colors.white10)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Carteiras & Endereços Favoritos',
                    style: GoogleFonts.outfit(
                      fontSize: 28,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(
                    width: 300,
                    child: TextField(
                      onChanged: (v) => setState(() => _searchQuery = v),
                      decoration: InputDecoration(
                        hintText: 'Buscar por nome ou ID...',
                        prefixIcon: const Icon(Icons.search),
                        filled: true,
                        fillColor: Colors.black12,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 0),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TabBar(
                controller: _tabController,
                indicatorColor: Colors.amberAccent,
                labelColor: Colors.amberAccent,
                unselectedLabelColor: Colors.white54,
                tabs: const [
                  Tab(
                    icon: Icon(Icons.account_balance_wallet, size: 18),
                    text: 'Carteiras (wallets)',
                  ),
                  Tab(
                    icon: Icon(Icons.bookmark_outline, size: 18),
                    text: 'Endereços Favoritos',
                  ),
                  Tab(
                    icon: Icon(Icons.star_outline, size: 18),
                    text: 'Motoristas Favoritos',
                  ),
                ],
              ),
            ],
          ),
        ),

        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildWalletsTab(),
              _buildFavoriteAddressesTab(),
              _buildFavoriteDriversTab(),
            ],
          ),
        ),
      ],
    );
  }

  // ==========================================
  // TAB 1: Wallets
  // ==========================================
  Widget _buildWalletsTab() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client
          .from('wallets')
          .stream(primaryKey: ['id']),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          // Table may not exist, show graceful fallback
          return _buildWalletsFallback();
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        var wallets = snapshot.data!;

        if (_searchQuery.isNotEmpty) {
          final q = _searchQuery.toLowerCase();
          wallets = wallets.where((w) {
            final userId = (w['user_id'] ?? '').toString().toLowerCase();
            final currency = (w['currency'] ?? '').toString().toLowerCase();
            return userId.contains(q) || currency.contains(q);
          }).toList();
        }

        if (wallets.isEmpty) {
          return _buildWalletsFallback();
        }

        return ListView.builder(
          padding: const EdgeInsets.all(24),
          itemCount: wallets.length,
          itemBuilder: (context, index) {
            final wallet = wallets[index];
            final userId = wallet['user_id']?.toString() ?? '';
            final balance =
                (wallet['balance'] as num?)?.toDouble() ?? 0.0;
            final currency = wallet['currency']?.toString() ?? 'BRL';
            final updatedAt =
                wallet['updated_at']?.toString().substring(0, 16) ?? '';

            return FutureBuilder(
              future: Supabase.instance.client
                  .from('profiles')
                  .select('full_name, role, phone_number')
                  .eq('id', userId)
                  .maybeSingle(),
              builder: (ctx, AsyncSnapshot<Map<String, dynamic>?> snap) {
                final name = snap.data?['full_name'] ?? 'Carregando...';
                final role = snap.data?['role'] ?? '';
                final phone = snap.data?['phone_number'] ?? '';

                return Card(
                  color: Theme.of(context).colorScheme.surface.withAlpha(200),
                  margin: const EdgeInsets.only(bottom: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: role == 'driver'
                              ? Colors.orangeAccent.withOpacity(0.15)
                              : Colors.blueAccent.withOpacity(0.15),
                          child: Icon(
                            role == 'driver'
                                ? Icons.drive_eta
                                : Icons.person,
                            color: role == 'driver'
                                ? Colors.orangeAccent
                                : Colors.blueAccent,
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: GoogleFonts.outfit(
                                    fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${role == 'driver' ? '🚗 Motorista' : '👤 Passageiro'} | 📱 $phone',
                                style: const TextStyle(
                                    color: Colors.white54, fontSize: 12),
                              ),
                              Text(
                                'Atualizado: $updatedAt',
                                style: const TextStyle(
                                    color: Colors.white38, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              currency,
                              style: const TextStyle(
                                  color: Colors.white38, fontSize: 11),
                            ),
                            Text(
                              'R\$ ${balance.toStringAsFixed(2)}',
                              style: GoogleFonts.outfit(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: balance < 0
                                    ? Colors.redAccent
                                    : balance == 0
                                        ? Colors.white38
                                        : Colors.greenAccent,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 16),
                        ElevatedButton.icon(
                          onPressed: () => _adjustWalletBalance(
                            wallet['id'].toString(),
                            userId,
                            name,
                            balance,
                          ),
                          icon: const Icon(Icons.edit, size: 14),
                          label: const Text('Ajustar'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.amberAccent.withOpacity(0.2),
                            foregroundColor: Colors.amberAccent,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildWalletsFallback() {
    // Fallback: show wallets via profiles.wallet_balance
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client
          .from('profiles')
          .stream(primaryKey: ['id'])
          .order('wallet_balance', ascending: false),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        var profiles = snapshot.data!;
        profiles = profiles
            .where((p) =>
                (p['wallet_balance'] as num?)?.toDouble() != null &&
                (p['wallet_balance'] as num?)?.toDouble() != 0)
            .toList();

        if (_searchQuery.isNotEmpty) {
          final q = _searchQuery.toLowerCase();
          profiles = profiles.where((p) {
            final name = (p['full_name'] ?? '').toString().toLowerCase();
            return name.contains(q);
          }).toList();
        }

        if (profiles.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.account_balance_wallet_outlined,
                    color: Colors.white24, size: 64),
                SizedBox(height: 16),
                Text('Nenhuma carteira com saldo encontrada.',
                    style: TextStyle(color: Colors.white54)),
                SizedBox(height: 8),
                Text(
                  'Mostrando dados de profiles.wallet_balance como fallback.',
                  style: TextStyle(color: Colors.white24, fontSize: 11),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(24),
          itemCount: profiles.length,
          itemBuilder: (context, index) {
            final p = profiles[index];
            final name = p['full_name']?.toString() ?? 'Sem Nome';
            final role = p['role']?.toString() ?? '';
            final balance =
                (p['wallet_balance'] as num?)?.toDouble() ?? 0.0;

            return Card(
              color: Theme.of(context).colorScheme.surface.withAlpha(200),
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                contentPadding: const EdgeInsets.all(16),
                leading: CircleAvatar(
                  backgroundColor: role == 'driver'
                      ? Colors.orangeAccent.withOpacity(0.15)
                      : Colors.blueAccent.withOpacity(0.15),
                  child: Icon(
                    role == 'driver' ? Icons.drive_eta : Icons.person,
                    color: role == 'driver'
                        ? Colors.orangeAccent
                        : Colors.blueAccent,
                  ),
                ),
                title: Text(name,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(
                  role == 'driver' ? '🚗 Motorista' : '👤 Passageiro',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                trailing: Text(
                  'R\$ ${balance.toStringAsFixed(2)}',
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: balance < 0
                        ? Colors.redAccent
                        : Colors.greenAccent,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ==========================================
  // TAB 2: Favorite Addresses
  // ==========================================
  Widget _buildFavoriteAddressesTab() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client
          .from('favorite_addresses')
          .stream(primaryKey: ['id']),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.location_off, color: Colors.white24, size: 64),
                const SizedBox(height: 16),
                Text('Erro: ${snapshot.error}',
                    style: const TextStyle(color: Colors.redAccent)),
              ],
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        var addresses = snapshot.data!;

        if (_searchQuery.isNotEmpty) {
          final q = _searchQuery.toLowerCase();
          addresses = addresses.where((a) {
            final title = (a['title'] ?? a['name'] ?? '').toString().toLowerCase();
            final address = (a['address'] ?? '').toString().toLowerCase();
            final userId = (a['user_id'] ?? '').toString().toLowerCase();
            return title.contains(q) || address.contains(q) || userId.contains(q);
          }).toList();
        }

        if (addresses.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.bookmark_border, color: Colors.white24, size: 64),
                SizedBox(height: 16),
                Text('Nenhum endereço favorito encontrado.',
                    style: TextStyle(color: Colors.white54)),
              ],
            ),
          );
        }

        // Group by user_id
        final grouped = <String, List<Map<String, dynamic>>>{};
        for (var a in addresses) {
          final uid = a['user_id']?.toString() ?? 'unknown';
          grouped.putIfAbsent(uid, () => []).add(a);
        }

        final userIds = grouped.keys.toList();

        return ListView.builder(
          padding: const EdgeInsets.all(24),
          itemCount: userIds.length,
          itemBuilder: (context, index) {
            final userId = userIds[index];
            final userAddresses = grouped[userId]!;

            return FutureBuilder(
              future: Supabase.instance.client
                  .from('profiles')
                  .select('full_name, phone_number')
                  .eq('id', userId)
                  .maybeSingle(),
              builder: (ctx, AsyncSnapshot<Map<String, dynamic>?> snap) {
                final name = snap.data?['full_name'] ?? 'Carregando...';
                final phone = snap.data?['phone_number'] ?? '';

                return Card(
                  color: Theme.of(context).colorScheme.surface.withAlpha(200),
                  margin: const EdgeInsets.only(bottom: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: ExpansionTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.purpleAccent.withOpacity(0.15),
                      child: const Icon(Icons.bookmark,
                          color: Colors.purpleAccent),
                    ),
                    title: Text(
                      name,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    subtitle: Text(
                      '📱 $phone | ${userAddresses.length} endereço(s)',
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 12),
                    ),
                    children: userAddresses.map((a) {
                      final title = a['title']?.toString() ??
                          a['name']?.toString() ??
                          'Sem título';
                      final address = a['address']?.toString() ??
                          a['formatted_address']?.toString() ??
                          '';
                      final lat = a['lat']?.toString() ?? '';
                      final lng = a['lng']?.toString() ?? '';
                      final type = a['type']?.toString() ?? '';

                      IconData typeIcon;
                      switch (type.toLowerCase()) {
                        case 'home':
                        case 'casa':
                          typeIcon = Icons.home;
                          break;
                        case 'work':
                        case 'trabalho':
                          typeIcon = Icons.work;
                          break;
                        default:
                          typeIcon = Icons.location_on;
                      }

                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 4),
                        leading: Icon(typeIcon, color: Colors.purpleAccent),
                        title: Text(title,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (address.isNotEmpty)
                              Text(address,
                                  style: const TextStyle(
                                      color: Colors.white54, fontSize: 12)),
                            if (lat.isNotEmpty && lng.isNotEmpty)
                              Text('📍 $lat, $lng',
                                  style: const TextStyle(
                                      color: Colors.white38, fontSize: 11)),
                          ],
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline,
                              color: Colors.redAccent, size: 20),
                          tooltip: 'Excluir endereço',
                          onPressed: () =>
                              _deleteFavoriteAddress(a['id'].toString(), userId),
                        ),
                      );
                    }).toList(),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  // ==========================================
  // TAB 3: Favorite Drivers
  // ==========================================
  Widget _buildFavoriteDriversTab() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client
          .from('favorite_drivers')
          .stream(primaryKey: ['id']),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: Colors.white24, size: 64),
                const SizedBox(height: 16),
                Text('Erro: ${snapshot.error}',
                    style: const TextStyle(color: Colors.redAccent)),
              ],
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        var favorites = snapshot.data!;

        if (_searchQuery.isNotEmpty) {
          final q = _searchQuery.toLowerCase();
          favorites = favorites.where((f) {
            final userId = (f['user_id'] ?? '').toString().toLowerCase();
            final driverId = (f['driver_id'] ?? '').toString().toLowerCase();
            return userId.contains(q) || driverId.contains(q);
          }).toList();
        }

        if (favorites.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.star_border, color: Colors.white24, size: 64),
                SizedBox(height: 16),
                Text('Nenhum motorista favorito encontrado.',
                    style: TextStyle(color: Colors.white54)),
              ],
            ),
          );
        }

        // Group by user_id
        final grouped = <String, List<Map<String, dynamic>>>{};
        for (var f in favorites) {
          final uid = f['user_id']?.toString() ?? 'unknown';
          grouped.putIfAbsent(uid, () => []).add(f);
        }

        final userIds = grouped.keys.toList();

        return ListView.builder(
          padding: const EdgeInsets.all(24),
          itemCount: userIds.length,
          itemBuilder: (context, index) {
            final userId = userIds[index];
            final userFavs = grouped[userId]!;

            return FutureBuilder(
              future: Supabase.instance.client
                  .from('profiles')
                  .select('full_name, phone_number')
                  .eq('id', userId)
                  .maybeSingle(),
              builder: (ctx, AsyncSnapshot<Map<String, dynamic>?> snapUser) {
                final userName = snapUser.data?['full_name'] ?? 'Passageiro Carregando...';
                final userPhone = snapUser.data?['phone_number'] ?? '';

                return Card(
                  color: Theme.of(context).colorScheme.surface.withAlpha(200),
                  margin: const EdgeInsets.only(bottom: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: ExpansionTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.amberAccent.withOpacity(0.15),
                      child: const Icon(Icons.person, color: Colors.amberAccent),
                    ),
                    title: Text(
                      userName,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    subtitle: Text(
                      '📱 $userPhone | ${userFavs.length} motorista(s) favorito(s)',
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    children: userFavs.map((f) {
                      final driverId = f['driver_id']?.toString() ?? '';
                      final createdAt = f['created_at']?.toString().substring(0, 10) ?? '';

                      return FutureBuilder(
                        future: Supabase.instance.client
                            .from('profiles')
                            .select('full_name')
                            .eq('id', driverId)
                            .maybeSingle(),
                        builder: (ctx, AsyncSnapshot<Map<String, dynamic>?> snapDriver) {
                          final driverName = snapDriver.data?['full_name'] ?? 'Motorista Carregando...';

                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                            leading: const Icon(Icons.drive_eta, color: Colors.amberAccent),
                            title: Text(driverName, style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text('ID: ${driverId.substring(0, 8)}... | Adicionado em: $createdAt',
                                style: const TextStyle(color: Colors.white54, fontSize: 12)),
                          );
                        },
                      );
                    }).toList(),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  // ==========================================
  // Actions
  // ==========================================
  Future<void> _adjustWalletBalance(
    String walletId,
    String userId,
    String userName,
    double currentBalance,
  ) async {
    final amountCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text('Ajustar Carteira: $userName'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Saldo atual: R\$ ${currentBalance.toStringAsFixed(2)}',
              style: const TextStyle(color: Colors.amberAccent, fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                  signed: true, decimal: true),
              decoration: const InputDecoration(
                labelText: 'Novo saldo (R\$)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(
                labelText: 'Motivo',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amberAccent),
            onPressed: () async {
              final newBalance = double.tryParse(amountCtrl.text);
              if (newBalance == null) return;

              try {
                await Supabase.instance.client
                    .from('wallets')
                    .update({'balance': newBalance}).eq('id', walletId);

                final adminId = Supabase.instance.client.auth.currentUser?.id ??
                    'UNKNOWN';
                await Supabase.instance.client.from('admin_audit_log').insert({
                  'admin_id': adminId,
                  'action_type': 'wallet_balance_adjusted',
                  'target_user_id': userId,
                  'target_resource_id': walletId,
                  'details': {
                    'old_balance': currentBalance,
                    'new_balance': newBalance,
                    'reason': reasonCtrl.text,
                  },
                });

                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          'Saldo atualizado: R\$ ${newBalance.toStringAsFixed(2)}'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text('Erro: $e'),
                        backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('Salvar',
                style: TextStyle(color: Colors.black87)),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteFavoriteAddress(
      String addressId, String userId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: const Text('Excluir Endereço Favorito?'),
        content: const Text(
            'O passageiro perderá este endereço salvo.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:
                const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await Supabase.instance.client
          .from('favorite_addresses')
          .delete()
          .eq('id', addressId);

      final adminId =
          Supabase.instance.client.auth.currentUser?.id ?? 'UNKNOWN';
      await Supabase.instance.client.from('admin_audit_log').insert({
        'admin_id': adminId,
        'action_type': 'favorite_address_deleted',
        'target_user_id': userId,
        'target_resource_id': addressId,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Endereço excluído.'),
              backgroundColor: Colors.redAccent),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}
