# git-alias

Um subcomando `git alias` para criar, listar, exportar, importar e
sincronizar os aliases do Git pela linha de comando — e versionar o
resultado como um `aliases.gitconfig` legível, com diffs mínimos.

## Estrutura

```
bin/
  git-alias           # implementação do subcomando `git alias`
examples/
  aliases.gitconfig   # amostra do formato gerado por `git alias --export`
completions/
  git-alias.bash      # completion de `git alias` para bash
  git-alias.zsh       # completion de `git alias` para zsh
docs/
  adr/                # decisões de arquitetura (ADR)
  roadmap.md          # roteiro pré-1.0 (transitório)
  releasing.md        # passo a passo de release
  known-issues.md     # bugs conhecidos de baixa probabilidade, adiados
  portabilidade.md    # auditoria coreutils vs. BSD/macOS
tests/
  run.sh              # runner: roda todas as suítes de tests/
  git-alias.sh        # testes do script (HOME isolado)
  install.sh          # testes do install.sh (HOME isolado)
  repo.sh             # checagem estática do repositório
  version.sh          # checa VERSION do script == cabeçalho do CHANGELOG
  completions.sh      # checagem estática dos arquivos de completion
install.sh            # liga os mecanismos de instalação (include.path, PATH, completions)
CONTRIBUTING.md       # fluxo de trabalho, TDD, Conventional Commits, ADR
CHANGELOG.md          # mudanças por versão (Keep a Changelog)
LICENSE               # MIT
```

## Requisitos

- **Shell POSIX** — o script e os testes rodam em qualquer `sh` compatível
  (testado em `dash` e `bash`).
- **Git ≥ 2.9** — depende de `git config --name-only --get-regexp`.
- **coreutils ou o userland BSD/macOS** — `stat`, `readlink`, `mktemp`,
  `head`, `sed`, `grep`, `find`; o script detecta e usa as duas variantes
  (`stat -c`/`stat -f`, `readlink` sem `-f`).
- Opcional: **bash-completion** e/ou **zsh** para as completions de
  [`git alias <TAB>`](#completions-de-shell).

## Instalação

Clone o repositório em qualquer diretório e rode o `install.sh` de dentro
dele — o script deriva seu próprio caminho, não presume onde você clonou:

```sh
git clone <url-do-repo> git-alias
git-alias/install.sh
```

O script é idempotente e faz / orienta quatro coisas:

1. **`include.path`** — garante que há um arquivo de aliases versionado no
   seu `~/.gitconfig` global. Se `git alias --doctor` já detecta um (em
   qualquer caminho, veja [Versionamento dos aliases](#versionamento-dos-aliases)),
   não mexe em nada. Senão, cria um a partir do que você já tem
   (`git alias --export`) em `${XDG_CONFIG_HOME:-~/.config}/git/aliases.gitconfig`
   — fora do clone, para sobreviver a um `git pull`/reclone da ferramenta —
   e adiciona ao `include.path`:

   ```sh
   git config --global --add include.path \
     "${XDG_CONFIG_HOME:-$HOME/.config}/git/aliases.gitconfig"
   ```

   `examples/aliases.gitconfig`, no repositório, é só uma amostra do formato
   — não é o arquivo que o `install.sh` usa.

2. **`PATH`** — o subcomando `git alias` é o script `bin/git-alias`. Para o
   Git encontrá-lo, `bin` precisa estar no `PATH`. O `install.sh` **não**
   edita seu shell rc; ele imprime a linha para você colar em
   `~/.bashrc` / `~/.zshrc`:

   ```sh
   export PATH="<caminho-do-clone>/bin:$PATH"
   ```

3. **Remoção do alias inline antigo** — se ainda existir um `alias.alias` no
   seu `~/.gitconfig` (a versão anterior, embutida como `!f() { … }`),
   remova: um alias tem precedência sobre o script `git-alias`.

   ```sh
   git config --global --unset alias.alias
   ```

4. **Completions de shell** — instala as completions de `git alias` para
   bash e zsh por symlink para `completions/`, no mesmo espírito dos pontos
   1 e 2 (a árvore de trabalho continua sendo a fonte da verdade). Para zsh,
   imprime um `PENDENTE` com a linha de `$fpath` a acrescentar ao `~/.zshrc`.
   Detalhes em [Completions de shell](#completions-de-shell).

Para conferir a qualquer momento se a instalação básica (pontos 1 a 3) está
de pé, rode [`git alias --doctor`](#--doctor-diagnóstico-da-instalação) — é o
`install.sh` invertido, só leitura. (O `--doctor` não cobre as completions.)

## Desinstalação

Não há um `uninstall.sh`; os quatro passos do `install.sh` se desfazem à
mão, na mesma ordem:

```sh
# 1. o arquivo de aliases criado pelo install.sh (ajuste o caminho se você
#    apontou o include.path para outro lugar); os aliases em si continuam
#    no arquivo — remova-o só se também quiser descartá-los.
git config --global --unset include.path \
  "${XDG_CONFIG_HOME:-$HOME/.config}/git/aliases.gitconfig"

# 2. remova a linha de PATH acrescentada ao seu ~/.bashrc / ~/.zshrc

# 3. nada a desfazer (o install.sh só remove o alias.alias legado; não
#    recria nada em troca)

# 4. completions (o install.sh só faz symlink; remova o link)
rm -f "${XDG_DATA_HOME:-$HOME/.local/share}/bash-completion/completions/git-alias"
rm -f "${XDG_DATA_HOME:-$HOME/.local/share}/zsh/site-functions/_git-alias"
```

## `git alias`

```
git alias                        Mostra a sintaxe de uso
git alias help                   Idem (veja a nota sobre --help)
git alias --version              Mostra a versão (também: -v)
git alias --list [--file] [--origin|-o]
                                 Lista todos os aliases; --file restringe ao
                                 arquivo de aliases incluído; --origin marca
                                 de onde cada um vem
git alias --export [<arquivo>]   Exporta em formato gitconfig; sem
                                 <arquivo>, escreve na saída padrão
git alias --import <arquivo>     Funde os aliases de <arquivo> (- = stdin) no
                                 arquivo versionado; [--overwrite] [--dry-run]
git alias <nome>                 Mostra a definição de um alias
git alias <nome> '<cmd>'         Cria ou atualiza um alias
git alias --unset <nome>         Remove um alias
git alias --rename <velho> <novo>
                                 Renomeia um alias, preservando o valor
git alias --doctor               Diagnóstico read-only da instalação
```

`git alias <nome> '<cmd>'` e `git alias --unset <nome>` gravam no arquivo de
aliases incluído no seu `~/.gitconfig` (ver
[versionamento](#versionamento-dos-aliases)); sem esse arquivo, caem no
`git config --global` e avisam. `git alias --import <arquivo>` também grava
nesse arquivo — mas, sem ele detectado, é erro, não fallback.

### `--list`: filtros e origem

- `git alias --list` lista todos os aliases do config mesclado (global +
  includes), no formato `nome = valor`; omite o dispatcher `alias.alias`.
  Se uma chave `alias.X` tiver mais de um valor na mesma camada (ex.:
  `git config --add` usado por fora do `git-alias`), a linha mostra o
  último valor — o mesmo que `git config --get` resolveria — e um aviso
  em stderr aponta a anomalia, sugerindo `git config --get-all` para ver
  todos (ver [`--rename`](#--rename-renomear-preservando-o-valor), que
  recusa mexer nesse caso pelo mesmo motivo).
- `git alias --list --file` restringe a lista aos aliases que existem no
  arquivo de aliases incluído detectado (ver
  [Versionamento dos aliases](#versionamento-dos-aliases)). Sem arquivo
  detectado, avisa e não lista nada (ver [Códigos de saída](#códigos-de-saída)).
- `git alias --list --origin` (também: `-o`) acrescenta, antes de cada linha,
  a origem do valor efetivo — `arquivo:<caminho>` quando vem do arquivo
  incluído, `--global` quando vem do `~/.gitconfig` (ou do
  `$GIT_CONFIG_GLOBAL` vigente), ou `outro:<origem>` para qualquer outra
  fonte (config do repositório, do sistema, `-c` de linha de comando etc.),
  no espírito de `git config --show-origin`. As duas flags combinam:
  `git alias --list --file --origin`.

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

O número sai da constante `VERSION` no topo de `bin/git-alias`, que é a
fonte única da verdade. Ver [Versão e release](#versão-e-release).

## Versionamento dos aliases

Com o `install.sh` rodado, há um arquivo de aliases (`aliases.gitconfig`) no
`include.path` do seu `~/.gitconfig`. A partir daí, **`git alias <nome> '<cmd>'` e
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
`--unset`, `--rename` e essa limpeza de sombra também alcançam um alias
que more só no fallback XDG do config global
(`$XDG_CONFIG_HOME/git/config`, default `~/.config/git/config`): em
algumas versões do Git, `git config --global --get`/`--unset-all` não
enxergam esse arquivo quando `~/.gitconfig` existe, mesmo a leitura
mesclada enxergando os dois — o script tenta o fallback diretamente
quando `--global` não encontra nada. Exceção deliberada: `GIT_CONFIG_GLOBAL=""`
(string vazia, não indefinida) desliga esse fallback também — é assim
que o próprio Git se comporta (nenhuma fonte `--global`, nem
`~/.gitconfig` nem XDG), e é a forma de isolar completamente o Git do
`$HOME` real (ex.: sandboxes de teste).

O `include.path` pode ser caminho absoluto, `~/…` ou relativo (resolvido
contra `$HOME`); um config global fora de `$HOME` (layout XDG) não é
resolvido e cai no fallback. Se o caminho for um symlink (ou cadeia deles,
comum com gerenciadores de dotfiles), a gravação resolve até o arquivo real,
troca-o por rename atômico e preserva tanto o(s) link(s) quanto o modo do
arquivo.

Detalhes em [docs/adr/0001-git-alias-grava-no-arquivo-de-aliases.md](docs/adr/0001-git-alias-grava-no-arquivo-de-aliases.md).

### `--export`: reconstruir o arquivo do zero

```sh
git alias --export ~/.config/git/aliases.gitconfig
```

Regenera o arquivo de aliases inteiro a partir do config mesclado, já
ordenado. Útil na primeira migração ou para consolidar aliases criados antes
desta mudança. O dispatcher `alias.alias` é omitido de propósito (senão faria
sombra no script). Rodar `--export` de outra máquina com aliases diferentes
sobrescreve o arquivo — trate o commit como o estado canônico.

### `--import`: trazer aliases de fora sem sobrescrever

```sh
git alias --import <arquivo>          # - lê da entrada padrão
git alias --import <arquivo> --overwrite
git alias --import <arquivo> --dry-run
```

Lê as entradas `alias.*` de `<arquivo>` (um gitconfig com seção `[alias]` —
tipicamente a saída de um `--export`) e as **funde** na seção `[alias]` do
arquivo de aliases versionado detectado, renormalizando ao final. É o inverso
do `--export`, e ao contrário dele **não destrói** o que já está no arquivo:
só acrescenta o que falta. `<arquivo>` = `-` lê da entrada padrão.

Por entrada da fonte, comparada com o arquivo:

| Estado no arquivo | Sem `--overwrite` | Com `--overwrite` |
| --- | --- | --- |
| ausente | grava (importado) | grava (importado) |
| mesmo valor | no-op silencioso | no-op silencioso |
| valor diferente | **pula** e relata a colisão | grava (a fonte vence) |

Ao final, um resumo em stdout, p.ex.
`4 importados; 2 já existentes com valor diferente: co, st (use --overwrite)`.
Uma entrada da fonte com nome reservado (`help`), nome inválido, ou múltiplos
valores para a mesma chave (a mesma condição que
[`--rename`](#--rename-renomear-preservando-o-valor) recusa) é **ignorada com
aviso**, sem bloquear as demais; `alias.alias` é omitido, como no `--export`.
O mesmo guard vale para um nome que já esteja multivalorado **no arquivo**.

O "não destrói" cobre as entradas que o merge toca. Como toda gravação no
arquivo, a renormalização final está sujeita à **KI-1** (`docs/known-issues.md`):
um `alias.X` com mais de um valor editado à mão no arquivo — que a fonte nem
menciona — é colapsado para o último valor. Resolva a multiplicidade antes
(`git config --file <arquivo> --get-all alias.X`).

- `--dry-run` mostra o resumo e não grava nada; sai `0` quando chega a
  executar o merge. As pré-condições que já valem `1` — fonte
  inexistente/ilegível/inválida, nenhum arquivo versionado detectado —
  valem igual em `--dry-run` (ver [Códigos de saída](#códigos-de-saída)).
- Sem arquivo de aliases versionado detectado: erro (ver
  [Códigos de saída](#códigos-de-saída)). O `--import` **não** cai no
  `git config --global` — ele existe só para alimentar o arquivo versionado.

> **Segurança.** Um alias cujo valor começa por `!` executa shell quando é
> invocado. Importar de uma fonte não confiável é, na prática, aceitar
> executar comando arbitrário depois — revise o `<arquivo>` antes. O comando
> lembra disso quando algum alias importado tem valor com `!`.

Detalhes em
[docs/adr/0004-semantica-de-merge-do-import.md](docs/adr/0004-semantica-de-merge-do-import.md).

### `--rename`: renomear preservando o valor

```sh
git alias --rename <velho> <novo>
```

Equivale a `git alias <novo> "$(git alias <velho> | ...)" && git alias --unset <velho>`,
num único comando: lê o valor exato de `<velho>` (newlines internas do
corpo inclusive — o padrão de uma função multilinha `!f() { ...; }; f`),
grava `<novo>` no mesmo lugar (arquivo incluído ou `--global`, seguindo a
mesma regra de [`git alias <nome> '<cmd>'`](#versionamento-dos-aliases)) e
remove `<velho>` de onde estiver, com a mesma limpeza de cópia obsoleta no
`--global` que a criação e o `--unset` já fazem. Limitação inerente ao
shell, não específica do `--rename`: newline(s) no **fim** do valor não
sobrevivem à captura via `"$(...)"` (o shell sempre descarta toda
newline final de uma substituição de comando) — o mesmo já valia para
`--export` antes desta branch, e não afeta o corpo de uma função
multilinha normal, só uma quebra de linha deliberadamente deixada como
o último caractere do valor.

- `<velho>` inexistente: erro, nada é gravado (ver
  [Códigos de saída](#códigos-de-saída)).
- `<novo>` já existente: recusa por padrão, para não sobrescrever um alias
  em silêncio — remova `<novo>` primeiro com `git alias --unset <novo>` se a
  intenção for substituí-lo (a mensagem só sugere isso quando de fato
  funcionaria — se `<novo>` existir só numa fonte fora do arquivo incluído
  e do `--global`, ex. `--system`, a mensagem explica isso em vez de
  sugerir um `--unset` que não alcançaria essa fonte).
- `<novo>` igual a `alias`: recusado pela mesma guarda que protege a criação
  (ver abaixo).

### `--doctor`: diagnóstico da instalação

```sh
git alias --doctor
```

Relatório **read-only** (não grava nada) que confere se a instalação está de
pé — o [`install.sh`](#instalação) invertido. Sai `0` quando não há nenhuma
linha `erro:` no relatório, `1` quando há pelo menos uma (ver
[Códigos de saída](#códigos-de-saída)); uma linha `aviso:` sozinha não muda o
código. As seções:

- **`[arquivo de aliases versionado]`** — o `include.path` do `git config
  --global` aponta para um arquivo com o cabeçalho `# Gerado por: git alias
  --export`? Para cada entrada de `include.path`, mostra como o Git a
  interpreta (caminho absoluto, `~/…` → `$HOME`, ou relativo a `$HOME`), se
  ela resolve num arquivo real (seguindo a cadeia de symlinks) e se o arquivo
  traz o cabeçalho. Sem arquivo detectado: `aviso:` — `git alias <nome>
  '<cmd>'` cairia no fallback `git config --global`, sem versionar.
- **`[git config --global: aliases fora do arquivo]`** — aliases definidos
  direto no `~/.gitconfig` (ou no fallback XDG), fora do arquivo versionado:
  não entram no commit e, se a definição vier depois da linha `[include]`,
  fazem sombra no arquivo. Lista os nomes, marcando os que também existem no
  arquivo (sombra) e os que só existem no `--global` (não versionados). O
  dispatcher `alias.alias` fica para a seção seguinte.
- **`[git-alias no PATH]`** — o Git despacha `git alias` procurando um
  executável `git-alias` no `PATH`. A checagem passa (`ok:`) quando algum
  diretório do `PATH` contém um `git-alias` que resolve para este script —
  seja o próprio diretório do script, seja um symlink para ele dentro de um
  diretório do `PATH` (layouts tipo GNU stow / dotbot). Nenhum: `erro:` (o
  subcomando `git alias` não chega a este script).
- **`[alias.alias legado]`** — resquício da implementação anterior (embutida
  como `!f() { … }` no `~/.gitconfig`). Qualquer `alias.alias` no `git config
  --global` tem precedência sobre o script no `PATH` — `git alias` executaria
  a entrada de config, não este script. Presente: `erro:`, com o comando para
  removê-la.

### Guardas ao criar, renomear ou remover um alias

`git alias <nome> '<cmd>'` e o `<novo>` de `git alias --rename` passam por
três checagens antes de gravar:

- **Nome inválido** — só letras minúsculas, números e hífen são aceitos,
  começando por uma letra; um nome fora desse formato (vazio, com
  maiúscula, começando por dígito ou hífen, com espaço, ponto etc.) é
  recusado com mensagem amigável, em vez do erro cru do `git config`.
  Minúscula é obrigatório porque o `git config` normaliza toda chave para
  minúsculas em qualquer modo de enumeração (`--list`, `--get-regexp`) —
  um nome com maiúscula seria silenciosamente renomeado da próxima vez que
  qualquer alias fosse criado/renomeado/removido (a normalização
  reescreve a seção `[alias]` inteira a cada gravação no arquivo).
- **`alias` e `help` são reservados** — `git alias alias '<cmd>'`
  sombrearia o próprio dispatcher (o `git-alias` no `PATH`), já que
  `alias.alias` é o nome que o Git usa para despachar o subcomando
  `alias`; `git alias help '<cmd>'` seria interceptado pelo próprio
  dispatcher antes de qualquer alias ser consultado (mostra a ajuda, nunca
  chega a ser lido como `git alias help`). A mesma guarda vale para
  `<velho>` de `--rename` e para `git alias --unset <nome>` — sem ela,
  `--rename alias foo` ou `--unset alias` apagariam a própria entrada
  `alias.alias` que faz `git alias` funcionar como subcomando do Git,
  quebrando o dispatcher até ser recriado manualmente. Ignora caixa
  (`Alias`, `HELP` etc. também são recusados).
- **Sombra de comando builtin do Git** — se `<nome>` coincidir com um
  comando builtin do próprio Git (`checkout`, `status` etc.), o alias nunca
  seria chamado — o Git prioriza o builtin silenciosamente. O comando
  **avisa** mas grava mesmo assim (é um aviso, não uma recusa; o usuário
  pode ter um motivo). Detecção via `git --list-cmds=builtins` (Git ≥
  2.18); numa versão mais antiga, ou sem suporte à opção, a checagem é
  pulada sem erro.

## Completions de shell

`completions/` traz a completion de `git alias` para **bash** e **zsh**. O
`install.sh` (ponto 4 da [Instalação](#instalação)) faz o symlink para os
diretórios de completion do usuário; abaixo, o que elas cobrem e como ativar
à mão se você não usar o `install.sh`.

Em `git alias <TAB>` as duas completam:

- os subcomandos (`help`, `--version`/`-v`, `--list`, `--export`, `--import`,
  `--unset`, `--rename`, `--doctor`);
- as flags de cada um — `--list` → `--file`, `--origin`/`-o`; `--import` →
  `--overwrite`, `--dry-run`;
- nomes de alias já definidos onde faz sentido: `git alias <nome>`,
  `git alias --unset <TAB>` e o `<velho>` de
  `git alias --rename <velho> <TAB>` (a lista sai de
  `git config --name-only --get-regexp '^alias\.'`, sem o dispatcher
  `alias.alias`, como no próprio script);
- `--export` e o `<arquivo>` de `--import` completam nomes de arquivo.

### bash

`completions/git-alias.bash` define a função `_git_alias`, que a completion
do próprio Git (`git-completion.bash`) procura ao completar `git alias …`.
Não é um script `source`ável genérico — depende do `git-completion.bash`
estar carregado (ele já vem com o Git e costuma ser ativado pelo pacote
`bash-completion` da distro).

O `install.sh` faz o equivalente a:

```sh
ln -s <repo>/completions/git-alias.bash \
   "${XDG_DATA_HOME:-$HOME/.local/share}/bash-completion/completions/git-alias"
```

Esse diretório é o que o *dynamic loader* do `bash-completion` consulta ao
completar um comando pela primeira vez — nada a acrescentar ao `~/.bashrc`.

### zsh

`completions/git-alias.zsh` define `_git-alias`, que o `_git` nativo do zsh
procura para o subcomando `alias`. Não usa `bashcompinit`.

O `install.sh` faz o symlink como `_git-alias` em
`${XDG_DATA_HOME:-$HOME/.local/share}/zsh/site-functions/` e imprime um
`PENDENTE`: como ele roda em `sh`, não enxerga o `$fpath` do seu zsh
interativo. Garanta que o diretório está no `$fpath` **antes** do `compinit`
no `~/.zshrc`:

```sh
fpath=("${XDG_DATA_HOME:-$HOME/.local/share}/zsh/site-functions" $fpath)
autoload -Uz compinit && compinit
```

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

## Códigos de saída

Contrato estável, parte da superfície versionada por SemVer
([ADR-0003](docs/adr/0003-politica-de-versionamento-e-release.md)): scripts
podem depender destes três valores.

| Código | Significado       | Exemplos                                                                                   |
| ------ | ------------------ | ------------------------------------------------------------------------------------------- |
| `0`    | Sucesso             | Alias criado/consultado/removido/renomeado; `--list`, `--export`, `--version`, `--help`; `--import` que roda até o fim (mesmo com colisões puladas ou entradas ignoradas — são relatório, não falha), inclusive `--import --dry-run`; `--doctor` sem nenhuma linha `erro:` (só `ok:` e/ou `aviso:`). |
| `1`    | Falha esperada      | Consulta de alias inexistente; `--unset`/`--rename` de alias que não existe; `--rename` cujo destino já existe; `--list --file` sem arquivo de aliases incluído; `--import` sem arquivo de aliases versionado detectado, com a fonte inexistente/ilegível/sintaxe inválida, ou cuja gravação de uma entrada falha por um motivo genuíno (lock, permissão) — a entrada não conta como importada; `--rename`/criação cuja limpeza de uma cópia obsoleta falha por um motivo genuíno (lock, permissão), deixando duas definições coexistindo (ou a nova sombreada pela antiga); `--unset` cuja remoção falha pelo mesmo motivo; `--doctor` com pelo menos uma linha `erro:` (`git-alias` fora do `PATH`, `alias.alias` legado sombreando o script). |
| `2`    | Erro de uso         | Flag ou argumento inválido/faltando; nome de alias inválido; nome reservado (`alias`/`help`) em criação, `--rename` (`<velho>` ou `<novo>`) ou `--unset`. |

## Testes

```sh
sh tests/run.sh
```

O runner roda todas as suítes de `tests/`:

- `tests/git-alias.sh` — exercita o script num `HOME` e num `git config`
  temporários; não altera seu ambiente.
- `tests/install.sh` — exercita o `install.sh` num `HOME` temporário: detecção
  de um arquivo de aliases já configurado, criação do alvo XDG quando não há
  nenhum, idempotência.
- `tests/repo.sh` — checagem estática do repositório (existe exatamente um
  `README.md`, na raiz; layout de ferramenta — `bin/git-alias`, sem `git/`).
- `tests/version.sh` — checagem estática: a constante `VERSION` do script é
  igual ao cabeçalho de versão mais recente do `CHANGELOG.md`.
- `tests/completions.sh` — checagem estática dos arquivos de
  `completions/`: existem, têm sintaxe válida (`bash -n` / `zsh -n` quando
  o shell está disponível) e citam cada subcomando e flag de `git alias`
  (uma regressão que tire um subcomando da completion quebra a suíte).

O script é POSIX sh e precisa passar tanto em `dash` quanto em `bash`. Para
fixar o shell de cada suíte:

```sh
SHELL_UNDER_TEST=dash sh tests/run.sh
SHELL_UNDER_TEST=bash sh tests/run.sh
```

O CI (`.github/workflows/ci.yml`) roda a suíte sob `dash` e `bash`, contra
duas versões de git — o piso de compatibilidade (git ≥ 2.9, por causa de
`git config --name-only`) e a mais nova disponível no runner —, num runner
Linux e num macOS (BSD `stat`/`readlink`/`mktemp`; ver
[docs/portabilidade.md](docs/portabilidade.md)); e passa o `shellcheck` em
`bin/git-alias`, `install.sh`, `tests/*.sh` e
`completions/git-alias.bash` (o `.zsh` fica de fora — o `shellcheck` não
cobre zsh). Ver [CONTRIBUTING.md](CONTRIBUTING.md).

## Licença

MIT (`SPDX-License-Identifier: MIT`) — ver [LICENSE](LICENSE).
