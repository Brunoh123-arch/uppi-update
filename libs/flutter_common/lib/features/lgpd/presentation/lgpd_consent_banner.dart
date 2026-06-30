import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../domain/lgpd_consent.dart';

/// Banner compacto de privacidade — exibido na primeira sessão após cadastro.
/// Versão minimalista (estilo app 99/Uber) para não bloquear o fluxo.
///
/// Pode ser exibido como SnackBar ou Widget fixo no fundo da tela.
class LgpdConsentBanner extends StatelessWidget {
  final VoidCallback onAccept;
  final VoidCallback onViewDetails;

  const LgpdConsentBanner({
    super.key,
    required this.onAccept,
    required this.onViewDetails,
  });

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Material(
      color: cs.inverseSurface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          MediaQuery.of(context).padding.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.shield_rounded,
                  color: cs.inversePrimary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Privacidade e LGPD',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: cs.onInverseSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            RichText(
              text: TextSpan(
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onInverseSurface.withValues(alpha: 0.8),
                  height: 1.5,
                ),
                children: [
                  const TextSpan(
                    text:
                        'Usamos seus dados para conectar você a motoristas e melhorar o app. '
                        'Veja nossa ',
                  ),
                  TextSpan(
                    text: 'Política de Privacidade',
                    style: TextStyle(
                      color: cs.inversePrimary,
                      decoration: TextDecoration.underline,
                      fontWeight: FontWeight.w600,
                    ),
                    recognizer: TapGestureRecognizer()
                      ..onTap = () => _openUrl(LgpdConsent.privacyPolicyUrl),
                  ),
                  const TextSpan(text: '.'),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onViewDetails,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: cs.onInverseSurface,
                      side: BorderSide(
                        color: cs.onInverseSurface.withValues(alpha: 0.3),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Detalhes'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: onAccept,
                    style: FilledButton.styleFrom(
                      backgroundColor: cs.inversePrimary,
                      foregroundColor: cs.onInverseSurface,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Aceitar e continuar',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
