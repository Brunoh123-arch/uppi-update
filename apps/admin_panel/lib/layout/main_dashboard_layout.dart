import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'menu_items.dart';
import 'widgets/sidebar_item.dart';
import 'widgets/sos_alert_dialog.dart';
import '../features/kyc/kyc_approval_screen.dart';

// ─────────────────────────────────────────────
// Layout Principal do Dashboard
// ─────────────────────────────────────────────
class MainDashboardLayout extends StatefulWidget {
  const MainDashboardLayout({super.key});

  @override
  State<MainDashboardLayout> createState() => _MainDashboardLayoutState();
}

class _MainDashboardLayoutState extends State<MainDashboardLayout> {
  int _selectedIndex = 0;
  String _currentRole = 'operator';
  bool _isLoadingRole = true;

  StreamSubscription? _sosSubscription;
  StreamSubscription? _registrationSubscription;
  RealtimeChannel? _globalEventsChannel;

  int _lastPendingCount = -1;
  bool _isSosShowing = false;
  DateTime? _lastErrorTime;

  List<AdminMenuItem> get _allMenuItems => allMenuItems;

  @override
  void initState() {
    super.initState();
    _fetchAdminRole();
    _startRealtimeListeners();
  }

  Future<void> _fetchAdminRole() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        final res = await Supabase.instance.client
            .from('admins')
            .select('role')
            .eq('id', user.id)
            .maybeSingle();
        if (res != null && res['role'] != null) {
          if (mounted) setState(() => _currentRole = res['role']);
        } else {
          // Fallback to operator
          if (mounted) setState(() => _currentRole = 'operator');
        }
      }
    } catch (e) {
      debugPrint('Error fetching admin role: $e');
    } finally {
      if (mounted) setState(() => _isLoadingRole = false);
    }
  }

  void _handleRealtimeError(String source, dynamic error) {
    debugPrint('[$source error]: $error');
    if (!mounted) return;
    
    final now = DateTime.now();
    if (_lastErrorTime == null || now.difference(_lastErrorTime!) > const Duration(seconds: 30)) {
      _lastErrorTime = now;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.wifi_off_rounded, color: Colors.white),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Instabilidade na conexão em tempo real. Tentando reconectar automaticamente...',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.redAccent.shade700,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  void _startRealtimeListeners() {
    try {
      // Usando sos_alerts — tabela unificada (submitted_by: 'rider' | 'driver')
      _sosSubscription = Supabase.instance.client
          .from('sos_alerts')
          .stream(primaryKey: ['id'])
          .listen((List<Map<String, dynamic>> data) {
            final activeSos = data.where((e) => e['status'] == 'active').toList();
            if (activeSos.isNotEmpty) {
              _showSosAlert(activeSos.last);
            }
          }, onError: (e) {
            _handleRealtimeError('SOS Alerts Stream', e);
          });

      _registrationSubscription = Supabase.instance.client
          .from('profiles')
          .stream(primaryKey: ['id'])
          .eq('role', 'driver')
          .listen((List<Map<String, dynamic>> data) {
            final pendingDrivers = data.where((p) => p['is_approved'] != true).toList();
            if (pendingDrivers.length > _lastPendingCount && _lastPendingCount >= 0) {
              _showNewRegistrationAlert(pendingDrivers.length);
            }
            _lastPendingCount = pendingDrivers.length;
          }, onError: (e) {
            _handleRealtimeError('Profiles Stream', e);
          });

      _globalEventsChannel = Supabase.instance.client.channel('global_admin_events')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'rides',
            callback: (payload) {
              _showGlobalToast('🚕 Nova corrida solicitada!', Colors.blueAccent);
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'rides',
            callback: (payload) {
              final newRecord = payload.newRecord;
              final oldRecord = payload.oldRecord;
              final newStatus = newRecord['status'];
              final oldStatus = oldRecord['status'];

              if (newStatus != null && newStatus != oldStatus) {
                if (newStatus == 'finished' || newStatus == 'completed' || newStatus == 'waiting_for_review') {
                  _showGlobalToast('✅ Uma corrida foi concluída!', Colors.green);
                } else if (newStatus == 'rider_canceled' || newStatus == 'driver_canceled' || newStatus == 'canceled') {
                  _showGlobalToast('❌ Uma corrida foi cancelada.', Colors.redAccent);
                } else if (newStatus == 'started' || newStatus == 'in_progress') {
                  _showGlobalToast('🚀 Uma corrida foi iniciada!', Colors.orangeAccent);
                }
              }
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'profiles',
            callback: (payload) {
              final p = payload.newRecord;
              final displayName = p['full_name'] ?? p['name'] ?? 'Sem Nome';
              if (p['role'] == 'rider') {
                _showGlobalToast('👤 Novo passageiro: $displayName', Colors.purpleAccent);
              } else if (p['role'] == 'driver') {
                _showGlobalToast('🚗 Novo motorista: $displayName', Colors.indigoAccent);
              }
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'wallet_transactions',
            callback: (payload) {
              final tx = payload.newRecord;
              final type = tx['ref_type']?.toString() ?? tx['transaction_type']?.toString() ?? '';
              if (type == 'withdraw') {
                _showGlobalToast('💸 Nova solicitação de saque recebida!', Colors.orangeAccent);
              }
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'complaints',
            callback: (payload) {
              _showGlobalToast('📢 Nova reclamação registrada!', Colors.redAccent);
            },
          )
          .subscribe((status, error) {
            if (status.toString().contains('errored') || error != null) {
              _handleRealtimeError('GlobalEventsChannel', error);
            }
          });
    } catch (e) {
      debugPrint('Admin Realtime - Falha ao iniciar listeners: $e');
    }
  }

  void _showGlobalToast(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        margin: const EdgeInsets.only(bottom: 20, left: 20, right: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _showNewRegistrationAlert(int totalPending) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.person_add_alt_1_rounded, color: Colors.white),
            const SizedBox(width: 12),
            Text('Novo motorista aguardando aprovação! Total na fila: $totalPending'),
          ],
        ),
        backgroundColor: Colors.blueAccent.shade700,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'VER',
          textColor: Colors.white,
          onPressed: () {
            final visibleMenus = _allMenuItems.where((m) => m.allowedRoles.contains(_currentRole)).toList();
            final kycIndex = visibleMenus.indexWhere((m) => m.content is KycApprovalScreen);
            if (kycIndex != -1) {
              setState(() => _selectedIndex = kycIndex);
            }
          },
        ),
      ),
    );
  }

  void _showSosAlert(Map<String, dynamic> sosData) {
    if (_isSosShowing) return;
    _isSosShowing = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return SosAlertDialog(
          sosData: sosData,
          onResolveComplete: () {
            Navigator.of(context).pop();
            _isSosShowing = false;
          },
        );
      },
    ).then((_) => _isSosShowing = false);
  }

  @override
  void dispose() {
    _sosSubscription?.cancel();
    _registrationSubscription?.cancel();
    _globalEventsChannel?.unsubscribe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingRole) {
      return Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final theme = Theme.of(context);
    final isDesktop = MediaQuery.of(context).size.width >= 1024;
    final currentEmail = Supabase.instance.client.auth.currentUser?.email ?? 'admin';

    final visibleMenus = _allMenuItems
        .where((menu) => menu.allowedRoles.contains(_currentRole))
        .toList();

    if (_selectedIndex >= visibleMenus.length) {
      _selectedIndex = 0;
    }

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Row(
        children: [
          Container(
            width: isDesktop ? 260 : 72,
            color: theme.colorScheme.surface,
            child: Column(
              children: [
                // 1. LEADING (Logo e papel)
                Padding(
                  padding: const EdgeInsets.only(bottom: 24.0, top: 16, left: 8, right: 8),
                  child: Column(
                    children: [
                      Image.asset(
                        'assets/images/logo.png',
                        width: 42,
                        height: 42,
                        errorBuilder: (context, error, stackTrace) =>
                            Icon(Icons.hexagon, size: 42, color: theme.colorScheme.primary),
                      ),
                      if (isDesktop) ...[
                        const SizedBox(height: 8),
                        Image.asset(
                          'assets/images/logo-header.png',
                          height: 20,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) => Text(
                            'UPPI',
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                              letterSpacing: 2,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: _currentRole == 'superadmin' ? Colors.deepPurpleAccent.withAlpha(50) : Colors.blueAccent.withAlpha(50),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _currentRole == 'superadmin' ? Colors.deepPurpleAccent : Colors.blueAccent,
                              width: 1,
                            ),
                          ),
                          child: Text(
                            _currentRole.toUpperCase(),
                            style: TextStyle(
                              color: _currentRole == 'superadmin' ? Colors.purpleAccent : Colors.blueAccent,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const Divider(color: Colors.white10, height: 1),
                
                // 2. DESTINATIONS (Scrollável)
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: List.generate(visibleMenus.length, (index) {
                        final menu = visibleMenus[index];
                        final isSelected = index == _selectedIndex;
                        return SidebarItem(
                          icon: isSelected ? menu.selectedIcon : menu.icon,
                          label: menu.label,
                          isSelected: isSelected,
                          isExpanded: isDesktop,
                          onTap: () {
                            setState(() => _selectedIndex = index);
                          },
                        );
                      }),
                    ),
                  ),
                ),
                
                const Divider(color: Colors.white10, height: 1),
                
                // 3. TRAILING (Email e Logout)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16, top: 16, left: 8, right: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isDesktop) ...[
                        Text(
                          currentEmail,
                          style: const TextStyle(color: Colors.white38, fontSize: 11),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                      ],
                      IconButton(
                        icon: const Icon(Icons.logout, color: Colors.redAccent),
                        tooltip: 'Sair do Painel',
                        onPressed: () async {
                          await Supabase.instance.client.auth.signOut();
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const VerticalDivider(thickness: 1, width: 1, color: Colors.white10),
          Expanded(
            child: visibleMenus.isNotEmpty 
              ? visibleMenus[_selectedIndex].content 
              : const Center(child: Text('Acesso Negado')),
          ),
        ],
      ),
    );
  }
}
