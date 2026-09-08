# Roteiro manual — workflow `exclusive-scoped-labels`

Verifica o comportamento de
[`.github/workflows/exclusive-scoped-labels.yml`](../../.github/workflows/exclusive-scoped-labels.yml)
numa issue descartável, contra a API real do GitHub.

Por que manual: o workflow reage a `issues.labeled` e mexe em labels de
issue via API — não há como exercitar isso na suíte estática de `tests/`
(ver a issue [#17](https://github.com/axmbo/git-alias/issues/17), que
rastreia extrair a lógica para um módulo `.js` com teste automatizado).

> **Um workflow de evento de repositório (`issues`, `label`, …) só roda a
> partir do branch _default_ (`main`).** Para testar uma *alteração* neste
> workflow, ela precisa já estar em `main`.

Convenções gerais de teste manual: ver a seção **Testes manuais** do
[`CONTRIBUTING.md`](../../CONTRIBUTING.md).

## Pré-requisitos

- Permissão para criar/apagar issue e label no repositório.
- O grupo `priority::p0`…`priority::p3` cadastrado (já é o caso).
- `gh` autenticado.

## Setup

```sh
# issue-rascunho, já com uma label de prioridade
gh issue create -t "[SCRATCH] teste exclusive-scoped-labels" \
  -b "Descartável. Apagar ao fim." --label "priority::p1"
#   -> anote o número em N

# labels auxiliares
gh label create "type::feature" --color 1D76DB -d "[scratch]"
gh label create "priority:p2"   --color FBCA04 -d "[scratch] typo de um :"
gh label create "priority::"    --color cccccc -d "[scratch] valor vazio"
```

Depois de **cada** ação, confira o run e o estado da issue:

```sh
gh run list --workflow exclusive-scoped-labels.yml -L 1   # completed / success
gh issue view N --json labels --jq '[.labels[].name] | sort'
```

## Casos

| # | Situação | Estado antes | Ação (`gh issue edit N …`) | Esperado depois |
|---|---|---|---|---|
| 1 | **Substituição exclusiva** — o caso central | `[priority::p1]` | `--add-label "priority::p3"` | `[priority::p3]` — a anterior sai |
| 2 | **Grupo diferente não é tocado** | `[priority::p3]` | `--add-label "type::feature"` | `[priority::p3, type::feature]` — nada removido |
| 3 | **Label solta** | `[priority::p3, type::feature]` | `--add-label "bug"` | as três presentes — nada removido |
| 4 | **Typo de um `:`** — grupo já exclusivo | `[bug, priority::p3, type::feature]` | `--add-label "priority:p2"` | `[bug, priority::p2, type::feature]` — vira `::`, `priority::p3` sai, `priority:p2` some |
| 5 | **Guarda de valor vazio** | `[bug, priority::p2, type::feature]` | `--add-label "priority::"` | `priority::` presente e **`priority::p2` continua** — o guard barra |
| 6 | **Remover label não dispara nada** | qualquer | `--remove-label "bug"` | nenhum run novo; nada mais muda |

### Opcionais (deixam label nova no repositório — apagar depois)

| # | Situação | Ação | Esperado |
|---|---|---|---|
| 7 | **Criação de label** | criar e aplicar `area:web` (um `:`), com algum `area::x` já existente no repo | workflow cria `area::web`, aplica, remove `area:web` |
| 8 | **Namespacing livre** | criar e aplicar `topic:docs` num grupo `topic` **sem** nenhum `topic::` | fica como está — não é reescrita |

## Fora de escopo (não reproduzível à mão de forma confiável)

- Corrida de duas escritas do mesmo grupo no mesmo segundo — pode deixar o
  grupo sem label.
- Lag de réplica além do retry de 1,5 s — pode deixar duas labels.

Ambas são limitações *best-effort* documentadas no cabeçalho do workflow e
na seção "Labels de issue" do `CONTRIBUTING.md`.

## Teardown

```sh
gh issue delete N --yes
for l in "type::feature" "priority:p2" "priority::"; do gh label delete "$l" --yes; done
# + quaisquer labels criadas nos casos 7/8
gh label list -L 100 | grep -i scratch   # deve não retornar nada
```

## Registro de execuções

| Data | Commit de `main` | Casos | Resultado | Notas |
|---|---|---|---|---|
| 2026-09-08 | `19cd392` | 1, 2, 3, 4, 5 (via `gh`, sem passo 6) | 5/5 OK | 1ª execução, logo após o merge do #16. Caminho de criação de label (`ensureRepoLabel` → 404 → `createLabel`) não exercitado ao vivo. |
