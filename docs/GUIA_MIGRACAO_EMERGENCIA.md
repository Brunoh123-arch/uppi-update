# 🚨 Plano de Evacuação e Migração de Emergência — Uppi (Supabase)

Este guia prático ensina o passo a passo de como migrar rapidamente o ecossistema Uppi (banco de dados, dados de produção, chaves de API e Edge Functions) para um novo projeto/conta do Supabase em caso de suspensão de conta, exclusão acidental ou estouro de limites de cota.

---

## 🛠️ Passo 1: Atualize seu Backup de Dados Local
Antes de qualquer mudança, garanta que você tenha a foto mais recente do seu banco de dados rodando o script de backup automatizado que instalamos no projeto:
```bash
npm run backup
```
*Este comando gerará/atualizará o arquivo `backup_dados.sql` na raiz do monorepo, contendo a cópia atualizada de todos os usuários, motoristas e corridas.*

---

## 🆕 Passo 2: Crie a Nova Conta e Projeto no Supabase
1. Acesse o [Dashboard do Supabase](https://supabase.com/dashboard) na nova conta e clique em **New Project**.
2. Escolha o nome do projeto (ex: `Uppi Produção`), defina a **Database Password** (senha do banco) e anote-a em local seguro.
3. Aguarde o projeto terminar de ser provisionado na nuvem.

---

## 🔌 Passo 3: Vincule o Monorepo Local ao Novo Projeto
1. Pegue a referência do seu novo projeto (Project Ref). Você a encontra na URL do seu painel do Supabase:
   * Exemplo: na URL `https://supabase.com/dashboard/project/abcde12345...`, a referência é **`abcde12345`**.
2. Abra o terminal na raiz do projeto local no seu computador e execute:
   ```bash
   npx supabase link --project-ref [SUA_NOVA_PROJECT_REF]
   ```
3. Digite a senha do banco de dados que você definiu ao criar o projeto.

---

## 🚀 Passo 4: Suba a Estrutura do Banco (Tabelas, RLS, Triggers e Funções)
Como toda a infraestrutura está documentada como código nas migrations locais do seu computador, você pode subir o banco de dados completo e vazio rodando um único comando:
```bash
npx supabase db push
```
*Este comando lerá todas as migrations na pasta `supabase/migrations/` e as executará no novo banco remoto da nuvem, deixando a estrutura idêntica à original.*

---

## 💾 Passo 5: Importe os Dados do Backup
Agora vamos povoar o novo banco de dados com todos os seus motoristas, passageiros e histórico de corridas:
1. No painel do seu novo projeto Supabase na web, clique em **SQL Editor** no menu lateral esquerdo.
2. Clique em **New Query** (Nova Consulta).
3. Abra o arquivo `backup_dados.sql` gerado no seu PC, copie todo o seu conteúdo e cole-o no SQL Editor do navegador.
4. Clique em **Run** (Executar) na parte inferior direita do editor.
   * *O script irá desabilitar as triggers temporariamente, limpar as tabelas e povoá-las com os dados originais sem causar erros de integridade.*

---

## 🔑 Passo 6: Envie suas Chaves de API e Segredos do Backend
Para que o novo Supabase consiga enviar notificações Push (Firebase), processar pagamentos (Mercado Pago) e disparar SMS (Twilio), envie as variáveis de ambiente locais do seu PC para o novo servidor:
```bash
npx supabase secrets set --env-file supabase/.env
```

---

## ⚡ Passo 7: Faça o Deploy das Edge Functions
Publique todo o código das Edge Functions do monorepo na nova conta:
```bash
npx supabase functions deploy --all --project-ref [SUA_NOVA_PROJECT_REF] --no-verify-jwt
```

---

## 📱 Passo 8: Aponte o App Flutter para o Novo Supabase
Para finalizar, precisamos que o aplicativo dos passageiros e motoristas se conecte à nova URL e chave:
1. No painel do novo Supabase na web, vá em **Project Settings > API**.
2. Copie a **Project URL** e a **anon key** pública.
3. No código-fonte local do seu monorepo, abra o arquivo:
   * **`apps/rider-frontend/.env`**
4. Substitua os campos correspondentes pelas novas informações:
   ```env
   SUPABASE_URL=https://[SUA_NOVA_PROJECT_REF].supabase.co
   SUPABASE_ANON_KEY=[SUA_NOVA_ANON_KEY]
   ```
5. Salve o arquivo e recompile o seu app móvel normalmente (`flutter run` ou gerando novo APK). O app se conectará instantaneamente ao novo banco na nova conta, mantendo todos os dados intactos!
