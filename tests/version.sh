#!/usr/bin/env sh
# Checagem estática do repositório: a constante VERSION do script tem de ser
# igual ao cabeçalho de versão mais recente do CHANGELOG.md. Amarra as duas
# fontes exigidas por docs/adr/0003-politica-de-versionamento-e-release.md:
# esquecer de atualizar uma das duas numa release quebra o CI.
# Determinístico e sem ferramenta externa: só shell POSIX e sed(1).

set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/bin/git-alias"
CHANGELOG="$ROOT/CHANGELOG.md"
pass=0
fail=0

check() { # descrição, esperado, obtido
	if [ "$2" = "$3" ]; then
		pass=$((pass + 1))
		echo "ok   - $1"
	else
		fail=$((fail + 1))
		echo "FAIL - $1"
		echo "        esperado: [$2]"
		echo "        obtido:   [$3]"
	fi
}

# Valor de VERSION='X.Y.Z' na primeira linha do script que o define.
script_version="$(
	sed -n "s/^VERSION='\([^']*\)'.*/\1/p" "$SCRIPT" | head -n 1
)"

# Primeiro cabeçalho "## [X.Y.Z]" do CHANGELOG (o mais recente; "## [Não
# lançado]" não casa o padrão de dígitos). [0-9][0-9]* em vez de [0-9]\+
# para não depender de BRE do GNU (o runner macOS usa o sed do BSD).
changelog_version="$(
	sed -n 's/^## \[\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)\].*/\1/p' \
		"$CHANGELOG" | head -n 1
)"

check "a constante VERSION do script está preenchida" \
	"preenchida" "$([ -n "$script_version" ] && echo preenchida || echo vazia)"
check "há um cabeçalho de versão X.Y.Z no CHANGELOG" \
	"presente" "$([ -n "$changelog_version" ] && echo presente || echo ausente)"
check "VERSION do script == versão mais recente do CHANGELOG" \
	"$changelog_version" "$script_version"

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
