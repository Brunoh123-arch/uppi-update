# 🤝 Guia de Contribuição — Uppi

## 🔒 Branch Protection & Code Review (Obrigatório)

O repositório segue uma política estrita de proteção de branches para garantir a qualidade e segurança das entregas em produção:

### Regras da Branch `main` (configurar no GitHub Settings → Branches):
- **Require a pull request before merging** — Nenhum commit direto na `main`. Todo código chega por PR.
- **Require approvals: 1** — Ao menos 1 review aprovado de um membro do time `@uppi-brasil/tech-leads`.
- **Require review from Code Owners** — O arquivo [`.github/CODEOWNERS`](.github/CODEOWNERS) define os revisores obrigatórios por área do monorepo. Mudanças em `supabase/migrations/` exigem aprovação do `@uppi-brasil/backend-team` + `@uppi-brasil/tech-leads`.
- **Require status checks to pass** — O workflow de CI (`flutter_ci.yml`) deve estar verde antes de qualquer merge.
- **Require branches to be up to date** — A branch do PR deve estar atualizada com a `main` antes do merge.
- **Do not allow bypassing the above settings** — Nenhum Admin pode fazer bypass das regras.

---

## Regras de Ouro

1. **Nunca rode `driver-frontend` isoladamente.** Ele é um módulo do `rider-frontend`.
2. **Nunca commite `.env`, keystores (`.jks`) ou service accounts.**
3. **Sempre rode `flutter analyze` antes de abrir um PR.**
4. **Use `debugPrint()` ao invés de `print()`.** O `print()` vaza dados no console de produção.

## Padrões de Código

- **State Management:** BLoC / Cubit (nunca use setState em telas complexas)
- **DI:** Injectable + GetIt (registre dependências via `@injectable`)
- **Roteamento:** AutoRoute (gere rotas com `build_runner`)
- **Nomenclatura:** Arquivos em `snake_case`, classes em `PascalCase`
- **Idioma do código:** Inglês para nomes de variáveis e classes. Português apenas em strings de UI (l10n).

## Estrutura de Features

Cada feature segue a arquitetura limpa:
```
features/
└── nome_da_feature/
    ├── data/
    │   └── repositories/       # Implementação concreta (*.prod.dart)
    ├── domain/
    │   ├── entities/            # Modelos de dados (freezed)
    │   └── repositories/       # Contratos abstratos
    └── presentation/
        ├── blocs/               # Cubits e BLoCs
        ├── screens/             # Telas (*.mobile.dart / *.desktop.dart)
        ├── components/          # Widgets reutilizáveis da feature
        └── widgets/             # Widgets menores
```

## Fluxo de Trabalho

```bash
# 1. Criar branch
git checkout -b feature/nome-da-feature

# 2. Desenvolver e testar
cd apps/rider-frontend
flutter run -d chrome --web-port 3000

# 3. Verificar qualidade
flutter analyze
dart format .

# 4. Commit e PR
git add .
git commit -m "feat: descrição clara da mudança"
git push origin feature/nome-da-feature
```

## Convenções de Commit

| Prefixo | Uso |
|---------|-----|
| `feat:` | Nova funcionalidade |
| `fix:` | Correção de bug |
| `refactor:` | Refatoração sem mudar comportamento |
| `docs:` | Alteração em documentação |
| `chore:` | Manutenção (deps, configs, CI) |
| `style:` | Formatação, espaços, ponto-e-vírgula |
