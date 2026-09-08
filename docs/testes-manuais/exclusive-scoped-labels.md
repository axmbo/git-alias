# Fumaça manual — workflow `exclusive-scoped-labels`

Confirma, ponta a ponta, que
[`.github/workflows/exclusive-scoped-labels.yml`](../../.github/workflows/exclusive-scoped-labels.yml)
está vivo e faz o essencial (ver
[ADR-0005](../adr/0005-workflow-de-labels-so-impoe-exclusividade.md)): ao
aplicar `grupo::valor` numa issue, remove as demais `grupo::*` dela; label
sem `::` não mexe em nada.

> **Workflow de evento de repositório só roda a partir de `main`.** Rode
> esta fumaça depois que uma mudança no workflow entrar em `main`.
>
> A matriz de comportamento (grupo diferente intocado, `a::b::c` → grupo
> `a`, retry de replicação, 404 tolerante) é cobertura de teste
> automatizado — issue [#17](https://github.com/axmbo/git-alias/issues/17).

Pré-requisitos: `gh` autenticado, permissão para criar/apagar issue, e o
grupo `priority::p0`…`priority::p3` cadastrado (já é o caso). **Não cria
label** — só a issue-rascunho, apagada no fim.

## Passos

Rode um passo de cada vez, sem outra issue sendo rotulada em paralelo (o
`gh run list -L 1` não distingue).

```sh
# issue-rascunho já com uma prioridade
gh issue create -t "[SCRATCH] smoke exclusive-scoped-labels" \
  -b "Descartável. Apagar ao fim." --label "priority::p1"
#   -> anote o número em N

# 1. substituição exclusiva: aplicar outra prioridade tira a primeira
gh issue edit N --add-label "priority::p3"
sleep 5
gh run list --workflow exclusive-scoped-labels.yml -L 1   # -> completed / success
gh issue view N --json labels --jq '[.labels[].name] | sort'
#   esperado: ["priority::p3"]

# 2. no-op: label sem "::" não remove nada
gh issue edit N --add-label "bug"
sleep 5
gh issue view N --json labels --jq '[.labels[].name] | sort'
#   esperado: ["bug", "priority::p3"]

# limpeza
gh issue delete N --yes
```

> Se o repo ganhar um `grupo:valor` (um `:` só) ou um segundo grupo scoped,
> vale um passo a mais: aplicá-lo e confirmar que não mexe no grupo
> `priority::`.

## Registro de execuções

| Data | Commit de `main` | Resultado | Notas |
|---|---|---|---|
| 2026-09-08 | `cee1c02` | OK | Após o merge do #23 (workflow simplificado, ADR-0005). À época o roteiro tinha 5 casos via `gh`; reduzido a esta fumaça de 2 depois. |
