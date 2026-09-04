# Projetos similares no GitHub

Levantamento feito em 2026-08-30 via `gh search repos` / `gh repo view`.
Contagem de estrelas é do dia da consulta e envelhece rápido.

## Escopo da comparação

Este repositório faz duas coisas:

1. o subcomando `git alias` (`bin/git-alias`), que cria, lista, exporta
   e remove aliases do Git pela linha de comando;
2. versiona esses aliases num `aliases.gitconfig` carregado via
   `include.path`.

O levantamento abaixo cobre três círculos concêntricos de semelhança.

## 1. Nicho exato — ferramenta que gerencia aliases do Git como CLI/subcomando

Semelhança máxima, mas **não há nada popular**: é um nicho praticamente
vazio.

| Estrelas | Repo | O que é |
|---:|---|---|
| 1 | [cyberskill-official/gam](https://github.com/cyberskill-official/gam) | GUI desktop (TypeScript) p/ gerenciar aliases do Git no Windows/Linux/macOS |
| 0 | [gbvkUtilities/git-alias-manager](https://github.com/gbvkUtilities/git-alias-manager) | CLI em Python: list/add/remove/update de aliases globais |
| 0 | [jishanahmed-shaikh/git-alias-manager](https://github.com/jishanahmed-shaikh/git-alias-manager) | CLI em Python, 20 aliases embutidos, export/import em JSON |
| 0 | [garrettbutler/gitam](https://github.com/garrettbutler/gitam) | "Git Alias Manager" |
| 0 | [carlosmn/git-alias](https://github.com/carlosmn/git-alias) | experimento com libgit2sharp (do mantenedor da libgit2) |

A ideia de um `git alias` como subcomando executável no `PATH`, com
`--export` para um arquivo versionável, aparenta ser original — ninguém
consolidou isso num projeto com tração.

## 2. Coleções curadas de aliases (versionam, mas sem ferramenta de CRUD)

Abordagem majoritária: manter um `aliases.gitconfig` à mão, sem script.

| Estrelas | Repo |
|---:|---|
| 2.694 | [GitAlias/gitalias](https://github.com/GitAlias/gitalias) — referência da categoria; `git alias` como coleção, não como gerenciador |
| 694 | [maciejkorsan/podlaskigit](https://github.com/maciejkorsan/podlaskigit) |
| 148 | [SixArm/gitconfig-settings](https://github.com/SixArm/gitconfig-settings) |

## 3. Categoria ampla — gerenciadores de dotfiles / utilitários que estendem o Git

| Estrelas | Repo |
|---:|---|
| 31.461 | [mathiasbynens/dotfiles](https://github.com/mathiasbynens/dotfiles) |
| 21.380 | [twpayne/chezmoi](https://github.com/twpayne/chezmoi) |
| 18.099 | [tj/git-extras](https://github.com/tj/git-extras) — dezenas de subcomandos `git-*` no `PATH`, mesmo mecanismo do nosso `git-alias` |
| 7.995 | [anishathalye/dotbot](https://github.com/anishathalye/dotbot) |
| 6.408 | [yadm-dev/yadm](https://github.com/yadm-dev/yadm) |

## Conclusão

- Mais próximo **e** mais popular: [GitAlias/gitalias](https://github.com/GitAlias/gitalias)
  (2,7k estrelas) — mas é lista curada, não gerencia aliases.
- Ferramenta de gerenciamento equivalente à deste repo: só projetos de
  0–1 estrela.
- O padrão mecânico (`git-<sub>` no `PATH`) é o mesmo de
  [git-extras](https://github.com/tj/git-extras) (18k estrelas).
