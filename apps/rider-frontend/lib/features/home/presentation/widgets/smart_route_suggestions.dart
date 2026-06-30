import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';
import 'package:ionicons/ionicons.dart';

/// Widget que mostra sugestões de destino baseadas no histórico do passageiro.
/// Detecta o horário atual e sugere "Ir pro trabalho", "Voltar pra casa", etc.
///
/// Uso: adicionar acima dos outros cards na HomeScreen do passageiro.
class SmartRouteSuggestions extends StatefulWidget {
  const SmartRouteSuggestions({super.key, this.onSuggestionTap});

  /// Callback quando o usuário toca numa sugestão
  final void Function(Map<String, dynamic> suggestion)? onSuggestionTap;

  @override
  State<SmartRouteSuggestions> createState() => _SmartRouteSuggestionsState();
}

class _SmartRouteSuggestionsState extends State<SmartRouteSuggestions> {
  List<_Suggestion> _suggestions = [];
  bool _dismissed = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _loadSuggestions();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadSuggestions() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      final now = DateTime.now();
      final suggestions = <_Suggestion>[];

      // 1. Buscar endereços salvos (casa/trabalho) do usuário
      final savedPlaces = await Supabase.instance.client
          .from('saved_places')
          .select('id, name, address, lat, lng, place_type')
          .eq('user_id', user.id)
          .limit(5);

      // 2. Lógica de sugestão baseada em horário
      final hour = now.hour;
      final isWeekday = now.weekday <= 5;

      // ── Casa → Trabalho (manhã útil: 6h–10h) ──
      if (isWeekday && hour >= 6 && hour < 10) {
        final work = _findPlace(savedPlaces, 'work');
        if (work != null) {
          suggestions.add(_Suggestion(
            icon: Ionicons.briefcase_outline,
            label: 'Ir pro trabalho',
            address: work['address'] ?? '',
            lat: (work['lat'] as num).toDouble(),
            lng: (work['lng'] as num).toDouble(),
            color: Colors.blue,
            data: work,
          ));
        }
      }

      // ── Trabalho → Casa (tarde/noite útil: 17h–21h) ──
      if (isWeekday && hour >= 17 && hour < 21) {
        final home = _findPlace(savedPlaces, 'home');
        if (home != null) {
          suggestions.add(_Suggestion(
            icon: Ionicons.home_outline,
            label: 'Voltar pra casa',
            address: home['address'] ?? '',
            lat: (home['lat'] as num).toDouble(),
            lng: (home['lng'] as num).toDouble(),
            color: ColorPalette.primary40,
            data: home,
          ));
        }
      }

      if (mounted && suggestions.isNotEmpty) {
        setState(() => _suggestions = suggestions);
      }
    } catch (e) {
      debugPrint('[SmartRouteSuggestions] Erro ao carregar sugestões: $e');
    }
  }

  Map<String, dynamic>? _findPlace(List places, String type) {
    try {
      return places.firstWhere(
        (p) => (p['place_type'] ?? '').toString().toLowerCase() == type,
      ) as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  @override
  @override
  Widget build(BuildContext context) {
    if (_dismissed || _suggestions.isEmpty) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark ? Colors.white54 : ColorPalette.neutral50;
    final closeIconColor = isDark ? Colors.white38 : ColorPalette.neutral70;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Sugestões',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: titleColor,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => setState(() => _dismissed = true),
                child: Icon(Ionicons.close_outline, color: closeIconColor, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            child: Row(
              children: _suggestions
                  .map((s) => Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: _SuggestionChip(
                          suggestion: s,
                          onTap: () => widget.onSuggestionTap?.call(s.data),
                        ),
                      ))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _Suggestion {
  const _Suggestion({
    required this.icon,
    required this.label,
    required this.address,
    required this.lat,
    required this.lng,
    required this.color,
    required this.data,
  });

  final IconData icon;
  final String label;
  final String address;
  final double lat;
  final double lng;
  final Color color;
  final Map<String, dynamic> data;
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({required this.suggestion, required this.onTap});

  final _Suggestion suggestion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 220),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: suggestion.color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: suggestion.color.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: suggestion.color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(suggestion.icon, color: suggestion.color, size: 16),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    suggestion.label,
                    style: TextStyle(
                      color: suggestion.color,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    suggestion.address,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isDark ? Colors.white54 : ColorPalette.neutral50,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Ionicons.arrow_forward_circle_outline,
              color: suggestion.color.withValues(alpha: 0.7),
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}
