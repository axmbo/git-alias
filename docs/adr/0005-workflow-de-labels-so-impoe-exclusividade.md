# 5. O workflow de labels só impõe exclusividade

## Status

Aceito — 2026-09-07

Supersede a política de *typo-fix* que o
[`.github/workflows/exclusive-scoped-labels.yml`](../../.github/workflows/exclusive-scoped-labels.yml)
carregou desde o #16 (não formalizada em ADR; discutida no próprio PR).

## Contexto

O #16 entregou um workflow `issues.labeled` que fazia três coisas ao ver
uma label:

1. **Impor exclusividade** — ao aplicar `grupo::valor`, remover as demais
   `grupo::*` da issue.
2. **Corrigir typo** — ao aplicar `grupo:valor` (um `:`) num grupo que já
   tinha alguma `grupo::*` no repo, reescrever para `grupo::valor` e então
   impor a exclusividade.
3. **Criar label** — parte de (2), via `getLabel`/`createLabel` com
   tratamento de 404/422.

(2) e (3) foram a origem de quase toda a complexidade do script: enumeração
paginada `listLabelsForRepo` a cada evento de um `:`, detecção dinâmica de
"o grupo é exclusivo?", a escada `getLabel` → `createLabel` → `422` →
`getLabel`, o `addLabels` seguido de `removeLabel`, a recursão de volta em
`enforceExclusive`, um guard posicional para `grupo::` de valor vazio, e
`.toLowerCase()` espalhado.

Ao exercitar o workflow ao vivo (roteiro em
[`docs/testes-manuais/`](../testes-manuais/exclusive-scoped-labels.md)),
ficou claro que a justificativa de (2) não se sustenta:

- **Não dá para aplicar uma label que não existe.** `POST .../labels` com
  um nome inexistente falha. O workflow só vê labels já cadastradas no
  repositório.
- **Criar label é ato deliberado e privilegiado.** Só quem tem escrita cria
  label, e não é rotina. Uma label `grupo:valor` existir significa que
  alguém a criou de propósito — tratá-la como engano é adivinhar, e
  reverter, uma decisão.
- **Um grupo não tem como ter duas grafias.** Nome de label no GitHub é
  único sem distinção de caixa: `Priority::p0` e `priority::p0` não
  coexistem, e aplicar `PRIORITY::P0` numa issue resolve para a label
  canônica `priority::p0`. Logo `context.payload.label.name` e tudo que vem
  de `listLabelsOnIssue` são sempre a mesma grafia — o `.toLowerCase()`
  guardava um estado impossível.

## Decisão

O workflow faz **uma** coisa: ao aplicar `grupo::valor` bem-formado numa
issue, remove as demais labels de prefixo `grupo::` **dessa issue**.

- **Bem-formado** = casa `/^([^:]+)::(.+)$/` — algo antes e algo depois do
  primeiro `::` (`a::b::c` → grupo `a`). `grupo:valor` (um `:`), `grupo::`
  (valor vazio), `::valor` e label solta caem no no-op.
- **Um `:` é sempre namespacing livre.** O workflow nunca reescreve
  `grupo:valor`, nunca cria label, nunca decide que "um grupo virou
  exclusivo".
- **Comparação literal** (sem `.toLowerCase()`) — a grafia é única por
  construção do GitHub.
- Mantido: leitura das labels atuais da issue via `listLabelsOnIssue` (não
  o snapshot do webhook), com 1 retry para o lag de replicação; tolerância
  a 404 no `removeLabel`; ausência de `concurrency:` (a fila de
  profundidade 1 do Actions descartaria eventos do meio de um burst).

## Consequências

- O `script:` cai de ~180 para ~45 linhas. Somem `listLabelsForRepo`,
  `ensureRepoLabel` + a escada 404/422, `addLabels`, a recursão, a
  detecção dinâmica de grupo exclusivo, o guard posicional e todo
  `.toLowerCase()`. `enforceExclusive` deixa de ser função à parte.
- **Perde-se a auto-correção de typo.** Se alguém aplicar `priority:p2`
  (um `:`) num grupo exclusivo, a issue fica com essa label e sem
  exclusividade imposta até alguém trocar à mão. É aceito: o caso exige uma
  label `priority:p2` criada de propósito, e adivinhar intenção não
  compensa o custo.
- `permissions: issues: write` continua cobrindo tudo (`removeLabel` +
  `listLabelsOnIssue`); nunca foi preciso `contents` nem criação de label
  como escopo à parte.
- `tests/workflows.sh` perde os checks de `listLabelsForRepo` e
  `KNOWN_EXCLUSIVE_GROUPS`; o roteiro manual perde os casos de typo-fix e
  de criação de label.
- A seção "Labels de issue" do `CONTRIBUTING.md` é reescrita: `grupo:valor`
  (um `:`) é sempre livre; não existe "grupo vira exclusivo ao ganhar a 1ª
  `grupo::*`".
- O workflow não é a ferramenta `git alias` — não toca a superfície de
  comandos nem o `# Formato:` do `aliases.gitconfig`. Nenhuma implicação
  sobre a política de versão (ADR-0003).
