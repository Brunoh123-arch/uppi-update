import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class ServicesPricingScreen extends StatefulWidget {
  const ServicesPricingScreen({super.key});

  @override
  State<ServicesPricingScreen> createState() => _ServicesPricingScreenState();
}

class _ServicesPricingScreenState extends State<ServicesPricingScreen> {
  List<Map<String, dynamic>> _surgeZones = [];
  bool _isLoadingSurge = false;

  @override
  void initState() {
    super.initState();
    _loadSurgeZones();
  }

  Future<void> _loadSurgeZones() async {
    if (!mounted) return;
    setState(() => _isLoadingSurge = true);
    try {
      final data = await Supabase.instance.client
          .from('vw_surge_zones')
          .select()
          .order('created_at', ascending: false);
      if (mounted) {
        setState(() {
          _surgeZones = List<Map<String, dynamic>>.from(data);
          _isLoadingSurge = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingSurge = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao carregar zonas surge: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _openServiceDialog({Map<String, dynamic>? service}) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ServiceEditDialog(service: service),
    );
  }

  Future<void> _openSurgeZoneDialog({Map<String, dynamic>? zone}) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _SurgeZoneEditDialog(zone: zone),
    );
    if (result == true) {
      _loadSurgeZones();
    }
  }

  Future<void> _toggleActive(Map<String, dynamic> service) async {
    final current = service['is_active'] as bool? ?? true;
    try {
      await Supabase.instance.client
          .from('services')
          .update({'is_active': !current})
          .eq('id', service['id']);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _toggleSurgeActive(Map<String, dynamic> zone) async {
    final current = zone['is_active'] as bool? ?? true;
    try {
      await Supabase.instance.client
          .from('surge_zones')
          .update({'is_active': !current})
          .eq('id', zone['id']);
      _loadSurgeZones();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao alternar status da zona: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteService(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir Serviço'),
        content: const Text('Tem certeza que deseja excluir este serviço?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await Supabase.instance.client.from('services').delete().eq('id', id);
    }
  }

  Future<void> _deleteSurgeZone(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir Zona Dinâmica'),
        content: const Text('Tem certeza que deseja excluir esta zona de preço dinâmico?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await Supabase.instance.client.from('surge_zones').delete().eq('id', id);
        _loadSurgeZones();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro ao excluir zona: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 110,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: const Border(bottom: BorderSide(color: Colors.white10)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Precificação & Tarifas',
                        style: GoogleFonts.outfit(
                          fontSize: 26,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TabBar(
                        isScrollable: true,
                        tabAlignment: TabAlignment.start,
                        indicatorColor: Colors.orangeAccent,
                        labelColor: Colors.white,
                        unselectedLabelColor: Colors.white38,
                        dividerColor: Colors.transparent,
                        labelStyle: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 14),
                        unselectedLabelStyle: GoogleFonts.outfit(fontSize: 14),
                        tabs: const [
                          Tab(text: 'Categorias de Serviços'),
                          Tab(text: 'Zonas de Preço Dinâmico (Surge)'),
                          Tab(text: 'Simulador de Preço'),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildServicesTab(context),
                _buildSurgeZonesTab(context),
                const _PriceSimulatorTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServicesTab(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 24, 32, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Categorias Ativas',
                style: TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              ElevatedButton.icon(
                onPressed: () => _openServiceDialog(),
                icon: const Icon(Icons.add),
                label: const Text('Novo Serviço'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: Supabase.instance.client
                .from('services')
                .stream(primaryKey: ['id']),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: Text(
                    'Erro: ${snapshot.error}',
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                );
              }
              final services = snapshot.data ?? [];
              if (services.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.category_outlined,
                        size: 64,
                        color: Colors.white24,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Nenhum serviço configurado.',
                        style: TextStyle(color: Colors.white54, fontSize: 18),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: () => _openServiceDialog(),
                        icon: const Icon(Icons.add),
                        label: const Text('Criar Primeiro Serviço'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                );
              }
              return GridView.builder(
                padding: const EdgeInsets.all(32),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 24,
                  mainAxisSpacing: 24,
                  childAspectRatio: 1.8,
                ),
                itemCount: services.length,
                itemBuilder: (context, index) {
                  final service = services[index];
                  final isActive = service['is_active'] as bool? ?? true;
                  final imageUrl = service['image_url'] as String?;

                  return Card(
                    color: Theme.of(context).colorScheme.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  color: Colors.white10,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: imageUrl != null && imageUrl.isNotEmpty
                                    ? ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: Image.network(
                                          imageUrl,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) =>
                                              const Icon(
                                                Icons.directions_car,
                                                color: Colors.white38,
                                                size: 32,
                                              ),
                                        ),
                                      )
                                    : const Icon(
                                        Icons.directions_car,
                                        color: Colors.white38,
                                        size: 32,
                                      ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          service['name'] ?? 'Serviço',
                                          style: GoogleFonts.outfit(
                                            fontSize: 22,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: (service['vehicle_category'] == 'moto'
                                                    ? Colors.orangeAccent
                                                    : Colors.blueAccent)
                                                .withOpacity(0.15),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(
                                              color: (service['vehicle_category'] == 'moto'
                                                      ? Colors.orangeAccent
                                                      : Colors.blueAccent)
                                                  .withOpacity(0.4),
                                            ),
                                          ),
                                          child: Text(
                                            (service['vehicle_category'] as String? ?? 'carro').toUpperCase(),
                                            style: TextStyle(
                                              color: service['vehicle_category'] == 'moto'
                                                  ? Colors.orangeAccent
                                                  : Colors.blueAccent,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (service['description'] != null)
                                      Text(
                                        service['description'],
                                        style: const TextStyle(
                                          color: Colors.white54,
                                          fontSize: 13,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                  ],
                                ),
                              ),
                              Column(
                                children: [
                                  Switch(
                                    value: isActive,
                                    onChanged: (_) => _toggleActive(service),
                                    activeThumbColor: Colors.greenAccent,
                                  ),
                                  Text(
                                    isActive ? 'Ativo' : 'Inativo',
                                    style: TextStyle(
                                      color: isActive
                                          ? Colors.greenAccent
                                          : Colors.white38,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const Spacer(),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _PriceBadge('Tarifa Base', service['base_fare']),
                              _PriceBadge(
                                'Por KM',
                                service['per_km_fare'] ??
                                    service['per_km_price'],
                              ),
                              _PriceBadge(
                                'Por Min',
                                service['per_minute_fare'] ??
                                    service['per_minute_price'],
                              ),
                              _PriceBadge('Mínimo', service['minimum_fare']),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  icon: const Icon(
                                    Icons.edit_outlined,
                                    size: 16,
                                  ),
                                  label: const Text('Editar Tarifas'),
                                  onPressed: () =>
                                      _openServiceDialog(service: service),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.blueAccent,
                                    side: const BorderSide(
                                      color: Colors.blueAccent,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: Colors.redAccent,
                                ),
                                onPressed: () =>
                                    _deleteService(service['id'].toString()),
                                tooltip: 'Excluir serviço',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSurgeZonesTab(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 24, 32, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Zonas Dinâmicas de Alta Demanda',
                style: TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.refresh, color: Colors.white70),
                    onPressed: _loadSurgeZones,
                    tooltip: 'Atualizar Lista',
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () => _openSurgeZoneDialog(),
                    icon: const Icon(Icons.add_location_alt),
                    label: const Text('Nova Zona (Surge)'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orangeAccent.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: _isLoadingSurge
              ? const Center(child: CircularProgressIndicator(color: Colors.orangeAccent))
              : _surgeZones.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.flash_off_outlined,
                            size: 64,
                            color: Colors.white24,
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Nenhuma zona dinâmica cadastrada.',
                            style: TextStyle(color: Colors.white54, fontSize: 18),
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton.icon(
                            onPressed: () => _openSurgeZoneDialog(),
                            icon: const Icon(Icons.add_location_alt),
                            label: const Text('Configurar Primeira Zona'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orangeAccent.shade700,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(32),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 24,
                        mainAxisSpacing: 24,
                        childAspectRatio: 2.2,
                      ),
                      itemCount: _surgeZones.length,
                      itemBuilder: (context, index) {
                        final zone = _surgeZones[index];
                        final isActive = zone['is_active'] as bool? ?? true;
                        final multiplier = (zone['multiplier'] as num?)?.toDouble() ?? 1.0;
                        final expiresAtStr = zone['expires_at'] as String?;
                        DateTime? expiresAt = expiresAtStr != null ? DateTime.tryParse(expiresAtStr) : null;
                        final isExpired = expiresAt != null && expiresAt.isBefore(DateTime.now());

                        return Card(
                          color: Theme.of(context).colorScheme.surface,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(
                              color: isActive && !isExpired ? Colors.orangeAccent.withOpacity(0.4) : Colors.transparent,
                              width: 1.5,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 48,
                                      height: 48,
                                      decoration: BoxDecoration(
                                        color: Colors.orangeAccent.withOpacity(0.1),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.flash_on,
                                        color: Colors.orangeAccent,
                                        size: 28,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            zone['name'] ?? 'Zona Surge',
                                            style: GoogleFonts.outfit(
                                              fontSize: 20,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          Text(
                                            expiresAt != null
                                                ? 'Expira: ${expiresAt.day.toString().padLeft(2, '0')}/${expiresAt.month.toString().padLeft(2, '0')} ${expiresAt.hour.toString().padLeft(2, '0')}:${expiresAt.minute.toString().padLeft(2, '0')}'
                                                : 'Sem Expiração',
                                            style: TextStyle(
                                              color: isExpired ? Colors.redAccent : Colors.white38,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      children: [
                                        Switch(
                                          value: isActive && !isExpired,
                                          onChanged: isExpired ? null : (_) => _toggleSurgeActive(zone),
                                          activeThumbColor: Colors.orangeAccent,
                                        ),
                                        Text(
                                          isExpired
                                              ? 'Expirado'
                                              : (isActive ? 'Ativo' : 'Inativo'),
                                          style: TextStyle(
                                            color: isExpired
                                                ? Colors.redAccent
                                                : (isActive ? Colors.orangeAccent : Colors.white38),
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                const Spacer(),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text('Multiplicador', style: TextStyle(color: Colors.white54, fontSize: 11)),
                                        Text(
                                          '${multiplier.toStringAsFixed(2)}x',
                                          style: GoogleFonts.outfit(
                                            fontSize: 24,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.orangeAccent,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Row(
                                      children: [
                                        OutlinedButton.icon(
                                          icon: const Icon(Icons.edit_location_alt, size: 16),
                                          label: const Text('Editar'),
                                          onPressed: () => _openSurgeZoneDialog(zone: zone),
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: Colors.orangeAccent,
                                            side: const BorderSide(color: Colors.orangeAccent),
                                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                          onPressed: () => _deleteSurgeZone(zone['id'].toString()),
                                          tooltip: 'Excluir Zona',
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _PriceBadge(String label, dynamic value) {
    final val = (value as num?)?.toDouble() ?? 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 11),
        ),
        Text(
          'R\$ ${val.toStringAsFixed(2)}',
          style: GoogleFonts.outfit(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.greenAccent,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// Modal de Edição / Criação de Serviço
// ─────────────────────────────────────────────
class _ServiceEditDialog extends StatefulWidget {
  final Map<String, dynamic>? service;
  const _ServiceEditDialog({this.service});

  @override
  State<_ServiceEditDialog> createState() => _ServiceEditDialogState();
}

class _ServiceEditDialogState extends State<_ServiceEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _baseFareCtrl;
  late final TextEditingController _perKmCtrl;
  late final TextEditingController _perMinCtrl;
  late final TextEditingController _minFareCtrl;
  late final TextEditingController _capacityCtrl;

  bool _isActive = true;
  bool _isSaving = false;
  bool _isUploadingImage = false;
  String? _imageUrl;
  Uint8List? _pickedImageBytes;
  String? _pickedImageName;
  String _vehicleCategory = 'carro';

  bool get _isEditing => widget.service != null;

  @override
  void initState() {
    super.initState();
    final s = widget.service;
    _nameCtrl = TextEditingController(text: s?['name'] ?? '');
    _descCtrl = TextEditingController(text: s?['description'] ?? '');
    _baseFareCtrl = TextEditingController(
      text: s?['base_fare']?.toString() ?? '5.00',
    );
    _perKmCtrl = TextEditingController(
      text: (s?['per_km_fare'] ?? s?['per_km_price'])?.toString() ?? '2.00',
    );
    _perMinCtrl = TextEditingController(
      text:
          (s?['per_minute_fare'] ?? s?['per_minute_price'])?.toString() ??
          '0.50',
    );
    _minFareCtrl = TextEditingController(
      text: s?['minimum_fare']?.toString() ?? '7.00',
    );
    _capacityCtrl = TextEditingController(
      text: s?['capacity']?.toString() ?? '4',
    );
    _isActive = s?['is_active'] as bool? ?? true;
    _imageUrl = s?['image_url'] as String?;
    _vehicleCategory = s?['vehicle_category'] ?? 'carro';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _baseFareCtrl.dispose();
    _perKmCtrl.dispose();
    _perMinCtrl.dispose();
    _minFareCtrl.dispose();
    _capacityCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final xFile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 400,
    );
    if (xFile == null) return;
    final bytes = await xFile.readAsBytes();
    setState(() {
      _pickedImageBytes = bytes;
      _pickedImageName = xFile.name;
    });
  }

  Future<String?> _uploadImage() async {
    if (_pickedImageBytes == null || _pickedImageName == null) return _imageUrl;
    setState(() => _isUploadingImage = true);
    try {
      final path =
          'service_images/${DateTime.now().millisecondsSinceEpoch}_$_pickedImageName';
      await Supabase.instance.client.storage
          .from('service-images')
          .uploadBinary(
            path,
            _pickedImageBytes!,
            fileOptions: const FileOptions(
              upsert: true,
              contentType: 'image/png',
            ),
          );
      final url = Supabase.instance.client.storage
          .from('service-images')
          .getPublicUrl(path);
      return url;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao fazer upload da imagem: $e'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return _imageUrl;
    } finally {
      if (mounted) setState(() => _isUploadingImage = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      final uploadedUrl = await _uploadImage();

      final data = {
        'name': _nameCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'base_fare': double.tryParse(_baseFareCtrl.text) ?? 5.0,
        'per_km_fare': double.tryParse(_perKmCtrl.text) ?? 2.0,
        'per_minute_fare': double.tryParse(_perMinCtrl.text) ?? 0.5,
        'minimum_fare': double.tryParse(_minFareCtrl.text) ?? 7.0,
        'capacity': int.tryParse(_capacityCtrl.text) ?? 4,
        'is_active': _isActive,
        'image_url': uploadedUrl ?? '',
        'vehicle_category': _vehicleCategory,
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (_isEditing) {
        await Supabase.instance.client
            .from('services')
            .update(data)
            .eq('id', widget.service!['id']);
      } else {
        await Supabase.instance.client.from('services').insert(data);
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isEditing
                  ? 'Serviço atualizado com sucesso!'
                  : 'Serviço criado com sucesso!',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao salvar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: 680,
        padding: const EdgeInsets.all(40),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Row(
                  children: [
                    Icon(
                      _isEditing
                          ? Icons.edit_rounded
                          : Icons.add_circle_outline,
                      color: Colors.blueAccent,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _isEditing ? 'Editar Serviço' : 'Novo Serviço',
                      style: GoogleFonts.outfit(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 32),

                // Image picker
                Center(
                  child: GestureDetector(
                    onTap: _pickImage,
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.blueAccent.withOpacity(0.4),
                          width: 2,
                          style: BorderStyle.solid,
                        ),
                      ),
                      child: _isUploadingImage
                          ? const Center(child: CircularProgressIndicator())
                          : _pickedImageBytes != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: Image.memory(
                                _pickedImageBytes!,
                                fit: BoxFit.cover,
                              ),
                            )
                          : (_imageUrl != null && _imageUrl!.isNotEmpty)
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: Image.network(
                                _imageUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    _uploadPlaceholder(),
                              ),
                            )
                          : _uploadPlaceholder(),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Center(
                  child: Text(
                    'Toque para alterar imagem',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ),

                const SizedBox(height: 32),

                // Name + Description
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _nameCtrl,
                        decoration: _inputDecor(
                          'Nome do Serviço',
                          Icons.label_outline,
                        ),
                        validator: (v) => (v == null || v.isEmpty)
                            ? 'Campo obrigatório'
                            : null,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextFormField(
                        controller: _descCtrl,
                        decoration: _inputDecor(
                          'Descrição',
                          Icons.info_outline,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Pricing section
                const Text(
                  'TARIFAS',
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 12,
                    letterSpacing: 2,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),

                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _baseFareCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: _inputDecor(
                          'Tarifa Base (R\$)',
                          Icons.attach_money,
                        ),
                        validator: _validateNumber,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextFormField(
                        controller: _minFareCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: _inputDecor(
                          'Tarifa Mínima (R\$)',
                          Icons.money_off,
                        ),
                        validator: _validateNumber,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _perKmCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: _inputDecor('Por KM (R\$)', Icons.route),
                        validator: _validateNumber,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextFormField(
                        controller: _perMinCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: _inputDecor(
                          'Por Minuto (R\$)',
                          Icons.timer_outlined,
                        ),
                        validator: _validateNumber,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextFormField(
                        controller: _capacityCtrl,
                        keyboardType: TextInputType.number,
                        decoration: _inputDecor(
                          'Capacidade (pessoas)',
                          Icons.people_outline,
                        ),
                        validator: _validateNumber,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _vehicleCategory,
                        dropdownColor: const Color(0xFF1E293B),
                        decoration: _inputDecor('Categoria de Veículo', Icons.category_outlined),
                        items: const [
                          DropdownMenuItem(value: 'carro', child: Text('Carro', style: TextStyle(color: Colors.white))),
                          DropdownMenuItem(value: 'moto', child: Text('Moto', style: TextStyle(color: Colors.white))),
                        ],
                        onChanged: (v) {
                          if (v != null) {
                            setState(() => _vehicleCategory = v);
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Active toggle
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.toggle_on_outlined,
                        color: Colors.white54,
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Serviço ativo no app',
                        style: TextStyle(fontSize: 16),
                      ),
                      const Spacer(),
                      Switch(
                        value: _isActive,
                        onChanged: (v) => setState(() => _isActive = v),
                        activeThumbColor: Colors.greenAccent,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                // Save button
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: _isSaving ? null : _save,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.save),
                    label: Text(
                      _isEditing ? 'Salvar Alterações' : 'Criar Serviço',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.greenAccent,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _uploadPlaceholder() {
    return const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.cloud_upload_outlined, color: Colors.blueAccent, size: 32),
        SizedBox(height: 8),
        Text(
          'Imagem do carro',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white38, fontSize: 11),
        ),
      ],
    );
  }

  InputDecoration _inputDecor(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 20),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      filled: true,
      fillColor: Colors.white.withOpacity(0.05),
    );
  }

  String? _validateNumber(String? v) {
    if (v == null || v.isEmpty) return 'Obrigatório';
    if (double.tryParse(v) == null) return 'Número inválido';
    return null;
  }
}

class _SurgeZoneEditDialog extends StatefulWidget {
  final Map<String, dynamic>? zone;
  const _SurgeZoneEditDialog({this.zone});

  @override
  State<_SurgeZoneEditDialog> createState() => _SurgeZoneEditDialogState();
}

class _SurgeZoneEditDialogState extends State<_SurgeZoneEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _multCtrl;
  
  bool _isActive = true;
  bool _isSaving = false;
  DateTime? _expiresAt;
  
  List<LatLng> _points = [];
  final MapController _mapController = MapController();

  bool get _isEditing => widget.zone != null;

  @override
  void initState() {
    super.initState();
    final z = widget.zone;
    _nameCtrl = TextEditingController(text: z?['name'] ?? '');
    _multCtrl = TextEditingController(text: z?['multiplier']?.toString() ?? '1.50');
    _isActive = z?['is_active'] as bool? ?? true;
    final expiresStr = z?['expires_at'] as String?;
    if (expiresStr != null) {
      _expiresAt = DateTime.tryParse(expiresStr);
    }
    
    final wkt = z?['boundary_wkt'] as String?;
    if (wkt != null && wkt.isNotEmpty) {
      _points = _parseWKT(wkt);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _multCtrl.dispose();
    super.dispose();
  }

  List<LatLng> _parseWKT(String wkt) {
    try {
      final match = RegExp(r'POLYGON\s*\(\((.*?)\)\)', caseSensitive: false).firstMatch(wkt);
      if (match == null) return [];
      final coordsStr = match.group(1)!;
      final points = coordsStr.split(',').map((coord) {
        final parts = coord.trim().split(RegExp(r'\s+'));
        final lng = double.parse(parts[0]);
        final lat = double.parse(parts[1]);
        return LatLng(lat, lng);
      }).toList();
      if (points.length > 1 && points.first == points.last) {
        points.removeLast(); // remove duplicate closing point for easy editing
      }
      return points;
    } catch (e) {
      debugPrint('Erro ao parsear WKT: $e');
      return [];
    }
  }

  String _coordsToWKT(List<LatLng> points) {
    if (points.isEmpty) return '';
    final list = List<LatLng>.from(points);
    if (list.first != list.last) {
      list.add(list.first);
    }
    final coordsStr = list.map((p) => '${p.longitude} ${p.latitude}').join(', ');
    return 'POLYGON(($coordsStr))';
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _expiresAt ?? now.add(const Duration(hours: 4)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null) return;
    if (!mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_expiresAt ?? now.add(const Duration(hours: 4))),
    );
    if (time == null) return;
    setState(() {
      _expiresAt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_points.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, desenhe uma área com pelo menos 3 pontos no mapa.'), backgroundColor: Colors.orange),
      );
      return;
    }
    
    setState(() => _isSaving = true);
    try {
      final wkt = _coordsToWKT(_points);
      
      // Calcular o centroide da área desenhada
      double sumLat = 0;
      double sumLng = 0;
      for (final p in _points) {
        sumLat += p.latitude;
        sumLng += p.longitude;
      }
      final centerLat = sumLat / _points.length;
      final centerLng = sumLng / _points.length;
      
      // Formatar as coordenadas no formato JSON Array [[lng, lat], ...] para polygon_coords
      final coordsJson = _points.map((p) => [p.longitude, p.latitude]).toList();

      final data = {
        'name': _nameCtrl.text.trim(),
        'multiplier': double.tryParse(_multCtrl.text) ?? 1.50,
        'is_active': _isActive,
        'boundary': wkt, // Implicit cast in postgres
        'expires_at': _expiresAt?.toIso8601String(),
        'center_lat': centerLat,
        'center_lng': centerLng,
        'radius_km': 1.0,
        'polygon_coords': coordsJson,
      };

      if (_isEditing) {
        await Supabase.instance.client
            .from('surge_zones')
            .update(data)
            .eq('id', widget.zone!['id']);
      } else {
        await Supabase.instance.client.from('surge_zones').insert(data);
      }

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEditing ? 'Zona dinâmica atualizada!' : 'Zona dinâmica criada com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar zona dinâmica: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: 1100,
        height: 700,
        padding: const EdgeInsets.all(32),
        child: Row(
          children: [
            Expanded(
              flex: 4,
              child: Form(
                key: _formKey,
                child: Padding(
                  padding: const EdgeInsets.only(right: 24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.flash_on, color: Colors.orangeAccent, size: 28),
                          const SizedBox(width: 12),
                          Text(
                            _isEditing ? 'Editar Zona Surge' : 'Nova Zona Surge',
                            style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      TextFormField(
                        controller: _nameCtrl,
                        decoration: InputDecoration(
                          labelText: 'Nome da Região',
                          prefixIcon: const Icon(Icons.map_outlined),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.05),
                        ),
                        validator: (v) => (v == null || v.isEmpty) ? 'Obrigatório' : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _multCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: 'Multiplicador de Tarifa (ex: 1.50)',
                          prefixIcon: const Icon(Icons.trending_up),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.05),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Obrigatório';
                          final val = double.tryParse(v);
                          if (val == null) return 'Número inválido';
                          if (val < 1.0) return 'Multiplicador deve ser >= 1.0';
                          return null;
                        },
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'EXPIRAÇÃO',
                        style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.5),
                      ),
                      const SizedBox(height: 12),
                      InkWell(
                        onTap: _pickDateTime,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.calendar_today, size: 20, color: Colors.orangeAccent),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _expiresAt != null
                                      ? 'Expira em: ${_expiresAt!.day}/${_expiresAt!.month}/${_expiresAt!.year} ${_expiresAt!.hour.toString().padLeft(2, '0')}:${_expiresAt!.minute.toString().padLeft(2, '0')}'
                                      : 'Sem Expiração (Perene)',
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ),
                              if (_expiresAt != null)
                                IconButton(
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: () => setState(() => _expiresAt = null),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      SwitchListTile(
                        title: const Text('Zona ativa imediatamente'),
                        subtitle: const Text('Se desativado, o multiplicador não será aplicado.'),
                        value: _isActive,
                        onChanged: (v) => setState(() => _isActive = v),
                        activeThumbColor: Colors.orangeAccent,
                        contentPadding: EdgeInsets.zero,
                      ),
                      const Spacer(),
                      const Text(
                        'Dica: Clique no mapa ao lado para traçar as bordas da região. Use no mínimo 3 pontos para criar o perímetro.',
                        style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.4),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(context),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                side: const BorderSide(color: Colors.white38),
                                foregroundColor: Colors.white70,
                              ),
                              child: const Text('Cancelar'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _isSaving ? null : _save,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orangeAccent.shade700,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: _isSaving
                                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                  : const Text('Salvar Região', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 6,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Stack(
                  children: [
                    FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: _points.isNotEmpty ? _points.first : const LatLng(-1.4558, -48.5024),
                        initialZoom: 13.0,
                        onTap: (tapPosition, point) {
                          setState(() {
                            _points.add(point);
                          });
                        },
                      ),
                      children: [
                        TileLayer(
                          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.uppi.admin',
                        ),
                        PolygonLayer(
                          polygons: [
                            if (_points.length >= 3)
                              Polygon(
                                points: _points,
                                color: Colors.orange.withOpacity(0.25),
                                borderColor: Colors.orangeAccent.shade700,
                                borderStrokeWidth: 3,
                                isFilled: true,
                              ),
                          ],
                        ),
                        PolylineLayer(
                          polylines: [
                            if (_points.length >= 2)
                              Polyline(
                                points: [..._points, if (_points.length >= 3) _points.first],
                                color: Colors.orangeAccent,
                                strokeWidth: 2,
                              ),
                          ],
                        ),
                        MarkerLayer(
                          markers: _points.asMap().entries.map((entry) {
                            final idx = entry.key;
                            final pt = entry.value;
                            return Marker(
                              point: pt,
                              width: 28,
                              height: 28,
                              child: GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _points.removeAt(idx);
                                  });
                                },
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.redAccent.shade700,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 2),
                                    boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4, spreadRadius: 1)],
                                  ),
                                  child: Center(
                                    child: Text(
                                      '${idx + 1}',
                                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                    Positioned(
                      top: 16,
                      left: 16,
                      right: 16,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A).withOpacity(0.85),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.touch_app, size: 16, color: Colors.orangeAccent),
                                const SizedBox(width: 8),
                                Text(
                                  'Pontos definidos: ${_points.length}',
                                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                          Row(
                            children: [
                              ElevatedButton.icon(
                                onPressed: _points.isEmpty
                                    ? null
                                    : () => setState(() => _points.removeLast()),
                                icon: const Icon(Icons.undo, size: 16),
                                label: const Text('Desfazer'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF1E293B),
                                  foregroundColor: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton.icon(
                                onPressed: _points.isEmpty
                                    ? null
                                    : () => setState(() => _points.clear()),
                                icon: const Icon(Icons.clear, size: 16),
                                label: const Text('Limpar'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.redAccent.shade700,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Aba do Simulador de Preços de Corrida
// ─────────────────────────────────────────────
class _PriceSimulatorTab extends StatefulWidget {
  const _PriceSimulatorTab();

  @override
  State<_PriceSimulatorTab> createState() => _PriceSimulatorTabState();
}

class _PriceSimulatorTabState extends State<_PriceSimulatorTab> {
  final _formKey = GlobalKey<FormState>();
  final _distanceCtrl = TextEditingController(text: '5.0');
  final _durationCtrl = TextEditingController(text: '10');
  final _surgeCtrl = TextEditingController(text: '1.0');

  List<Map<String, dynamic>> _services = [];
  Map<String, dynamic>? _selectedService;
  bool _isLoading = false;

  // Calculos
  double _subtotal = 0.0;
  double _surgeBonus = 0.0;
  double _finalFare = 0.0;
  bool _isMinFareTriggered = false;

  @override
  void initState() {
    super.initState();
    _loadServices();
    _distanceCtrl.addListener(_calculate);
    _durationCtrl.addListener(_calculate);
    _surgeCtrl.addListener(_calculate);
  }

  @override
  void dispose() {
    _distanceCtrl.dispose();
    _durationCtrl.dispose();
    _surgeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadServices() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final data = await Supabase.instance.client
          .from('services')
          .select()
          .order('name', ascending: true);
      if (mounted) {
        setState(() {
          _services = List<Map<String, dynamic>>.from(data);
          if (_services.isNotEmpty) {
            _selectedService = _services.first;
            _calculate();
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao carregar serviços: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _calculate() {
    if (_selectedService == null) return;
    final baseFare = (_selectedService!['base_fare'] as num?)?.toDouble() ?? 0.0;
    final perKm = ((_selectedService!['per_km_fare'] ?? _selectedService!['per_km_price']) as num?)?.toDouble() ?? 0.0;
    final perMin = ((_selectedService!['per_minute_fare'] ?? _selectedService!['per_minute_price']) as num?)?.toDouble() ?? 0.0;
    final minFare = (_selectedService!['minimum_fare'] as num?)?.toDouble() ?? 0.0;

    final km = double.tryParse(_distanceCtrl.text) ?? 0.0;
    final min = double.tryParse(_durationCtrl.text) ?? 0.0;
    final surge = double.tryParse(_surgeCtrl.text) ?? 1.0;

    final computedSubtotal = baseFare + (km * perKm) + (min * perMin);
    final computedFinal = computedSubtotal * surge;

    setState(() {
      _subtotal = computedSubtotal;
      _surgeBonus = computedSubtotal * (surge - 1.0);
      if (computedFinal < minFare) {
        _finalFare = minFare;
        _isMinFareTriggered = true;
      } else {
        _finalFare = computedFinal;
        _isMinFareTriggered = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_services.isEmpty) {
      return const Center(
        child: Text(
          'Nenhum serviço disponível para simulação.',
          style: TextStyle(color: Colors.white54, fontSize: 16),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Painel de Configuração
          Expanded(
            flex: 4,
            child: Card(
              color: Theme.of(context).colorScheme.surface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Parâmetros da Corrida',
                        style: GoogleFonts.outfit(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 24),
                      DropdownButtonFormField<Map<String, dynamic>>(
                        initialValue: _selectedService,
                        dropdownColor: Theme.of(context).colorScheme.surface,
                        decoration: InputDecoration(
                          labelText: 'Categoria de Serviço',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          prefixIcon: const Icon(Icons.directions_car),
                        ),
                        items: _services.map((s) {
                          return DropdownMenuItem<Map<String, dynamic>>(
                            value: s,
                            child: Text(s['name'] ?? 'Serviço'),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _selectedService = val;
                              _calculate();
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _distanceCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: 'Distância Estimada (KM)',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          prefixIcon: const Icon(Icons.map_outlined),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Informe a distância';
                          final val = double.tryParse(v);
                          if (val == null || val < 0) return 'Valor inválido';
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _durationCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: 'Duração Estimada (Minutos)',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          prefixIcon: const Icon(Icons.timer_outlined),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Informe a duração';
                          final val = double.tryParse(v);
                          if (val == null || val < 0) return 'Valor inválido';
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _surgeCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: 'Multiplicador de Preço Dinâmico (Surge)',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          prefixIcon: const Icon(Icons.flash_on),
                          helperText: 'Valor mínimo 1.0 (ex: 1.5 para 50% de acréscimo)',
                          helperStyle: const TextStyle(color: Colors.white38),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Informe o multiplicador';
                          final val = double.tryParse(v);
                          if (val == null || val < 1.0) return 'Multiplicador deve ser >= 1.0';
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 32),
          // Painel de Resultados
          Expanded(
            flex: 5,
            child: Card(
              color: Theme.of(context).colorScheme.surface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Resultado do Cálculo',
                      style: GoogleFonts.outfit(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 24),
                    _buildResultRow('Tarifa Base', 'R\$ ${((_selectedService?['base_fare'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2)}'),
                    _buildResultRow('Distância (${_distanceCtrl.text} KM)', 'R\$ ${((double.tryParse(_distanceCtrl.text) ?? 0.0) * (((_selectedService?['per_km_fare'] ?? _selectedService?['per_km_price']) as num?)?.toDouble() ?? 0.0)).toStringAsFixed(2)}'),
                    _buildResultRow('Duração (${_durationCtrl.text} Min)', 'R\$ ${((double.tryParse(_durationCtrl.text) ?? 0.0) * (((_selectedService?['per_minute_fare'] ?? _selectedService?['per_minute_price']) as num?)?.toDouble() ?? 0.0)).toStringAsFixed(2)}'),
                    const Divider(color: Colors.white10, height: 32),
                    _buildResultRow('Subtotal Estimado', 'R\$ ${_subtotal.toStringAsFixed(2)}'),
                    if (double.tryParse(_surgeCtrl.text) != null && (double.tryParse(_surgeCtrl.text) ?? 1.0) > 1.0)
                      _buildResultRow('Bônus de Surge (${((double.tryParse(_surgeCtrl.text) ?? 1.0) - 1.0) * 100}% extra)', '+ R\$ ${_surgeBonus.toStringAsFixed(2)}', color: Colors.orangeAccent),
                    if (_isMinFareTriggered)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline, color: Colors.amberAccent, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Tarifa Mínima Ativada (Valor mínimo configurado: R\$ ${((_selectedService?['minimum_fare'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2)})',
                                style: const TextStyle(color: Colors.amberAccent, fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const Divider(color: Colors.white10, height: 32),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.greenAccent.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.greenAccent.withOpacity(0.15)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Preço Final Estimado',
                            style: GoogleFonts.outfit(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            'R\$ ${_finalFare.toStringAsFixed(2)}',
                            style: GoogleFonts.outfit(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Colors.greenAccent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 14)),
          Text(value, style: TextStyle(color: color ?? Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
