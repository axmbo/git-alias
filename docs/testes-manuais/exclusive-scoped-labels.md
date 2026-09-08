# Roteiro manual — workflow `exclusive-scoped-labels`

Verifica o comportamento de
[`.github/workflows/exclusive-scoped-labels.yml`](../../.github/workflows/exclusive-scoped-labels.yml)
numa issue descartável, contra a API real do GitHub.

O workflow faz **uma** coisa (ver
[ADR-0005](../adr/0005-workflow-de-labels-so-impoe-exclusividade.md)): ao
aplicar `grupo::valor` bem-formado, remove as demais `grupo::*` da issue.
Não reescreve `grupo:valor`, não cria label, não normaliza caixa.

Por que manual: reage a `issues.labeled` e mexe em labels via API — a
suíte estática de `tests/` só checa a forma do `script:`, não o roda (a
issue [#17](https://github.com/axmbo/git-alias/issues/17) rastreia tirar o
JS de dentro do YAML para um módulo com teste automatizado).

> **Um workflow de evento de repositório (`issues`, `label`, …) só roda a
> partir do branch _default_ (`main`).** Para testar uma *alteração* neste
> workflow, ela precisa já estar em `main`.

Convenções gerais de teste manual: ver a seção **Testes manuais** do
[`CONTRIBUTING.md`](../../CONTRIBUTING.md).

## Pré-requisitos

- Permissão para criar/apagar issue e label no repositório.
- O grupo `priority::p0`…`priority::p3` cadastrado (já é o caso).
- A label default do GitHub `bug` presente (caso 3).
- `gh` autenticado.

## Setup

**Preflight** — as labels auxiliares têm nome fixo. Rode isto; se listar
**qualquer** nome, **pare**: é config real do repo, e o teardown a
apagaria. Investigue antes.

```sh
for l in "type::scratch" "area:scratch" "priority::"; do
  gh label list -L 200 --json name --jq '.[].name' | grep -qxF "$l" && echo "JÁ EXISTE: $l"
done
```

Preflight limpo → crie a issue (**sem** label) e as auxiliares:

```sh
gh issue create -t "[SCRATCH] teste exclusive-scoped-labels" \
  -b "Descartável. Apagar ao fim."
#   -> anote o número em N

gh label create "type::scratch" --color ededed -d "[scratch]"
gh label create "area:scratch"  --color ededed -d "[scratch] um :"
gh label create "priority::"    --color ededed -d "[scratch] valor vazio"
```

## Como observar cada caso

Rode um caso de cada vez, sem outra issue sendo rotulada em paralelo (senão
o `gh run list` pode pegar o run errado):

```sh
gh issue edit N --add-label "…"                 # a ação (coluna "Ação" da tabela)
sleep 3
RUN=$(gh run list --workflow exclusive-scoped-labels.yml -L 1 --json databaseId --jq '.[0].databaseId')
gh run watch "$RUN" --exit-status               # falha se o run falhar
gh issue view N --json labels --jq '[.labels[].name] | sort'   # confira o estado
```

**Caso 6** (remover label): não há run esperado. Faça o `--remove-label`,
espere ~15 s e confirme que `gh run list -L 3` não tem run novo e que as
labels não mudaram.

## Casos

| # | Situação | Estado antes | Ação (`gh issue edit N …`) | Esperado depois |
|---|---|---|---|---|
| 0 | **Semear a prioridade** | `[]` | `--add-label "priority::p1"` | `[priority::p1]` — run roda, nada a reconciliar |
| 1 | **Substituição exclusiva** — o caso central | `[priority::p1]` | `--add-label "priority::p3"` | `[priority::p3]` — a anterior sai |
| 2 | **Grupo diferente não é tocado** | `[priority::p3]` | `--add-label "type::scratch"` | `[priority::p3, type::scratch]` — nada removido |
| 3 | **Label solta** | `[priority::p3, type::scratch]` | `--add-label "bug"` | as três presentes — nada removido |
| 4 | **Um `:` só — namespacing livre** | `[bug, priority::p3, type::scratch]` | `--add-label "area:scratch"` | `area:scratch` fica como está — **não** vira `area::scratch`, nada removido |
| 5 | **Valor vazio — não casa** | `[area:scratch, bug, priority::p3, type::scratch]` | `--add-label "priority::"` | `priority::` presente e **`priority::p3` continua** — a regex não casa |
| 6 | **Remover label não dispara nada** | qualquer | `--remove-label "bug"` | nenhum run novo (ver acima); nada mais muda |

## Fora de escopo (não reproduzível à mão de forma confiável)

- Corrida de duas escritas do mesmo grupo no mesmo segundo — pode deixar o
  grupo sem label.
- Lag de réplica além do único retry — pode deixar duas labels.

Ambas são limitações *best-effort* documentadas no cabeçalho do workflow e
no [ADR-0005](../adr/0005-workflow-de-labels-so-impoe-exclusividade.md).

## Teardown

O preflight garantiu que nenhuma dessas labels existia antes; se o setup e
os casos rodaram, elas são deste run. Ainda assim, cada `delete` é
guardado por existência.

```sh
gh issue delete N --yes
gh issue view N >/dev/null 2>&1 && echo "ATENÇÃO: issue N ainda existe"

for l in "type::scratch" "area:scratch" "priority::"; do
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
| 2026-09-08 | `cee1c02` | 0–5 (via `gh`) | 6/6 OK | Após o merge do #23 (workflow simplificado, ADR-0005). Caso 4 confirma que `area:scratch` não é reescrita. |
