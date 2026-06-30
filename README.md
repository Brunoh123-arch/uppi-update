# 🚗 Uppi — Super App de Mobilidade Urbana

> Plataforma de transporte urbano desenvolvida em Flutter, integrando **Passageiro**, **Motorista** e **Painel Administrativo** em um único ecossistema.

---

## 🏗️ Arquitetura do Monorepo

```
Uppi/
├── apps/
│   ├── rider-frontend/       # Super App unificado (Passageiro + Motorista)
│   ├── driver-frontend/      # Módulo do Motorista (importado pelo rider)
│   └── admin_panel/          # Painel Administrativo (Flutter Web)
├── libs/
│   ├── flutter_common/       # Componentes, entidades e utils compartilhados
│   └── generic_map/          # Abstração de mapas (Google Maps / Leaflet / MapBox)
├── supabase/
│   ├── functions/            # 58 Edge Functions (Deno/TypeScript)
│   └── migrations/           # Migrações SQL (PostgreSQL)
│   └── seeds/                # Triggers e expire scripts (PostgreSQL)
├── scripts/
│   ├── build/                # Scripts de build (.bat)
│   └── dev/                  # Scripts de desenvolvimento e config (.bat)
├── docs/                     # Documentação técnica
└── .github/workflows/        # CI/CD (GitHub Actions)
```

> ⚠️ **IMPORTANTE:** O `driver-frontend` é um **módulo** consumido pelo `rider-frontend`.
> Nunca compile ou rode ele isoladamente.

---

## 🚀 Stack Tecnológica

| Camada | Tecnologia |
|---|---|
| **Frontend** | Flutter (Dart) + BLoC/Cubit |
| **Backend** | Supabase Edge Functions (Deno/TypeScript) |
| **Banco de Dados** | Supabase PostgreSQL + PostGIS |
| **Autenticação** | Firebase Auth (SMS + Google Sign-In) |
| **Storage** | Supabase Storage (documentos e avatares) |
| **Pagamentos** | Mercado Pago (PIX via QR Code) |
| **Push Notifications** | Firebase Cloud Messaging (FCM) |
| **Hosting (Admin)** | Firebase Hosting |
| **Mapas** | Google Maps / OpenStreetMap (Leaflet) — configurável via Admin Panel |
| **Roteamento** | AutoRoute |
| **DI** | Injectable / GetIt |
| **Monitoramento** | Sentry (crash reporting + performance) |

---

## 🛠️ Setup de Desenvolvimento

### Pré-requisitos
- [Flutter SDK](https://flutter.dev/docs/get-started/install) v3.27+
- [Supabase CLI](https://supabase.com/docs/guides/cli)
- Conta no [Firebase Console](https://console.firebase.google.com/) (para Auth + FCM)

### 1. Clonar e instalar dependências
```bash
git clone <repo-url>
cd Uppi

# Instalar dependências de todos os projetos e linkar pacotes locais
melos bootstrap
```

### 2. Configurar variáveis de ambiente
```bash
# Copiar o template e preencher com suas chaves
cp apps/rider-frontend/.env.example apps/rider-frontend/.env
```

Variáveis necessárias:
| Variável | Onde encontrar |
|---|---|
| `SUPABASE_URL` | Supabase Dashboard → Settings → API |
| `SUPABASE_ANON_KEY` | Supabase Dashboard → Settings → API |
| `SENTRY_DSN` | Sentry → Project Settings → DSN |

### 3. Rodar o projeto
```bash
# App principal (Android/iOS)
cd apps/rider-frontend
flutter run

# App Web (porta 3000)
flutter run -d chrome --web-port 3000

# Painel Administrativo
cd apps/admin_panel
flutter run -d chrome
```

---

## 📦 Deploy

### App Mobile (Google Play)
```bash
cd apps/rider-frontend
flutter build appbundle --release
```

### Painel Admin (Firebase Hosting)
```bash
cd apps/admin_panel
flutter build web
firebase deploy --only hosting
```

### Backend (Supabase Edge Functions)
```bash
# Deploy de todas as funções
supabase functions deploy

# Deploy de uma função específica
supabase functions deploy start-order

# Aplicar migrações ao banco
supabase db push
```

---

## 🗺️ Sistema de Mapas

O provedor de mapas é **controlado dinamicamente pelo Painel Admin**:
- **OpenStreetMap (Leaflet)**: Gratuito, sem necessidade de API Key.
- **Google Maps**: Requer API Key configurada no Painel Admin.
- **MapBox**: Requer token configurado no `.env`.

A troca de mapa é instantânea para todos os usuários conectados (via Supabase Realtime).

---

## 🛡️ Arquitetura Edge Function First (Segurança Hardened)

A plataforma Uppi adota uma arquitetura rigorosa de **"Edge Function First"** para todas as operações críticas de gravação no banco de dados (`INSERT`, `UPDATE` e `DELETE`). Isso elimina qualquer possibilidade de bypass de segurança (RLS) no lado do cliente.

### Princípios de Segurança Implementados:
- **Zero Gravações Diretas do Cliente**: Nenhum aplicativo mobile (Rider ou Driver) faz chamadas diretas de escrita no banco de dados Supabase via `supabase.from().insert()`, `update()` ou `delete()`.
- **Validação Server-Side**: Todas as ações de persistência de dados são validadas e processadas no lado do servidor através de Edge Functions em Deno/TypeScript.
- **Verificação de Identidade Inabalável**: Cada Edge Function decodifica o cabeçalho de autorização JWT (`Authorization: Bearer <token>`) enviada pelo cliente, extrai o `uid` (Auth) do usuário autenticado e verifica a propriedade de forma estrita contra o banco de dados antes de processar qualquer alteração.
- **Consolidação de Fluxos**:
  - **`user-actions`**: EF centralizada para operações CRUD em tabelas de usuário (`favorite_addresses`, `payment_methods`, `payout_accounts`).
  - **`sync-profile`**: EF robusta responsável pela sincronização de dados de cadastro e documentos de identidade (KYC).
  - **`submit-feedback`**: EF otimizada para recepção segura de feedbacks e reclamações (`is_complaint: true/false`).

---

## 🔒 Segurança & RLS

- **NUNCA** commite chaves privadas, `.env` ou keystores (`.jks`).
- Chaves públicas do Supabase/Firebase ficam nos arquivos de configuração do Flutter.
- **Service Role Keys** ficam exclusivamente nas Edge Functions (server-side).
- Uploads no Storage são estritamente protegidos por políticas RLS robustas.
- O banco de dados PostgreSQL possui políticas de **Row Level Security (RLS)** ativas em 100% das tabelas, garantindo segurança em múltiplas camadas caso o cliente tente ler dados diretamente.

---

## 🧹 Manutenção, Otimização & Limpeza

O monorepo foi totalmente limpo e reestruturado para máxima velocidade de compilação e leveza de armazenamento:

```bash
# 1. Limpar caches e reinstalar dependências em todo o Workspace (Melos)
melos bootstrap

# 2. Recompilar e gerar códigos do build_runner (freezed, injectable, auto_route) em todos os pacotes
melos run build:runner

# 3. Formatar código
dart format .

# 4. Análise estática
melos run analyze
```

### Otimizações Recentes:
- **Redução Física do Workspace**: Remoção de caches inflados do Gradle (`.gradle/`), arquivos temporários redundantes (`Temp/`), diretórios órfãos do `.fvm` e resíduos antigos de compilação, diminuindo o tamanho geral do projeto.
- **Flatenização de Diretórios**: Toda a estrutura de pastas redundantes e aninhadas (`Uppi 3.0/Uppi 3.0/Uppi 2.0/`) foi 100% achatada e unificada diretamente na raiz do workspace.
- **Centralização de Assets**: Fontes e animações Lottie duplicadas foram consolidadas sob o pacote `libs/flutter_common/assets` para pavimentar o caminho para a eliminação total de redundâncias visuais.

---

## 📁 Scripts Utilitários

| Script | Descrição |
|--------|-----------|
| `scripts/dev/abrir_app_web.bat` | Abre o Super App na Web (porta 3000) |
| `scripts/dev/abrir_admin_panel.bat` | Abre o Painel Administrativo na Web (porta 4000) |
| `scripts/dev/configurar_mercadopago.bat` | Configura chaves do Mercado Pago interativamente |
| `scripts/dev/transformar_em_admin.bat` | Promove um usuário a administrador do sistema |
| `scripts/build/gerar_build_producao.bat` | Gera `.aab` e `.apk` de produção com ofuscação (Windows) |
| `scripts/build/build_production.sh` | Gera `.aab` e `.apk` de produção com ofuscação (Linux/macOS/CI) |
| `scripts/build/gerar_android_apk_teste.bat` | Gera `.apk` rápido para testes locais |
| `scripts/build/limpar_e_atualizar.bat` | Limpa todos os builds e executa bootstrap no workspace |
| `scripts/backup_data.js` | Faz backup completo das tabelas do banco (requer `SUPABASE_SERVICE_KEY`) |

---

*Mantido pela equipe Uppi Brasil. 🇧🇷*

