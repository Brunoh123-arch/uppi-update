# 🛠️ Relatório de Melhorias & Guia do Ambiente de Staging

> Este documento resume as melhorias arquiteturais, de testes e infraestrutura que foram implementadas, além de servir como guia rápido de consulta sobre o funcionamento do ambiente de Staging.

---

## 🚀 Como Funciona o Ambiente de Staging (Homologação)?

O ambiente de **Staging** é um "espelho de testes" do projeto real (Produção). Ele serve para testar novas corridas, motoristas, cupons e pagamentos simulados sem afetar os dados reais de produção.

### 1. O Mecanismo Técnico
Nos arquivos `main.dart` do `rider-frontend` e do `admin_panel`, adicionamos a verificação da variável de compilador Dart `ENV`:

```dart
const String env = String.fromEnvironment('ENV', defaultValue: 'prod');
if (env == 'staging') {
  await dotenv.load(fileName: '.env.staging');
} else {
  await dotenv.load(fileName: '.env');
}
```

* **Modo Produção (Padrão):** Carrega o arquivo `.env` (Supabase oficial, chaves reais do Google Maps e pagamentos).
* **Modo Staging:** Carrega o arquivo `.env.staging` (Supabase de testes/homologação e chaves mockadas).

### 2. Comandos Úteis para o Dia a Dia

Sempre que quiser alternar os ambientes, adicione a flag `--dart-define=ENV=staging`:

* **Rodar o Super App no Celular em modo Staging:**
  ```bash
  cd apps/rider-frontend
  flutter run --dart-define=ENV=staging
  ```
* **Compilar o APK/AAB de Homologação para a Google Play (Testes Internos):**
  ```bash
  cd apps/rider-frontend
  flutter build appbundle --release --dart-define=ENV=staging
  ```
* **Rodar o Painel Admin Web conectado ao Staging:**
  ```bash
  cd apps/admin_panel
  flutter run -d chrome --dart-define=ENV=staging
  ```

Os novos templates de `.env.staging` já estão declarados nos assets dos `pubspec.yaml`, garantindo que o Flutter os empacote nas builds.

---

## 🛠️ Resumo de Melhorias Implementadas

### 1. Testes Automatizados no Painel Admin (`admin_panel`)
- Criada a pasta de testes para o painel administrativo.
- Adicionado o arquivo `apps/admin_panel/test/admin_menu_test.dart` com suite de testes unitários para o menu.
- Atualizado o `melos.yaml` para executar e integrar os testes do painel no pipeline, ignorando as bibliotecas sem testes.

### 2. Decomposição de Layout (`admin_panel`)
- O arquivo principal de layout `main_dashboard_layout.dart` foi limpo, extraindo componentes complexos em arquivos dedicados:
  - `apps/admin_panel/lib/layout/widgets/sidebar_item.dart` (Item de menu lateral)
  - `apps/admin_panel/lib/layout/widgets/sos_alert_dialog.dart` (Dialog de alerta SOS)

### 3. Limpeza do Módulo do Motorista (`driver-frontend`)
- Como o motorista roda unificado no Super App, removemos as pastas nativas obsoletas em `apps/driver-frontend/` (`android/`, `ios/`, `macos/`, `web/`).
- Atualizado o script de produção `build_production.sh` na raiz do projeto para remover as etapas redundantes de compilação independente do motorista.

### 4. Pipeline de CI/CD para iOS
- Atualizado o `.github/workflows/flutter_ci.yml` adicionando o job `build_ios` em macOS para garantir a compatibilidade e compilação do iOS no pipeline.

### 5. Configuração do Git (`.gitignore`)
- Adicionada exceção no `.gitignore` para o arquivo `.env.staging` (`!.env.staging`). Isso permite que os novos modelos de configuração do Staging sejam monitorados e compartilhados com o time via controle de versão.

### 8. Automação de Publicação de iOS/Android (Fastlane)
- **[Novo - iOS]** [Appfile](file:///c:/Users/Dell/Downloads/Uppi%20v.18.0/apps/rider-frontend/ios/fastlane/Appfile) e [Fastfile](file:///c:/Users/Dell/Downloads/Uppi%20v.18.0/apps/rider-frontend/ios/fastlane/Fastfile): Automação para compilar e enviar builds iOS para o TestFlight (`fastlane beta`).
- **[Novo - Android]** [Appfile](file:///c:/Users/Dell/Downloads/Uppi%20v.18.0/apps/rider-frontend/android/fastlane/Appfile) e [Fastfile](file:///c:/Users/Dell/Downloads/Uppi%20v.18.0/apps/rider-frontend/android/fastlane/Fastfile): Automação para compilar o AAB (App Bundle) e fazer o upload do track interno do Google Play Console.

### 9. Banco de Dados com Dados de Teste (Seeding de Staging)
- **[Modificado]** [seed.sql](file:///c:/Users/Dell/Downloads/Uppi%20v.18.0/supabase/seed.sql): Populadas tabelas do Supabase com dados realistas (motoristas, passageiros, localizações geoespaciais em Castanhal e histórico de corridas) para testes rápidos de homologação local/remoto.

### 10. Testes da Biblioteca Compartilhada (flutter_common)
- **[Novo]** [utils_test.dart](file:///c:/Users/Dell/Downloads/Uppi%20v.18.0/libs/flutter_common/test/utils_test.dart): Criados testes automatizados para validadores e formatadores (CPF, Uppercase) da biblioteca compartilhada.
- **[Modificado]** [melos.yaml](file:///c:/Users/Dell/Downloads/Uppi%20v.18.0/melos.yaml): Habilitados os testes para `flutter_common`.

### 11. Decomposição Modular do Dashboard Admin (`OverviewDashboardScreen`)
- O arquivo massivo de 107 KB foi decomposto. Seus componentes visuais principais foram migrados para widgets reutilizáveis e isolados na pasta [widgets](file:///c:/Users/Dell/Downloads/Uppi%20v.18.0/apps/admin_panel/lib/features/dashboard/widgets/):
  - `pulsing_indicator.dart`: Indicador animado pulsante.
  - `kpi_card.dart`: Painel de visualização de métricas (conversão, faturamento, etc).
  - `live_status_card.dart`: Monitoramento de corridas ativas por status.
  - `dashboard_chart_box.dart`: Abstração de desenho de gráficos com a biblioteca `fl_chart`.
  - `top_drivers_section.dart`: Tabela de ranking dos 5 melhores motoristas com delegação de eventos via callbacks.

---

## 🧪 Verificação e Validação

- **Melos Bootstrap**: Executado com sucesso.
- **Suíte de Testes**: Todos os testes do `admin_panel`, `flutter_common`, `rider_flutter` e `uppi_motorista` executados localmente via Melos e aprovados com 100% de sucesso.
- **Análise Estática**: Executada em todos os pacotes do monorepo, atestando conformidade estrutural.
