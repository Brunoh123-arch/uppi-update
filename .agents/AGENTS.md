# Regras do Projeto (Uppi)

- **Fluxo de Trabalho Git Automático:** Sempre que finalizar o desenvolvimento, correção ou qualquer alteração solicitada no código, o agente deve assumir a responsabilidade de staging, commit e push para o repositório remoto.
  - O fluxo deve ser proposto em sequência no terminal:
    1. `git add .`
    2. `git commit -m "<tipo>: <mensagem em português>"`
    3. `git push`
  - Sempre propor a execução desses comandos assim que a alteração for verificada e concluída.

- **Execução do Flutter Run (Modo Live):** Ao executar o aplicativo em modo "live" ou depuração no celular via USB, utilize apenas o comando padrão `flutter run -d <device_id>`. Nunca tente criar scripts customizados de monitoramento de arquivos (file watcher/Node.js/PowerShell) para forçar o Hot Reload, pois o editor (VS Code) e o próprio Flutter já gerenciam isso nativamente de forma automática ao salvar os arquivos.

- **Evitar Superengenharia e Alucinações:** O agente deve priorizar sempre as soluções mais simples, diretas e nativas do próprio framework. Não crie scripts adicionais ou ferramentas paralelas sem necessidade real. Evite propor complexidades desnecessárias ou inventar soluções de contorno para ferramentas oficiais estáveis (como o Flutter CLI e VS Code).

- **Força Máxima e Inteligência Suprema:** O agente deve agir com o máximo de precisão, foco e inteligência. Resolva os problemas de ponta a ponta de forma direta, analisando logs reais e aplicando correções definitivas no código. Evite suposições superficiais, siga as instruções à risca e mantenha a qualidade de código em nível sênior.

- **Ambiente de Testes e Login Real:** O login nos aplicativos (Passageiro e Motorista) em ambiente de teste deve ser feito sempre usando as credenciais oficiais de teste (+55 11 99999-9999 / OTP 123456) configuradas no Firebase. Nunca crie botões visuais de desvio de login (Bypass / Ignorar Login) na interface de produção.

- **Google Maps e Chaves de API:** Chaves de API (especialmente da Google Maps API) devem ser lidas estritamente do arquivo `.env` local, sem codificação estática. Se o carregamento de configurações do Supabase falhar (Timeout), o aplicativo deve prosseguir usando o fallback local com a chave do `.env`.

- **Deploy na Play Store (Fastlane):** O deploy do app na Play Store é feito navegando até a pasta `apps/rider-frontend/android` e executando `fastlane beta`. O `versionCode` no arquivo `pubspec.yaml` do rider-frontend deve ser incrementado antes de cada nova build de deploy.

- **Fluxo de Trabalho Git (Sincronização para Trabalho Remoto):** Sempre que concluir qualquer alteração solicitada, o agente deve propor e rodar os comandos `git add .`, `git commit -m "<tipo>: <mensagem em português>"` e `git push` para sincronizar o repositório remoto e permitir que o usuário trabalhe do escritório de forma transparente.

- **Ciclo de Autoanálise e Qualidade Máxima (Loop de Correção):** Ao receber qualquer tarefa de desenvolvimento, depuração ou ajuste visual, o agente deve entrar em um ciclo interno de autoavaliação antes de dar o trabalho como concluído.
  1. **Implementar:** Fazer a alteração no código de forma limpa.
  2. **Verificar e Compilar:** Executar ou atualizar no dispositivo e analisar logs e erros.
  3. **Autoanalisar:** Identificar pontos fortes, possíveis brechas, bugs de layout ou inconsistências no fluxo.
  4. **Refinar:** Corrigir os pontos fracos identificados.
  5. **Entrega Final:** Só reportar o resultado ao usuário quando tiver alcançado o nível máximo de qualidade possível.
