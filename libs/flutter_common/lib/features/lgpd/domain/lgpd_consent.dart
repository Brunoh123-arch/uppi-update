/// Represents a snapshot of the user's LGPD consent state.
class LgpdConsent {
  final bool hasGivenConsent;
  final DateTime? consentDate;
  final bool analyticsConsent;
  final bool marketingConsent;
  final bool locationConsent;

  const LgpdConsent({
    required this.hasGivenConsent,
    this.consentDate,
    required this.analyticsConsent,
    required this.marketingConsent,
    required this.locationConsent,
  });

  /// URL da Política de Privacidade da Uppi
  static const String privacyPolicyUrl =
      'https://uppimobilidade.com.br/privacidade.html';

  /// URL dos Termos de Uso da Uppi
  static const String termsOfServiceUrl =
      'https://uppimobilidade.com.br/termos.html';

  /// URL da Política de Cookies
  static const String cookiePolicyUrl =
      'https://uppimobilidade.com.br/privacidade.html#cookies';

  /// Contato do DPO (Data Protection Officer) — exigido pela LGPD art. 41
  static const String dpoEmail = 'privacidade@uppimobilidade.com.br';

  /// Nome do controlador de dados — exigido pela LGPD art. 18
  static const String controllerName = 'Uppi Mobilidade Ltda.';

  /// Dados que a Uppi coleta e a finalidade (art. 9 LGPD)
  static const List<Map<String, String>> dataCategories = [
    {
      'dado': 'Nome e telefone',
      'finalidade': 'Identificação e acesso à conta',
      'base_legal': 'Execução de contrato (art. 7, V)',
    },
    {
      'dado': 'Localização GPS',
      'finalidade': 'Conexão com motoristas e cálculo de rota',
      'base_legal': 'Execução de contrato (art. 7, V)',
    },
    {
      'dado': 'Dados de pagamento',
      'finalidade': 'Processamento de cobranças via Mercado Pago',
      'base_legal': 'Execução de contrato (art. 7, V)',
    },
    {
      'dado': 'CPF',
      'finalidade': 'Verificação de identidade (KYC) e emissão de nota fiscal',
      'base_legal': 'Cumprimento de obrigação legal (art. 7, II)',
    },
    {
      'dado': 'Foto e selfie',
      'finalidade': 'Verificação de identidade (KYC) para motoristas',
      'base_legal': 'Consentimento (art. 7, I)',
    },
    {
      'dado': 'Dados de uso do app',
      'finalidade': 'Melhoria do serviço e detecção de erros (Sentry)',
      'base_legal': 'Consentimento (art. 7, I)',
    },
    {
      'dado': 'Histórico de corridas',
      'finalidade': 'Suporte ao cliente e resolução de disputas',
      'base_legal': 'Interesse legítimo (art. 7, IX)',
    },
  ];
}
