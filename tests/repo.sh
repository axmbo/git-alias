#!/usr/bin/env sh
# Checagem estática do repositório.
# Hoje cobre uma única propriedade: existe exatamente um README.md, e ele
# está na raiz. É exigência do fluxo de trabalho do autor — um único ponto
# de entrada de documentação, sem ambiguidade para humanos, ferramentas e
# agentes de IA. Determinístico e sem ferramenta externa: só shell POSIX,
# find(1) e grep(1).

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

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
