# Auditoria de portabilidade

Levantamento dos pontos do script e dos testes que variam entre
implementações de utilitários POSIX — coreutils (GNU/Linux) e o userland
BSD/macOS — e como cada um é tratado hoje. Item do passo 9 do
`docs/roadmap.md`, coberto a partir daqui pelo job `portabilidade-macos`
do CI (`.github/workflows/ci.yml`), que roda a suíte inteira num runner
`macos-latest` (BSD `stat`, `readlink` sem `-f`, `mktemp` da Apple).

## `mktemp`

Todo uso no repositório passa um template explícito com `XXXXXX`
(`bin/git-alias`: `mktemp "$dir/git-alias.XXXXXX"`,
`mktemp "$TMPDIR/git-alias-import.XXXXXX"`) ou usa só `mktemp -d` sem
template — a forma que tanto o GNU coreutils quanto o `mktemp` da Apple
(derivado do BSD) aceitam sem flags adicionais, criando um diretório sob
`$TMPDIR`/`/tmp`. Nenhum uso depende de uma extensão GNU-only (como
`--tmpdir` explícito ou um template sem `X` suficiente).

## `stat`

`file_mode()` (`bin/git-alias`) e o helper de teste equivalente
(`tests/git-alias.sh`) tentam a sintaxe GNU (`stat -c '%a'`) e, se falhar,
a BSD/macOS (`stat -f '%Lp'`), retornando vazio se nenhuma funcionar — a
saída é sempre tratada como best-effort (preservar o modo do arquivo numa
substituição atômica), nunca uma dependência rígida.

## `readlink`

Usado sempre sem `-f` (flag GNU-only para resolver a cadeia inteira de
symlinks; a variante BSD/macOS não a aceita da mesma forma). A resolução
de cadeia é feita à mão em `resolve_link()` (`bin/git-alias`) e
`link_completion()` (`install.sh`), um nível por vez, com teto de
iterações — portável nas duas famílias.

## `head -n`

Único uso de corte de arquivo (`head -n 3`, `head -n 1`), sintaxe POSIX
comum às duas famílias. Sem `head -c` nem `-n -N` (formas que divergem
entre GNU e BSD).

## Ausência de `sed -i`

Nenhum script deste repositório edita arquivo em lugar (`sed -i`) — a
sintaxe da flag diverge entre GNU (`-i` aceita sufixo colado,
`-i.bak`) e BSD/macOS (exige o sufixo como argumento separado, mesmo
vazio: `-i ''`). Toda reescrita de arquivo aqui passa por
`write_aliases()`/`alias_render()` (`bin/git-alias`): grava um temporário
do zero e substitui por `mv` atômico.

## `LC_COLLATE` / faixas de case e glob

`bin/git-alias` fixa `LC_ALL=C` para o processo inteiro (linha ~41) —
cobre tanto a ordenação (`sort`) quanto as faixas `[a-z]`/`[A-Za-z0-9-]`
usadas por `validate_alias_name`/`to_lower`, sensíveis a `LC_COLLATE` em
teoria (mesmo não reproduzido em pt_BR/en_US/C.UTF-8/POSIX neste
ambiente). `install.sh` não tem faixa de case/glob equivalente — só
comparações de string exatas e `case` sobre caminhos —, então não precisa
da mesma fixação.

## Versões de git

`--name-only` em `git config --get-regexp`/`--name-only` sozinho é o piso
de compatibilidade: **git ≥ 2.9**. `.github/workflows/ci.yml` passa a
compilar essa versão exata (`git-version: floor` na matriz do job
`testes`) a partir do código-fonte oficial, verificado por SHA256, e roda
a suíte inteira contra ela — ao lado da versão mais nova disponível no
runner (`git-version: latest`), para pegar o *last-wins* de
`git config --get` e qualquer outra diferença de comportamento entre as
duas pontas suportadas.
