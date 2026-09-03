# 4. Semântica de merge do `git alias --import`

## Status

Aceito — 2026-09-03

## Contexto

O `--export` (ADR-0001) é mão única: reconstrói o `aliases.gitconfig` inteiro
a partir do config mesclado. Não há caminho para trazer *só* alguns aliases
de uma fonte externa — um `aliases.gitconfig` de um colega, um dump de
`git config --file`, a saída de um `--export` de outra máquina — para dentro
do arquivo versionado sem sobrescrever tudo o que já está lá.

O F2 do roteiro pré-1.0 (`docs/roadmap.md`) pede um `git alias --import
<arquivo>` que funda as entradas `alias.*` da fonte na seção `[alias]` do
arquivo versionado. As forças em jogo:

- **Não destruir o que já existe.** Importar não pode apagar aliases do
  arquivo que a fonte não menciona, nem sobrescrever em silêncio um alias
  local que a fonte redefine com outro valor.
- **Fonte externa não é confiável.** Um valor de alias começando por `!`
  executa shell quando o alias é invocado. Importar de fonte não auditada é,
  na prática, aceitar executar comando arbitrário depois. O comando tem de
  dizer isso.
- **Fonte externa não pertence ao `--global`.** O `--global` (ADR-0001) é a
  camada de fallback e de config específica de máquina. Despejar aliases de
  terceiros nele os deixaria fora do versionamento e ainda com precedência
  sobre o arquivo. O `--import` opera *exclusivamente* sobre o arquivo
  versionado.
- **Consistência com o resto da ferramenta.** A leitura e a escrita de
  gitconfig são sempre via `git config --file` (ADR-0001, F5) — nunca
  parsing manual. O `--import` segue a mesma regra.

## Decisão

`git alias --import <arquivo>` lê as entradas `alias.*` da fonte e as funde,
**sem destruir**, na seção `[alias]` do arquivo de aliases versionado
detectado (o mesmo que `alias_file` acha pelo cabeçalho), renormalizando o
arquivo ao final (ordem alfabética + cabeçalho, como toda gravação).

### Fonte

- A fonte é lida com `git config --file <arquivo>` — exige um gitconfig
  válido com seção `[alias]`, exatamente o que o `--export` produz (o
  `--import` é o inverso do `--export`, e o par tem de fazer round-trip).
  Sintaxe inválida ou arquivo ilegível: erro, exit 1.
- `<arquivo>` = `-` lê da entrada padrão: o conteúdo é gravado num
  temporário (`mktemp`, removido ao final) e lido de lá, já que `git config
  --file` precisa de um caminho real.
- Fonte válida, mas sem nenhuma entrada `alias.*`: não é erro (exit 0), só
  informa que não havia nada a importar.
- A entrada `alias.alias` é omitida, como no `--export` (uma cópia inline
  faria sombra no dispatcher do próprio `git alias`).

### Merge, por entrada

Para cada `alias.<nome>` da fonte, comparado com o valor no arquivo
versionado:

| Estado no arquivo | Ação |
| --- | --- |
| ausente | grava; conta como **importado** |
| presente, valor **idêntico** | no-op silencioso |
| presente, valor **diferente**, sem `--overwrite` | **pula**; entra na lista de colisões do relatório |
| presente, valor **diferente**, com `--overwrite` | grava (a fonte vence); conta como **sobrescrito** |

Um valor multilinha legítimo (uma entrada só, com `\n` embutido — o corpo de
uma função `!f() { … }; f`) é preservado como qualquer outro: a leitura é
`git config --file <src> --get` exato, a escrita `git config --file <dest>`,
a mesma técnica de `alias_render` e `--rename`.

### Entradas problemáticas: pular, não abortar

Uma entrada da fonte com **nome reservado** (`help`), **nome inválido** pelo
charset da ferramenta, ou **múltiplos valores** (`alias.X` repetido na fonte
— a mesma condição que `--rename` recusa e que a KI-1 descreve) é **pulada
com aviso**, e o import segue com as demais. Contam no relatório como
*ignoradas*. Motivo: import de fonte externa tem de ser resiliente — uma
entrada estranha não pode bloquear dezenas de boas —, e pular sem gravar não
arrisca perda de dado (ao contrário de deixar `alias_render` colapsar um
multivalor em silêncio).

### `--overwrite` e `--dry-run`

- `--overwrite`: na colisão de valor, a fonte vence. Sem ele, a colisão é
  pulada e relatada.
- `--dry-run`: calcula e imprime o mesmo relatório, prefixado, **sem gravar
  nada** e sem renormalizar. Exit 0 quando o merge chega a rodar; as
  pré-condições que já valem 1 (fonte inválida, nenhum arquivo versionado
  detectado) valem igual em `--dry-run` — não são mascaradas.

### Relatório

Bloco único em stdout (é a saída primária do comando, como as mensagens de
create/`--unset`/`--rename`), no espírito de
`"4 importados; 2 já existentes com valor diferente: co, st (use --overwrite)"`.
Só menciona as categorias que ocorreram; valor idêntico não aparece.

### Nota de segurança

Quando ao menos um alias importado (ou, em `--dry-run`, previsto) tem valor
começando por `!`, o comando imprime em stderr um lembrete de que esses
aliases executam shell e de que importar de fonte não confiável equivale a
executar comando arbitrário ao invocá-los. O README traz a mesma nota.

### Sem arquivo versionado detectado

Erro, exit 1, com orientação para rodar o `install.sh` ou
`git alias --export <arquivo>`. **Não** há fallback para `--global`: o
`--import` existe para alimentar o arquivo versionado, e mandar aliases de
fonte externa para o `--global` contraria o propósito.

### Códigos de saída

Dentro do contrato 0/1/2 (ADR-0003, F7):

- **0** — importou (mesmo que parcialmente, com colisões puladas e/ou
  entradas ignoradas: são relatório, não falha); fonte sem aliases;
  qualquer `--dry-run` que rode até o fim.
- **1** — fonte inexistente/ilegível/inválida; nenhum arquivo versionado
  detectado; gravação de uma entrada que falha por um motivo genuíno (lock,
  permissão) — a entrada não conta como importada e o comando sai 1 mesmo
  que outras tenham entrado. (A renormalização final continua best-effort,
  como em `create`/`--rename`: só avisa, via `normalize_or_warn`.)
- **2** — erro de uso (flag desconhecida, `<arquivo>` faltando, argumento
  extra).

### Fora de escopo (v1.1)

- `git alias --import <src> <nome>...` — importar só um subconjunto nomeado.
- `git alias --adopt` — fundir os aliases do `--global` no arquivo *e*
  limpar as cópias redundantes (mexe em massa no `~/.gitconfig`, exige
  confirmação).

## Consequências

- O arquivo versionado ganha um caminho de entrada aditivo: dá para trazer
  aliases de fora sem `--export` (que sobrescreveria tudo). O `--export`
  continua sendo a via de reconstrução do zero.
- `--import` sem `--overwrite` nunca altera um alias que já existe no
  arquivo com valor diferente — a decisão de trocar é sempre explícita.
- A garantia "não destrói o que já está lá" cobre as entradas que o merge
  toca. A renormalização final (`normalize_or_warn`, como em toda gravação
  no arquivo) ainda está sujeita à **KI-1**: um `alias.X` multivalorado
  editado à mão no arquivo — que a fonte nem menciona — é colapsado para o
  último valor sem aviso. É a mesma limitação de `create`/`--unset`/`--rename`
  (`docs/known-issues.md`), não introduzida aqui; o guard de multivalor do
  `--import` só cobre o nome que ele próprio importaria.
- Como só escreve no arquivo versionado, `--import` não interage com a
  limpeza de sombra do `--global` que create/`--unset`/`--rename` fazem;
  uma cópia de mesmo nome no `--global` posicionada depois do `[include]`
  continuaria fazendo sombra, e o `--doctor` já sinaliza isso.
- A superfície de comandos cresce (novo subcomando + duas flags): é
  **MINOR** sob a política da fase `0.y` (ADR-0003). O formato do
  `aliases.gitconfig` não muda — `# Formato: 1`.
- O ADR-0001 e o ADR-0003 permanecem em vigor sem alteração; este ADR
  descreve um comando novo que segue as regras de ambos.
- Assumida a limitação de shell já documentada para `--export`/`--rename`:
  newline(s) no fim do valor não sobrevivem à captura por `"$(...)"`. Não
  afeta corpo de função multilinha normal.
