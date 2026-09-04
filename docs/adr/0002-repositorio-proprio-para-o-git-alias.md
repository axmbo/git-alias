# 2. Repositório próprio para o `git-alias`

## Status

Aceito — 2026-08-30

## Contexto

Este repositório nasceu com o nome `dotfiles`, mas contém apenas o
`git-alias`: o script `bin/git-alias`, o `install.sh`, os testes, o
ADR-0001 e o roadmap pré-1.0. Não há histórico de outros arquivos de
configuração pessoal.

Queremos publicar o `git-alias` como código aberto (ver `docs/roadmap.md`).
Publicar sob o nome `dotfiles` tem problemas:

- Repositório de dotfiles as pessoas forkam ou copiam; uma ferramenta as
  pessoas instalam e executam. Nome e forma não batem.
- Uma tag do `dotfiles` não diz nada sobre a versão da ferramenta; SemVer só
  faz sentido com escopo da ferramenta.
- Descoberta ruim: quem procura "git alias manager" não acha
  `usuário/dotfiles`.
- Issues, PRs, CI e badges ficariam com escopo ambíguo.

## Decisão

O `git-alias` passa a ter **repositório próprio**.

Como o repositório atual já é 100% `git-alias`, ele mesmo se torna o
repositório da ferramenta — via rename, **sem extração de histórico**
(`git filter-repo`/`subtree` não são necessários).

Uma futura coleção de dotfiles pessoais, se vier a existir, será um
repositório **separado** que consome o `git-alias` (submódulo, subtree ou
cópia vendorizada).

Implicações, a executar antes da tag `v1.0.0` (itens no `docs/roadmap.md`):

- Rename do repositório para `git-alias`.
- README, `install.sh` e layout reorientados para a ferramenta — inclusive
  avaliar achatar `git/bin/git-alias` → `bin/git-alias` e tratar o
  `git/aliases.gitconfig` de exemplo como amostra (`examples/`) ou apenas
  documentação.
- Remover pressupostos de caminho pessoal (`~/Dev/dotfiles`) da prosa e do
  `CLAUDE.md` do projeto.
- Tags SemVer, CI, releases e issue tracker passam a ter escopo da
  ferramenta.

## Consequências

- Custo agora é baixo (rename + reorientação de docs/layout). Adiar teria
  custo crescente: assim que o repositório acumulasse qualquer outro
  conteúdo, a separação exigiria cirurgia de histórico.
- A renumeração de ADRs no roadmap segue esta decisão: política de
  versionamento vira ADR-0003; semântica do `--import`, ADR-0004.
- O ADR-0001 continua válido como está — descreve comportamento do script,
  não a estrutura do repositório.
- Executado no passo 9 do roadmap (2026-09-04): layout achatado para
  `bin/git-alias`; `aliases.gitconfig` de exemplo movido para
  `examples/aliases.gitconfig`; `install.sh` deixou de apontar o
  `include.path` para um arquivo dentro do clone.
