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
- A label default do GitHub `bug` presente (usada no caso 3).
- `gh` autenticado.

## Setup

**Preflight** — as labels auxiliares têm nome fixo. Se qualquer uma já
existir, **pare**: pode ser config real do repo, e o teardown apagaria.
Renomeie/remova antes, ou investigue.

```sh
for l in "type::feature" "priority:p2" "priority::"; do
  gh label list -L 200 --json name --jq '.[].name' | grep -qxF "$l" &&
    { echo "ABORTAR: label '$l' já existe"; break; }
done
```

Se o preflight passou limpo:

```sh
# issue-rascunho, já com uma label de prioridade
gh issue create -t "[SCRATCH] teste exclusive-scoped-labels" \
  -b "Descartável. Apagar ao fim." --label "priority::p1"
#   -> anote o número em N

gh label create "type::feature" --color 1D76DB -d "[scratch]"
gh label create "priority:p2"   --color FBCA04 -d "[scratch] typo de um :"
gh label create "priority::"    --color cccccc -d "[scratch] valor vazio"
```

## Como observar cada caso

`gh run list -L 1` logo após a ação pode devolver o run **anterior** (o
evento ainda não foi enfileirado). Para cada caso:

```sh
# 1. ID do último run ANTES da ação
PREV=$(gh run list --workflow exclusive-scoped-labels.yml -L 1 --json databaseId --jq '.[0].databaseId')

# 2. dispare a ação (a coluna "Ação" da tabela)
gh issue edit N --add-label "…"

# 3. espere surgir um run novo e aguarde-o terminar
until NEW=$(gh run list --workflow exclusive-scoped-labels.yml -L 1 --json databaseId --jq '.[0].databaseId'); [ "$NEW" != "$PREV" ]; do sleep 3; done
gh run watch "$NEW" --exit-status        # falha se o run falhar

# 4. confira o estado
gh issue view N --json labels --jq '[.labels[].name] | sort'
```

No **caso 6** (remover label), o passo 3 é ao contrário: espere alguns
segundos e confirme que `NEW` continua igual a `PREV` — nenhum run novo.

## Casos

| # | Situação | Estado antes | Ação (`gh issue edit N …`) | Esperado depois |
|---|---|---|---|---|
| 1 | **Substituição exclusiva** — o caso central | `[priority::p1]` | `--add-label "priority::p3"` | `[priority::p3]` — a anterior sai |
| 2 | **Grupo diferente não é tocado** | `[priority::p3]` | `--add-label "type::feature"` | `[priority::p3, type::feature]` — nada removido |
| 3 | **Label solta** | `[priority::p3, type::feature]` | `--add-label "bug"` | as três presentes — nada removido |
| 4 | **Typo de um `:`** — grupo já exclusivo | `[bug, priority::p3, type::feature]` | `--add-label "priority:p2"` | `[bug, priority::p2, type::feature]` — vira `::`, `priority::p3` sai, `priority:p2` some |
| 5 | **Guarda de valor vazio** | `[bug, priority::p2, type::feature]` | `--add-label "priority::"` | `priority::` presente e **`priority::p2` continua** — o guard barra |
| 6 | **Remover label não dispara nada** | qualquer | `--remove-label "bug"` | nenhum run novo (ver acima); nada mais muda |

### Opcionais (criam label nova no repositório — o teardown já cobre)

| # | Situação | Passos | Esperado |
|---|---|---|---|
| 7 | **Criação de label** | `gh label create "area::seed" --color ededed -d "[scratch]"` (pré-condição: o grupo `area` passa a ser exclusivo); `gh label create "area:web" --color ededed -d "[scratch]"`; `gh issue edit N --add-label "area:web"` | workflow cria `area::web`, aplica na issue, remove `area:web` |
| 8 | **Namespacing livre** | `gh label create "topic:docs" --color ededed -d "[scratch]"` (nenhum `topic::` existe); `gh issue edit N --add-label "topic:docs"` | `topic:docs` fica como está — não é reescrita, nada removido |

## Fora de escopo (não reproduzível à mão de forma confiável)

- Corrida de duas escritas do mesmo grupo no mesmo segundo — pode deixar o
  grupo sem label.
- Lag de réplica além do retry de 1,5 s — pode deixar duas labels.

Ambas são limitações *best-effort* documentadas no cabeçalho do workflow e
na seção "Labels de issue" do `CONTRIBUTING.md`.

## Teardown

Apague **só** o que este run criou.

```sh
gh issue delete N --yes
gh issue view N >/dev/null 2>&1 && echo "ATENÇÃO: issue N ainda existe"

# labels do setup, sempre:
for l in "type::feature" "priority:p2" "priority::"; do gh label delete "$l" --yes; done
# labels dos opcionais, só se rodou o caso:
for l in "area::seed" "area:web" "area::web" "topic:docs"; do
  gh label list -L 200 --json name --jq '.[].name' | grep -qxF "$l" && gh label delete "$l" --yes
done

gh label list -L 200 --json name,description --jq '.[] | select(.description | test("scratch"; "i")) | .name'
# ^ não deve listar nada; se listar, é label de outro teste sua para limpar
```

`bug` e o grupo `priority::p0..p3` são labels reais — **não** apague.

## Registro de execuções

| Data | Commit de `main` | Casos | Resultado | Notas |
|---|---|---|---|---|
| 2026-09-08 | `19cd392` | 1, 2, 3, 4, 5 (via `gh`, sem passo 6) | 5/5 OK | 1ª execução, logo após o merge do #16. Caminho de criação de label (`ensureRepoLabel` → 404 → `createLabel`) não exercitado ao vivo — só coberto agora pelo caso 7. |
