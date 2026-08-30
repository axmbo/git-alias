#!/usr/bin/env sh
# Testes do script git/bin/git-alias.
# Roda num HOME/config temporário — não toca no ambiente real.

set -eu

SCRIPT="$(cd "$(dirname "$0")/../git/bin" && pwd)/git-alias"
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

SB="$(mktemp -d)"
trap 'rm -rf "$SB"' EXIT
export HOME="$SB"
export GIT_CONFIG_GLOBAL="$SB/.gitconfig"
export GIT_CONFIG_SYSTEM=/dev/null
cd "$SB"

git config --global user.email t@t
git config --global user.name t
git config --global alias.co checkout
git config --global alias.gone '!git branch # limpa'

check "sem args mostra a sintaxe" \
	"Sintaxe de uso:" "$("$SCRIPT" | head -1)"
check "help mostra a sintaxe" \
	"Sintaxe de uso:" "$("$SCRIPT" help | head -1)"
check "-h mostra a sintaxe" \
	"Sintaxe de uso:" "$("$SCRIPT" -h | head -1)"
check "consulta alias existente" \
	"co = checkout" "$("$SCRIPT" co)"
check "consulta alias inexistente" \
	"Aviso: O alias 'nada' não foi encontrado." "$("$SCRIPT" nada)"
check "cria alias" \
	"Alias 'foo' configurado com sucesso!" "$("$SCRIPT" foo '!echo foo')"
check "alias recém-criado é consultável" \
	"foo = !echo foo" "$("$SCRIPT" foo)"
check "--list traz co" \
	"co = checkout" "$("$SCRIPT" --list | grep '^co ')"

git config --global alias.alias '!true'
check "--list omite alias.alias" \
	"" "$("$SCRIPT" --list | grep '^alias ' || true)"

check "--unset remove" \
	"Alias 'foo' removido com sucesso!" "$("$SCRIPT" --unset foo)"
check "--unset de alias ausente avisa" \
	"Aviso: O alias 'foo' não existe ou já foi removido." "$("$SCRIPT" --unset foo)"
check "--unset sem nome erra" \
	"Erro: Informe o nome do atalho para remover. Ex: git alias --unset <nome>" \
	"$("$SCRIPT" --unset 2>&1 || true)"

# --export (alias.alias ainda presente, deve ser omitido)
check "--export stdout tem cabeçalho" \
	"# Gerado por: git alias --export" "$("$SCRIPT" --export | head -1)"
check "--export stdout tem seção [alias]" \
	"[alias]" "$("$SCRIPT" --export | grep -F '[alias]')"

EXP="$SB/out.gitconfig"
"$SCRIPT" --export "$EXP" 2>/dev/null
check "--export para arquivo: co reimportável" \
	"checkout" "$(git config --file "$EXP" alias.co)"
check "--export para arquivo: gone reimportável" \
	"!git branch # limpa" "$(git config --file "$EXP" alias.gone)"
check "--export para arquivo: omite alias.alias" \
	"" "$(git config --file "$EXP" alias.alias 2>/dev/null || true)"

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
