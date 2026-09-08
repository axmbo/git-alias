#!/usr/bin/env sh
# Checagem estática dos workflows de .github/workflows/ que carregam lógica
# não-trivial em github-script. Hoje: exclusive-scoped-labels.yml.
#
# Sem harness de GitHub Actions: trava as invariantes que uma review humana
# deixa passar batido por serem string dentro de YAML — bloco de permissões
# presente e mínimo, action pinada em SHA (não tag flutuante @vN), e o corpo
# do `script:` sem erro de sintaxe JS (via `node --check`, quando o node
# está instalado). Também fixa a decisão do ADR-0005: o workflow SÓ impõe
# exclusividade — reconcilia pelo estado atual da issue (listLabelsOnIssue),
# não enumera as labels do repo, não cria label — e nada de `concurrency:`
# (a fila de profundidade 1 do Actions descartava eventos do meio de um
# burst).
#
# É o próprio artefato entregue, então checa também que o discriminador
# discrimina (um token inexistente NÃO é encontrado). A cobertura de
# comportamento fica para a issue #17.
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

# --- existência ----------------------------------------------------------
check ".github/workflows/exclusive-scoped-labels.yml existe" \
	"sim" "$(yn test -f "$WF")"

# --- permissões: deny-all no topo, issues:write só no job -------------
check "declara 'permissions: {}' no topo (deny-all)" \
	"sim" "$(yn grep -Eq '^permissions:[[:space:]]*\{\}[[:space:]]*$' "$WF")"
issues_re="^[[:space:]]+issues:[[:space:]]+['\"]?write['\"]?[[:space:]]*$"
check "o job pede 'issues: write'" "sim" "$(yn grep -Eq "$issues_re" "$WF")"
# Robusto a forma: extrai só as regiões `permissions:` (a linha + o bloco
# mais indentado que a segue), normaliza aspas/comentário, e varre
# `<escopo>: write|read` / `write-all` / `read-all` — cobre bloco, escalar
# e flow-mapping. A única concessão aceitável é `issues: write`; qualquer
# outra (inclusive um `contents: read`) reprova, forçando decisão
# consciente. Escopar evita falso-FAIL por um `x: write` no `script:`.
perm_region=$(awk '
	/^[[:space:]]*permissions:/ { print; ind = match($0, /[^[:space:]]/); inb = 1; next }
	inb && /^[[:space:]]*$/ { next }
	inb && match($0, /[^[:space:]]/) > ind { print; next }
	inb { inb = 0 }
' "$WF")
perm_bad=$(printf '%s\n' "$perm_region" | sed 's/#.*//' | tr -d "\"'" |
	grep -oE '[a-z_-]+:[[:space:]]*(write|read)|write-all|read-all' |
	grep -cvE '^issues:[[:space:]]*write$' || true)
check "nenhuma concessão de permissão além de 'issues: write'" "0" "$perm_bad"

# --- supply chain: todo `uses:` remoto pinado em SHA de 40 hex --------
# Pega `@main`, `@master`, `@v7`, `@1.2.3` — qualquer ref que não seja 40
# hex. Local (`./…`) e docker (`docker://…`) não se aplicam. Aspas YAML
# opcionais.
unpinned=$(
	grep -E "^[[:space:]]*-?[[:space:]]*uses:[[:space:]]" "$WF" |
		grep -vE \
			-e "uses:[[:space:]]+['\"]?(\\./|docker://)" \
			-e "uses:[[:space:]]+['\"]?[^@[:space:]'\"]+@[0-9a-f]{40}['\"]?([[:space:]#]|\$)" |
		grep -c . || true
)
check "todo 'uses:' remoto pinado em SHA de 40 hex" "0" "$unpinned"

# --- concorrência: NÃO reintroduzir 'concurrency:' -----------------
# A fila de profundidade 1 do Actions descarta eventos do meio de um burst
# de labels (review #16); a reconciliação por estado atual dispensa
# serialização. Pega em qualquer nível (topo ou job) e com qualquer valor
# (vazio, `{}` ou escalar inline) — não só a chave solta no topo.
check "não reintroduz 'concurrency:'" \
	"nao" "$(yn grep -Eq '^[[:space:]]*concurrency:' "$WF")"

# --- só impõe exclusividade (ADR-0005) -------------------------------
check "reconcilia pelo estado atual da issue (listLabelsOnIssue)" \
	"sim" "$(yn grep -Fq 'listLabelsOnIssue' "$WF")"
check "não enumera as labels do repo (não reintroduz typo-fix)" \
	"nao" "$(yn grep -Fq 'listLabelsForRepo' "$WF")"
check "não cria label (não reintroduz createLabel)" \
	"nao" "$(yn grep -Fq 'createLabel' "$WF")"

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
		awk 'f && $0 != "" && $0 !~ /^            / { f = 0 }
		     f { sub(/^            /, ""); print; next }
		     /script: \|[-+]?[[:space:]]*$/ { f = 1 }' "$WF"
		echo '})'
	} >"$tmp"
	# Guarda: se a extração falhar (o bloco `script:` mudar de forma), o
	# corpo sai vazio/truncado e o `node --check` passaria em vácuo. Exige
	# um sentinela no começo E um no fim (a última função do script), então
	# um corte no meio é pego.
	check "extração do corpo do script: pegou o começo (sentinela newLabel)" \
		"sim" "$(yn grep -Fq 'const newLabel = context.payload.label.name' "$tmp")"
	check "extração do corpo do script: pegou até o fim (sentinela removeLabelIfPresent)" \
		"sim" "$(yn grep -Fq 'function removeLabelIfPresent' "$tmp")"
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
