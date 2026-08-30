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
tests/
  git-alias.sh        # testes do script (HOME isolado)
install.sh            # liga os dois mecanismos de instalação
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

## Versionamento dos aliases

Com o `install.sh` rodado, o `git/aliases.gitconfig` está no `include.path`
do seu `~/.gitconfig`. A partir daí, **`git alias <nome> '<cmd>'` e
`git alias --unset <nome>` gravam direto nesse arquivo** — ele é reconhecido
pelo cabeçalho `# Gerado por: git alias --export` — e a seção `[alias]` é
mantida em ordem alfabética (`LC_ALL=C`, estável entre máquinas). Cada
criação ou remoção já produz um diff pronto para commit.

Sem arquivo incluído detectado, os dois comandos caem no `git config
--global` e avisam: o alias **não** foi para um arquivo versionado.

Tanto a criação quanto o `--unset` também apagam qualquer cópia do alias no
`git config --global` — se ela ficar depois da linha `[include]` no
`~/.gitconfig`, faz sombra no arquivo (e o `--export`, que lê config
mesclado, a ressuscitaria). As mensagens dizem de onde o alias saiu.

Se o `include.path` apontar para um symlink (comum com gerenciadores de
dotfiles), a gravação escreve através dele e preserva o link.

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

## Testes

```sh
sh tests/git-alias.sh
```

Executa num `HOME` e num `git config` temporários; não altera seu ambiente.
