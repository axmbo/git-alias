#!/usr/bin/env sh
# Runner das suítes de teste: roda todo tests/*.sh (menos este arquivo).
# Sem ferramenta externa — só shell POSIX.
#
# O shell usado para cada suíte vem de $SHELL_UNDER_TEST (default: sh). O CI
# roda com "dash" e com "bash" para pegar regressão de portabilidade:
#
#   SHELL_UNDER_TEST=dash sh tests/run.sh
#   SHELL_UNDER_TEST=bash sh tests/run.sh

set -eu

SH_UT="${SHELL_UNDER_TEST:-sh}"
DIR="$(cd "$(dirname "$0")" && pwd)"
rc=0

for suite in "$DIR"/*.sh; do
	name="${suite##*/}"
	case "$name" in
	run.sh) continue ;;
	esac

	echo "=== $name ($SH_UT) ==="
	if "$SH_UT" "$suite"; then
		:
	else
		rc=1
		echo "--- $name FALHOU"
	fi
	echo
done

if [ "$rc" -eq 0 ]; then
	echo "run.sh: todas as suítes passaram"
else
	echo "run.sh: houve suíte com falha"
fi
exit "$rc"
