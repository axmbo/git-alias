#!/usr/bin/env sh
# Checagem estática dos workflows de .github/workflows/ que carregam lógica
# não-trivial em github-script. Hoje: exclusive-scoped-labels.yml.
#
# Sem harness de GitHub Actions: trava as invariantes que uma review humana
# deixa passar batido por serem string dentro de YAML — bloco de permissões
# presente e mínimo, action pinada em SHA (não tag flutuante @vN), nada de
# `concurrency:` (a fila de profundidade 1 do Actions descartava eventos do
# meio de um burst), e a forma do `script:` conforme o ADR-0005: SÓ impõe
# exclusividade (reconcilia por `listLabelsOnIssue`, não enumera as labels
# do repo, não cria label).
#
# É checagem de FORMA, não de sintaxe nem de comportamento — o corpo do
# `script:` só é grepado, não executado (issue #17 tira o JS de dentro do
# YAML). É o próprio artefato entregue, então checa também que o
# discriminador discrimina (um token inexistente NÃO é encontrado).
# Determinístico: só shell POSIX, grep e awk.

set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WF="$ROOT/.github/workflows/exclusive-scoped-labels.yml"
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
check "não enumera as labels do repo" \
	"nao" "$(yn grep -Fq 'listLabelsForRepo' "$WF")"
check "não cria label" \
	"nao" "$(yn grep -Fq 'createLabel' "$WF")"

# --- forma do corpo do script: as funções top-level esperadas ------
# Não é validação de sintaxe (isso é a issue #17, que tira o JS de dentro
# do YAML); só pega um script gutado/truncado — começo, meio e fim.
check "o script lê a label do gatilho" \
	"sim" "$(yn grep -Fq 'const newLabel = context.payload.label.name' "$WF")"
check "o script define currentLabelNames()" \
	"sim" "$(yn grep -Fq 'async function currentLabelNames' "$WF")"
check "o script define removeLabelIfPresent()" \
	"sim" "$(yn grep -Fq 'async function removeLabelIfPresent' "$WF")"

# --- o discriminador de fato discrimina ---------------------------
check "controle: token inexistente não é encontrado" \
	"nao" "$(yn grep -Fq 'zzz-nao-existe-no-workflow' "$WF")"

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
