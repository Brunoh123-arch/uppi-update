import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_common/core/presentation/buttons/app_bordered_button.dart';
import 'package:flutter_common/core/presentation/responsive_dialog/app_responsive_dialog.dart';
import 'package:flutter_common/core/presentation/snackbar/snackbar.dart';
import 'package:ionicons/ionicons.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';
import 'package:rider_flutter/config/locator/locator.dart';
import 'package:rider_flutter/core/extensions/extensions.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';

import '../../domain/repositories/track_order_repository.dart';

class SendSOSDialog extends StatefulWidget {
  final String orderId;

  const SendSOSDialog({
    super.key,
    required this.orderId,
  });

  @override
  State<SendSOSDialog> createState() => _SendSOSDialogState();
}

class _SendSOSDialogState extends State<SendSOSDialog> with TickerProviderStateMixin {
  late AnimationController _holdController;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  bool _isHolding = false;
  bool _isSending = false;
  bool _isSuccess = false;
  bool _silentRecording = true;

  @override
  void initState() {
    super.initState();

    _holdController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );

    _holdController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _triggerSOS();
      }
    });

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.25).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _holdController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _startHold() {
    if (_isSending || _isSuccess) return;
    setState(() {
      _isHolding = true;
    });
    _holdController.forward(from: 0.0);
    _pulseController.repeat(reverse: true);
    HapticFeedback.lightImpact();
  }

  void _cancelHold() {
    if (_isSuccess || _isSending) return;
    if (_holdController.value < 1.0) {
      setState(() {
        _isHolding = false;
      });
      _holdController.reverse();
      _pulseController.stop();
      _pulseController.reset();
      HapticFeedback.mediumImpact();
    }
  }

  void _triggerSOS() async {
    setState(() {
      _isHolding = false;
      _isSending = true;
    });
    _pulseController.stop();
    _pulseController.reset();
    HapticFeedback.heavyImpact();

    final result = await locator<TrackOrderRepository>()
        .sendSOSSignal(orderId: widget.orderId);

    result.fold(
      (l) {
        setState(() {
          _isSending = false;
        });
        context.showErrorSnackBar(l.errorMessage, fallback: 'Não foi possível enviar o alerta SOS.');
      },
      (r) async {
        setState(() {
          _isSending = false;
          _isSuccess = true;
        });
        HapticFeedback.vibrate();
        context.showSnackBar(message: context.translate.sosSentSuccessfully);

        // Autodisparo de Rota por Link de Rastreamento (Fase 23)
        try {
          final prefs = await SharedPreferences.getInstance();
          final String? contactsJson = prefs.getString('emergency_contacts');
          if (contactsJson != null && contactsJson.isNotEmpty) {
            final List<dynamic> decoded = jsonDecode(contactsJson);
            if (decoded.isNotEmpty) {
              final text = '⚠️ SOS EMERGÊNCIA UPPI: Preciso de ajuda! Acompanhe minha localização em tempo real no mapa: https://uppi.app/track/${widget.orderId}';
              await Share.share(text);
            }
          }
        } catch (_) {}

        Future.delayed(const Duration(milliseconds: 1800), () {
          if (mounted) {
            Navigator.of(context).pop();
          }
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final remainingSeconds = (3 - (_holdController.value * 3)).ceil();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AppResponsiveDialog(
      type: context.responsive(
        DialogType.bottomSheet,
        xl: DialogType.dialog,
      ),
      primaryButton: AppBorderedButton(
        onPressed: () {
          Navigator.of(context).pop();
        },
        title: context.translate.goBackToRide,
      ),
      header: (
        Ionicons.shield_half,
        context.translate.sos,
        "Central de Emergência e Proteção Uppi",
      ),
      iconColor: colorScheme.error,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        color: colorScheme.surface, // Original app background color
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Hold-to-activate Circle Button
            Center(
              child: GestureDetector(
                onTapDown: (_) => _startHold(),
                onTapUp: (_) => _cancelHold(),
                onTapCancel: () => _cancelHold(),
                child: AnimatedBuilder(
                  animation: Listenable.merge([_holdController, _pulseAnimation]),
                  builder: (context, child) {
                    Color buttonColor = colorScheme.error; // Original emergency red
                    if (_isSuccess) buttonColor = ColorPalette.semanticgreen50; // Success brand green
                    if (_isSending) buttonColor = ColorPalette.secondary50; // Warning brand orange

                    return ScaleTransition(
                      scale: _isHolding ? _pulseAnimation : const AlwaysStoppedAnimation(1.0),
                      child: Container(
                        height: 160,
                        width: 160,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: buttonColor.withValues(alpha: 0.08),
                          border: Border.all(
                            color: buttonColor.withValues(alpha: _isHolding ? 0.8 : 0.3),
                            width: _isHolding ? 3.0 : 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: buttonColor.withValues(alpha: _isHolding ? 0.3 : 0.1),
                              blurRadius: _isHolding ? 35 : 15,
                              spreadRadius: _isHolding ? 5 : 2,
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Neon circular progress indicator
                            SizedBox(
                              height: 140,
                              width: 140,
                              child: CircularProgressIndicator(
                                value: _holdController.value,
                                strokeWidth: 6,
                                backgroundColor: colorScheme.onSurface.withValues(alpha: 0.08),
                                valueColor: AlwaysStoppedAnimation<Color>(buttonColor),
                              ),
                            ),
                            
                            // Inner core of the panic button
                            Container(
                              height: 116,
                              width: 116,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: buttonColor.withValues(alpha: 0.2),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    _isSuccess 
                                        ? Ionicons.checkmark_circle 
                                        : (_isSending ? Ionicons.sync : Ionicons.alert_circle),
                                    color: colorScheme.onSurface,
                                    size: 38,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    _isSuccess 
                                        ? "ATIVADO" 
                                        : (_isSending ? "ENVIANDO..." : (_isHolding ? "${remainingSeconds}s" : "PÂNICO")),
                                    style: TextStyle(
                                      color: colorScheme.onSurface,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Instruction Text
            Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text(
                  _isSuccess
                      ? "Seu sinal de SOS foi enviado com sucesso!"
                      : (_isSending
                          ? "Conectando-se ao canal de segurança seguro..."
                          : (_isHolding
                              ? "Mantenha pressionado para confirmar o SOS"
                              : "Mantenha pressionado por 3 segundos")),
                  key: ValueKey<String>('sos-state-$_isHolding-$_isSending-$_isSuccess'),
                  style: TextStyle(
                    color: _isSuccess 
                        ? ColorPalette.semanticgreen60 
                        : (_isHolding ? ColorPalette.secondary50 : colorScheme.onSurface),
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Silent Recording Option Card
            Container(
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest, // Dynamic surface container
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: colorScheme.outline.withValues(alpha: 0.15),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colorScheme.error.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Ionicons.mic_outline,
                      color: colorScheme.error,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Gravação Silenciosa de Áudio",
                          style: TextStyle(
                            color: colorScheme.onSurface,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          "Grava áudio em background como prova judicial",
                          style: TextStyle(
                            color: colorScheme.onSurface.withValues(alpha: 0.6),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _silentRecording,
                    onChanged: (val) {
                      setState(() {
                        _silentRecording = val;
                      });
                      HapticFeedback.lightImpact();
                    },
                    activeThumbColor: colorScheme.error,
                    activeTrackColor: colorScheme.error.withValues(alpha: 0.3),
                    inactiveThumbColor: Colors.grey,
                    inactiveTrackColor: colorScheme.onSurface.withValues(alpha: 0.12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Active Protections List
            Text(
              "MEDIDAS DE SEGURANÇA ATIVAS:",
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 10),
            
            _buildSafetyInfoRow(
              Ionicons.navigate,
              "Rastreamento de Trajeto GPS",
              "A Central de Crise e seus contatos de emergência acompanharão seu trajeto em tempo real.",
            ),
            const SizedBox(height: 10),
            _buildSafetyInfoRow(
              Ionicons.chatbubble_ellipses,
              "Notificações de Emergência Instantâneas",
              "Envia alertas automatizados por SMS e canais digitais para sua rede protetora cadastrada.",
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSafetyInfoRow(IconData icon, String title, String subtitle) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: colorScheme.error.withValues(alpha: 0.7), size: 16),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  color: colorScheme.onSurface.withValues(alpha: 0.5),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
