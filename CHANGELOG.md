# Changelog / Progresso do Projeto

## [Reorganização e Higienização Geral] - Achatamento, Segurança, Novos Scripts & Limpeza (Junho 2026)

### Reestruturação Física do Workspace:
- **Flatenização de Diretórios**: Achatamento da estrutura de pastas tripla aninhada (`Uppi 3.0/Uppi 3.0/Uppi 2.0/`) para a raiz (`Uppi 3.0/`), simplificando o desenvolvimento e build locais.
- **Limpeza de IDE e Caches**: Remoção de arquivos `.iml` redundantes da raiz, cache de estado do CLI do Supabase (`supabase/.temp/`), e diretórios locais de AI tools obsoletos (`.antigravitycli`, `.claude`).

### Segurança e Compliance:
- **Saneamento de Credenciais**: Remoção do arquivo `supabase/.env` com chaves de produção/desenvolvimento reais (movido para `.env.example`).
- **Desacoplamento de Chaves**: Substituição do token Supabase hardcoded em `.gemini/settings.json` por referência à variável de ambiente `%SUPABASE_ACCESS_TOKEN%`.
- **Políticas de Ignorar (Git)**: Atualização do `.gitignore` para barrar a inclusão de pastas locais de ferramentas de IA (`.claude/`, `.antigravitycli/`, `.cursor/`).

### Scripts & Automação:
- **Scripts de Build no Windows**: Criação dos scripts utilitários `.bat` em `scripts/build/` para automatizar tarefas no ambiente Windows:
  - `gerar_build_producao.bat`: Compilação ofuscada de AAB e APK de produção.
  - `gerar_android_apk_teste.bat`: Compilação rápida de APK de depuração.
  - `limpar_e_atualizar.bat`: Limpeza recursiva dos builds e caches Flutter, seguida de bootstrap via Melos.
- **Padronização de Ambiente**: Criação do modelo `.env.example` unificado na raiz do workspace.

### Configurações de IDE:
- **Correção de Paths do VSCode**: Remoção de caminhos absolutos locais de outros desenvolvedores no `.vscode/settings.json` (como `cmake.sourceDirectory` apontando para a máquina física de outro usuário).

---

## [Sessão Anterior] - Segurança, Compliance LGPD, i18n Reativa, Novo Painel Admin & CI/CD Robusto (Maio 2026)

### Adições e Refatorações de Segurança:
- **Criptografia Nativa (`pgcrypto`)**: Implementada migração estrutural para armazenar CPFs de usuários (`profiles.cpf`) e contas de repasse PIX (`payout_accounts.account_number`) utilizando cifra simétrica com `pgcrypto` no PostgreSQL, garantindo segurança estrita de dados sensíveis em repouso.
- **KYC & Descarte de Arquivos no Storage**:
  - Nova tela de Documentos Obrigatórios do Motorista (`driver_documents_screen.dart`) com slots fixos rotulados: CNH, CRLV e Comprovante de Residência.
  - Implementado expurgo automático e em tempo real no Supabase Storage: ao substituir qualquer imagem em um dos slots de documentos, o app invoca fisicamente o método `deleteDocument` que executa a remoção física permanente do arquivo antigo no bucket.
- **Direito ao Esquecimento LGPD Automatizado**: Refatoração profunda da Edge Function `delete-user-account`. Ao deletar a conta de um usuário, o backend realiza uma limpeza atômica em cascata (deleta payouts, zera CPFs/documentos na tabela `profiles` e exclui fisicamente todas as imagens nos buckets `avatars` e `documents` do Storage), gerando logs pseudonimizados em `admin_audit_log`.
- **Resiliência e Tratamento de Sinal de Rede (Item 54)**: Implementada verificação real de internet via lookup DNS com fallback em múltiplos servidores no `ConnectivityCubit` (evitando falsos positivos de redes Wi-Fi ativas sem conexão de internet). Refatorados o `TrackOrderBloc` e o `HomeBloc` para consumirem a stream de conectividade do cubit, assegurando reconexão reativa automática e retentativa confiável de envio de mensagens de chat pendentes.

### Novo Console Administrativo Web (`apps/admin_panel`):
- **Dashboard Executivo Interativo**:
  - Implementação de 8 cartões estatísticos de KPIs com cálculo percentual de variação ($\Delta\%$) comparando com o período anterior.
  - Gráficos lineares dinâmicos (`fl_chart`) para volume de corridas e faturamento.
  - Funil gráfico de conversão de corridas (Solicitadas → Aceitas → Concluídas → Avaliadas).
  - Heatmap 7x24 termal de densidade de tráfego.
  - Monitoramento reativo em tempo real via streams das últimas corridas ativas e contadores pulsantes.
- **Módulo de Relatórios Exportáveis (CSV)**: Criada seção com abas (Corridas, Motoristas e Financeiro) suportando filtragem indexada por período e download imediato de arquivos CSV no navegador do usuário via emparelhamento de base64 e `url_launcher`.

### Sincronismo e Localização Reativa:
- **Internacionalização Avançada (i18n)**: Mapeamento de todas as strings literais das configurações e slots de documentos de motorista/passageiro para arquivos de tradução ARB (`intl_en.arb` e `intl_pt.arb`).
- **Sincronização em Tempo Real por Streams**: Integração mútua dos blocos de preferências no entrypoint `main.dart` do Super App, forçando a reconstrução instantânea e dinâmica do `MaterialApp.router` no idioma ou tema correto assim que o usuário faz uma alteração em tela.

### DevOps e Pipelines de CI/CD:
- **Esteira do GitHub Actions (.github/workflows/flutter_ci.yml)**:
  - Integração de concorrência (`cancel-in-progress: true`) para abortar compilações redundantes.
  - Ativado cache inteligente do `pub.dev` e compilações Gradle, agilizando builds em até 70%.
  - Mecanismo de **Signing Pipeline Bypass** injetando chaves Gradle e keystores autoassinadas mockadas em runtime de CI para que a compilação de teste do AAB passe autonomamente sem expor segredos privados locais.
  - CD automático do `admin_panel` direto para o Firebase Hosting ao fazer push na branch `main`.

---

## [Sessão Anterior] - Implementação LGPD e Monorepo (Maio 2026)

### Adições e Refatorações:
- **Consolidação de Monorepo**: Migramos a tela `MapSettingsScreen` dos apps `rider-frontend` e `driver-frontend` para um componente compartilhado na biblioteca `libs/flutter_common`, eliminando código duplicado.
- **Correção no Fluxo de Motorista**: O fluxo de autenticação via Google no app do motorista (`LoginBloc`) foi ajustado para extrair corretamente os metadados (nome e e-mail) do Supabase Auth e preenchê-los no formulário de registro de novos motoristas.
- **Implementação do Consentimento LGPD Obrigatório**:
  - Implementação do `LgpdConsentWrapperScreen` e sua respectiva rota no `app_router.dart` do app.
  - Inserção de uma verificação em `SplashScreen` (`LgpdPreferences.hasGivenConsent`) que impede o acesso ao app sem o consentimento dos termos de privacidade e coleta de dados.
- **Página de Direitos de Dados LGPD**:
  - Adicionado o botão para visualizar/revogar o consentimento na tela de Configurações (`SettingsScreen`) do aplicativo do motorista (Driver), espelhando o que já existia no aplicativo do passageiro (Rider).
  - Ambos os aplicativos agora suportam a funcionalidade de solicitação de "Exclusão de Conta" diretamente da tela de consentimento de dados.

### Manutenção e Limpeza:
- Realizado script de limpeza (`flutter clean`) em todos os subprojetos para liberar aproximadamente 540 MB de cache acumulado nos diretórios `build/` e `.dart_tool/`.
