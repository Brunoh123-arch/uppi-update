import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ionicons/ionicons.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';

/// Botão "Modo Voltar pra Casa" no painel do motorista.
///
/// Quando ativado:
/// - Salva o destino casa no perfil do motorista
/// - Exibe um banner indicando o modo ativo
/// - O backend recebe o destino via coluna `driver_home_destination`
///   na tabela `profiles` e prioriza corridas no caminho
///
/// Uso: adicionar como filho no OnlineOfflineSheet quando o motorista está online.
class GoHomeModeButton extends StatefulWidget {
  const GoHomeModeButton({super.key});

  @override
  State<GoHomeModeButton> createState() => _GoHomeModeButtonState();
}

class _GoHomeModeButtonState extends State<GoHomeModeButton> {
  bool _active = false;
  bool _loading = false;
  String? _homeAddress;

  @override
  void initState() {
    super.initState();
    _loadHomeDestination();
  }

  Future<void> _loadHomeDestination() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      // Carrega endereço casa dos lugares salvos
      final place = await Supabase.instance.client
          .from('saved_places')
          .select('address, lat, lng')
          .eq('user_id', userId)
          .eq('place_type', 'home')
          .maybeSingle();

      if (place != null && mounted) {
        setState(() => _homeAddress = place['address']?.toString());
      }

      // Verifica se modo já está ativo (persiste entre sessões)
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('go_home_mode')
          .eq('id', userId)
          .maybeSingle();

      if (profile != null && mounted) {
        setState(() => _active = profile['go_home_mode'] == true);
      }
    } catch (e) {
      debugPrint('[GoHomeMode] Erro ao carregar: $e');
    }
  }

  Future<void> _toggle() async {
    if (_homeAddress == null && !_active) {
      // Sem endereço casa cadastrado
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(children: [
              Icon(Icons.home_outlined, color: Colors.white),
              SizedBox(width: 12),
              Expanded(child: Text('Cadastre seu endereço de casa no perfil primeiro.')),
            ]),
            backgroundColor: Colors.orange.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
      return;
    }

    setState(() => _loading = true);
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      final newActive = !_active;
      await Supabase.instance.client
          .from('profiles')
          .update({'go_home_mode': newActive})
          .eq('id', userId);

      if (mounted) setState(() => _active = newActive);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(children: [
              Icon(newActive ? Icons.home : Icons.work_outline, color: Colors.white),
              const SizedBox(width: 12),
              Text(newActive
                ? 'Modo "Voltar pra Casa" ativado! Você receberá corridas no caminho.'
                : 'Modo "Voltar pra Casa" desativado.'),
            ]),
            backgroundColor: newActive ? ColorPalette.primary40 : Colors.grey.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      debugPrint('[GoHomeMode] Erro ao togglear: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_homeAddress == null && !_active) {
      // Sem casa cadastrada: mostra botão discreto para cadastrar
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: _loading ? null : _toggle,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: _active
                ? ColorPalette.primary40.withOpacity(0.12)
                : Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _active
                  ? ColorPalette.primary40.withOpacity(0.5)
                  : Colors.white.withOpacity(0.15),
              width: _active ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: _loading
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
                      )
                    : Icon(
                        _active ? Ionicons.home : Ionicons.home_outline,
                        key: ValueKey(_active),
                        size: 18,
                        color: _active ? ColorPalette.primary40 : Colors.white54,
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _active ? 'Modo "Voltar pra Casa" ativo' : 'Voltar pra Casa',
                      style: TextStyle(
                        color: _active ? ColorPalette.primary40 : Colors.white70,
                        fontWeight: _active ? FontWeight.bold : FontWeight.normal,
                        fontSize: 13,
                      ),
                    ),
                    if (_homeAddress != null)
                      Text(
                        _homeAddress!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _active ? ColorPalette.primary40.withOpacity(0.7) : Colors.white38,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
              AnimatedRotation(
                turns: _active ? 0 : 0.5,
                duration: const Duration(milliseconds: 300),
                child: Icon(
                  _active ? Ionicons.checkmark_circle : Ionicons.add_circle_outline,
                  color: _active ? ColorPalette.primary40 : Colors.white38,
                  size: 18,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
