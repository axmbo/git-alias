#!/usr/bin/env sh
# Checagem estática dos workflows de .github/workflows/ que carregam lógica
# não-trivial em github-script. Hoje: exclusive-scoped-labels.yml.
#
# Sem harness de GitHub Actions: trava as invariantes que uma review humana
# deixa passar batido por serem string dentro de YAML — bloco de permissões
# presente e mínimo, action pinada em SHA (não tag flutuante @vN), e o corpo
# do `script:` sem erro de sintaxe JS (via `node --check`, quando o node
# está instalado). Também fixa decisões da review #16: sem
# KNOWN_EXCLUSIVE_GROUPS, exclusividade a partir de listLabelsForRepo,
# reconciliação pelo estado atual da issue (listLabelsOnIssue) e nada de
# `concurrency:` (a fila de profundidade 1 do Actions descartava eventos do
# meio de um burst de labels).
#
# É o próprio artefato entregue, então checa também que o discriminador
# discrimina (um token inexistente NÃO é encontrado). A cobertura de
# comportamento (typo, 404, ordem add-antes-de-remove) fica para a issue do
# Nível 2.
# Determinístico: só shell POSIX, grep e awk (node é opcional).

set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WF="$ROOT/.github/workflows/exclusive-scoped-labels.yml"
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

has() { # has <arquivo> <ere>: <ere> casa em <arquivo>?
	grep -Eq -- "$2" "$1"
}

# --- existência ----------------------------------------------------------
check ".github/workflows/exclusive-scoped-labels.yml existe" \
	"sim" "$(yn test -f "$WF")"

# --- permissões: deny-all no topo, issues:write só no job -------------
check "declara 'permissions: {}' no topo (deny-all)" \
	"sim" "$(yn has "$WF" '^permissions:[[:space:]]*\{\}[[:space:]]*$')"
check "o job pede 'issues: write'" \
	"sim" "$(yn has "$WF" '^[[:space:]]+issues:[[:space:]]+write[[:space:]]*$')"
# Genérico de propósito: qualquer chave `<escopo>: write` indentada cujo
# nome não seja `issues` reprova — não uma lista de escopos conhecidos, que
# esqueceria os que o GitHub criar depois (attestations, models, pages…).
if grep -E '^[[:space:]]+[a-z_-]+:[[:space:]]+write' "$WF" |
	grep -Evq '^[[:space:]]+issues:[[:space:]]+write[[:space:]]*$'; then
	outro_write=sim
else
	outro_write=nao
fi
check "não pede escrita de nenhum escopo além de 'issues'" "nao" "$outro_write"

# --- supply chain: action pinada em SHA, não tag flutuante -----------
check "actions/github-script pinada em SHA de 40 hex" \
	"sim" "$(yn has "$WF" 'uses:[[:space:]]+actions/github-script@[0-9a-f]{40}[[:space:]]+#')"
check "nenhum 'uses:' preso a tag flutuante @vN" \
	"nao" "$(yn grep -Eq 'uses:[[:space:]]+[^@[:space:]]+@v[0-9]+([.][0-9]+)*([[:space:]]|$)' "$WF")"

# --- concorrência: NÃO reintroduzir 'concurrency:' -----------------
# A fila de profundidade 1 do Actions descarta eventos do meio de um burst
# de labels (review #16); a reconciliação por estado atual dispensa
# serialização. Pega em qualquer nível (topo ou job) e com qualquer valor
# (vazio, `{}` ou escalar inline) — não só a chave solta no topo.
check "não reintroduz 'concurrency:'" \
	"nao" "$(yn grep -Eq '^[[:space:]]*concurrency:' "$WF")"

# --- redesenho da exclusividade (review #16) --------------------------
check "exclusividade vem das labels do repo (listLabelsForRepo)" \
	"sim" "$(yn grep -Fq 'listLabelsForRepo' "$WF")"
check "reconcilia pelo estado atual da issue (listLabelsOnIssue)" \
	"sim" "$(yn grep -Fq 'listLabelsOnIssue' "$WF")"
check "não sobrou a lista fixa KNOWN_EXCLUSIVE_GROUPS" \
	"nao" "$(yn grep -Fq 'KNOWN_EXCLUSIVE_GROUPS' "$WF")"

# --- sintaxe do corpo do script: (best effort: só com node) --------
# github-script roda o corpo dentro de uma async function; para o
# `node --check` refletir isso, envolve igual antes de checar.
if command -v node >/dev/null 2>&1; then
	# Nome com sufixo .js: o `node --check` recente deduz o formato do
	# módulo pela extensão e recusa um nome sem extensão conhecida.
	tmpd="$(mktemp -d)"
	trap 'rm -rf "$tmpd"' EXIT
	tmp="$tmpd/script.js"
	{
		echo '(async () => {'
		awk 'f { sub(/^            /, ""); print; next }
		     /script: \|[-+]?[[:space:]]*$/ { f = 1 }' "$WF"
		echo '})'
	} >"$tmp"
	# Guarda: se a extração falhar (o bloco `script:` mudar de forma), o
	# corpo sai vazio e o `node --check` passaria em vácuo. Exige um
	# sentinela que tem de estar no script.
	check "extração do corpo do script: pegou algo (sentinela enforceExclusive)" \
		"sim" "$(yn grep -Fq 'enforceExclusive' "$tmp")"
	st=0
	node --check "$tmp" 2>/dev/null || st=$?
	check "node --check no corpo do script: sem erro de sintaxe" "0" "$st"
else
	skip=$((skip + 1))
	echo "skip - node não encontrado; pulando 'node --check' do script"
fi

# --- o discriminador de fato discrimina ---------------------------
check "controle: token inexistente não é encontrado" \
	"nao" "$(yn grep -Fq 'zzz-nao-existe-no-workflow' "$WF")"

echo
echo "pass=$pass fail=$fail skip=$skip"
[ "$fail" -eq 0 ]
