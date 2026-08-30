# 1. `git alias` grava direto no arquivo de aliases incluído

## Status

Aceito — 2026-08-30

## Contexto

O subcomando `git alias` (script `git/bin/git-alias`) até aqui:

- `git alias <nome> '<cmd>'` grava sempre em `git config --global`
  (`~/.gitconfig`).
- `git alias --unset <nome>` remove só do `--global`.
- `git alias --export [<arquivo>]` é o único caminho que escreve em
  `git/aliases.gitconfig`, regenerando o arquivo inteiro a partir do config
  mesclado.

O fluxo era "mão única": o arquivo versionado derivava do config local, nunca
o contrário. Consequência prática: criar um alias e versioná-lo exigia dois
passos (`git alias foo …` e depois
`git alias --export ~/Dev/dotfiles/git/aliases.gitconfig`), e era fácil
esquecer o segundo — o alias ficava só na máquina.

## Decisão

`git alias <nome> '<cmd>'` e `git alias --unset <nome>` passam a operar sobre
o **arquivo de aliases incluído**, quando houver um.

- **Detecção:** varre `git config --global --get-all include.path` e escolhe o
  primeiro arquivo cujo conteúdo tem o cabeçalho que o próprio script escreve
  (`# Gerado por: git alias --export`). Só reconhece arquivos que ele mesmo
  gerou; sobrevive a rename.
- **Fallback:** se nenhum arquivo for detectado, grava em
  `git config --global` como antes, mas imprime um aviso de que o alias não
  foi para um arquivo versionado.
- **`--unset`:** remove o alias de onde ele estiver — do arquivo incluído
  **e** do `--global` — para não deixar cópia órfã fazendo sombra.
- **Ordem alfabética:** toda gravação no arquivo é seguida de uma
  normalização que reescreve a seção `[alias]` ordenada (`LC_ALL=C`, ordem
  estável independente de locale), com o cabeçalho padrão. O `--export` passa
  a usar a mesma rotina. Objetivo: diffs mínimos e determinísticos no
  versionamento.

## Consequências

- O arquivo versionado deixa de ser estritamente derivado: `git alias` escreve
  nele diretamente. O `--export` continua existindo para reconstruir o arquivo
  do zero a partir do config mesclado (primeira migração; consolidar aliases
  criados antes desta mudança).
- Um `git alias foo …` agora produz, sozinho, um diff em
  `git/aliases.gitconfig` pronto para commit — sem passo extra.
- A ordenação estável pode reordenar uma vez um `aliases.gitconfig` legado que
  estivesse fora de ordem; depois disso os diffs ficam limpos.
- Máquinas sem o `install.sh` rodado continuam funcionando via fallback
  `--global` (com aviso).
