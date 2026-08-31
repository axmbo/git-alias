# Changelog

Todas as mudanças notáveis do `git-alias` são registradas aqui.

O formato segue o [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/)
e o projeto adota o [Versionamento Semântico](https://semver.org/lang/pt-BR/),
conforme o
[ADR-0003](docs/adr/0003-politica-de-versionamento-e-release.md). Enquanto o
projeto estiver na série `0.y`, a superfície de comandos e o formato do
`aliases.gitconfig` ainda podem mudar entre versões MINOR.

## [Não lançado]

## [0.1.0] - 2026-08-31

Primeira versão numerada. O histórico anterior — o subcomando `git alias`, a
gravação direta no arquivo incluído
([ADR-0001](docs/adr/0001-git-alias-grava-no-arquivo-de-aliases.md)), o
repositório próprio
([ADR-0002](docs/adr/0002-repositorio-proprio-para-o-git-alias.md)) e o
plumbing de abertura do código (LICENSE, CONTRIBUTING, `.editorconfig`, CI,
runner de testes) — está no `git log`. Não há tag `v0.1.0`: o número passa a
identificar a build e o changelog durante o desenvolvimento pré-1.0.

### Adicionado

- `git alias --version` e o sinônimo `-v`: imprimem a constante `VERSION`.
  Quando o diretório do script está num repositório git, anexam o detalhe
  de `git describe` entre parênteses.
- Constante `VERSION` no topo de `git/bin/git-alias`, fonte única da versão
  ([ADR-0003](docs/adr/0003-politica-de-versionamento-e-release.md)).
- Marcador `# Formato: 1` na terceira linha do cabeçalho gerado do
  `aliases.gitconfig`. Arquivos com o cabeçalho antigo (duas linhas)
  continuam sendo detectados e ganham o marcador ao serem reescritos.
- `CHANGELOG.md` (este arquivo) e `docs/releasing.md` (passo a passo de
  release).
- `tests/version.sh`: checagem estática que amarra a constante `VERSION` ao
  cabeçalho de versão mais recente deste arquivo.
