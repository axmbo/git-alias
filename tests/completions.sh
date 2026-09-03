#!/usr/bin/env sh
# Checagem estática dos arquivos de completion (completions/git-alias.bash e
# completions/git-alias.zsh). Sem harness de TAB: verifica existência,
# sintaxe (quando o shell correspondente está instalado) e que cada
# subcomando/flag de "git alias" aparece nos dois arquivos — uma regressão
# que tire um subcomando da completion quebra esta suíte. É o próprio
# artefato entregue, então testa também que o discriminador de fato
# discrimina (um token inexistente NÃO é encontrado).
# Determinístico, só shell POSIX e grep.

set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASH_COMP="$ROOT/completions/git-alias.bash"
ZSH_COMP="$ROOT/completions/git-alias.zsh"
pass=0
fail=0
skip=0

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

yn() { # ecoa "sim" se o comando passar, "nao" se falhar
	if "$@"; then echo sim; else echo nao; fi
}

has() { # has <arquivo> <literal>: <literal> aparece em <arquivo>?
	grep -qF -- "$2" "$1"
}

# --- existência --------------------------------------------------------
check "completions/git-alias.bash existe" "sim" "$(yn test -f "$BASH_COMP")"
check "completions/git-alias.zsh existe" "sim" "$(yn test -f "$ZSH_COMP")"

# --- sintaxe (best effort: só se o shell estiver instalado) -----------
if command -v bash >/dev/null 2>&1; then
	st=0
	bash -n "$BASH_COMP" 2>/dev/null || st=$?
	check "bash -n completions/git-alias.bash: sem erro de sintaxe" "0" "$st"
else
	skip=$((skip + 1))
	echo "skip - bash não encontrado; pulando 'bash -n'"
fi

if command -v zsh >/dev/null 2>&1; then
	st=0
	zsh -n "$ZSH_COMP" 2>/dev/null || st=$?
	check "zsh -n completions/git-alias.zsh: sem erro de sintaxe" "0" "$st"
else
	skip=$((skip + 1))
	echo "skip - zsh não encontrado; pulando 'zsh -n'"
fi

# --- forma esperada de cada arquivo ---------------------------------
check "o .bash define a função _git_alias" "sim" "$(yn has "$BASH_COMP" '_git_alias ()')"
check "o .zsh tem a tag #compdef git-alias" "sim" "$(yn has "$ZSH_COMP" '#compdef git-alias')"
check "o .zsh define a função _git-alias" "sim" "$(yn has "$ZSH_COMP" '_git-alias()')"

# --- cobertura de subcomandos e flags ------------------------------
# Cada token de "git alias" tem de aparecer literalmente nos DOIS arquivos.
# Se um subcomando some da completion, o grep correspondente falha e a suíte
# acusa (o "pegaria a regressão" exigido para um teste que é o artefato).
# Os sinônimos curtos -v/-o ficam de fora deste laço (a busca por substring
# casaria dentro de --version/--origin); são checados à parte, logo abaixo.
set -- help --version --list --export --import --unset --rename --doctor \
	--file --origin --overwrite --dry-run
for tok do
	for f in "$BASH_COMP" "$ZSH_COMP"; do
		check "${f##*/} cita '$tok'" "sim" "$(yn has "$f" "$tok")"
	done
done

# Sinônimos curtos, checados por um trecho de contexto que só existe se o
# sinônimo estiver de fato ofertado.
check ".bash oferta o sinônimo -v" "sim" "$(yn has "$BASH_COMP" '-v --list')"
check ".zsh oferta o sinônimo -v" "sim" "$(yn has "$ZSH_COMP" '-v --list')"
check ".bash oferta o sinônimo -o de --origin" "sim" "$(yn has "$BASH_COMP" '--origin -o')"
check ".zsh oferta o sinônimo -o de --origin" "sim" "$(yn has "$ZSH_COMP" '(--origin -o)')"

# --- o discriminador de fato discrimina ---------------------------
# Contraprova: um token que NÃO deveria existir não é encontrado. Sem isto,
# um grep sempre-verdadeiro passaria despercebido.
check "controle: token inexistente não é encontrado no .bash" \
	"nao" "$(yn has "$BASH_COMP" '--nao-existe-subcomando')"
check "controle: token inexistente não é encontrado no .zsh" \
	"nao" "$(yn has "$ZSH_COMP" '--nao-existe-subcomando')"

echo
echo "pass=$pass fail=$fail skip=$skip"
[ "$fail" -eq 0 ]
