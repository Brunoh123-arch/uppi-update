import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;


// ─────────────────────────────────────────────
//  Color constants (matches app theme)
// ─────────────────────────────────────────────
const _kPrimary = Color(0xFF096EFF);
const _kSurface = Color(0xFF1E293B);
const _kBackground = Color(0xFF0F172A);
const _kSubtext = Color(0xFF94A3B8);
const _kBorder = Color(0xFF2D3F58);

// ─────────────────────────────────────────────
//  ReportsScreen
// ─────────────────────────────────────────────
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Per-tab date ranges
  DateTime _ridesFrom = DateTime.now().subtract(const Duration(days: 30));
  DateTime _ridesTo = DateTime.now();

  DateTime _driversFrom = DateTime.now().subtract(const Duration(days: 30));
  DateTime _driversTo = DateTime.now();

  DateTime _financialFrom = DateTime.now().subtract(const Duration(days: 30));
  DateTime _financialTo = DateTime.now();

  // Rides tab
  List<Map<String, dynamic>> _ridesData = [];
  bool _ridesLoading = false;

  // Drivers tab
  List<Map<String, dynamic>> _driversData = [];
  bool _driversLoading = false;

  // Financial tab
  List<Map<String, dynamic>> _financialData = [];
  bool _financialLoading = false;

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

  // ──────────────────────────────────────────
  //  CSV Export
  // ──────────────────────────────────────────
  void _exportCsv(List<List<String>> rows, String filename) async {
    try {
      final csv = rows
          .map((r) =>
              r.map((c) => '"${c.replaceAll('"', '""')}"').join(','))
          .join('\n');
      final bytes = utf8.encode(csv);
      final b64 = base64Encode(bytes);
      final uri = Uri.parse('data:text/csv;charset=utf-8;base64,$b64');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, webOnlyWindowName: '_self');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('"$filename" exportado com sucesso!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Falha ao exportar: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  // ──────────────────────────────────────────
  //  Date helpers
  // ──────────────────────────────────────────
  Future<DateTime?> _pickDate(BuildContext ctx, DateTime initial) async {
    return showDatePicker(
      context: ctx,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
              primary: _kPrimary, surface: _kSurface),
        ),
        child: child!,
      ),
    );
  }

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  String _iso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // ──────────────────────────────────────────
  //  RIDES query
  // ──────────────────────────────────────────
  Future<void> _fetchRides() async {
    setState(() => _ridesLoading = true);
    try {
      final client = Supabase.instance.client;
      final data = await client
          .from('rides')
          .select(
              'id, created_at, status, fare, platform_fee, driver:driver_id(full_name), rider:rider_id(full_name)')
          .gte('created_at', '${_iso(_ridesFrom)}T00:00:00')
          .lte('created_at', '${_iso(_ridesTo)}T23:59:59')
          .order('created_at', ascending: false)
          .limit(500);

      if (mounted) setState(() => _ridesData = List<Map<String, dynamic>>.from(data));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro ao buscar corridas: $e')));
      }
    } finally {
      if (mounted) setState(() => _ridesLoading = false);
    }
  }

  // ──────────────────────────────────────────
  //  DRIVERS query
  // ──────────────────────────────────────────
  Future<void> _fetchDrivers() async {
    setState(() => _driversLoading = true);
    try {
      final client = Supabase.instance.client;
      final driversRaw = await client
          .from('profiles')
          .select('id, full_name, phone, status, created_at')
          .eq('role', 'driver')
          .gte('created_at', '${_iso(_driversFrom)}T00:00:00')
          .lte('created_at', '${_iso(_driversTo)}T23:59:59')
          .order('created_at', ascending: false)
          .limit(500);

      final drivers = List<Map<String, dynamic>>.from(driversRaw);

      // Aggregate ride stats
      final ridesRaw = await client
          .from('rides')
          .select('driver_id, fare, driver_rating')
          .eq('status', 'completed')
          .not('driver_id', 'is', null);

      final Map<String, _DriverStats> stats = {};
      for (var r in ridesRaw) {
        final dId = r['driver_id'] as String?;
        if (dId == null) continue;
        stats.putIfAbsent(dId, () => _DriverStats());
        stats[dId]!.totalRides++;
        stats[dId]!.totalEarnings += (r['fare'] as num?)?.toDouble() ?? 0.0;
        if (r['driver_rating'] != null) {
          stats[dId]!.ratingSum += (r['driver_rating'] as num).toDouble();
          stats[dId]!.ratingCount++;
        }
      }

      final merged = drivers.map((d) {
        final s = stats[d['id']] ?? _DriverStats();
        return {
          ...d,
          'total_rides': s.totalRides,
          'avg_rating': s.ratingCount > 0 ? s.ratingSum / s.ratingCount : 0.0,
          'total_earnings': s.totalEarnings,
        };
      }).toList();

      if (mounted) setState(() => _driversData = merged);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro ao buscar motoristas: $e')));
      }
    } finally {
      if (mounted) setState(() => _driversLoading = false);
    }
  }

  // ──────────────────────────────────────────
  //  FINANCIAL query
  // ──────────────────────────────────────────
  Future<void> _fetchFinancial() async {
    setState(() => _financialLoading = true);
    try {
      final client = Supabase.instance.client;
      final raw = await client
          .from('rides')
          .select('created_at, fare, platform_fee')
          .eq('status', 'completed')
          .gte('created_at', '${_iso(_financialFrom)}T00:00:00')
          .lte('created_at', '${_iso(_financialTo)}T23:59:59')
          .order('created_at', ascending: true);

      final Map<String, _DayFinancial> byDay = {};
      for (var row in raw) {
        final dt = DateTime.parse(row['created_at']).toLocal();
        final key =
            '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
        byDay.putIfAbsent(key, () => _DayFinancial(date: key));
        byDay[key]!.count++;
        byDay[key]!.grossRevenue += (row['fare'] as num?)?.toDouble() ?? 0.0;
        byDay[key]!.platformFee +=
            (row['platform_fee'] as num?)?.toDouble() ?? 0.0;
      }

      final result = byDay.values.toList()
        ..sort((a, b) => a.date.compareTo(b.date));

      if (mounted) {
        setState(() => _financialData = result
            .map((d) => {
                  'date': d.date,
                  'count': d.count,
                  'gross_revenue': d.grossRevenue,
                  'platform_fee': d.platformFee,
                  'driver_repasse': d.grossRevenue - d.platformFee,
                })
            .toList());
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro ao buscar financeiro: $e')));
      }
    } finally {
      if (mounted) setState(() => _financialLoading = false);
    }
  }

  // ──────────────────────────────────────────
  //  Export callbacks
  // ──────────────────────────────────────────
  void _exportRidesCsv() {
    final rows = [
      ['ID', 'Data', 'Motorista', 'Passageiro', 'Status', 'Valor (R\$)', 'Comissão (R\$)'],
      ..._ridesData.map((r) => [
            (r['id'] as String?)?.substring(0, 8) ?? '-',
            r['created_at'] != null
                ? _fmt(DateTime.parse(r['created_at']).toLocal())
                : '-',
            ((r['driver'] as Map?)?['full_name'] ?? '-').toString(),
            ((r['rider'] as Map?)?['full_name'] ?? '-').toString(),
            (r['status'] ?? '-').toString(),
            (r['fare'] as num?)?.toStringAsFixed(2) ?? '0.00',
            (r['platform_fee'] as num?)?.toStringAsFixed(2) ?? '0.00',
          ]),
    ];
    _exportCsv(rows, 'corridas_${_iso(_ridesFrom)}_${_iso(_ridesTo)}.csv');
  }

  void _exportDriversCsv() {
    final rows = [
      ['Nome', 'Telefone', 'Status', 'Corridas Totais', 'Avaliação Média', 'Ganhos Totais (R\$)'],
      ..._driversData.map((d) => [
            (d['full_name'] ?? '-').toString(),
            (d['phone'] ?? '-').toString(),
            (d['status'] ?? '-').toString(),
            d['total_rides'].toString(),
            (d['avg_rating'] as double).toStringAsFixed(1),
            (d['total_earnings'] as double).toStringAsFixed(2),
          ]),
    ];
    _exportCsv(rows, 'motoristas_${_iso(_driversFrom)}_${_iso(_driversTo)}.csv');
  }
  void _exportFinancialCsv() {
    final rows = [
      ['Data', 'Total de Corridas', 'Receita Bruta (R\$)', 'Comissão Plataforma (R\$)', 'Repasse Motoristas (R\$)'],
      ..._financialData.map((d) => [
            d['date'].toString(),
            d['count'].toString(),
            (d['gross_revenue'] as double).toStringAsFixed(2),
            (d['platform_fee'] as double).toStringAsFixed(2),
            (d['driver_repasse'] as double).toStringAsFixed(2),
          ]),
    ];
    _exportCsv(rows, 'financeiro_${_iso(_financialFrom)}_${_iso(_financialTo)}.csv');
  }

  Future<void> _exportPdf(
    String title,
    List<String> headers,
    List<List<String>> data,
    String filename,
  ) async {
    try {
      final pdf = pw.Document();
      
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (pw.Context context) {
            return [
              pw.Header(
                level: 0,
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'Uppi - Relatorios Operacionais',
                      style: pw.TextStyle(
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.blue700,
                      ),
                    ),
                    pw.Text(
                      DateTime.now().toLocal().toString().substring(0, 16),
                      style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),
              pw.Text(
                title,
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.grey900,
                ),
              ),
              pw.SizedBox(height: 10),
              pw.Divider(color: PdfColors.grey300),
              pw.SizedBox(height: 15),
              pw.TableHelper.fromTextArray(
                headers: headers,
                data: data,
                border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                headerStyle: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                ),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColors.blue700,
                ),
                cellAlignment: pw.Alignment.centerLeft,
                cellStyle: const pw.TextStyle(fontSize: 9),
                rowDecoration: const pw.BoxDecoration(
                  border: pw.Border(
                    bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
                  ),
                ),
              ),
            ];
          },
        ),
      );

      final bytes = await pdf.save();
      final b64 = base64Encode(bytes);
      final uri = Uri.parse('data:application/pdf;base64,$b64');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, webOnlyWindowName: '_blank');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('"$filename" exportado com sucesso!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Falha ao exportar PDF: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _exportRidesPdf() {
    final headers = ['ID', 'Data', 'Motorista', 'Passageiro', 'Status', 'Valor', 'Comissao'];
    final data = _ridesData.map((r) => [
          (r['id'] as String?)?.substring(0, 8) ?? '-',
          r['created_at'] != null
              ? _fmt(DateTime.parse(r['created_at']).toLocal())
              : '-',
          ((r['driver'] as Map?)?['full_name'] ?? '-').toString(),
          ((r['rider'] as Map?)?['full_name'] ?? '-').toString(),
          (r['status'] ?? '-').toString().toUpperCase(),
          'R\$ ${(r['fare'] as num?)?.toStringAsFixed(2) ?? '0.00'}',
          'R\$ ${(r['platform_fee'] as num?)?.toStringAsFixed(2) ?? '0.00'}',
        ]).toList();
    _exportPdf(
      'Relatorio de Corridas - Uppi',
      headers,
      data,
      'corridas_${_iso(_ridesFrom)}_${_iso(_ridesTo)}.pdf',
    );
  }

  void _exportDriversPdf() {
    final headers = ['Nome', 'Telefone', 'Status', 'Corridas Totais', 'Avaliacao', 'Ganhos'];
    final data = _driversData.map((d) => [
          (d['full_name'] ?? '-').toString(),
          (d['phone'] ?? '-').toString(),
          (d['status'] ?? '-').toString().toUpperCase(),
          d['total_rides'].toString(),
          (d['avg_rating'] as double).toStringAsFixed(1),
          'R\$ ${(d['total_earnings'] as double).toStringAsFixed(2)}',
        ]).toList();
    _exportPdf(
      'Relatorio de Desempenho de Motoristas - Uppi',
      headers,
      data,
      'motoristas_${_iso(_driversFrom)}_${_iso(_driversTo)}.pdf',
    );
  }

  void _exportFinancialPdf() {
    final headers = ['Data', 'Corridas', 'Receita Bruta', 'Comissao App', 'Repasse Motorista'];
    final data = _financialData.map((d) => [
          d['date'].toString(),
          d['count'].toString(),
          'R\$ ${(d['gross_revenue'] as double).toStringAsFixed(2)}',
          'R\$ ${(d['platform_fee'] as double).toStringAsFixed(2)}',
          'R\$ ${(d['driver_repasse'] as double).toStringAsFixed(2)}',
        ]).toList();
    _exportPdf(
      'Relatorio Financeiro Diario - Uppi',
      headers,
      data,
      'financeiro_${_iso(_financialFrom)}_${_iso(_financialTo)}.pdf',
    );
  }
  // ──────────────────────────────────────────
  //  Build
  // ──────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(32, 32, 32, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _kPrimary.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.assessment_rounded,
                        color: _kPrimary, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Relatórios & Exportação',
                        style: GoogleFonts.outfit(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        'Filtre por período e exporte dados em CSV.',
                        style: GoogleFonts.outfit(
                            fontSize: 13, color: _kSubtext),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // TabBar
              Container(
                decoration: BoxDecoration(
                  color: _kSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _kBorder),
                ),
                padding: const EdgeInsets.all(4),
                child: TabBar(
                  controller: _tabController,
                  indicator: BoxDecoration(
                    color: _kPrimary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  labelColor: Colors.white,
                  unselectedLabelColor: _kSubtext,
                  labelStyle: GoogleFonts.outfit(
                      fontWeight: FontWeight.w600, fontSize: 14),
                  unselectedLabelStyle: GoogleFonts.outfit(fontSize: 14),
                  tabs: const [
                    Tab(text: 'Corridas'),
                    Tab(text: 'Motoristas'),
                    Tab(text: 'Financeiro'),
                  ],
                ),
              ),
            ],
          ),
        ),
        // TabBarView
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              // ── TAB 1: Corridas ─────────────
              _buildRidesTab(),
              // ── TAB 2: Motoristas ───────────
              _buildDriversTab(),
              // ── TAB 3: Financeiro ───────────
              _buildFinancialTab(),
            ],
          ),
        ),
      ],
    );
  }

  // ──────────────────────────────────────────
  //  TAB 1 – Corridas
  // ──────────────────────────────────────────
  Widget _buildRidesTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DateRangeRow(
            fromDate: _ridesFrom,
            toDate: _ridesTo,
            onPickFrom: () async {
              final d = await _pickDate(context, _ridesFrom);
              if (d != null) setState(() => _ridesFrom = d);
            },
            onPickTo: () async {
              final d = await _pickDate(context, _ridesTo);
              if (d != null) setState(() => _ridesTo = d);
            },
            onSearch: _fetchRides,
            onExport: _ridesData.isEmpty ? null : _exportRidesCsv,
            onExportPdf: _ridesData.isEmpty ? null : _exportRidesPdf,
            formatDate: _fmt,
          ),
          const SizedBox(height: 24),
          if (_ridesLoading)
            const Center(
                child: Padding(
                    padding: EdgeInsets.all(48),
                    child: CircularProgressIndicator()))
          else if (_ridesData.isEmpty)
            const _EmptyState(
                message: 'Nenhuma corrida encontrada. Clique em "Buscar".')
          else
            _TableCard(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(
                      _kBackground.withOpacity(0.6)),
                  dataRowColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.hovered)) {
                      return _kPrimary.withOpacity(0.05);
                    }
                    return null;
                  }),
                  dividerThickness: 0.5,
                  columnSpacing: 24,
                  columns: [
                    _col('ID'),
                    _col('Data'),
                    _col('Motorista'),
                    _col('Passageiro'),
                    _col('Status'),
                    _col('Valor (R\$)'),
                    _col('Comissão (R\$)'),
                  ],
                  rows: _ridesData.map((r) {
                    final id = (r['id'] as String?)?.substring(0, 8) ?? '-';
                    final dt = r['created_at'] != null
                        ? _fmt(DateTime.parse(r['created_at']).toLocal())
                        : '-';
                    final driver =
                        ((r['driver'] as Map?)?['full_name'] ?? '-').toString();
                    final rider =
                        ((r['rider'] as Map?)?['full_name'] ?? '-').toString();
                    final status = r['status'] as String?;
                    final fare =
                        (r['fare'] as num?)?.toStringAsFixed(2) ?? '0.00';
                    final fee = (r['platform_fee'] as num?)
                            ?.toStringAsFixed(2) ??
                        '0.00';

                    return DataRow(cells: [
                      DataCell(Text(id,
                          style: GoogleFonts.outfit(
                              color: _kSubtext, fontSize: 13))),
                      DataCell(Text(dt,
                          style: GoogleFonts.outfit(fontSize: 13))),
                      DataCell(Text(driver,
                          style: GoogleFonts.outfit(
                              fontWeight: FontWeight.w500,
                              fontSize: 13))),
                      DataCell(Text(rider,
                          style: GoogleFonts.outfit(fontSize: 13))),
                      DataCell(_StatusChip(status: status)),
                      DataCell(Text('R\$ $fare',
                          style: GoogleFonts.outfit(
                              color: Colors.greenAccent,
                              fontWeight: FontWeight.w600,
                              fontSize: 13))),
                      DataCell(Text('R\$ $fee',
                          style: GoogleFonts.outfit(
                              color: Colors.orangeAccent,
                              fontWeight: FontWeight.w600,
                              fontSize: 13))),
                    ]);
                  }).toList(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────
  //  TAB 2 – Motoristas
  // ──────────────────────────────────────────
  Widget _buildDriversTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DateRangeRow(
            fromDate: _driversFrom,
            toDate: _driversTo,
            onPickFrom: () async {
              final d = await _pickDate(context, _driversFrom);
              if (d != null) setState(() => _driversFrom = d);
            },
            onPickTo: () async {
              final d = await _pickDate(context, _driversTo);
              if (d != null) setState(() => _driversTo = d);
            },
            onSearch: _fetchDrivers,
            onExport: _driversData.isEmpty ? null : _exportDriversCsv,
            onExportPdf: _driversData.isEmpty ? null : _exportDriversPdf,
            formatDate: _fmt,
          ),
          const SizedBox(height: 24),
          if (_driversLoading)
            const Center(
                child: Padding(
                    padding: EdgeInsets.all(48),
                    child: CircularProgressIndicator()))
          else if (_driversData.isEmpty)
            const _EmptyState(
                message:
                    'Nenhum motorista cadastrado no período. Clique em "Buscar".')
          else
            _TableCard(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(
                      _kBackground.withOpacity(0.6)),
                  dataRowColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.hovered)) {
                      return _kPrimary.withOpacity(0.05);
                    }
                    return null;
                  }),
                  dividerThickness: 0.5,
                  columnSpacing: 24,
                  columns: [
                    _col('Nome'),
                    _col('Telefone'),
                    _col('Status'),
                    _col('Corridas Totais'),
                    _col('Avaliação Média'),
                    _col('Ganhos Totais (R\$)'),
                  ],
                  rows: _driversData.map((d) {
                    final name = (d['full_name'] ?? '-').toString();
                    final phone = (d['phone'] ?? '-').toString();
                    final status = (d['status'] ?? '-').toString();
                    final rides = d['total_rides'] as int;
                    final avg = d['avg_rating'] as double;
                    final earnings = d['total_earnings'] as double;

                    return DataRow(cells: [
                      DataCell(Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircleAvatar(
                            radius: 14,
                            backgroundColor: _kPrimary.withOpacity(0.15),
                            child: Text(
                              name.isNotEmpty
                                  ? name[0].toUpperCase()
                                  : '?',
                              style: GoogleFonts.outfit(
                                  color: _kPrimary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(name,
                              style: GoogleFonts.outfit(
                                  fontWeight: FontWeight.w500,
                                  fontSize: 13)),
                        ],
                      )),
                      DataCell(Text(phone,
                          style: GoogleFonts.outfit(
                              fontSize: 13, color: _kSubtext))),
                      DataCell(Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: status == 'active'
                              ? Colors.greenAccent.withOpacity(0.12)
                              : Colors.redAccent.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          status,
                          style: GoogleFonts.outfit(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: status == 'active'
                                  ? Colors.greenAccent
                                  : Colors.redAccent),
                        ),
                      )),
                      DataCell(Text(rides.toString(),
                          style: GoogleFonts.outfit(
                              fontWeight: FontWeight.w600,
                              fontSize: 13))),
                      DataCell(Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star_rounded,
                              color: Colors.amber, size: 16),
                          const SizedBox(width: 4),
                          Text(
                            avg > 0 ? avg.toStringAsFixed(1) : '-',
                            style: GoogleFonts.outfit(
                                fontWeight: FontWeight.w600,
                                fontSize: 13),
                          ),
                        ],
                      )),
                      DataCell(Text('R\$ ${earnings.toStringAsFixed(2)}',
                          style: GoogleFonts.outfit(
                              color: Colors.greenAccent,
                              fontWeight: FontWeight.w600,
                              fontSize: 13))),
                    ]);
                  }).toList(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────
  //  TAB 3 – Financeiro
  // ──────────────────────────────────────────
  Widget _buildFinancialTab() {
    double totalGross = 0, totalFee = 0, totalRepasse = 0;
    int totalRides = 0;
    for (final d in _financialData) {
      totalGross += d['gross_revenue'] as double;
      totalFee += d['platform_fee'] as double;
      totalRepasse += d['driver_repasse'] as double;
      totalRides += d['count'] as int;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DateRangeRow(
            fromDate: _financialFrom,
            toDate: _financialTo,
            onPickFrom: () async {
              final d = await _pickDate(context, _financialFrom);
              if (d != null) setState(() => _financialFrom = d);
            },
            onPickTo: () async {
              final d = await _pickDate(context, _financialTo);
              if (d != null) setState(() => _financialTo = d);
            },
            onSearch: _fetchFinancial,
            onExport: _financialData.isEmpty ? null : _exportFinancialCsv,
            onExportPdf: _financialData.isEmpty ? null : _exportFinancialPdf,
            formatDate: _fmt,
          ),
          const SizedBox(height: 24),
          if (_financialLoading)
            const Center(
                child: Padding(
                    padding: EdgeInsets.all(48),
                    child: CircularProgressIndicator()))
          else if (_financialData.isEmpty)
            const _EmptyState(
                message: 'Nenhuma corrida concluída no período. Clique em "Buscar".')
          else ...[
            // Summary cards
            Row(
              children: [
                _FinanceSummaryCard(
                    label: 'Total de Corridas',
                    value: totalRides.toString(),
                    icon: Icons.route_rounded,
                    color: Colors.blueAccent),
                const SizedBox(width: 16),
                _FinanceSummaryCard(
                    label: 'Receita Bruta',
                    value: 'R\$ ${totalGross.toStringAsFixed(2)}',
                    icon: Icons.attach_money_rounded,
                    color: Colors.greenAccent),
                const SizedBox(width: 16),
                _FinanceSummaryCard(
                    label: 'Comissão Plataforma',
                    value: 'R\$ ${totalFee.toStringAsFixed(2)}',
                    icon: Icons.percent_rounded,
                    color: Colors.orangeAccent),
                const SizedBox(width: 16),
                _FinanceSummaryCard(
                    label: 'Repasse Motoristas',
                    value: 'R\$ ${totalRepasse.toStringAsFixed(2)}',
                    icon: Icons.people_rounded,
                    color: Colors.purpleAccent),
              ],
            ),
            const SizedBox(height: 24),
            _TableCard(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(
                      _kBackground.withOpacity(0.6)),
                  dataRowColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.hovered)) {
                      return _kPrimary.withOpacity(0.05);
                    }
                    return null;
                  }),
                  dividerThickness: 0.5,
                  columnSpacing: 24,
                  columns: [
                    _col('Data'),
                    _col('Total de Corridas'),
                    _col('Receita Bruta (R\$)'),
                    _col('Comissão Plataforma (R\$)'),
                    _col('Repasse Motoristas (R\$)'),
                  ],
                  rows: _financialData.map((d) {
                    return DataRow(cells: [
                      DataCell(Text(d['date'].toString(),
                          style: GoogleFonts.outfit(
                              fontWeight: FontWeight.w600, fontSize: 13))),
                      DataCell(Text(d['count'].toString(),
                          style: GoogleFonts.outfit(fontSize: 13))),
                      DataCell(Text(
                          'R\$ ${(d['gross_revenue'] as double).toStringAsFixed(2)}',
                          style: GoogleFonts.outfit(
                              color: Colors.greenAccent,
                              fontWeight: FontWeight.w600,
                              fontSize: 13))),
                      DataCell(Text(
                          'R\$ ${(d['platform_fee'] as double).toStringAsFixed(2)}',
                          style: GoogleFonts.outfit(
                              color: Colors.orangeAccent,
                              fontWeight: FontWeight.w600,
                              fontSize: 13))),
                      DataCell(Text(
                          'R\$ ${(d['driver_repasse'] as double).toStringAsFixed(2)}',
                          style: GoogleFonts.outfit(
                              color: Colors.purpleAccent,
                              fontWeight: FontWeight.w600,
                              fontSize: 13))),
                    ]);
                  }).toList(),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Helper data classes
// ─────────────────────────────────────────────
class _DriverStats {
  int totalRides = 0;
  double totalEarnings = 0.0;
  double ratingSum = 0.0;
  int ratingCount = 0;
}

class _DayFinancial {
  final String date;
  int count = 0;
  double grossRevenue = 0.0;
  double platformFee = 0.0;
  _DayFinancial({required this.date});
}

// ─────────────────────────────────────────────
//  Shared widgets
// ─────────────────────────────────────────────
class _DateRangeRow extends StatelessWidget {
  final DateTime fromDate;
  final DateTime toDate;
  final VoidCallback onPickFrom;
  final VoidCallback onPickTo;
  final VoidCallback onSearch;
  final VoidCallback? onExport;
  final VoidCallback? onExportPdf;
  final String Function(DateTime) formatDate;

  const _DateRangeRow({
    required this.fromDate,
    required this.toDate,
    required this.onPickFrom,
    required this.onPickTo,
    required this.onSearch,
    required this.onExport,
    required this.onExportPdf,
    required this.formatDate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _DateField(label: 'De', value: formatDate(fromDate), onTap: onPickFrom),
          _DateField(label: 'Até', value: formatDate(toDate), onTap: onPickTo),
          SizedBox(
            height: 44,
            child: ElevatedButton.icon(
              onPressed: onSearch,
              icon: const Icon(Icons.search_rounded, size: 18),
              label: Text('Buscar',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          SizedBox(
            height: 44,
            child: OutlinedButton.icon(
              onPressed: onExport,
              icon: const Icon(Icons.download_rounded, size: 18),
              label: Text('Exportar CSV',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                foregroundColor:
                    onExport != null ? Colors.greenAccent : _kSubtext,
                side: BorderSide(
                    color: onExport != null
                        ? Colors.greenAccent.withOpacity(0.6)
                        : _kBorder),
                padding: const EdgeInsets.symmetric(horizontal: 24),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          SizedBox(
            height: 44,
            child: OutlinedButton.icon(
              onPressed: onExportPdf,
              icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
              label: Text('Exportar PDF',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                foregroundColor:
                    onExportPdf != null ? Colors.redAccent : _kSubtext,
                side: BorderSide(
                    color: onExportPdf != null
                        ? Colors.redAccent.withOpacity(0.6)
                        : _kBorder),
                padding: const EdgeInsets.symmetric(horizontal: 24),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;

  const _DateField(
      {required this.label, required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: _kBackground,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _kBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$label: ',
                style: GoogleFonts.outfit(color: _kSubtext, fontSize: 13)),
            Text(value,
                style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            const Icon(Icons.calendar_today_rounded,
                size: 14, color: _kPrimary),
          ],
        ),
      ),
    );
  }
}

class _TableCard extends StatelessWidget {
  final Widget child;
  const _TableCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
      ),
      child: child,
    );
  }
}

DataColumn _col(String label) => DataColumn(
      label: Text(label,
          style: GoogleFonts.outfit(
              color: _kSubtext,
              fontWeight: FontWeight.w600,
              fontSize: 12)),
    );

class _StatusChip extends StatelessWidget {
  final String? status;
  const _StatusChip({this.status});

  @override
  Widget build(BuildContext context) {
    final color = _color(status);
    final label = _label(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(label,
          style: GoogleFonts.outfit(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color)),
    );
  }

  static Color _color(String? s) {
    switch (s) {
      case 'completed':
        return Colors.greenAccent;
      case 'canceled':
      case 'driver_canceled':
      case 'rider_canceled':
        return Colors.redAccent;
      case 'in_progress':
        return Colors.blueAccent;
      default:
        return Colors.orangeAccent;
    }
  }

  static String _label(String? s) {
    switch (s) {
      case 'completed':
        return 'Concluída';
      case 'canceled':
      case 'driver_canceled':
      case 'rider_canceled':
        return 'Cancelada';
      case 'in_progress':
        return 'Em Viagem';
      case 'requested':
      case 'searching':
        return 'Procurando';
      default:
        return s ?? '-';
    }
  }
}

class _FinanceSummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _FinanceSummaryCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _kSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _kBorder),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: GoogleFonts.outfit(
                          fontSize: 12, color: _kSubtext)),
                  const SizedBox(height: 4),
                  Text(value,
                      style: GoogleFonts.outfit(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String message;
  const _EmptyState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(64),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox_rounded,
              size: 48, color: _kSubtext.withOpacity(0.4)),
          const SizedBox(height: 16),
          Text(message,
              style: GoogleFonts.outfit(color: _kSubtext, fontSize: 15),
              textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text('Selecione o período e clique em "Buscar".',
              style: GoogleFonts.outfit(
                  color: _kSubtext.withOpacity(0.6), fontSize: 13)),
        ],
      ),
    );
  }
}
