import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

class SuspiciousDevicesScreen extends StatefulWidget {
  const SuspiciousDevicesScreen({super.key});

  @override
  State<SuspiciousDevicesScreen> createState() => _SuspiciousDevicesScreenState();
}

class _SuspiciousDevicesScreenState extends State<SuspiciousDevicesScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  String _threatFilter = 'Todos';

  Color _threatColor(String threat) {
    switch (threat) {
      case 'root_jailbreak':
        return Colors.redAccent;
      case 'emulator':
        return Colors.amberAccent;
      case 'fake_gps':
        return Colors.orangeAccent;
      default:
        return Colors.white54;
    }
  }

  String _threatLabel(String threat) {
    switch (threat) {
      case 'root_jailbreak':
        return 'ROOT / JAILBREAK';
      case 'emulator':
        return 'EMULADOR DETECTADO';
      case 'fake_gps':
        return 'MOCK GPS (GPS FALSO)';
      default:
        return threat.toUpperCase();
    }
  }

  IconData _threatIcon(String threat) {
    switch (threat) {
      case 'root_jailbreak':
        return Icons.security_outlined;
      case 'emulator':
        return Icons.phone_android_outlined;
      case 'fake_gps':
        return Icons.wrong_location_outlined;
      default:
        return Icons.warning_amber_outlined;
    }
  }

  Future<void> _unblockDevice({
    required String logId,
    required String profileId,
    required String threatType,
  }) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: Text(
          'Desbloquear Motorista',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        content: const Text(
          'Esta ação removerá o alerta de integridade do aparelho e trará o motorista de volta ao status ativo. Confirmar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF096EFF)),
            child: const Text('Desbloquear', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        // 1. Deleta registro da tabela suspicious_devices
        await _supabase.schema('safety').from('suspicious_devices').delete().eq('id', logId);

        // 2. Atualiza status do motorista para offline e aprovado
        await _supabase.from('profiles').update({
          'status': 'offline',
          'is_approved': true,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', profileId);

        // 3. Registra logs no admin_audit_log
        final adminId = _supabase.auth.currentUser?.id ?? 'sistema';
        await _supabase.from('admin_audit_log').insert({
          'admin_id': adminId,
          'action_type': 'unblock_suspicious_device',
          'target_user_id': profileId,
          'details': {
            'threat_released': threatType,
            'released_at': DateTime.now().toUtc().toIso8601String(),
          },
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Motorista e aparelho liberados com sucesso!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erro ao liberar motorista: $e'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Column(
        children: [
          // CABEÇALHO DA TELA
          Container(
            padding: const EdgeInsets.fromLTRB(32, 24, 32, 24),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: const Border(bottom: BorderSide(color: Colors.white10)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Segurança & Integridade de Dispositivos',
                      style: GoogleFonts.outfit(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Monitore e gerencie tentativas de fraude por Root, Emuladores ou GPS Falso.',
                      style: TextStyle(color: Colors.white54, fontSize: 14),
                    ),
                  ],
                ),
                DropdownButton<String>(
                  value: _threatFilter,
                  dropdownColor: theme.colorScheme.surface,
                  underline: const SizedBox(),
                  icon: const Icon(Icons.filter_list, color: Colors.white70),
                  items: const [
                    DropdownMenuItem(value: 'Todos', child: Text('Todas Ameaças')),
                    DropdownMenuItem(value: 'root_jailbreak', child: Text('Root / Jailbreak')),
                    DropdownMenuItem(value: 'emulator', child: Text('Emulador')),
                    DropdownMenuItem(value: 'fake_gps', child: Text('GPS Falso')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _threatFilter = v);
                  },
                ),
              ],
            ),
          ),

          // LISTA DE OCORRÊNCIAS
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _supabase.schema('safety').from('suspicious_devices').stream(primaryKey: ['id']).order('created_at', ascending: false),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(
                    child: Text('Erro ao carregar dados: ${snap.error}', style: const TextStyle(color: Colors.redAccent)),
                  );
                }
                var logs = snap.data ?? [];
                if (_threatFilter != 'Todos') {
                  logs = logs.where((l) => l['threat_type'] == _threatFilter).toList();
                }

                if (logs.isEmpty) {
                  return const Center(
                    child: Text(
                      'Nenhum alerta de integridade ativo.',
                      style: TextStyle(color: Colors.white38, fontSize: 16),
                    ),
                  );
                }

                // Buscamos perfis de motoristas na tabela profiles
                return StreamBuilder<List<Map<String, dynamic>>>(
                  stream: _supabase.from('profiles').stream(primaryKey: ['id']).eq('role', 'driver'),
                  builder: (context, profileSnap) {
                    final profiles = profileSnap.data ?? [];

                    return ListView.builder(
                      padding: const EdgeInsets.all(32),
                      itemCount: logs.length,
                      itemBuilder: (context, index) {
                        final log = logs[index];
                        final threat = log['threat_type']?.toString() ?? 'unknown';
                        final color = _threatColor(threat);
                        final icon = _threatIcon(threat);
                        final dateStr = log['created_at'] != null
                            ? DateTime.parse(log['created_at'].toString()).toLocal().toString().substring(0, 16)
                            : '';

                        final driverId = log['profile_id']?.toString() ?? '';
                        final driverProfile = profiles.firstWhere(
                          (p) => p['id'].toString() == driverId,
                          orElse: () => <String, dynamic>{},
                        );

                        final driverName = driverProfile['full_name']?.toString() ?? 'ID: $driverId';
                        final driverPhone = driverProfile['phone_number']?.toString() ?? 'N/A';
                        final driverStatus = driverProfile['status']?.toString() ?? 'N/A';

                        final details = log['details'] is Map ? log['details'] as Map<String, dynamic> : <String, dynamic>{};

                        return Card(
                          color: theme.colorScheme.surface.withOpacity(0.8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          margin: const EdgeInsets.only(bottom: 16),
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: color.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(icon, color: color, size: 28),
                                ),
                                const SizedBox(width: 20),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: color.withOpacity(0.2),
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(color: color, width: 0.5),
                                            ),
                                            child: Text(
                                              _threatLabel(threat),
                                              style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Text(
                                            dateStr,
                                            style: const TextStyle(color: Colors.white38, fontSize: 12),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        'Motorista: $driverName',
                                        style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Telefone: $driverPhone  •  Status Atual: ${driverStatus.toUpperCase()}',
                                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                                      ),
                                      if (details.isNotEmpty) ...[
                                        const SizedBox(height: 12),
                                        Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: Colors.white10,
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: details.entries.map((entry) {
                                              return Padding(
                                                padding: const EdgeInsets.only(bottom: 4.0),
                                                child: Row(
                                                  children: [
                                                    Text(
                                                      '${entry.key}: ',
                                                      style: const TextStyle(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.bold),
                                                    ),
                                                    Expanded(
                                                      child: Text(
                                                        entry.value.toString(),
                                                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              );
                                            }).toList(),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 20),
                                Center(
                                  child: ElevatedButton(
                                    onPressed: () => _unblockDevice(
                                      logId: log['id'].toString(),
                                      profileId: driverId,
                                      threatType: threat,
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green.shade800,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    child: const Text('Liberar'),
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
            ),
          ),
        ],
      ),
    );
  }
}
