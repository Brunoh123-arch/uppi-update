import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:ionicons/ionicons.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';
import 'package:flutter_common/core/extensions/extensions.dart';
import 'package:flutter_common/core/utils/friendly_error.dart';
import 'package:flutter_common/core/presentation/buttons/app_primary_button.dart';
import 'package:flutter_common/core/presentation/buttons/app_bordered_button.dart';
import 'package:flutter_common/core/presentation/card_handle.dart';

/// Widget de gorjeta pós-corrida no padrão Uppi
/// Mostra 3 sugestões + campo customizado
/// 100% do valor vai pro motorista (sem comissão da plataforma)
class TipSheet extends StatefulWidget {
  final String orderId;
  final double fareCost;
  final String driverName;
  final String currency;
  final Future<void> Function(double amount)? onSendTip;
  final Future<Map<String, dynamic>> Function()? onFetchSuggestions;
  final VoidCallback? onTipSent;
  final VoidCallback? onSkip;

  const TipSheet({
    super.key,
    required this.orderId,
    required this.fareCost,
    required this.driverName,
    this.currency = 'BRL',
    this.onSendTip,
    this.onFetchSuggestions,
    this.onTipSent,
    this.onSkip,
  });

  @override
  State<TipSheet> createState() => _TipSheetState();
}

class _TipSheetState extends State<TipSheet>
    with SingleTickerProviderStateMixin {
  int? selectedIndex;
  double? customAmount;
  bool isSending = false;
  bool tipSent = false;
  bool alreadyTipped = false;
  bool loadingSuggestions = true;
  late AnimationController _checkController;
  late Animation<double> _checkAnimation;

  // Sugestões carregadas do backend (reais) ou fallback local
  List<double> suggestions = [];

  @override
  void initState() {
    super.initState();
    _checkController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _checkAnimation = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(parent: _checkController, curve: Curves.elasticOut),
    );

    // Pré-preencher com fallback local (evita tela vazia)
    suggestions = [
      _roundToNice(widget.fareCost * 0.10),
      _roundToNice(widget.fareCost * 0.15),
      _roundToNice(widget.fareCost * 0.20),
    ];

    _loadSuggestionsFromBackend();
  }

  /// Carrega sugestões reais calculadas pelo backend
  /// (baseado no costAfterCoupon real da corrida, não no fareCost do widget)
  Future<void> _loadSuggestionsFromBackend() async {
    try {
      if (widget.onFetchSuggestions != null) {
        final data = await widget.onFetchSuggestions!();
        if (mounted) {
          final rawSuggestions = data['suggestions'] as List<dynamic>? ?? [];
          final backendSuggestions = rawSuggestions
              .map((s) => (s as num).toDouble())
              .toList();
          final already = data['alreadyTipped'] as bool? ?? false;

          setState(() {
            if (backendSuggestions.isNotEmpty) {
              suggestions = backendSuggestions;
            }
            alreadyTipped = already;
            tipSent = already; // Já deu gorjeta — mostra tela de sucesso
            loadingSuggestions = false;
          });
        }
      } else {
        if (mounted) setState(() => loadingSuggestions = false);
      }
    } catch (_) {
      // Mantém fallback local — não bloqueia a UI
      if (mounted) setState(() => loadingSuggestions = false);
    }
  }

  @override
  void dispose() {
    _checkController.dispose();
    super.dispose();
  }

  double _roundToNice(double value) {
    if (value < 1) return 1;
    if (value < 5) return (value).ceilToDouble();
    return (value / 5).ceil() * 5.0;
  }

  double? get selectedAmount {
    if (selectedIndex != null && selectedIndex! < suggestions.length) {
      return suggestions[selectedIndex!];
    }
    if (selectedIndex == suggestions.length && customAmount != null) {
      return customAmount;
    }
    return null;
  }

  Future<void> _sendTip() async {
    final amount = selectedAmount;
    if (amount == null || amount <= 0) return;

    setState(() => isSending = true);

    try {
      if (widget.onSendTip != null) {
        await widget.onSendTip!(amount);
      }

      setState(() {
        tipSent = true;
        isSending = false;
      });

      _checkController.forward();
      await Future.delayed(const Duration(seconds: 2));
      widget.onTipSent?.call();
    } catch (e) {
      setState(() => isSending = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyErrorMessage(e, fallback: 'Não foi possível enviar a gorjeta.')),
            backgroundColor: ColorPalette.error40,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (tipSent) return _buildSuccessView(context);

    return Container(
      decoration: context.responsive(
        const BoxDecoration(
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          color: ColorPalette.neutralVariant99,
          boxShadow: [
            BoxShadow(
              color: Color(0x3F0E275D),
              blurRadius: 20,
              offset: Offset(2, 4),
            ),
          ],
        ),
        xl: const BoxDecoration(),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          const CardHandle(),

          // Ícone
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: ColorPalette.semanticgreen60,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: ColorPalette.semanticgreen50.withValues(alpha: 0.25),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Icon(Ionicons.heart, color: Colors.white, size: 28),
          ),
          const SizedBox(height: 12),
          Text('Gostou da corrida?', style: context.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Deixe uma gorjeta para ${widget.driverName}',
            style: context.bodyMedium?.copyWith(
              color: ColorPalette.neutralVariant50,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '100% do valor vai direto pro motorista 💚',
            style: context.bodySmall?.copyWith(
              color: ColorPalette.semanticgreen50,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 20),

          // Sugestões de valor
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (int i = 0; i < suggestions.length; i++) ...[
                  if (i > 0) const SizedBox(width: 12),
                  _buildSuggestionChip(context, i, suggestions[i]),
                ],
                const SizedBox(width: 12),
                _buildCustomChip(context),
              ],
            ),
          ),

          // Campo customizado
          if (selectedIndex == suggestions.length) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: 120,
              child: CupertinoTextField(
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textAlign: TextAlign.center,
                style: context.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                prefix: Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Text(
                    'R\$',
                    style: context.titleMedium?.copyWith(
                      color: ColorPalette.neutralVariant50,
                    ),
                  ),
                ),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: ColorPalette.primary50, width: 2),
                  ),
                ),
                onChanged: (value) {
                  setState(() {
                    customAmount = double.tryParse(value.replaceAll(',', '.'));
                  });
                },
              ),
            ),
          ],

          const SizedBox(height: 24),

          // Botões no padrão Uppi
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: AppPrimaryButton(
                      isDisabled: selectedAmount == null || isSending,
                      onPressed: _sendTip,
                      child: isSending
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.5,
                              ),
                            )
                          : Text(
                              selectedAmount != null
                                  ? 'Enviar R\$ ${selectedAmount!.toStringAsFixed(2)}'
                                  : 'Selecione um valor',
                            ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: AppBorderedButton(
                      onPressed: () => widget.onSkip?.call(),
                      title: 'Não, obrigado',
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestionChip(BuildContext context, int index, double amount) {
    final isSelected = selectedIndex == index;
    return GestureDetector(
      onTap: () => setState(() => selectedIndex = isSelected ? null : index),
      child: AnimatedScale(
        scale: isSelected ? 1.05 : 1.0,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: isSelected
                ? ColorPalette.semanticgreen50
                : ColorPalette.neutral95,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? ColorPalette.semanticgreen50
                  : ColorPalette.neutralVariant90,
              width: isSelected ? 2 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: ColorPalette.semanticgreen50.withValues(
                        alpha: 0.25,
                      ),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ]
                : [],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'R\$',
                style: context.labelSmall?.copyWith(
                  color: isSelected
                      ? Colors.white70
                      : ColorPalette.neutralVariant50,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                amount.toStringAsFixed(0),
                style: context.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: isSelected ? Colors.white : ColorPalette.neutral20,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCustomChip(BuildContext context) {
    final isSelected = selectedIndex == suggestions.length;
    return GestureDetector(
      onTap: () => setState(
        () => selectedIndex = isSelected ? null : suggestions.length,
      ),
      child: AnimatedScale(
        scale: isSelected ? 1.05 : 1.0,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: isSelected
                ? ColorPalette.semanticgreen50
                : ColorPalette.neutral95,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? ColorPalette.semanticgreen50
                  : ColorPalette.neutralVariant90,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Ionicons.create_outline,
                size: 18,
                color: isSelected
                    ? Colors.white
                    : ColorPalette.neutralVariant50,
              ),
              const SizedBox(height: 2),
              Text(
                'Outro',
                style: context.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: isSelected
                      ? Colors.white
                      : ColorPalette.neutralVariant40,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSuccessView(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: const BoxDecoration(
        color: ColorPalette.neutralVariant99,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        boxShadow: [
          BoxShadow(
            color: Color(0x3F0E275D),
            blurRadius: 20,
            offset: Offset(2, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ScaleTransition(
            scale: _checkAnimation,
            child: Container(
              width: 80,
              height: 80,
              decoration: const BoxDecoration(
                color: ColorPalette.semanticgreen60,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Ionicons.checkmark,
                color: Colors.white,
                size: 40,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('Gorjeta enviada! 🎉', style: context.titleLarge),
          const SizedBox(height: 8),
          Text(
            '${widget.driverName} agradece!',
            style: context.bodyMedium?.copyWith(
              color: ColorPalette.neutralVariant50,
            ),
          ),
        ],
      ),
    );
  }
}
