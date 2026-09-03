# Changelog

Todas as mudanças notáveis do `git-alias` são registradas aqui.

O formato segue o [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/)
e o projeto adota o [Versionamento Semântico](https://semver.org/lang/pt-BR/),
conforme o
[ADR-0003](docs/adr/0003-politica-de-versionamento-e-release.md). Enquanto o
projeto estiver na série `0.y`, a superfície de comandos e o formato do
`aliases.gitconfig` ainda podem mudar entre versões MINOR.

## [Não lançado]

### Adicionado

- `git alias --doctor`: relatório read-only de diagnóstico da instalação (o
  inverso do `install.sh`) — confere se o arquivo de aliases versionado está
  no `include.path` e é detectável (com a resolução do caminho: absoluto,
  `~/…`, relativo a `$HOME`, cadeia de symlinks), se há aliases no `git
  config --global` fora dele (não versionados / risco de sombra), se
  `git/bin` está no `PATH` e se sobrou um `alias.alias` legado sombreando o
  script. Sai `1` se encontra algo que impede `git alias` de funcionar como
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

- `git alias --list` migrou o parsing para `git config --name-only
  --get-regexp` + consulta por chave — o parsing anterior (`--get-regexp |
  sed`) corrompia a listagem diante de um alias com valor multilinha, o
  mesmo bug já corrigido no `--export` (`alias_render`).
- `git alias --unset <nome>` recusa o nome reservado `alias`/`help`
  (ignorando caixa), mesma guarda já aplicada a criação e `--rename` —
  sem ela, `--unset alias` apagava silenciosamente a entrada
  `alias.alias` no `--global` que faz `git alias` funcionar como
  subcomando do Git.
- `git alias --list`: uma falha ao consultar um alias já enumerado (ex.:
  removido por outro processo entre a enumeração e a consulta) não aborta
  mais a listagem inteira sob `set -eu` — a entrada é pulada e o restante
  é listado normalmente, com exit code `0`.
- `git alias --list` avisa (stderr) quando uma chave `alias.X` tem mais de
  um valor na mesma camada (ex.: `git config --add` usado por fora do
  script) — antes, a listagem mostrava só o último valor sem nenhuma
  pista da anomalia, a mesma que `--rename` (F4) já recusa citando
  `git config --get-all`. Escopado por camada (arquivo incluído e
  `--global`, separadamente) desde o início — a primeira versão deste
  aviso contava o config mesclado inteiro e confundia uma cópia obsoleta
  no `--global` (a mesma sombra que `--unset`/`--rename`/criação já
  limpam em outros pontos) com multivalor real, disparando falso
  positivo.
- `git alias --list --origin`: cada linha física de um valor multilinha
  agora carrega o rótulo de origem — antes, só a 1ª linha vinha
  prefixada com `<origem>\t`, e as linhas de continuação do corpo saíam
  cruas, quebrando o parsing por `cut -f1`.
- `git alias --unset` e `--rename` (lookup de `<velho>`, checagem de
  `<novo>` já existente e limpeza de cópia obsoleta) agora alcançam um
  alias que more só no fallback XDG do config global
  (`$XDG_CONFIG_HOME/git/config`) — em algumas versões do Git, `git
  config --global --get`/`--unset-all` não enxergam esse arquivo quando
  `~/.gitconfig` existe, mesmo a leitura mesclada (usada por `--list`)
  enxergando os dois. Antes, `--unset` desse alias dizia "não existe" e
  `--rename` misdiagnosticava a causa (ex.: sugerindo `--system`/`--local`
  quando o alias estava genuinamente no `--global`).
- `git alias --rename`: quando a remoção de `<velho>` de sua origem falha
  por um motivo genuíno (lock, permissão) em vez de "chave não existe", a
  mensagem final agora aponta a causa real (`<velho>` continua na MESMA
  fonte de onde veio) em vez da mensagem genérica de "outra fonte de
  configuração", que era factualmente errada nesse caso. A mesma checagem
  cobre a limpeza oportunista da cópia obsoleta no `--global` quando
  `<velho>` vem do arquivo incluído.
- **Perda de dado corrigida**: a guarda de multiplicidade do `--rename` e
  o aviso de multiplicidade do `--list` tinham o mesmo blind spot de
  fallback XDG que `--unset`/`--rename` (acima) — um alias com múltiplos
  valores só no fallback XDG passava pela guarda sem ser detectado,
  fazendo `--rename` gravar só o último valor sob o novo nome e apagar
  todos os valores originais. Corrigido com o mesmo mecanismo de
  fallback usado nas demais correções desta lista.
- `GIT_CONFIG_GLOBAL=""` (string vazia, definida de propósito para
  isolar o Git — técnica real de sandboxing/teste) agora isola
  `--unset`/`--rename`/criação do fallback XDG, como o próprio Git faz.
  Antes, essas checagens tratavam "definida como vazia" e "indefinida"
  como a mesma coisa.
- `git alias <nome> '<cmd>'` (criação/atualização): quando a limpeza
  oportunista de uma cópia obsoleta no `--global` falha por um motivo
  genuíno (lock, permissão), o comando agora avisa que o alias
  recém-gravado ficou sombreado pela cópia antiga (que vem depois do
  `[include]` e por isso vence na resolução do Git) em vez de anunciar
  sucesso puro e simples.
- `git alias --unset`: quando a remoção falha por um motivo genuíno em
  vez de a chave já não existir, a mensagem agora diz isso — antes,
  dizia "não existe ou já foi removido" mesmo com o alias intacto. A
  mesma checagem agora distingue "existe numa camada que --unset nunca
  tenta tocar" (`--system`/`--local`) de "a remoção falhou de verdade" —
  as duas caíam na mesma mensagem de "remoção falhou", mesmo sem
  nenhuma tentativa real na primeira.
- **Perda de dado corrigida (variante adicional)**: a guarda de
  multiplicidade do `--rename` (e o aviso do `--list`) ainda perdiam
  dado quando `~/.gitconfig` **e** o fallback XDG definiam a MESMA
  chave com valores DIFERENTES ao mesmo tempo — a correção anterior só
  cobria "existe só num dos dois". A contagem agora soma os dois lados
  em vez de escolher um.
- A correção acima, por sua vez, contava o fallback XDG em dobro quando
  `~/.gitconfig` **não existe de jeito nenhum** — nesse estado, `git
  config --global` já lê o XDG transparentemente, então somar a
  contagem do XDG de novo por cima fazia `--rename` recusar um alias
  com um valor só (regressão da correção anterior, corrigida no mesmo
  ciclo de revisão).

### Alterado

- Contrato de códigos de saída: `--rename` e `git alias <nome> '<cmd>'`
  (criação) agora retornam `1` (antes: `0`) quando a limpeza de uma
  cópia obsoleta falha por um motivo genuíno (lock, permissão) em vez
  de "chave não existe", deixando duas definições coexistindo (ou, no
  caso da criação, a nova ficando silenciosamente sombreada pela
  antiga) — antes, o comando anunciava sucesso mesmo nesses casos.

- Contrato de códigos de saída: consulta de alias inexistente, `--unset` de
  alias ausente e (novo) `--rename` de alias ausente ou para destino já
  existente agora retornam `1` (antes: `0`, com aviso em stdout/stderr).
  Ver a tabela no README.
- `git alias help` com argumentos extras (ex.: `git alias help foo bar`,
  forma não documentada) passa a retornar `2` (erro de uso) em vez de `0`
  — consequência da guarda de F6 que só reserva `help` sem um segundo
  argumento, para permitir `git alias help '<cmd>'` cair na checagem de
  nome reservado em vez de virar um no-op silencioso.

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
