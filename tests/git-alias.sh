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
check "cria alias sem arquivo incluído: fallback --global com aviso" \
	"Alias 'foo' gravado no git config --global (nenhum arquivo de aliases incluído encontrado)." \
	"$("$SCRIPT" foo '!echo foo')"
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

# --- gravação no arquivo de aliases incluído ------------------------------
AF="$SB/aliases.gitconfig"
printf '%s\n' \
	'# Gerado por: git alias --export' \
	'# Nao edite a mao; rode o comando novamente para atualizar.' \
	'' \
	'[alias]' \
	'	zz = !echo zz' >"$AF"
git config --global --add include.path "$AF"

"$SCRIPT" novo '!echo novo' >/dev/null
check "cria alias grava no arquivo incluído" \
	"!echo novo" "$(git config --file "$AF" alias.novo)"
check "cria alias não escreve a chave crua no ~/.gitconfig" \
	"" "$(grep -F 'novo' "$GIT_CONFIG_GLOBAL" || true)"
check "cria alias no arquivo incluído: mensagem cita o arquivo" \
	"Alias 'outro' gravado em $AF." "$("$SCRIPT" outro '!echo outro')"

check "arquivo incluído fica em ordem alfabética" \
	"novo outro zz" \
	"$(git config --file "$AF" --get-regexp '^alias\.' | cut -d. -f2- | cut -d' ' -f1 | paste -sd' ' -)"
check "cabeçalho preservado após gravar" \
	"# Gerado por: git alias --export" "$(head -n1 "$AF")"

check "--unset remove do arquivo incluído" \
	"Alias 'novo' removido com sucesso!" "$("$SCRIPT" --unset novo)"
check "--unset: alias sai do arquivo incluído" \
	"" "$(git config --file "$AF" alias.novo 2>/dev/null || true)"
check "--unset: arquivo incluído segue ordenado e com cabeçalho" \
	"# Gerado por: git alias --export|outro zz" \
	"$(head -n1 "$AF")|$(git config --file "$AF" --get-regexp '^alias\.' | cut -d. -f2- | cut -d' ' -f1 | paste -sd' ' -)"

git config --file "$AF" alias.dupe '!echo do-arquivo'
git config --global alias.dupe '!echo do-global'
"$SCRIPT" --unset dupe >/dev/null
check "--unset remove a cópia do arquivo e a do --global" \
	"|" "$(git config --file "$AF" alias.dupe 2>/dev/null || true)|$(git config --file "$GIT_CONFIG_GLOBAL" alias.dupe 2>/dev/null || true)"

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
