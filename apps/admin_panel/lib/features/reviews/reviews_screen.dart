import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

class ReviewsScreen extends StatefulWidget {
  const ReviewsScreen({super.key});

  @override
  State<ReviewsScreen> createState() => _ReviewsScreenState();
}

class _ReviewsScreenState extends State<ReviewsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _filterType = 'Todas';
  final List<String> _filters = ['Todas', 'Alta (4-5)', 'Média (3)', 'Baixa (1-2)'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: const Border(bottom: BorderSide(color: Colors.white10)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Central de Avaliações',
                    style: GoogleFonts.outfit(fontSize: 28, fontWeight: FontWeight.w600),
                  ),
                  DropdownButton<String>(
                    value: _filterType,
                    dropdownColor: Theme.of(context).colorScheme.surface,
                    underline: const SizedBox(),
                    items: _filters
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _filterType = val);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TabBar(
                controller: _tabController,
                isScrollable: true,
                indicatorColor: Colors.blueAccent,
                labelColor: Colors.blueAccent,
                unselectedLabelColor: Colors.white54,
                tabAlignment: TabAlignment.start,
                tabs: const [
                  Tab(icon: Icon(Icons.reviews, size: 18), text: 'reviews'),
                  Tab(icon: Icon(Icons.feedback, size: 18), text: 'feedbacks'),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _ReviewsTab(
                filterType: _filterType,
                onShowDriverDetails: _showDriverDetails,
                onWarnDriver: _warnDriver,
              ),
              _FeedbacksTab(
                filterType: _filterType,
                onShowDriverDetails: _showDriverDetails,
                onWarnDriver: _warnDriver,
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showDriverDetails(BuildContext context, String driverId) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Carregando perfil: $driverId...')));
  }

  Future<void> _warnDriver(BuildContext context, String driverId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enviar Advertência?'),
        content: const Text('O motorista será notificado sobre as avaliações baixas e uma nota será adicionada ao histórico.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent), child: const Text('Sim, Advertir')),
        ],
      ),
    );

    if (confirm != true) return;

    final adminId = Supabase.instance.client.auth.currentUser?.id ?? 'UNKNOWN';
    try {
      await Supabase.instance.client.from('admin_audit_log').insert({
        'admin_id': adminId,
        'action_type': 'driver_warning',
        'target_user_id': driverId,
        'details': {'reason': 'Baixas avaliações contínuas'},
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Usuário advertido com sucesso!'), backgroundColor: Colors.orange));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao advertir: $e'), backgroundColor: Colors.red));
      }
    }
  }
}

// ─── CARD GENÉRICO DE AVALIAÇÃO ───
Widget _buildReviewCard({
  required BuildContext context,
  required double rating,
  required String text,
  required String subtitle,
  required DateTime date,
  VoidCallback? onWarn,
  VoidCallback? onTap,
  required String source,
  Color badgeColor = Colors.blueAccent,
}) {
  return Card(
    color: Theme.of(context).colorScheme.surface,
    margin: const EdgeInsets.only(bottom: 16),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    child: Padding(
      padding: const EdgeInsets.all(24.0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: rating >= 4
                  ? Colors.greenAccent.withOpacity(0.1)
                  : rating == 3
                      ? Colors.orangeAccent.withOpacity(0.1)
                      : Colors.redAccent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Icon(Icons.star,
                    color: rating >= 4
                        ? Colors.greenAccent
                        : rating == 3
                            ? Colors.orangeAccent
                            : Colors.redAccent,
                    size: 32),
                const SizedBox(height: 4),
                Text(rating.toStringAsFixed(1),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: badgeColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(source, style: TextStyle(color: badgeColor, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('"$text"', style: GoogleFonts.outfit(fontSize: 16, fontStyle: FontStyle.italic)),
                const SizedBox(height: 8),
                Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                const SizedBox(height: 4),
                Text('Data: ${date.toString().substring(0, 16)}', style: const TextStyle(color: Colors.white38, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 24),
          if (onTap != null)
            ElevatedButton.icon(
              onPressed: onTap,
              icon: const Icon(Icons.person, size: 16),
              label: const Text('Ver Perfil'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.white10, foregroundColor: Colors.white),
            ),
          if (onWarn != null) ...[
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: onWarn,
              icon: const Icon(Icons.warning, size: 16),
              label: const Text('Advertir'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            ),
          ],
        ],
      ),
    ),
  );
}


// ─── SUB-WIDGET TAB 2: feedbacks ───
class _FeedbacksTab extends StatefulWidget {
  final String filterType;
  final void Function(BuildContext, String) onShowDriverDetails;
  final void Function(BuildContext, String) onWarnDriver;

  const _FeedbacksTab({
    required this.filterType,
    required this.onShowDriverDetails,
    required this.onWarnDriver,
  });

  @override
  State<_FeedbacksTab> createState() => _FeedbacksTabState();
}

class _FeedbacksTabState extends State<_FeedbacksTab> {
  final List<Map<String, dynamic>> _items = [];
  int _page = 0;
  bool _hasMore = true;
  bool _isLoading = false;
  final ScrollController _scrollController = ScrollController();

  RealtimeChannel? _realtimeChannel;

  @override
  void initState() {
    super.initState();
    _loadMore(reset: true);
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
        _loadMore();
      }
    });
    _startRealtimeListener();
  }

  void _startRealtimeListener() {
    _realtimeChannel = Supabase.instance.client
        .channel('feedbacks_realtime')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'feedbacks',
          callback: (payload) {
            _loadMore(reset: true, silent: true);
          },
        )
        .subscribe();
  }

  @override
  void didUpdateWidget(covariant _FeedbacksTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filterType != widget.filterType) {
      _loadMore(reset: true);
    }
  }

  @override
  void dispose() {
    _realtimeChannel?.unsubscribe();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMore({bool reset = false, bool silent = false}) async {
    if (_isLoading) return;
    if (reset) {
      _page = 0;
      _hasMore = true;
      _items.clear();
    }
    if (!_hasMore) return;

    if (!silent) setState(() => _isLoading = true);

    try {
      const pageSize = 50;
      final from = _page * pageSize;
      final to = from + pageSize - 1;

      var query = Supabase.instance.client
          .from('feedbacks')
          .select();

      if (widget.filterType == 'Alta (4-5)') {
        query = query.gte('rating', 4);
      } else if (widget.filterType == 'Média (3)') {
        query = query.eq('rating', 3);
      } else if (widget.filterType == 'Baixa (1-2)') {
        query = query.lte('rating', 2);
      }

      final data = await query
          .order('created_at', ascending: false)
          .range(from, to);

      if (mounted) {
        setState(() {
          _items.addAll(List<Map<String, dynamic>>.from(data));
          _page++;
          _hasMore = data.length == pageSize;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao buscar feedbacks: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty && !_isLoading) {
      return const Center(child: Text('Nenhum feedback encontrado.', style: TextStyle(color: Colors.white54)));
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(32),
      itemCount: _items.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _items.length) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: CircularProgressIndicator(),
            ),
          );
        }

        final fb = _items[index];
        final rating = (fb['rating'] as num?)?.toDouble() ?? 0.0;
        final text = fb['review'] ?? 'Sem comentário';
        final params = fb['parameters'];
        final driverId = fb['driver_id'] ?? '';
        final riderId = fb['rider_id'] ?? '';
        final rideId = fb['ride_id'] ?? '';
        final date = fb['created_at'] != null ? DateTime.parse(fb['created_at'].toString()).toLocal() : DateTime.now();

        String paramText = '';
        if (params is List && params.isNotEmpty) {
          paramText = '  🏷️ ${params.join(', ')}';
        }

        return _buildReviewCard(
          context: context,
          rating: rating,
          text: '$text$paramText',
          subtitle: 'Corrida: $rideId  •  Motorista: $driverId  •  Passageiro: $riderId',
          date: date,
          onWarn: rating <= 2 ? () => widget.onWarnDriver(context, driverId.toString()) : null,
          onTap: () => widget.onShowDriverDetails(context, driverId.toString()),
          source: 'feedbacks',
          badgeColor: Colors.deepPurpleAccent,
        );
      },
    );
  }
}

// ─── SUB-WIDGET TAB 3: reviews ───
class _ReviewsTab extends StatefulWidget {
  final String filterType;
  final void Function(BuildContext, String) onShowDriverDetails;
  final void Function(BuildContext, String) onWarnDriver;

  const _ReviewsTab({
    required this.filterType,
    required this.onShowDriverDetails,
    required this.onWarnDriver,
  });

  @override
  State<_ReviewsTab> createState() => _ReviewsTabState();
}

class _ReviewsTabState extends State<_ReviewsTab> {
  final List<Map<String, dynamic>> _items = [];
  int _page = 0;
  bool _hasMore = true;
  bool _isLoading = false;
  final ScrollController _scrollController = ScrollController();

  RealtimeChannel? _realtimeChannel;

  @override
  void initState() {
    super.initState();
    _loadMore(reset: true);
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
        _loadMore();
      }
    });
    _startRealtimeListener();
  }

  void _startRealtimeListener() {
    _realtimeChannel = Supabase.instance.client
        .channel('reviews_realtime')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'reviews',
          callback: (payload) {
            _loadMore(reset: true, silent: true);
          },
        )
        .subscribe();
  }

  @override
  void didUpdateWidget(covariant _ReviewsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filterType != widget.filterType) {
      _loadMore(reset: true);
    }
  }

  @override
  void dispose() {
    _realtimeChannel?.unsubscribe();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMore({bool reset = false, bool silent = false}) async {
    if (_isLoading) return;
    if (reset) {
      _page = 0;
      _hasMore = true;
      _items.clear();
    }
    if (!_hasMore) return;

    if (!silent) setState(() => _isLoading = true);

    try {
      const pageSize = 50;
      final from = _page * pageSize;
      final to = from + pageSize - 1;

      var query = Supabase.instance.client
          .from('reviews')
          .select();

      if (widget.filterType == 'Alta (4-5)') {
        query = query.gte('rating', 4);
      } else if (widget.filterType == 'Média (3)') {
        query = query.eq('rating', 3);
      } else if (widget.filterType == 'Baixa (1-2)') {
        query = query.lte('rating', 2);
      }

      final data = await query
          .order('created_at', ascending: false)
          .range(from, to);

      if (mounted) {
        setState(() {
          _items.addAll(List<Map<String, dynamic>>.from(data));
          _page++;
          _hasMore = data.length == pageSize;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao buscar reviews: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty && !_isLoading) {
      return const Center(child: Text('Nenhuma review encontrada.', style: TextStyle(color: Colors.white54)));
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(32),
      itemCount: _items.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _items.length) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: CircularProgressIndicator(),
            ),
          );
        }

        final rv = _items[index];
        final rating = (rv['rating'] as num?)?.toDouble() ?? 0.0;
        final comment = rv['comment'] ?? 'Sem comentário';
        final reviewerId = rv['reviewer_id'] ?? '';
        final reviewedId = rv['reviewed_id'] ?? '';
        final rideId = rv['ride_id'] ?? '';
        final date = rv['created_at'] != null ? DateTime.parse(rv['created_at'].toString()).toLocal() : DateTime.now();

        return _buildReviewCard(
          context: context,
          rating: rating,
          text: comment.toString(),
          subtitle: 'Corrida: $rideId  •  Avaliador: $reviewerId  •  Avaliado: $reviewedId',
          date: date,
          onWarn: rating <= 2 ? () => widget.onWarnDriver(context, reviewedId.toString()) : null,
          onTap: () => widget.onShowDriverDetails(context, reviewedId.toString()),
          source: 'reviews',
          badgeColor: Colors.tealAccent,
        );
      },
    );
  }
}
