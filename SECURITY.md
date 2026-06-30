# 🛡️ Política de Segurança — Uppi Brasil

Esta política descreve as diretrizes para notificação de vulnerabilidades no ecossistema Uppi (aplicativos móveis, painel de controle administrativo e infraestrutura backend baseada em Supabase).

---

## 🇧🇷 1. Notificação Responsável de Vulnerabilidades

A segurança dos motoristas, passageiros e dados de pagamentos é a nossa prioridade máxima. Se você descobrir qualquer brecha de segurança ou vulnerabilidade operacional no sistema Uppi, solicitamos que nos notifique de maneira responsável e confidencial.

### Como Enviar um Relatório
Por favor, envie um e-mail detalhado para:  
📧 **seguranca@uppi.com.br**

Para nos ajudar a avaliar e corrigir a vulnerabilidade o mais rápido possível, inclua em seu relatório:
* **Descrição Detalhada**: Um resumo claro do comportamento inesperado e o impacto potencial.
* **Passos para Reproduzir (PoC)**: Código de exemplo, payloads HTTP ou passos sequenciais para demonstrar a falha.
* **Ambiente Afetado**: Especifique se a vulnerabilidade reside no Rider App, Driver App, Admin Panel ou em uma Edge Function específica do Supabase.

### Nosso Compromisso
* Responderemos ao seu relatório em até **48 horas úteis**.
* Manteremos você atualizado sobre a triagem e o progresso da correção.
* Nós **não tomaremos medidas judiciais ou de repressão** contra pesquisadores que ajam de boa fé, respeitem a privacidade dos dados de nossos usuários reais e nos deem tempo razoável para corrigir a falha antes de qualquer divulgação pública.

---

## 🇺🇸 2. Security & Vulnerability Disclosure Policy (English)

We take the security of our riders, drivers, and payment systems extremely seriously. If you find any security vulnerability in the Uppi ecosystem, please report it to us privately and responsibly.

### How to Report
Please email your findings to:  
📧 **seguranca@uppi.com.br**

To help us evaluate and patch the issue quickly, please include:
* **Description**: A clear summary of the vulnerability and its potential impact.
* **Proof of Concept (PoC)**: Sample code, HTTP payloads, or clear step-by-step instructions to reproduce the issue.
* **Affected Area**: Identify whether the bug is in the Rider App, Driver App, Admin Panel, or inside a specific Supabase Edge Function.

### Our Commitment
* We will acknowledge receipt of your report within **48 business hours**.
* We will keep you updated as we triage and remediate the issue.
* We **will not pursue legal action** against security researchers who act in good faith, do not compromise private user data, and give us a reasonable amount of time to patch the vulnerability prior to public disclosure.

---

## 🔒 3. Práticas de Hardening Ativas no Projeto

Como parte de nossa infraestrutura de segurança moderna (Nível Uber/99), implementamos e mantemos:
* **Edge Function First (Bypass Protection)**: Todos os aplicativos clientes possuem permissões de escrita nulas ou extremamente restritas no banco de dados Supabase. Alterações de estado de corridas, saques e KYC são processadas exclusivamente por Edge Functions que verificam tokens JWT e identidades dos usuários server-side.
* **Criptografia Simétrica Transparente**: CPFs de usuários e dados de contas de repasse bancário (PIX) são protegidos usando criptografia em repouso por cifra simétrica com a extensão `pgcrypto` do PostgreSQL, mitigando vazamento físico de base de dados.
* **Row-Level Security (RLS) Restrita**: Todas as tabelas possuem políticas de RLS ativadas, impedindo a leitura não autorizada de dados operacionais e financeiros por usuários maliciosos.
