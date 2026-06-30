import 'package:flutter/material.dart';

import '../data/lgpd_preferences.dart';
import 'lgpd_privacy_terms_screen.dart';

/// Tela de consentimento LGPD — estilo bottom-sheet card.
/// Exibida após o splash screen no primeiro uso do app.
/// Possui apenas o botão "Concordo" — o usuário deve aceitar para usar o app.
class LgpdConsentScreen extends StatefulWidget {
  /// Callback chamado quando o usuário aceita os termos obrigatórios.
  final VoidCallback onConsentGiven;

  const LgpdConsentScreen({
    super.key,
    required this.onConsentGiven,
  });

  @override
  State<LgpdConsentScreen> createState() => _LgpdConsentScreenState();
}

class _LgpdConsentScreenState extends State<LgpdConsentScreen>
    with SingleTickerProviderStateMixin {
  bool _isLoading = false;

  late final AnimationController _animController;
  late final Animation<Offset> _slideAnim;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    ));
    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeIn,
    );
    // Inicia a animação após um pequeno delay para o efeito "subir"
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _animController.forward();
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _handleAccept() async {
    setState(() => _isLoading = true);
    await LgpdPreferences.giveConsent(
      analytics: true,
      marketing: false,
      location: true,
    );
    if (!mounted) return;
    widget.onConsentGiven();
  }

  void _openPrivacyTerms() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const LgpdPrivacyTermsScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    debugPrint("UPPI BRASIL [LgpdConsentScreen] build chamado");
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Cabeçalho / Branding ──────────────────────────
              const SizedBox(height: 24),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.shield_rounded,
                    color: cs.primary,
                    size: 40,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'UPPI',
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: cs.primary,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 4,
                  fontSize: 26,
                ),
                textAlign: TextAlign.center,
              ),
              Text(
                'Segurança e Termos de Uso',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurface.withValues(alpha: 0.5),
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),

              // ── Conteúdo Rolável (Título, Breve Texto e Card) ──
              Expanded(
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Termos e Privacidade',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: cs.onSurface,
                          fontSize: 20,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Para continuar e acessar a plataforma de mobilidade da Uppi, por favor leia e aceite as nossas diretrizes de uso e segurança. A proteção dos seus dados e a transparência são nossas prioridades.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: cs.onSurface.withValues(alpha: 0.6),
                          height: 1.6,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // ── Bloco de Link Moderno (Tipo Card Clicável) ──
                      InkWell(
                        onTap: _openPrivacyTerms,
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                          decoration: BoxDecoration(
                            color: cs.primary.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: cs.primary.withValues(alpha: 0.1),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.description_rounded,
                                size: 24,
                                color: cs.primary,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Contrato de Termos e Políticas',
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        color: cs.onSurface,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Toque para ler os termos completos',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: cs.onSurface.withValues(alpha: 0.5),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.chevron_right_rounded,
                                size: 22,
                                color: cs.primary,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),

              // ── Botão Concordo (Fixo no final da tela) ──────────
              Padding(
                padding: EdgeInsets.only(bottom: bottomPadding > 0 ? 0 : 8),
                child: SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: FilledButton(
                    onPressed: _isLoading ? null : _handleAccept,
                    style: FilledButton.styleFrom(
                      backgroundColor: cs.primary,
                      foregroundColor: cs.onPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Concordo e Continuar',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
