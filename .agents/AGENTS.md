# Regras do Projeto (Uppi)

- **Fluxo de Trabalho Git Automático:** Sempre que finalizar o desenvolvimento, correção ou qualquer alteração solicitada no código, o agente deve assumir a responsabilidade de staging, commit e push para o repositório remoto.
  - O fluxo deve ser proposto em sequência no terminal:
    1. `git add .`
    2. `git commit -m "<tipo>: <mensagem em português>"`
    3. `git push`
  - Sempre propor a execução desses comandos assim que a alteração for verificada e concluída.

- **Execução do Flutter Run (Modo Live):** Ao executar o aplicativo em modo "live" ou depuração no celular via USB, utilize apenas o comando padrão `flutter run -d <device_id>`. Nunca tente criar scripts customizados de monitoramento de arquivos (file watcher/Node.js/PowerShell) para forçar o Hot Reload, pois o editor (VS Code) e o próprio Flutter já gerenciam isso nativamente de forma automática ao salvar os arquivos.
