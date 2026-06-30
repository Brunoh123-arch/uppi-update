# 📚 Uppi — Documentação Técnica

> Referência completa da arquitetura, deploy e operação do Super App Uppi.

---

## 🏗️ 1. Arquitetura

### Visão Geral
O Uppi é um **Super App 2-em-1**: o mesmo binário contém a interface do Passageiro e do Motorista. O usuário alterna entre os modos via menu lateral, sem precisar baixar dois apps separados.

### Fluxo de Dados
```
┌─────────────┐     ┌──────────────────┐     ┌──────────────────┐
│ Flutter App  │────▶│ Supabase Edge Fn │────▶│ PostgreSQL + RLS │
│ (rider-app)  │◀────│ (Deno/TS)        │◀────│ (PostGIS)        │
└─────────────┘     └──────────────────┘     └──────────────────┘
       │                                            │
       │         ┌──────────────────┐               │
       └────────▶│ Firebase         │               │
                 │ • Auth (SMS/OTP) │               │
                 │ • FCM (Push)     │               │
                 │ • Hosting (Admin)│               │
                 └──────────────────┘
```

### Módulos do Monorepo

| Módulo | Caminho | Responsabilidade |
|--------|---------|------------------|
| **Super App** | `apps/rider-frontend` | App unificado (passageiro + motorista) |
| **Motorista** | `apps/driver-frontend` | Módulo importado como pacote pelo rider |
| **Admin** | `apps/admin_panel` | Painel de controle web (Flutter Web) |
| **Common** | `libs/flutter_common` | Entidades, enums, widgets e theme compartilhados |
| **Maps** | `libs/generic_map` | Abstração multi-provider (Google / Leaflet / MapBox) |
| **Backend** | `supabase/functions` | 49 Edge Functions serverless |
| **Migrações** | `supabase/migrations` | Schema SQL do PostgreSQL |

---

## 💳 2. Pagamentos

### Mercado Pago (PIX)
- **Edge Function:** `create-pix-payment` — Gera QR Code PIX para o passageiro
- **Webhook:** `mercado-pago-webhook` — Recebe confirmação de pagamento

### Carteira Digital (Wallet)
- Cada usuário tem um saldo interno em `wallets` (PostgreSQL)
- Recarga via PIX ou créditos administrativos
- Edge Functions: `get-wallet-balance`, `get-wallet-history`, `admin-recharge-wallet`

---

## 🔐 3. Autenticação

### Fluxo Atual (Nativo Supabase OTP)
1. **SMS/OTP**: O Supabase Auth gerencia o envio do SMS por OTP (One-Time Password) nativamente através da chamada `signInWithOtp`.
2. **Confirmação e Sessão**: O app móvel valida o código numérico via `verifyOTP` (do tipo `OtpType.sms`). Isso cria uma sessão criptográfica segura de forma nativa no Supabase Auth, dispensando senhas derivadas.
3. **Google Sign-In**: Disponível como método alternativo de login.

### Sessão do Supabase
- Necessária para uploads de documentos (CNH, selfie, etc.) e acesso às tabelas reativas (cujas políticas RLS exigem usuário autenticado).
- RLS (Row Level Security) em 100% das tabelas do banco de dados e no Storage exige `auth.uid()` válido do usuário autenticado no Supabase.
- Gerenciada automaticamente no repositório de produção `auth_repository.prod.dart` usando chamadas nativas do SDK do Supabase.

---

## 🗺️ 4. Mapas

O provedor de mapa é **controlado em tempo real** pelo Painel Admin via tabela `app_settings`:

| Provedor | API Key | Custo |
|----------|---------|-------|
| OpenStreetMap (Leaflet) | Não precisa | Gratuito |
| Google Maps | Configurada no Admin Panel | Pago por requisição |
| MapBox | Token no `.env` | Freemium |

### Como funciona
1. Admin altera `map_provider` na tabela `app_settings`
2. App recebe mudança via Supabase Realtime Stream
3. `SettingsCubit` troca o provider instantaneamente
4. Na Web, o script JS do Google é injetado dinamicamente se necessário

---

## 📡 5. Edge Functions (Backend)

As 49 funções estão em `supabase/functions/`. Principais:

### Corridas
| Função | Descrição |
|--------|-----------|
| `create-order` | Passageiro solicita corrida |
| `accept-order` | Motorista aceita a corrida |
| `start-order` | Motorista inicia a viagem |
| `finish-order` | Motorista finaliza a viagem |
| `cancel-order` | Cancelamento (passageiro ou motorista) |
| `calculate-fare` | Calcula tarifa baseada em distância e tempo |
| `calculate-surge` | Calcula multiplicador de tarifa dinâmica |

### Localização
| Função | Descrição |
|--------|-----------|
| `update-driver-location` | Atualiza posição do motorista em tempo real |
| `notify-nearby-drivers` | Envia push para motoristas no raio de busca |

### Comunicação
| Função | Descrição |
|--------|-----------|
| `chat-send-message` | Chat in-app entre passageiro e motorista |
| `send-notification` | Push notification individual |
| `send-multicast-push` | Push marketing para múltiplos usuários |
| `send-sos` | Alerta de emergência |

---

## 🔑 6. Variáveis de Ambiente

### `.env` (apps/rider-frontend)
```env
APP_NAME=Uppi
SUPABASE_URL=https://xxx.supabase.co
SUPABASE_ANON_KEY=eyJ...
SENTRY_DSN=https://xxx@sentry.io/xxx
```

> O arquivo `.env.example` contém o template. Copie para `.env` e preencha.

---

## 7. Build, Deploy e CI/CD

O ecossistema Uppi conta com fluxos de implantação física (manual) e uma esteira altamente automatizada de integração e entrega contínua (CI/CD) via GitHub Actions.

* **Deploy de Apps Móveis**: Compilados a partir de `apps/rider-frontend` utilizando `flutter build appbundle` (Android AAB) e `flutter build ipa` (iOS IPA).
* **Deploy da Web Administrativa**: Compilada em `apps/admin_panel` com `flutter build web` e publicada no Firebase Hosting com `firebase deploy`.
* **Deploy de Banco & Backend**: Implantação de Edge Functions e tabelas via Supabase CLI (`supabase functions deploy` e `supabase db push`).
* **Esteira Automatizada (GitHub Actions)**: Centralizada em `.github/workflows/flutter_ci.yml`. Inclui cancelamento inteligente de compilações órfãs (`cancel-in-progress`), caches do pub/gradle para builds ultrarrápidas, injeção dinâmica de keystores mockadas para bypass no CI, e deploy contínuo (CD) automático do Admin Panel para o Firebase Hosting no branch `main`.

> 📖 **Para instruções completas e sequenciais de implantação, consulte o guia dedicado [DEPLOY_E_CICD.md](DEPLOY_E_CICD.md).**

---

## 🛡️ 8. KYC de Motoristas e Conformidade LGPD (Direito ao Esquecimento)

Adotamos regras de segurança rígidas e conformidade integral com a Lei Geral de Proteção de Dados (LGPD) no fluxo cadastral e no descarte de informações pessoais.

### Slots Estruturados de KYC no Motorista:
Para evitar bagunça no envio e garantir legibilidade para a moderação, o fluxo em `driver_documents_screen.dart` exige exatamente 3 slots de documentos obrigatórios:
1. **Carteira Nacional de Habilitação (CNH)**
2. **Documento do Veículo (CRLV)**
3. **Comprovante de Residência**

### Exclusão Física em Tempo Real no Supabase Storage:
* **KYC Ativo**: Quando o motorista substitui qualquer imagem em um dos slots de documentos, o app invoca fisicamente o método `deleteDocument` do `upload_datasource.prod.dart` que executa `supabase.storage.from('documents').remove([oldPath])`. O arquivo obsoleto é **deletado física e permanentemente** de imediato, liberando armazenamento e mitigando acúmulo de dados passados.
* **Direito ao Esquecimento (Exclusão de Conta)**: O encerramento da conta do motorista ou passageiro é orquestrado pela Edge Function protegida `delete-user-account`. O fluxo executa uma purga atômica e em cascata:
  1. Deleta as contas de repasse bancário e chaves PIX em `payout_accounts`.
  2. Define o CPF e as URLs de documentos como `NULL` na tabela `profiles`.
  3. Varre e **exclui fisicamente todos os arquivos e pastas** do usuário nos buckets `avatars` e `documents` do Supabase Storage.
  4. Registra a operação de forma segura e pseudonimizada na tabela `admin_audit_log` para conformidade de auditoria.

---

## 📊 9. Console Administrativo Avançado (Flutter Web)

O painel de controle web (`apps/admin_panel`) foi totalmente remodelado para um nível executivo moderno, reativo e centrado em dados operacionais em tempo real.

### Painel de Analytics & Gráficos:
* **KPIs Executivos**: 8 cartões estatísticos interativos mostrando volume de corridas, motoristas ativos (online agora), passageiros registrados, receita da plataforma (taxa de comissão), taxa de conversão (corridas concluídas vs solicitadas), taxa de cancelamento e avaliação média com cálculo percentual de variação ($\Delta\%$) versus o período anterior.
* **Corridas ao Vivo**: Painel síncrono com contadores pulsantes monitorando em tempo real corridas pendentes, a caminho, em viagem e aguardando avaliação.
* **Gráficos Fl Charts**: Dois LineCharts dinâmicos mapeando o Volume de Corridas e a Receita de Comissão com base no período selecionado (Hoje, 7 dias, 30 dias ou 90 dias).
* **Funil de Conversão**: Funil gráfico representando as taxas de atrito em cada etapa da jornada (Solicitadas → Aceitas → Concluídas → Avaliadas).
* **Heatmap 7x24 de Densidade**: Grade horária de 7 dias × 24 horas mapeando termicamente as horas de pico da plataforma.
* **Saúde da Plataforma**: Métricas calculadas como Churn Rate de motoristas e Net Promoter Score (NPS) aproximado.

### Módulo de Relatórios Exportáveis (CSV):
Integração de busca indexada por período e download direto no browser de dados fiscais e operacionais nas abas:
* **Corridas**: ID, data, rider, driver, status, valor bruto e comissão.
* **Motoristas**: Nome, telefone, status de aprovação, total de viagens, nota e ganhos.
* **Financeiro**: Balanço consolidado diário por faturamento de plataforma.
* *Tecnologia*: Geração local de string CSV baseada em base64 e download instantâneo usando o emparelhamento do `url_launcher`.

---

## 🌐 10. Internacionalização Reativa e Sincronismo In-App

A plataforma foi convertida para um sistema de localização 100% dinâmico (multilinguismo total EN/PT-BR).

* **Internacionalização Centralizada**: As chaves literais foram migradas para arquivos de tradução ARB (`intl_en.arb` e `intl_pt.arb`) na biblioteca `libs/flutter_common`.
* **Reatividade por Streams**: Integramos os Cubits de preferências do motorista e do passageiro no entrypoint `main.dart` do Super App. Uma mudança de idioma ou tema (Claro/Escuro/Seguir System) em qualquer tela dispara instantaneamente um evento via stream, forçando a reconstrução reativa do `MaterialApp.router` sem necessidade de reinicializar o aplicativo.

## 📡 11. Resiliência e Tratamento de Sinal de Rede (Connectivity)

O Super App implementa uma política de tratamento explícito para quedas de sinal e falta de conexão com a rede, baseada no pacote `connectivity_plus` e lógica reativa centralizada:

* **Detecção Real de Internet**: Diferente do comportamento padrão que apenas valida a presença de uma interface de rede ativa (Wi-Fi/Celular), o `ConnectivityCubit` realiza verificação de conectividade real via lookup DNS (resolução de endereços públicos e estáveis como `dns.google` e `one.one.one.one` com timeout de 2 segundos). Isso previne falsos positivos em redes cativas ou sem acesso real à internet.
* **Sobreposição Global de Bloqueio (Offline Overlay)**: Quando o dispositivo perde a conectividade real, o widget `GlobalOfflineOverlay` intercepta o `MaterialApp.router` e exibe uma tela impenetrável de aviso offline ("Sem conexão com a internet") com ação de reteste manual.
* **Banner de Alerta (Connectivity Banner)**: Banner animado e discreto que desliza na parte superior da tela para indicar status de rede degradado.
* **Reconexão Reativa & Retentativa (Chats e Corridas)**: O `TrackOrderBloc` (acompanhamento de viagens) e o `HomeBloc` (fluxo de despacho) ouvem a stream do `ConnectivityCubit`. Ao reestabelecer o sinal, os blocos acionam automaticamente a retentativa de envio de mensagens de chat em fila local (`retryPendingMessages`) e reabrem os canais de escuta Supabase Realtime via streams WebSockets.

---

*Documentação consolidada e atualizada em Maio de 2026 — Engenharia Uppi Brasil 🇧🇷*
