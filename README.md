# dotfiles

Configurações pessoais versionadas. Hoje o repositório cobre os aliases do
Git e a implementação do subcomando `git alias`.

## Estrutura

```
git/
  aliases.gitconfig   # seção [alias]; git alias grava aqui, sempre ordenada
  bin/
    git-alias         # implementação do subcomando `git alias`
docs/
  adr/                # decisões de arquitetura (ADR)
  roadmap.md          # roteiro pré-1.0 (transitório)
  releasing.md        # passo a passo de release
tests/
  run.sh              # runner: roda todas as suítes de tests/
  git-alias.sh        # testes do script (HOME isolado)
  repo.sh             # checagem estática do repositório
  version.sh          # checa VERSION do script == cabeçalho do CHANGELOG
install.sh            # liga os dois mecanismos de instalação
CONTRIBUTING.md       # fluxo de trabalho, TDD, Conventional Commits, ADR
CHANGELOG.md          # mudanças por versão (Keep a Changelog)
LICENSE               # MIT
```

## Instalação

Clone o repositório em `~/Dev/dotfiles` e rode:

```sh
~/Dev/dotfiles/install.sh
```

O script é idempotente e faz / orienta três coisas:

1. **`include.path`** — adiciona `git/aliases.gitconfig` ao seu
   `~/.gitconfig` global, para carregar os aliases versionados. Equivale a:

   ```sh
   git config --global --add include.path ~/Dev/dotfiles/git/aliases.gitconfig
   ```

2. **`PATH`** — o subcomando `git alias` é o script `git/bin/git-alias`.
   Para o Git encontrá-lo, `git/bin` precisa estar no `PATH`. O `install.sh`
   **não** edita seu shell rc; ele imprime a linha para você colar em
   `~/.bashrc` / `~/.zshrc`:

   ```sh
   export PATH="$HOME/Dev/dotfiles/git/bin:$PATH"
   ```

3. **Remoção do alias inline antigo** — se ainda existir um `alias.alias` no
   seu `~/.gitconfig` (a versão anterior, embutida como `!f() { … }`),
   remova: um alias tem precedência sobre o script `git-alias`.

   ```sh
   git config --global --unset alias.alias
   ```

## `git alias`

```
git alias                        Mostra a sintaxe de uso
git alias help                   Idem (veja a nota sobre --help)
git alias --version              Mostra a versão (também: -v)
git alias --list                 Lista todos os aliases
git alias --export [<arquivo>]   Exporta em formato gitconfig; sem
                                 <arquivo>, escreve na saída padrão
git alias <nome>                 Mostra a definição de um alias
git alias <nome> '<cmd>'         Cria ou atualiza um alias
git alias --unset <nome>         Remove um alias
```

`git alias <nome> '<cmd>'` e `git alias --unset <nome>` gravam no arquivo de
aliases incluído no seu `~/.gitconfig` (ver
[versionamento](#versionamento-dos-aliases)); sem esse arquivo, caem no
`git config --global` e avisam.

### `git alias --help` não funciona

O Git intercepta `--help` antes de executar o subcomando — tenta abrir a man
page `git-alias`, que não existe. Use `git alias` ou `git alias help`.

### `git alias --version` funciona

Ao contrário de `--help`, o Git **não** intercepta `--version` de um
subcomando externo — ele repassa o argumento, e o script imprime a versão.
`git alias -v` é sinônimo. Se o diretório do script estiver num repositório
git, a saída anexa o detalhe do `git describe` entre parênteses, p.ex.
`0.1.0 (v0.1.0-3-gabc1234)`. Esse detalhe é contexto de melhor esforço: uma
cópia solta do script vendorizada noutro repositório mostra o `git describe`
daquele repo — o número antes do parêntese é sempre a resposta autoritativa.
`tests/git-alias.sh` fixa a não-interceptação.

O número sai da constante `VERSION` no topo de `git/bin/git-alias`, que é a
fonte única da verdade. Ver [Versão e release](#versão-e-release).

## Versionamento dos aliases

Com o `install.sh` rodado, o `git/aliases.gitconfig` está no `include.path`
do seu `~/.gitconfig`. A partir daí, **`git alias <nome> '<cmd>'` e
`git alias --unset <nome>` gravam direto nesse arquivo** — ele é reconhecido
pelo cabeçalho `# Gerado por: git alias --export` — e a seção `[alias]` é
mantida em ordem alfabética (`LC_ALL=C`, estável entre máquinas). Cada
criação ou remoção já produz um diff pronto para commit.

O cabeçalho gerado traz também `# Formato: 1` na terceira linha — a versão
do formato do arquivo, um eixo independente da versão da ferramenta (ver
[ADR-0003](docs/adr/0003-politica-de-versionamento-e-release.md)). Um
arquivo com o cabeçalho antigo, de duas linhas, continua sendo detectado e
ganha a linha na primeira reescrita.

Sem arquivo incluído detectado, os dois comandos caem no `git config
--global` e avisam: o alias **não** foi para um arquivo versionado.

Tanto a criação quanto o `--unset` também apagam qualquer cópia do alias no
`git config --global` — se ela ficar depois da linha `[include]` no
`~/.gitconfig`, faz sombra no arquivo (e o `--export`, que lê config
mesclado, a ressuscitaria). As mensagens dizem de onde o alias saiu.

O `include.path` pode ser caminho absoluto, `~/…` ou relativo (resolvido
contra `$HOME`); um config global fora de `$HOME` (layout XDG) não é
resolvido e cai no fallback. Se o caminho for um symlink (ou cadeia deles,
comum com gerenciadores de dotfiles), a gravação resolve até o arquivo real,
troca-o por rename atômico e preserva tanto o(s) link(s) quanto o modo do
arquivo.

Detalhes em [docs/adr/0001-git-alias-grava-no-arquivo-de-aliases.md](docs/adr/0001-git-alias-grava-no-arquivo-de-aliases.md).

### `--export`: reconstruir o arquivo do zero

```sh
git alias --export ~/Dev/dotfiles/git/aliases.gitconfig
```

Regenera `git/aliases.gitconfig` inteiro a partir do config mesclado, já
ordenado. Útil na primeira migração ou para consolidar aliases criados antes
desta mudança. O dispatcher `alias.alias` é omitido de propósito (senão faria
sombra no script). Rodar `--export` de outra máquina com aliases diferentes
sobrescreve o arquivo — trate o commit como o estado canônico.

## Versão e release

O projeto segue [Versionamento Semântico](https://semver.org/lang/pt-BR/)
ancorado em duas superfícies: a de comandos e o formato do
`aliases.gitconfig` gerado. Enquanto estiver na série `0.y` (pré-1.0), a
superfície ainda pode mudar entre versões MINOR. `git alias --version`
imprime o número; `CHANGELOG.md` registra as mudanças por versão.

- Política: [ADR-0003](docs/adr/0003-politica-de-versionamento-e-release.md).
- Passo a passo para cortar uma release:
  [docs/releasing.md](docs/releasing.md).
- `tests/version.sh` garante que a constante `VERSION` e o `CHANGELOG.md`
  não saiam de sincronia.

## Testes

```sh
sh tests/run.sh
```

O runner roda todas as suítes de `tests/`:

- `tests/git-alias.sh` — exercita o script num `HOME` e num `git config`
  temporários; não altera seu ambiente.
- `tests/repo.sh` — checagem estática do repositório (existe exatamente um
  `README.md`, na raiz).
- `tests/version.sh` — checagem estática: a constante `VERSION` do script é
  igual ao cabeçalho de versão mais recente do `CHANGELOG.md`.

O script é POSIX sh e precisa passar tanto em `dash` quanto em `bash`. Para
fixar o shell de cada suíte:

```sh
SHELL_UNDER_TEST=dash sh tests/run.sh
SHELL_UNDER_TEST=bash sh tests/run.sh
```

O CI roda a suíte sob `dash` e `bash` e passa o `shellcheck` em
`git/bin/git-alias`, `install.sh` e `tests/*.sh`. Ver
[CONTRIBUTING.md](CONTRIBUTING.md).

## Licença

MIT (`SPDX-License-Identifier: MIT`) — ver [LICENSE](LICENSE).
