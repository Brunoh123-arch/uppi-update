import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/lgpd_preferences.dart';
import '../domain/lgpd_consent.dart';

/// Tela de Direitos do Titular (art. 18 LGPD).
/// Acessível via Configurações → Privacidade e Dados.
/// Exibe dados coletados, finalidade, base legal e permite
/// revogar consentimentos opcionais ou solicitar exclusão de conta.
class LgpdDataRightsScreen extends StatefulWidget {
  /// Callback para iniciar o fluxo de exclusão de conta.
  final VoidCallback? onDeleteAccountRequested;

  const LgpdDataRightsScreen({
    super.key,
    this.onDeleteAccountRequested,
  });

  @override
  State<LgpdDataRightsScreen> createState() => _LgpdDataRightsScreenState();
}

class _LgpdDataRightsScreenState extends State<LgpdDataRightsScreen> {
  late bool _analyticsConsent;
  late bool _marketingConsent;

  @override
  void initState() {
    super.initState();
    _analyticsConsent = LgpdPreferences.analyticsConsent;
    _marketingConsent = LgpdPreferences.marketingConsent;
  }

  Future<void> _toggleAnalytics(bool value) async {
    await LgpdPreferences.giveConsent(
      analytics: value,
      marketing: _marketingConsent,
      location: LgpdPreferences.locationConsent,
    );
    setState(() => _analyticsConsent = value);
  }

  Future<void> _toggleMarketing(bool value) async {
    await LgpdPreferences.giveConsent(
      analytics: _analyticsConsent,
      marketing: value,
      location: LgpdPreferences.locationConsent,
    );
    setState(() => _marketingConsent = value);
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _sendDpoEmail() async {
    final uri = Uri(
      scheme: 'mailto',
      path: LgpdConsent.dpoEmail,
      queryParameters: {
        'subject': 'Direitos LGPD — Solicitação',
        'body':
            'Olá, gostaria de exercer meu direito conforme a LGPD (Lei 13.709/2018).\n\nDescreva sua solicitação:',
      },
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final consentDate = LgpdPreferences.consentDate;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Privacidade e Dados'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Seus direitos ──────────────────────────────
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CardTitle(
                  icon: Icons.gavel_rounded,
                  label: 'Seus direitos (art. 18 LGPD)',
                  color: cs.primary,
                ),
                const SizedBox(height: 12),
                _RightItem(
                  icon: Icons.visibility_outlined,
                  label: 'Acessar seus dados',
                  action: 'Solicitar via e-mail',
                  onTap: _sendDpoEmail,
                ),
                _RightItem(
                  icon: Icons.edit_outlined,
                  label: 'Corrigir dados incorretos',
                  action: 'Solicitar via e-mail',
                  onTap: _sendDpoEmail,
                ),
                _RightItem(
                  icon: Icons.download_outlined,
                  label: 'Portabilidade de dados',
                  action: 'Solicitar via e-mail',
                  onTap: _sendDpoEmail,
                ),
                _RightItem(
                  icon: Icons.delete_outline_rounded,
                  label: 'Excluir sua conta e dados',
                  action: 'Excluir conta',
                  actionColor: cs.error,
                  onTap: widget.onDeleteAccountRequested,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── Consentimentos opcionais ───────────────────
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CardTitle(
                  icon: Icons.tune_rounded,
                  label: 'Gerenciar consentimentos opcionais',
                  color: cs.secondary,
                ),
                const SizedBox(height: 8),
                SwitchListTile.adaptive(
                  value: _analyticsConsent,
                  onChanged: _toggleAnalytics,
                  title: const Text('Relatórios de erros (Sentry)'),
                  subtitle: const Text(
                    'Diagnósticos anônimos para melhorar o app',
                    style: TextStyle(fontSize: 12),
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
                const Divider(height: 1),
                SwitchListTile.adaptive(
                  value: _marketingConsent,
                  onChanged: _toggleMarketing,
                  title: const Text('Notificações e promoções'),
                  subtitle: const Text(
                    'Cupons e novidades da Uppi por push e e-mail',
                    style: TextStyle(fontSize: 12),
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── Dados coletados ────────────────────────────
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CardTitle(
                  icon: Icons.info_outline_rounded,
                  label: 'Dados coletados e finalidade (art. 9 LGPD)',
                  color: cs.tertiary,
                ),
                const SizedBox(height: 12),
                ...LgpdConsent.dataCategories.map(
                  (item) => _DataRow(
                    dado: item['dado']!,
                    finalidade: item['finalidade']!,
                    baseLegal: item['base_legal']!,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── DPO e documentos legais ────────────────────
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CardTitle(
                  icon: Icons.contact_mail_outlined,
                  label: 'Encarregado de Dados (DPO)',
                  color: cs.primary,
                ),
                const SizedBox(height: 8),
                Text(
                  LgpdConsent.controllerName,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  LgpdConsent.dpoEmail,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.primary,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () =>
                            _openUrl(LgpdConsent.privacyPolicyUrl),
                        icon: const Icon(Icons.privacy_tip_outlined, size: 16),
                        label: const Text('Privacidade'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () =>
                            _openUrl(LgpdConsent.termsOfServiceUrl),
                        icon: const Icon(Icons.article_outlined, size: 16),
                        label: const Text('Termos'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          if (consentDate != null) ...[
            const SizedBox(height: 16),
            Center(
              child: Text(
                'Consentimento dado em: '
                '${DateTime.parse(consentDate).toLocal().toString().substring(0, 16)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurface.withValues(alpha: 0.4),
                ),
              ),
            ),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ── Subwidgets ───────────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color:
              Theme.of(context).colorScheme.outline.withValues(alpha: 0.15),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: child,
      ),
    );
  }
}

class _CardTitle extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _CardTitle({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
      ],
    );
  }
}

class _RightItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String action;
  final Color? actionColor;
  final VoidCallback? onTap;

  const _RightItem({
    required this.icon,
    required this.label,
    required this.action,
    this.actionColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, size: 20, color: cs.onSurface.withValues(alpha: 0.6)),
      title: Text(label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
      trailing: TextButton(
        onPressed: onTap,
        child: Text(
          action,
          style: TextStyle(
            color: actionColor ?? cs.primary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _DataRow extends StatelessWidget {
  final String dado;
  final String finalidade;
  final String baseLegal;

  const _DataRow({
    required this.dado,
    required this.finalidade,
    required this.baseLegal,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            dado,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            finalidade,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurface.withValues(alpha: 0.7),
            ),
          ),
          Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              baseLegal,
              style: theme.textTheme.labelSmall?.copyWith(
                color: cs.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (dado != LgpdConsent.dataCategories.last['dado'])
            const Divider(height: 16),
        ],
      ),
    );
  }
}
