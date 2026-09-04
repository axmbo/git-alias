# Changelog

Todas as mudanças notáveis do `git-alias` são registradas aqui.

O formato segue o [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/)
e o projeto adota o [Versionamento Semântico](https://semver.org/lang/pt-BR/),
conforme o
[ADR-0003](docs/adr/0003-politica-de-versionamento-e-release.md). Enquanto o
projeto estiver na série `0.y`, a superfície de comandos e o formato do
`aliases.gitconfig` ainda podem mudar entre versões MINOR.

## [Não lançado]

## [1.0.0] - 2026-09-04

Primeira versão estável. Fecha o roteiro pré-1.0: a superfície de comandos e
o formato do `aliases.gitconfig` congelam aqui — a partir desta tag, as
regras de MAJOR/MINOR/PATCH do [ADR-0003](docs/adr/0003-politica-de-versionamento-e-release.md)
passam a valer integralmente.

### Adicionado

- Completions de `git alias` para bash e zsh (`completions/git-alias.bash`,
  `completions/git-alias.zsh`). Completam os subcomandos (`help`,
  `--version`/`-v`, `--list`, `--export`, `--import`, `--unset`, `--rename`,
  `--doctor`), as flags de cada um (`--list` → `--file`, `--origin`/`-o`;
  `--import` → `--overwrite`, `--dry-run`) e nomes de alias já definidos em
  `git alias <nome>`, `--unset <TAB>` e o `<velho>` de `--rename`. bash: a
  função `_git_alias`, carregada sob demanda pela completion do próprio Git
  (`git-completion.bash`). zsh: a função `_git-alias`, que o `_git` nativo
  procura para o subcomando `alias` — sem `bashcompinit`. O `install.sh`
  agora tem um 4º passo que faz o symlink das duas para os diretórios de
  completion do usuário (bash: dir do *dynamic loader* do `bash-completion`;
  zsh: um dir de `site-functions`, com `PENDENTE` orientando o `$fpath`).
  `tests/completions.sh` cobre a existência, a sintaxe e a cobertura de
  subcomandos/flags dos dois arquivos.
- `git alias --import <arquivo>` (`-` = entrada padrão): funde as entradas
  `alias.*` de uma fonte gitconfig (tipicamente a saída de um `--export`) na
  seção `[alias]` do arquivo de aliases versionado detectado, sem destruir o
  que já está lá — o inverso não-destrutivo do `--export`. Colisão de valor:
  pula e relata por padrão (`4 importados; 2 já existentes com valor
  diferente: co, st (use --overwrite)`); `--overwrite` faz a fonte vencer;
  valor idêntico dos dois lados é no-op silencioso. `--dry-run` imprime o
  resumo sem gravar. Uma entrada com nome reservado (`help`), nome inválido,
  ou múltiplos valores para a mesma chave (a condição que `--rename` recusa)
  é ignorada com aviso, sem bloquear as demais; `alias.alias` é omitido,
  como no `--export`. **Não** toca no `git config --global`; sem arquivo
  versionado detectado é erro (exit 1), não fallback. Avisa (stderr) quando
  algum alias importado tem valor começando por `!` — executa shell ao ser
  invocado, e importar de fonte não confiável equivale a executar comando
  arbitrário depois. Ver
  [ADR-0004](docs/adr/0004-semantica-de-merge-do-import.md).
- `git alias --doctor`: relatório read-only de diagnóstico da instalação (o
  inverso do `install.sh`) — confere se o arquivo de aliases versionado está
  no `include.path` e é detectável (com a resolução do caminho: absoluto,
  `~/…`, relativo a `$HOME`, cadeia de symlinks), se há aliases no `git
  config --global` fora dele (não versionados / risco de sombra), se
  há um `git-alias` no `PATH` e se sobrou um `alias.alias` legado sombreando
  o script. Sai `1` se encontra algo que impede `git alias` de funcionar como
  esperado (linha `erro:`), `0` caso contrário (`aviso:` não afeta o código).
- `git alias --rename <velho> <novo>`: renomeia um alias preservando o valor
  exato (newlines internas do corpo inclusive), no lugar de
  `git alias novo "$(...)" && git alias --unset velho`.
- `git alias --list --file`: restringe a listagem aos aliases presentes no
  arquivo de aliases incluído.
- `git alias --list --origin` (também: `-o`): marca a origem de cada alias
  listado (`arquivo:<caminho>`, `--global` ou `outro:<origem>`), no espírito
  de `git config --show-origin`.
- Guardas ao criar um alias (e no destino de `--rename`): recusa nome
  inválido ou o nome reservado `alias`; avisa (sem recusar) quando o nome
  sombreia um comando builtin do Git.
- Seção "Códigos de saída" no README, documentando o contrato 0/1/2.

### Corrigido

Achados e corrigidos ainda durante o desenvolvimento desta versão — não
chegaram a afetar nenhuma versão publicada antes desta:

- `git alias --list` (e `--list --origin`) migrou o parsing para `git
  config --name-only --get-regexp` + consulta por chave, o mesmo saneamento
  já aplicado ao `--export`: um alias com valor multilinha não corrompe
  mais a listagem, e cada linha física do valor carrega o rótulo de origem
  correto. A falha ao consultar um alias que sumiu entre a enumeração e a
  consulta (ex.: removido por outro processo) não aborta mais a listagem —
  a entrada é pulada e o resto sai normalmente.
- `git alias --unset` recusa o nome reservado `alias`/`help`, mesma guarda
  já aplicada à criação e ao `--rename` — sem ela, `--unset alias` apagava
  silenciosamente a entrada que faz `git alias` funcionar como subcomando
  do Git.
- `--list` e `--rename` agora avisam/recusam corretamente quando uma chave
  `alias.X` tem mais de um valor na mesma camada (ex.: `git config --add`
  usado por fora do script), inclusive quando a multiplicidade só aparece
  no fallback XDG do config global (`$XDG_CONFIG_HOME/git/config`) ou
  está dividida entre `~/.gitconfig` e esse fallback ao mesmo tempo —
  cenário em que `--rename` chegava a gravar só o último valor sob o novo
  nome e descartar os demais.
- `--unset`, `--rename` e a criação de alias agora alcançam e limpam
  consistentemente um alias que more só no fallback XDG do config global,
  que algumas versões do Git não enxergam via `--get`/`--unset-all` mesmo
  a leitura mesclada enxergando os dois arquivos; `GIT_CONFIG_GLOBAL=""`
  (isolamento deliberado de ambiente, usado em teste/sandbox) desliga esse
  fallback também, como o próprio Git faz.
- Mensagens de erro mais precisas quando uma remoção ou limpeza de cópia
  obsoleta falha por um motivo genuíno (lock, permissão) em vez de "a
  chave não existe" — `--unset`, `--rename` e a criação de alias agora
  distinguem esse caso e apontam a causa real, em vez de anunciar sucesso
  ou reportar "não existe" indevidamente.

### Alterado

- Contrato de códigos de saída (agora documentado no README, seção "Códigos
  de saída"): consulta de alias inexistente, `--unset` de alias ausente,
  `--rename` de alias ausente/para destino já existente, e uma limpeza de
  cópia obsoleta que falha por um motivo genuíno (lock, permissão) agora
  retornam `1` — antes, `0` com só um aviso em stdout/stderr, mesmo quando
  o alias ficava sombreado ou duas definições coexistindo. `git alias help`
  com argumentos extras (forma não documentada) passa a retornar `2` (erro
  de uso) em vez de `0`.
- Layout do repositório, reorientado para ferramenta instalável
  ([ADR-0002](docs/adr/0002-repositorio-proprio-para-o-git-alias.md)):
  `git/bin/git-alias` → `bin/git-alias`; `git/aliases.gitconfig` (o arquivo
  de aliases do próprio autor, usado como exemplo) → `examples/aliases.gitconfig`,
  amostra do formato — não é mais o alvo do `install.sh`.
- `git alias --doctor`: seção `[git/bin no PATH]` renomeada para
  `[git-alias no PATH]` — o diretório `git/bin` deixou de existir; a seção
  descreve a mesma checagem (um `git-alias` no `PATH` que resolve para o
  script). Texto informativo, não contrato de máquina.
- `install.sh` deixa de gravar `include.path` apontando para um arquivo
  dentro do clone. Se `git alias --doctor` já detecta um arquivo de aliases
  versionado (em qualquer caminho), não mexe em nada; senão, cria um a
  partir do config atual (`git alias --export`) em
  `${XDG_CONFIG_HOME:-~/.config}/git/aliases.gitconfig` — fora do clone,
  sobrevivendo a um reclone/`git pull` da ferramenta — e adiciona esse ao
  `include.path`.

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
