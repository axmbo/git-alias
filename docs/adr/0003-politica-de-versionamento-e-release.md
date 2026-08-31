# 3. Política de versionamento e release

## Status

Aceito — 2026-08-31

## Contexto

O `git-alias` vai ser publicado como código aberto e passa a ter repositório
próprio (ADR-0002). Um projeto público precisa de um número de versão: sem
ele, um relatório de bug não identifica a build, não há changelog e não há
critério objetivo para o que conta como mudança incompatível.

A ferramenta expõe **duas** superfícies das quais um consumidor pode
depender:

1. **Superfície de comandos** — os subcomandos e flags de `git alias`, a
   semântica de cada um, o formato legível por máquina das saídas
   (`--list`, `--export`) e o contrato de códigos de saída.
2. **Formato do `aliases.gitconfig` gerado** — não é artefato interno: o
   arquivo é versionado no repositório do usuário, carregado via
   `include.path` e **detectado pelo próprio script** pelo cabeçalho que ele
   escreve (ADR-0001). Uma mudança nesse cabeçalho ou na estrutura da seção
   `[alias]` pode fazer uma versão anterior deixar de reconhecer o arquivo,
   ou produzir um diff enorme num arquivo já commitado.

O roteiro atual (`docs/roadmap.md`) é explicitamente pré-1.0: os passos
seguintes ainda alteram a superfície de comandos antes da primeira tag
pública.

## Decisão

### Versionamento semântico ancorado nas duas superfícies

O projeto adota [SemVer 2.0.0](https://semver.org/lang/pt-BR/). O "contrato
público" para fins de SemVer é a união da superfície de comandos com o
formato do `aliases.gitconfig` gerado.

- **MAJOR** — remoção ou renomeação de subcomando/flag; mudança
  incompatível na semântica de um comando ou no formato de máquina de uma
  saída; mudança no contrato de códigos de saída que quebre scripts;
  qualquer mudança no formato do `aliases.gitconfig` que faça uma versão
  anterior deixar de detectar ou de reimportar o arquivo; incremento do
  marcador `# Formato: N` (abaixo).
- **MINOR** — subcomando ou flag novo, retrocompatível; nova linha
  informativa de saída; passar a aceitar entrada antes rejeitada. Nada que
  já funcionava muda.
- **PATCH** — correção de bug sem mudança de superfície; correção de
  portabilidade; ajuste de mensagem que não seja contrato de máquina.

### Fase 0.y.z

A série `0.y` começa em **`0.1.0`** e vale enquanto durar o roteiro pré-1.0.
Nela a garantia de retrocompatibilidade do MAJOR fica suspensa (cláusula 4
do SemVer): uma quebra de comando ou de formato incrementa **MINOR**
(`0.1.0` → `0.2.0`); correção incrementa PATCH. A tag **`v1.0.0`** (passo 10
do roteiro) marca o congelamento da superfície; a partir dela as regras de
MAJOR/MINOR/PATCH acima passam a valer integralmente. Não há intenção de
tagear as versões `0.y` — o número existe para identificar a build e o
changelog durante o desenvolvimento pré-1.0.

### Constante `VERSION` como fonte única

`git/bin/git-alias` carrega no topo `VERSION='X.Y.Z'`. É a única fonte da
verdade da versão. `git alias --version` (e o sinônimo `-v`) imprime essa
constante. Se o diretório do próprio script (resolvido seguindo symlinks,
não o diretório de trabalho) estiver dentro de um repositório git, anexa
entre parênteses a saída de `git describe --tags --always --dirty`, p.ex.
`0.1.0 (v0.1.0-3-gabc1234)`; fora de um repositório, imprime só a constante.
`git describe` **nunca** é fonte primária — `VERSION` é a resposta
autoritativa (ver *Consequências* para a limitação da cópia vendorizada).

O Git não intercepta `--version` de um subcomando externo (ao contrário de
`--help`, que ele desvia para a man page inexistente `git-alias`). Um teste
em `tests/git-alias.sh` fixa esse comportamento.

### CHANGELOG e checagem de consistência

`CHANGELOG.md` na raiz, no formato
[Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/), com a seção
`## [Não lançado]` no topo. Todo incremento de versão entra no `CHANGELOG.md`
**antes** da tag. `tests/version.sh` é uma checagem estática determinística
(no espírito do `tests/repo.sh`): a constante `VERSION` tem de ser igual ao
cabeçalho de versão mais recente do `CHANGELOG.md`. Dessincronizar os dois
quebra o CI.

### Processo de release

Documentado em `docs/releasing.md`: bump da constante → seção no
`CHANGELOG.md` → `git tag -a vX.Y.Z` → push da tag (quando houver remote).
A tag é sempre `vX.Y.Z`, com o `v` — é o que `git describe --tags` usa.

### Marcador de formato no `aliases.gitconfig`

O cabeçalho gerado (ADR-0001) ganha uma terceira linha de comentário,
`# Formato: 1`, antes da linha em branco que separa o cabeçalho da seção
`[alias]`:

```
# Gerado por: git alias --export
# Nao edite a mao; rode o comando novamente para atualizar.
# Formato: 1

[alias]
```

A versão do formato do arquivo é **independente** da versão da ferramenta:
a ferramenta pode chegar a `2.0.0` com o formato ainda em `1`. Incrementar
`# Formato: N` é, por si só, MAJOR da ferramenta, e nesse momento
import/export passam a precisar distinguir formatos. Hoje, e desde sempre,
`# Formato: 1`.

A detecção do arquivo incluído e a de reimportabilidade continuam sendo
`head -n 3 | grep -F '# Gerado por: git alias --export'` — a linha nova é a
terceira, ainda dentro dessa janela, e o `grep` casa na primeira linha de
qualquer forma.

## Consequências

- `git alias --version` passa a existir e será exigido pelo template de
  issue de bug (item no `docs/roadmap.md`).
- O detalhe entre parênteses (`git describe`) é contexto de melhor esforço,
  não contrato: ele reflete o repositório em que o *diretório do script*
  está. Numa cópia solta do script vendorizada e commitada noutro
  repositório, o parêntese mostra o `git describe` desse repositório
  hospedeiro — a constante `VERSION` continua correta. Não há como
  distinguir esse caso de um checkout legítimo só olhando o diretório;
  consumir o `git-alias` como submódulo evita a ambiguidade.
- O ADR-0001 permanece em vigor. Esta decisão **estende** o cabeçalho que
  ele define; não altera a semântica de gravação, detecção ou normalização.
- Um `aliases.gitconfig` gerado por uma versão anterior (cabeçalho de duas
  linhas) continua sendo detectado. O primeiro `git alias <nome> <cmd>` ou
  `git alias --export` depois do upgrade reescreve o arquivo com a linha
  `# Formato: 1` — um diff de uma linha, único e determinístico. É adição
  retrocompatível; não conta como quebra.
- O contrato de códigos de saída (item F7 do roadmap) passa a ser parte da
  superfície pública versionada; o passo do roadmap que o revisita já nasce
  sob esta política.
- Enquanto o projeto estiver em `0.y`, o README deixa claro que a superfície
  ainda pode mudar entre versões MINOR.
- Manter dois eixos de versão (a da ferramenta e o `# Formato: N`) é um
  custo pequeno agora e evita ambiguidade quando o formato finalmente
  mudar.
- A checagem `tests/version.sh` cria um acoplamento deliberado: toda release
  tem de tocar `VERSION` e `CHANGELOG.md` juntos, senão o CI falha.
