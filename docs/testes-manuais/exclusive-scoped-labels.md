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

**Preflight** — as labels auxiliares têm nome fixo. Rode isto; se listar
**qualquer** nome, **pare**: é config real do repo, e o teardown a
apagaria. Investigue antes.

```sh
for l in "type::feature" "priority:p2" "priority::" \
         "area::seed" "area:web" "area::web" "topic:docs"; do
  gh label list -L 200 --json name --jq '.[].name' | grep -qxF "$l" && echo "JÁ EXISTE: $l"
done
```

Preflight limpo → crie a issue (**sem** label) e as auxiliares do bloco
principal:

```sh
gh issue create -t "[SCRATCH] teste exclusive-scoped-labels" \
  -b "Descartável. Apagar ao fim."
#   -> anote o número em N

gh label create "type::feature" --color 1D76DB -d "[scratch]"
gh label create "priority:p2"   --color FBCA04 -d "[scratch] typo de um :"
gh label create "priority::"    --color cccccc -d "[scratch] valor vazio"
```

As labels dos casos opcionais (7/8) são criadas no próprio caso.

## Como observar cada caso

`gh run list -L 1` pode devolver o run **anterior** (o evento ainda não foi
enfileirado) ou o run de **outra** issue. Filtre pelos runs desta issue e
espere um ID novo:

```sh
run_id() {
  gh run list --workflow exclusive-scoped-labels.yml -L 20 \
    --json databaseId,displayTitle \
    --jq '[.[] | select(.displayTitle == "[SCRATCH] teste exclusive-scoped-labels")][0].databaseId // empty'
}
```

Para cada caso:

```sh
PREV=$(run_id)                                   # ID do último run desta issue, antes da ação
gh issue edit N --add-label "…"                  # a ação (coluna "Ação" da tabela)
until NEW=$(run_id); [ -n "$NEW" ] && [ "$NEW" != "$PREV" ]; do sleep 3; done
gh run watch "$NEW" --exit-status               # falha se o run falhar
gh issue view N --json labels --jq '[.labels[].name] | sort'   # confira o estado
```

**Caso 6** (remover label): não há run esperado. Guarde `PREV=$(run_id)`,
faça o `--remove-label`, espere ~20 s e confirme que `run_id` continua
igual a `PREV`.

## Casos

| # | Situação | Estado antes | Ação (`gh issue edit N …`) | Esperado depois |
|---|---|---|---|---|
| 0 | **Semear a prioridade** | `[]` | `--add-label "priority::p1"` | `[priority::p1]` — run roda, nada a reconciliar |
| 1 | **Substituição exclusiva** — o caso central | `[priority::p1]` | `--add-label "priority::p3"` | `[priority::p3]` — a anterior sai |
| 2 | **Grupo diferente não é tocado** | `[priority::p3]` | `--add-label "type::feature"` | `[priority::p3, type::feature]` — nada removido |
| 3 | **Label solta** | `[priority::p3, type::feature]` | `--add-label "bug"` | as três presentes — nada removido |
| 4 | **Typo de um `:`** — grupo já exclusivo | `[bug, priority::p3, type::feature]` | `--add-label "priority:p2"` | `[bug, priority::p2, type::feature]` — vira `::`, `priority::p3` sai, `priority:p2` some |
| 5 | **Guarda de valor vazio** | `[bug, priority::p2, type::feature]` | `--add-label "priority::"` | `priority::` presente e **`priority::p2` continua** — o guard barra |
| 6 | **Remover label não dispara nada** | qualquer | `--remove-label "bug"` | nenhum run novo (ver acima); nada mais muda |

### Opcionais (criam label nova no repositório — o teardown já cobre)

Confira antes que os nomes usados não existem (o preflight do setup já os cobre).

| # | Situação | Passos | Esperado |
|---|---|---|---|
| 7 | **Criação de label** | `gh label create "area::seed" --color ededed -d "[scratch]"` (agora o grupo `area` é exclusivo); `gh label create "area:web" --color ededed -d "[scratch]"`; `gh issue edit N --add-label "area:web"` | workflow cria `area::web`, aplica na issue, remove `area:web` |
| 8 | **Namespacing livre** | `gh label create "topic:docs" --color ededed -d "[scratch]"` (nenhum `topic::` existe); `gh issue edit N --add-label "topic:docs"` | `topic:docs` fica como está — não é reescrita, nada removido |

## Fora de escopo (não reproduzível à mão de forma confiável)

- Corrida de duas escritas do mesmo grupo no mesmo segundo — pode deixar o
  grupo sem label.
- Lag de réplica além do retry de 1,5 s — pode deixar duas labels.

Ambas são limitações *best-effort* documentadas no cabeçalho do workflow e
na seção "Labels de issue" do `CONTRIBUTING.md`.

## Teardown

O preflight garantiu que nenhuma dessas labels existia antes; se o setup e
os casos rodaram, elas são deste run. Ainda assim, cada `delete` é
guardado por existência.

```sh
gh issue delete N --yes
gh issue view N >/dev/null 2>&1 && echo "ATENÇÃO: issue N ainda existe"

for l in "type::feature" "priority:p2" "priority::" \
         "area::seed" "area:web" "area::web" "topic:docs"; do
  gh label list -L 200 --json name --jq '.[].name' | grep -qxF "$l" && gh label delete "$l" --yes
done

gh label list -L 200 --json name,description \
  --jq '.[] | select(.description | test("scratch"; "i")) | .name'
# ^ lembrete: se listar algo, é label de outro teste seu para limpar
```

`bug` e o grupo `priority::p0..p3` são labels reais — **não** apague.

## Registro de execuções

| Data | Commit de `main` | Casos | Resultado | Notas |
|---|---|---|---|---|
| 2026-09-07 | `19cd392` | 1, 2, 3, 4, 5 (via `gh`, sem passos 0/6) | 5/5 OK | 1ª execução, logo após o merge do #16. Caminho de criação de label (`ensureRepoLabel` → 404 → `createLabel`) não exercitado ao vivo — só coberto agora pelo caso 7. |
