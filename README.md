# dotfiles

Configurações pessoais versionadas. Hoje o repositório cobre os aliases do
Git e a implementação do subcomando `git alias`.

## Estrutura

```
git/
  aliases.gitconfig   # seção [alias] gerada por `git alias --export`
  bin/
    git-alias         # implementação do subcomando `git alias`
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

### `git alias --help` não funciona

O Git intercepta `--help` antes de executar o subcomando — tenta abrir a man
page `git-alias`, que não existe. Use `git alias` ou `git alias help`.

## Backup e versionamento dos aliases

```sh
git alias --export ~/Dev/dotfiles/git/aliases.gitconfig
```

Regenera `git/aliases.gitconfig` a partir do seu config atual. O dispatcher
`alias.alias` é omitido de propósito (senão faria sombra no script). Depois é
só commitar o arquivo.

É **mão única**: `aliases.gitconfig` é derivado do seu config, não o
contrário. Em runtime, o `include.path` faz o caminho de volta (arquivo →
config). Rodar `--export` de outra máquina com aliases diferentes
sobrescreve o arquivo — trate o commit como o estado canônico.

## Testes

```sh
sh tests/git-alias.sh
```

Executa num `HOME` e num `git config` temporários; não altera seu ambiente.
