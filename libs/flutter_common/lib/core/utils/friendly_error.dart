/// Converte erros técnicos (exceptions, stack traces, mensagens de SDK) em
/// mensagens curtas e amigáveis para o usuário final.
///
/// Nunca expõe detalhes internos como host, porta, `errno`, `uri=`, `statusCode`
/// ou nomes de exceção (ex.: `AuthRetryableFetchException`, `SocketException`).
///
/// Uso:
///   context.showErrorSnackBar(e);            // SnackBar amigável
///   final msg = friendlyErrorMessage(e);     // string amigável
String friendlyErrorMessage(
  Object? error, {
  String fallback = 'Algo deu errado. Tente novamente.',
}) {
  if (error == null) return fallback;

  final raw = error.toString();
  final lower = raw.toLowerCase();

  // ── Sem conexão / falha de rede ─────────────────────────────────────
  const networkMarkers = [
    'socketexception',
    'clientexception',
    'authretryablefetchexception',
    'connection refused',
    'connection reset',
    'connection closed',
    'connection abort',
    'failed host lookup',
    'network is unreachable',
    'no address associated',
    'handshakeexception',
    'os error',
    'errno = 111',
    'errno = 7',
    'errno = 8',
    'errno = 101',
    'errno = 110',
    'xmlhttprequest', // web: rede indisponível
    'failed to fetch',
  ];
  if (networkMarkers.any(lower.contains)) {
    return 'Sem conexão com a internet. Verifique sua rede e tente novamente.';
  }

  // ── Timeout ─────────────────────────────────────────────────────────
  if (lower.contains('timeoutexception') ||
      lower.contains('timed out') ||
      lower.contains('timeout')) {
    return 'A conexão demorou demais. Tente novamente.';
  }

  // ── Autenticação ────────────────────────────────────────────────────
  if (lower.contains('invalid login credentials')) {
    return 'Credenciais inválidas. Verifique e tente novamente.';
  }
  if (lower.contains('email not confirmed')) {
    return 'E-mail não confirmado. Verifique sua caixa de entrada.';
  }
  if (lower.contains('user already registered') ||
      lower.contains('already registered') ||
      lower.contains('already exists')) {
    return 'Esta conta já existe. Tente entrar.';
  }
  if (lower.contains('invalid otp') ||
      lower.contains('otp') && lower.contains('expired') ||
      lower.contains('token has expired')) {
    return 'Código inválido ou expirado. Solicite um novo.';
  }
  if ((lower.contains('jwt') || lower.contains('session')) &&
      lower.contains('expired')) {
    return 'Sua sessão expirou. Entre novamente.';
  }

  // ── Limite de tentativas ────────────────────────────────────────────
  if (lower.contains('rate limit') ||
      lower.contains('too many requests') ||
      lower.contains('429')) {
    return 'Muitas tentativas. Aguarde um momento e tente novamente.';
  }

  // ── Permissão ───────────────────────────────────────────────────────
  if (lower.contains('permission denied') ||
      lower.contains('row-level security') ||
      lower.contains('not authorized') ||
      lower.contains('unauthorized') ||
      lower.contains('403')) {
    return 'Você não tem permissão para esta ação.';
  }

  // ── Servidor ────────────────────────────────────────────────────────
  if (lower.contains('internal server error') ||
      lower.contains('statuscode: 500') ||
      lower.contains('"code":500')) {
    return 'Nosso servidor teve um problema. Tente novamente em instantes.';
  }

  // ── Mensagem já curta e sem ruído técnico? Mostra-a. Senão, fallback. ─
  // Evita vazar stack traces e construtores de exceção do tipo
  // "FooException(message: ...)" ou URLs/uri/portas internas.
  final looksTechnical = raw.contains('Exception') ||
      raw.contains('Error') ||
      raw.contains('uri=') ||
      raw.contains('http') ||
      raw.contains('statusCode') ||
      raw.contains('{') ||
      raw.length > 120;
  if (!looksTechnical && raw.trim().isNotEmpty) {
    return raw.trim();
  }

  return fallback;
}
