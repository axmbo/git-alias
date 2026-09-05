# Como contribuir

Obrigado pelo interesse. Este projeto é pequeno e tem regras de fluxo
deliberadas — segui-las mantém o histórico legível e os diffs mínimos.

## Rodando os testes

A suíte é shell POSIX puro, sobre `git` e utilitários POSIX padrão (`find`,
`grep`, `sed`, `mktemp`, `stat`…). Um runner roda todas as suítes de
`tests/`:

```sh
sh tests/run.sh
```

Ele executa:

- `tests/git-alias.sh` — exercita `bin/git-alias` num `HOME` e num
  `git config` temporários; não toca no seu ambiente.
- `tests/install.sh` — exercita `install.sh` num `HOME` temporário.
- `tests/repo.sh` — checagem estática do repositório (hoje: existe
  exatamente um `README.md`, na raiz; layout de ferramenta em `bin/`).
- `tests/version.sh` — checagem estática: a constante `VERSION` do script é
  igual ao cabeçalho de versão mais recente do `CHANGELOG.md`.
- `tests/completions.sh` — checagem estática dos arquivos de
  `completions/`: existência, sintaxe (`bash -n` / `zsh -n` quando o shell
  está disponível) e cobertura de cada subcomando/flag de `git alias`.

O script alvo é POSIX sh e precisa continuar limpo tanto em `dash` quanto em
`bash`. Fixe o shell de cada suíte com `SHELL_UNDER_TEST`:

```sh
SHELL_UNDER_TEST=dash sh tests/run.sh
SHELL_UNDER_TEST=bash sh tests/run.sh
```

Antes de abrir um PR, rode a suíte sob os dois. O CI faz o mesmo (ver
[.github/workflows/ci.yml](.github/workflows/ci.yml)).

### `shellcheck` limpo

Todo shell versionado tem que passar no `shellcheck` sem avisos:

```sh
shellcheck bin/git-alias install.sh tests/*.sh completions/git-alias.bash
```

`completions/git-alias.zsh` fica de fora: o `shellcheck` não analisa zsh. A
sintaxe dele é coberta por `tests/completions.sh` (via `zsh -n`, quando o
`zsh` está disponível).

O CI roda essa mesma checagem e falha o build se houver qualquer achado. Ele
usa uma versão fixa do `shellcheck`, baixada do release oficial e conferida
por SHA256 — `SHELLCHECK_VERSION` / `SHELLCHECK_SHA256` em
[.github/workflows/ci.yml](.github/workflows/ci.yml) (hoje `v0.10.0`). O
`shellcheck` do gerenciador de pacotes da sua distro pode ser mais antigo e
divergir; para bater exatamente com o CI, baixe o binário oficial daquela
versão dos [releases](https://github.com/koalaman/shellcheck/releases). Um
bump troca a versão **e** o checksum juntos, mais esta nota.

Se um aviso for falso positivo, suprima-o com um comentário
`# shellcheck disable=SCxxxx` — sempre em frente a um comando completo (o
`case` inteiro, não um ramo), com uma linha explicando o porquê. Nunca
desabilite de forma ampla.

O CI também converte a saída do `shellcheck` em SARIF e a publica na aba
**Security › Code scanning** do repositório — mesma checagem, com histórico
e anotação no PR. A trava que barra o merge continua sendo o job `shellcheck`
falhar; o code scanning é só a vitrine.

## Segurança

Como reportar uma vulnerabilidade: [SECURITY.md](SECURITY.md). Não abra
issue pública para falha de segurança.

O que roda sozinho, tudo gratuito no plano público do GitHub:

- **`shellcheck` → code scanning** — ver a seção acima.
- **zizmor** ([.github/workflows/security.yml](.github/workflows/security.yml))
  — audita os próprios workflows de `.github/workflows/` (injeção de
  `${{ }}` em `run:`, actions sem pin, `permissions:` largas). Achados vão
  para a aba Security. Versão do `zizmor` e SHA das actions são fixos, no
  mesmo espírito dos downloads verificados de `ci.yml`.
- **Dependabot** ([.github/dependabot.yml](.github/dependabot.yml)) — as
  GitHub Actions dos workflows são a única classe de dependência do projeto
  (não há manifesto de pacote). Um PR semanal agrupado sobe as versões;
  alertas e *security updates* estão ligados nas configurações do repo.
- **Secret scanning + push protection** e **private vulnerability
  reporting** — ligados nas configurações do repositório, sem arquivo neste
  repo.

CodeQL fica de fora de propósito: não analisa shell.

## TDD

Por padrão, todo trabalho de código segue TDD (red → green → refactor), com
pelo menos um commit por fase:

- **RED** — um teste por vez, e só nessa fase se cria ou edita teste. Commit
  do tipo `test`, descrevendo o teste que falha.
- **GREEN** — só código de produção; nada de teste. A implementação mais
  simples que faz o teste passar (inclusive hard-code no primeiro caso de um
  comportamento, generalizando por triangulação depois). O tipo do commit
  reflete a semântica real da mudança (`feat`, `fix`, `refactor`…), não
  `fix` só porque um teste passou a verde.
- **REFACTOR** — nenhum comportamento novo; todos os testes sempre verdes.
  Vale refatorar o código de teste também, sem mudar o que ele verifica. Só
  commite se houver algo de fato a melhorar.

Casos em que TDD não é o padrão (confirme antes de pular): refatoração pura,
ajuste puramente visual, script de auditoria pós-fato, spike descartável,
configuração declarativa (CI, `.editorconfig`, manifestos) e hotfix urgente
(o teste de regressão pode vir logo depois). Um teste estático que é o
próprio artefato entregue (como `tests/repo.sh`) escreve-se verificando que
ele passa **e** que falharia na condição que deveria pegar.

## Mensagens de commit

[Conventional Commits](https://www.conventionalcommits.org/):
`<tipo>[(escopo)]: <descrição>`.

- O **tipo** é sempre em inglês: `feat`, `fix`, `refactor`, `test`, `docs`,
  `chore`, `build`, `ci`, `perf`, `style`.
- O **escopo** (opcional) é o identificador técnico do módulo/área
  (`git-alias`, `install`, …), sem traduzir.
- A **descrição e o corpo** são em português. Termos técnicos consagrados
  (commit, hook, build, runner, symlink…) ficam em inglês; o resto em
  português correto, com acentuação.

Não commite direto em `main`: crie uma branch
`<tipo>/<descrição-curta-kebab-case>` (ou
`<tipo>/<número-da-issue>-<descrição>` quando houver issue).

## Labels de issue

Convenção estilo *scoped labels* do GitLab:

- `grupo::valor` — **exclusiva**: só uma label desse grupo por issue. Hoje
  os grupos exclusivos são `priority` (`priority::p0`…`priority::p3`) e
  `status`.
- `grupo:valor` (um `:` só) — namespacing livre, **não** exclusivo.
- label solta (`enhancement`, `bug`…) — não exclusiva.

O workflow
[.github/workflows/git-alias-priority-exclusive.yml](.github/workflows/git-alias-priority-exclusive.yml)
impõe isso: ao aplicar `grupo::valor` de um grupo exclusivo, remove as
outras labels do mesmo grupo; se alguém digitar `priority:p2` (esquecendo o
segundo `:`), o workflow corrige para `priority::p2`. A lista de grupos
exclusivos vive na constante `KNOWN_EXCLUSIVE_GROUPS` do próprio workflow.

## Decisões de arquitetura (ADR)

Todo comportamento visível, processo, padrão ou decisão de arquitetura fica
documentado nos fontes **antes** da mudança de código correspondente.
Decisão de arquitetura vira um ADR em `docs/adr/NNNN-titulo-curto-kebab.md`,
em formato leve:

```markdown
# N. Título da decisão

## Status

Aceito — AAAA-MM-DD

## Contexto

O problema e as forças em jogo.

## Decisão

O que foi decidido, no presente do indicativo.

## Consequências

O que passa a ser verdade — bom e ruim — depois desta decisão.
```

`NNNN` é sequencial e com zero-padding (`0001`, `0002`, …). ADR não se
edita para reverter: cria-se um novo ADR que supersede o anterior e
atualiza-se o `Status` do antigo.

## Versão e release

A versão vive na constante `VERSION` no topo de `bin/git-alias` — fonte
única. `CHANGELOG.md` (formato *Keep a Changelog*) registra as mudanças por
versão, e `tests/version.sh` falha o CI se os dois saírem de sincronia.
Toda mudança que altere a superfície de comandos ou o formato do
`aliases.gitconfig` deve acrescentar uma linha à seção `## [Não lançado]`
do `CHANGELOG.md` no mesmo PR.

Regras de MAJOR/MINOR/PATCH, a fase `0.y` e o marcador `# Formato: N`:
[ADR-0003](docs/adr/0003-politica-de-versionamento-e-release.md). Passo a
passo para cortar uma release: [docs/releasing.md](docs/releasing.md).

## Um único `README.md`

O repositório tem exatamente um `README.md`, na raiz — a porta de entrada da
documentação. Nenhum subdiretório tem `README.md` próprio; documentação
específica usa nome semântico em `docs/`. `tests/repo.sh` verifica isso de
forma determinística e o CI o executa.
