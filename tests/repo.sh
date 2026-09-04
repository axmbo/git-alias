#!/usr/bin/env sh
# Checagem estática do repositório: existe exatamente um README.md na raiz
# (fluxo de trabalho do autor — um único ponto de entrada de documentação,
# sem ambiguidade para humanos, ferramentas e agentes de IA) e o layout é o
# de repositório de ferramenta (ADR-0002: bin/git-alias, sem git/). Ambas
# determinísticas e sem ferramenta externa: só shell POSIX, find(1) e
# grep(1).

set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
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

# Todo arquivo chamado README.md na árvore de trabalho, exceto o que estiver
# sob .git/. Caminho relativo à raiz, sem o "./" inicial, em ordem estável.
# Varre a árvore de trabalho (não só o que o git rastreia) de propósito: um
# segundo README.md ainda não commitado também é ambíguo.
readmes="$(
	cd "$ROOT" &&
		find . -name README.md ! -path './.git/*' |
		sed 's|^\./||' |
		LC_ALL=C sort
)"

count="$(printf '%s\n' "$readmes" | grep -c . || true)"

check "existe exatamente um README.md no repositório" "1" "$count"
check "o único README.md está na raiz" "README.md" "$readmes"

# Layout de repositório de ferramenta (ADR-0002): o script mora em
# bin/git-alias, executável; git/ (layout antigo de dotfiles) não existe
# mais. Regressão aqui pegaria um "git mv" desfeito ou uma cópia extra do
# script deixada para trás.
check "bin/git-alias existe" \
	"sim" "$([ -f "$ROOT/bin/git-alias" ] && echo sim || echo nao)"
check "bin/git-alias é executável" \
	"sim" "$([ -x "$ROOT/bin/git-alias" ] && echo sim || echo nao)"
check "não sobrou um git/ do layout antigo" \
	"nao" "$([ -e "$ROOT/git" ] && echo sim || echo nao)"

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
