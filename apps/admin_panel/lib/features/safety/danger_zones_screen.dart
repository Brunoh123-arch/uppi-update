import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

class DangerZonesScreen extends StatefulWidget {
  const DangerZonesScreen({super.key});

  @override
  State<DangerZonesScreen> createState() => _DangerZonesScreenState();
}

class _DangerZonesScreenState extends State<DangerZonesScreen> {
  bool _isLoading = false;
  List<Map<String, dynamic>> _dangerZones = [];

  RealtimeChannel? _realtimeChannel;

  @override
  void initState() {
    super.initState();
    _loadDangerZones();
    _startRealtimeListener();
  }

  void _startRealtimeListener() {
    _realtimeChannel = Supabase.instance.client
        .channel('danger_zones_realtime')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'danger_zones',
          callback: (payload) {
            _loadDangerZones(silent: true);
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    _realtimeChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _loadDangerZones({bool silent = false}) async {
    if (!mounted) return;
    if (!silent) setState(() => _isLoading = true);

    try {
      final data = await Supabase.instance.client
          .from('danger_zones')
          .select()
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _dangerZones = List<Map<String, dynamic>>.from(data);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading danger zones: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _editDangerZone(Map<String, dynamic>? zone) {
    final nameCtrl = TextEditingController(text: zone?['name'] ?? '');
    final descCtrl = TextEditingController(text: zone?['description'] ?? '');
    final radiusCtrl = TextEditingController(text: zone?['radius_meters']?.toString() ?? '500');
    final bonusCtrl = TextEditingController(text: zone?['safety_bonus']?.toString() ?? '0.00');
    String riskLevel = zone?['risk_level'] ?? 'high'; // 'medium', 'high', 'critical'
    bool isActive = zone?['is_active'] ?? true;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              title: Text(
                zone == null ? 'Nova Área de Risco' : 'Editar Área de Risco',
                style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nome da Zona (ex: Zona Leste - Alto Risco)',
                        labelStyle: TextStyle(color: Colors.white54),
                      ),
                      style: const TextStyle(color: Colors.white),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: descCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Descrição ou Alerta Especial',
                        labelStyle: TextStyle(color: Colors.white54),
                      ),
                      style: const TextStyle(color: Colors.white),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: radiusCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Raio de Cobertura (metros)',
                        labelStyle: TextStyle(color: Colors.white54),
                      ),
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: bonusCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Taxa Bônus de Segurança (R\$) (Opcional)',
                        labelStyle: TextStyle(color: Colors.white54),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(color: Colors.white),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: riskLevel,
                      dropdownColor: const Color(0xFF1E293B),
                      decoration: const InputDecoration(
                        labelText: 'Nível de Perigo',
                        labelStyle: TextStyle(color: Colors.white54),
                      ),
                      style: const TextStyle(color: Colors.white),
                      items: const [
                        DropdownMenuItem(
                          value: 'medium',
                          child: Text('Médio - Alerta visual', style: TextStyle(color: Colors.yellowAccent)),
                        ),
                        DropdownMenuItem(
                          value: 'high',
                          child: Text('Alto - Confirmação de segurança', style: TextStyle(color: Colors.orangeAccent)),
                        ),
                        DropdownMenuItem(
                          value: 'critical',
                          child: Text('Crítico - Evitar solicitações', style: TextStyle(color: Colors.redAccent)),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) setDialogState(() => riskLevel = val);
                      },
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      title: const Text('Zona Ativa', style: TextStyle(color: Colors.white70)),
                      value: isActive,
                      activeThumbColor: Colors.redAccent,
                      onChanged: (val) => setDialogState(() => isActive = val),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    if (nameCtrl.text.isEmpty) return;

                    final updates = {
                      'name': nameCtrl.text,
                      'description': descCtrl.text,
                      'radius_meters': int.tryParse(radiusCtrl.text) ?? 500,
                      'safety_bonus': double.tryParse(bonusCtrl.text) ?? 0.00,
                      'risk_level': riskLevel,
                      'is_active': isActive,
                      'updated_at': DateTime.now().toIso8601String(),
                    };

                    try {
                      if (zone == null) {
                        // Nova Zona (Usa coordenadas padrão de Belém como placeholder ou centroid)
                        updates['center_latitude'] = -1.4558;
                        updates['center_longitude'] = -48.5024;
                        updates['created_at'] = DateTime.now().toIso8601String();
                        await Supabase.instance.client.from('danger_zones').insert(updates);
                      } else {
                        await Supabase.instance.client
                            .from('danger_zones')
                            .update(updates)
                            .eq('id', zone['id']);
                      }
                      
                      // Auditoria
                      final adminId = Supabase.instance.client.auth.currentUser?.id ?? 'UNKNOWN';
                      await Supabase.instance.client.from('admin_audit_log').insert({
                        'admin_id': adminId,
                        'action_type': zone == null ? 'danger_zone_created' : 'danger_zone_updated',
                        'target_resource_id': nameCtrl.text,
                        'details': updates,
                      });

                      _loadDangerZones();
                      if (context.mounted) Navigator.pop(context);
                    } catch (e) {
                      debugPrint('Error saving danger zone: $e');
                    }
                  },
                  child: const Text('Salvar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Color _getRiskColor(String level) {
    switch (level) {
      case 'medium':
        return Colors.yellowAccent;
      case 'high':
        return Colors.orangeAccent;
      case 'critical':
        return Colors.redAccent;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(32),
            decoration: const BoxDecoration(
              color: Color(0xFF1E293B),
              border: Border(bottom: BorderSide(color: Colors.white10)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Zonas de Risco & Segurança (99 Standard)',
                      style: GoogleFonts.outfit(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Monitore áreas perigosas, configure bônus de risco e envie alertas automáticos.',
                      style: TextStyle(color: Colors.white38, fontSize: 13),
                    ),
                  ],
                ),
                ElevatedButton.icon(
                  onPressed: () => _editDangerZone(null),
                  icon: const Icon(Icons.shield_outlined),
                  label: const Text('NOVA ÁREA DE RISCO'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ),

          // Lista de Zonas
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Colors.redAccent))
                : _dangerZones.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.verified_user_outlined, size: 64, color: Colors.greenAccent),
                            const SizedBox(height: 16),
                            Text(
                              'Nenhuma área de risco cadastrada. Sua operação está segura!',
                              style: GoogleFonts.outfit(color: Colors.white54, fontSize: 16),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(24),
                        itemCount: _dangerZones.length,
                        itemBuilder: (context, index) {
                          final zone = _dangerZones[index];
                          final isActive = zone['is_active'] == true;
                          final levelColor = _getRiskColor(zone['risk_level'] ?? 'high');
                          final bonus = (zone['safety_bonus'] as num?)?.toDouble() ?? 0.0;

                          return Card(
                            color: const Color(0xFF1E293B),
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: const BorderSide(color: Colors.white10),
                            ),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: levelColor.withOpacity(0.12),
                                radius: 24,
                                child: Icon(
                                  Icons.shield,
                                  color: isActive ? levelColor : Colors.white30,
                                  size: 24,
                                ),
                              ),
                              title: Row(
                                children: [
                                  Text(
                                    zone['name'] ?? 'Sem Nome',
                                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: levelColor.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: levelColor.withOpacity(0.3)),
                                    ),
                                    child: Text(
                                      (zone['risk_level'] as String? ?? 'high').toUpperCase(),
                                      style: TextStyle(color: levelColor, fontSize: 9, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 4),
                                  Text(
                                    zone['description'] ?? 'Sem descrição.',
                                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Text(
                                        'Raio: ${zone['radius_meters']}m',
                                        style: const TextStyle(color: Colors.white30, fontSize: 11),
                                      ),
                                      if (bonus > 0) ...[
                                        const SizedBox(width: 12),
                                        Text(
                                          'Bônus: +R\$ ${bonus.toStringAsFixed(2)}/corrida',
                                          style: const TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit, color: Colors.blueAccent),
                                    onPressed: () => _editDangerZone(zone),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.redAccent),
                                    onPressed: () async {
                                      final confirm = await showDialog<bool>(
                                        context: context,
                                        builder: (ctx) => AlertDialog(
                                          title: const Text('Deletar Zona de Perigo?'),
                                          content: Text('Confirmar a exclusão da zona "${zone['name']}"?'),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Navigator.pop(ctx, false),
                                              child: const Text('Cancelar'),
                                            ),
                                            ElevatedButton(
                                              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                              onPressed: () => Navigator.pop(ctx, true),
                                              child: const Text('Deletar'),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (confirm == true) {
                                        await Supabase.instance.client.from('danger_zones').delete().eq('id', zone['id']);
                                        _loadDangerZones();
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
