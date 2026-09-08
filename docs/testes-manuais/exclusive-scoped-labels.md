# Fumaça manual — workflow `exclusive-scoped-labels`

Confirma, ponta a ponta, que
[`.github/workflows/exclusive-scoped-labels.yml`](../../.github/workflows/exclusive-scoped-labels.yml)
está vivo e impõe a exclusividade de `grupo::valor` (ver
[ADR-0005](../adr/0005-workflow-de-labels-so-impoe-exclusividade.md)).

> **Workflow de evento de repositório só roda a partir de `main`.** Rode
> esta fumaça depois que uma mudança no workflow entrar em `main`.
>
> A matriz de comportamento (grupo diferente, `a::b::c`, retry, 404) é
> cobertura de teste automatizado — issue
> [#17](https://github.com/axmbo/git-alias/issues/17).

Pré-requisitos: `gh` autenticado, permissão para criar/apagar issue, e o
grupo `priority::p0`…`priority::p3` cadastrado (já é o caso). **Não cria
label** — só a issue-rascunho, apagada no fim.

## Passos

No mesmo shell, um bloco de cada vez (por causa do `$N` e da espera).

**Preparo** — issue-rascunho já com uma prioridade (`$N` guarda o número):

```sh
N=$(gh issue create -t "[SCRATCH] smoke exclusive-scoped-labels" \
      -b "Descartável. Apagar ao fim." --label "priority::p1" | grep -oE '[0-9]+$')
echo "issue #$N"
```

**Passo 1 — substituição exclusiva.** Aplicar outra prioridade tira a
primeira; o estado final deve ser só `["priority::p3"]`:

```sh
gh issue edit "$N" --add-label "priority::p3"
sleep 5
gh issue view "$N" --json labels --jq '[.labels[].name] | sort'
```

**Passo 2 — no-op.** Label sem `::` não remove nada; o estado final deve
ser `["bug", "priority::p3"]`:

```sh
gh issue edit "$N" --add-label "bug"
sleep 5
gh issue view "$N" --json labels --jq '[.labels[].name] | sort'
```

**Limpeza:**

```sh
gh issue delete "$N" --yes
```

Se algum passo falhar, o run em
[Actions](https://github.com/axmbo/git-alias/actions/workflows/exclusive-scoped-labels.yml)
diz por quê.

## Registro de execuções

| Data | Commit de `main` | Resultado |
|---|---|---|
| 2026-09-08 | `cee1c02` | OK — verificado ao vivo após o merge do #23 |
