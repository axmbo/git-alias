#!/usr/bin/env sh
# Testes do install.sh: detecção de um arquivo de aliases já versionado e
# derivação do alvo XDG quando nenhum é detectado (README "Instalação").
# Cada teste roda num HOME/git-config/XDG_CONFIG_HOME temporários — não
# altera seu ambiente. Não cobre PATH/completions (comportamento inalterado
# por este passo; já implícito nos testes manuais do install.sh).

set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL="$ROOT/install.sh"
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

# Roda o install.sh num sandbox isolado <home> ($1), com XDG_CONFIG_HOME
# próprio, e ecoa "exit=<st>\n<stdout+stderr>". Isola HOME, o config global
# (real e via fallback XDG) e GIT_CEILING_DIRECTORIES do ambiente real —
# mesmo cuidado de tests/git-alias.sh.
run_install() { # <home>
	ri_home="$1"
	mkdir -p "$ri_home/.config"
	(
		HOME="$ri_home"
		export HOME
		GIT_CONFIG_GLOBAL="$ri_home/.gitconfig"
		export GIT_CONFIG_GLOBAL
		GIT_CONFIG_SYSTEM=/dev/null
		export GIT_CONFIG_SYSTEM
		GIT_CEILING_DIRECTORIES="$ri_home"
		export GIT_CEILING_DIRECTORIES
		XDG_CONFIG_HOME="$ri_home/.config"
		export XDG_CONFIG_HOME
		XDG_DATA_HOME="$ri_home/.local/share"
		export XDG_DATA_HOME
		cd "$ri_home"
		git config --global user.email t@t
		git config --global user.name t
		st=0
		out="$("$INSTALL" 2>&1)" || st=$?
		printf 'exit=%s\n%s' "$st" "$out"
	)
}

XDG_ALIASES_REL=".config/git/aliases.gitconfig"

# --- 1. nenhum arquivo de aliases detectado: cria o alvo XDG -------------
H1="$SB/fresh"
mkdir -p "$H1"
R1="$(run_install "$H1")"
check "install.sh (sem arquivo detectado): exit 0" \
	"exit=0" "$(printf '%s\n' "$R1" | head -n1)"
check "install.sh (sem arquivo detectado): cria o arquivo de aliases no XDG" \
	"sim" "$([ -f "$H1/$XDG_ALIASES_REL" ] && echo sim || echo nao)"
check "install.sh (sem arquivo detectado): arquivo criado tem o cabeçalho" \
	"sim" "$(head -n 3 "$H1/$XDG_ALIASES_REL" 2>/dev/null | grep -qF '# Gerado por: git alias --export' && echo sim || echo nao)"
check "install.sh (sem arquivo detectado): include.path aponta para o XDG" \
	"sim" "$(git config --file "$H1/.gitconfig" --get-all include.path 2>/dev/null | grep -qxF "$H1/$XDG_ALIASES_REL" && echo sim || echo nao)"
check "install.sh (sem arquivo detectado): stdout relata o 'add'" \
	"sim" "$(printf '%s\n' "$R1" | grep -q '^add: include.path' && echo sim || echo nao)"

# --- 2. idempotência: rodar de novo não duplica include.path -------------
R2="$(run_install "$H1")"
check "install.sh (2ª execução): exit 0" \
	"exit=0" "$(printf '%s\n' "$R2" | head -n1)"
check "install.sh (2ª execução): stdout relata 'ok', não 'add'" \
	"sim" "$(printf '%s\n' "$R2" | grep -q '^ok: include.path' && echo sim || echo nao)"
check "install.sh (2ª execução): include.path continua com uma única entrada" \
	"1" "$(git config --file "$H1/.gitconfig" --get-all include.path 2>/dev/null | grep -cxF "$H1/$XDG_ALIASES_REL")"

# --- 3. já há um arquivo de aliases detectado em OUTRO caminho: não cria
#        um segundo no XDG -------------------------------------------------
H3="$SB/custom"
mkdir -p "$H3"
CUSTOM_AF="$H3/meus-aliases.gitconfig"
printf '%s\n' \
	'# Gerado por: git alias --export' \
	'# Nao edite a mao; rode o comando novamente para atualizar.' \
	'# Formato: 1' \
	'' \
	'[alias]' \
	'	co = checkout' >"$CUSTOM_AF"
(
	HOME="$H3"
	export HOME
	GIT_CONFIG_GLOBAL="$H3/.gitconfig"
	export GIT_CONFIG_GLOBAL
	GIT_CONFIG_SYSTEM=/dev/null
	export GIT_CONFIG_SYSTEM
	git config --global user.email t@t
	git config --global user.name t
	git config --global --add include.path "$CUSTOM_AF"
)
R3="$(run_install "$H3")"
check "install.sh (arquivo já detectado em outro caminho): exit 0" \
	"exit=0" "$(printf '%s\n' "$R3" | head -n1)"
check "install.sh (arquivo já detectado em outro caminho): não cria o XDG" \
	"nao" "$([ -e "$H3/$XDG_ALIASES_REL" ] && echo sim || echo nao)"
check "install.sh (arquivo já detectado em outro caminho): include.path continua com uma única entrada" \
	"1" "$(git config --file "$H3/.gitconfig" --get-all include.path 2>/dev/null | grep -c .)"
check "install.sh (arquivo já detectado em outro caminho): stdout relata 'ok'" \
	"sim" "$(printf '%s\n' "$R3" | grep -q '^ok: ' && echo sim || echo nao)"

# --- 4. sem arquivo detectado, mas com aliases já no --global: o XDG nasce
#        semeado do que já existe (--export lê o config mesclado) ---------
H4="$SB/seeded"
mkdir -p "$H4"
(
	HOME="$H4"
	export HOME
	GIT_CONFIG_GLOBAL="$H4/.gitconfig"
	export GIT_CONFIG_GLOBAL
	GIT_CONFIG_SYSTEM=/dev/null
	export GIT_CONFIG_SYSTEM
	git config --global user.email t@t
	git config --global user.name t
	git config --global alias.co checkout
)
run_install "$H4" >/dev/null
check "install.sh (semeado do --global): o alias pré-existente entra no arquivo criado" \
	"checkout" "$(git config --file "$H4/$XDG_ALIASES_REL" --get alias.co 2>/dev/null || true)"

# --- 5. mensagem de PATH cita bin/, não git/bin ---------------------------
H5="$SB/pathmsg"
mkdir -p "$H5"
R5="$(PATH=/usr/bin:/bin run_install "$H5")"
# O '$PATH' abaixo é literal de propósito (grep -F): a mensagem impressa
# pelo install.sh traz "$PATH" sem expandir (heredoc/echo com \$), e é
# exatamente esse literal que o teste procura.
# shellcheck disable=SC2016
check "install.sh: mensagem de PATH cita .../bin, não git/bin" \
	"sim" "$(printf '%s\n' "$R5" | grep -F 'export PATH=' | grep -qF '/bin:$PATH' && echo sim || echo nao)"
check "install.sh: mensagem de PATH não cita git/bin" \
	"nao" "$(printf '%s\n' "$R5" | grep -qF 'git/bin' && echo sim || echo nao)"

# --- 6. entrada de include.path órfã (aponta para um arquivo que não
#        existe mais — ex.: upgrade do layout antigo git/aliases.gitconfig
#        após um reclone/pull): avisa, não perde os aliases em silêncio,
#        cria o alvo XDG normalmente e NÃO mexe na entrada órfã -----------
H6="$SB/stale"
mkdir -p "$H6"
STALE_TOKEN="$H6/git/aliases.gitconfig"
(
	HOME="$H6"
	export HOME
	GIT_CONFIG_GLOBAL="$H6/.gitconfig"
	export GIT_CONFIG_GLOBAL
	GIT_CONFIG_SYSTEM=/dev/null
	export GIT_CONFIG_SYSTEM
	git config --global user.email t@t
	git config --global user.name t
	git config --global --add include.path "$STALE_TOKEN"
)
R6="$(run_install "$H6")"
check "install.sh (entrada órfã no include.path): exit 0" \
	"exit=0" "$(printf '%s\n' "$R6" | head -n1)"
check "install.sh (entrada órfã no include.path): avisa sobre a entrada órfã" \
	"sim" "$(printf '%s\n' "$R6" | grep -q "PENDENTE.*$STALE_TOKEN" && echo sim || echo nao)"
check "install.sh (entrada órfã no include.path): ainda assim cria o alvo XDG" \
	"sim" "$([ -f "$H6/$XDG_ALIASES_REL" ] && echo sim || echo nao)"
check "install.sh (entrada órfã no include.path): entrada órfã não foi removida" \
	"sim" "$(git config --file "$H6/.gitconfig" --get-all include.path 2>/dev/null | grep -qxF "$STALE_TOKEN" && echo sim || echo nao)"
check "install.sh (entrada órfã no include.path): alvo XDG também foi adicionado" \
	"sim" "$(git config --file "$H6/.gitconfig" --get-all include.path 2>/dev/null | grep -qxF "$H6/$XDG_ALIASES_REL" && echo sim || echo nao)"

# --- 7. já existe um arquivo (sem o cabeçalho) no caminho padrão do XDG:
#        não sobrescreve, não inclui no include.path, só avisa -----------
H7="$SB/headerless"
mkdir -p "$H7/.config/git"
HEADERLESS="$H7/.config/git/aliases.gitconfig"
printf 'conteudo alheio, sem o cabeçalho\n' >"$HEADERLESS"
R7="$(run_install "$H7")"
check "install.sh (arquivo sem cabeçalho no caminho padrão): exit 0" \
	"exit=0" "$(printf '%s\n' "$R7" | head -n1)"
check "install.sh (arquivo sem cabeçalho no caminho padrão): não sobrescreve o conteúdo" \
	"conteudo alheio, sem o cabeçalho" "$(cat "$HEADERLESS")"
check "install.sh (arquivo sem cabeçalho no caminho padrão): não entra no include.path" \
	"nao" "$(git config --file "$H7/.gitconfig" --get-all include.path 2>/dev/null | grep -qxF "$HEADERLESS" && echo sim || echo nao)"
check "install.sh (arquivo sem cabeçalho no caminho padrão): avisa" \
	"sim" "$(printf '%s\n' "$R7" | grep -q "PENDENTE.*$HEADERLESS" && echo sim || echo nao)"

# --- 8. a entrada PADRÃO já está no include.path mas o arquivo dela
#        sumiu (ex.: alvo XDG apagado à mão depois de instalado): não
#        duplica a entrada, só avisa — não tenta recriar por conta própria
H8="$SB/defaultgone"
mkdir -p "$H8"
run_install "$H8" >/dev/null
rm -f "$H8/$XDG_ALIASES_REL"
R8="$(run_install "$H8")"
check "install.sh (alvo padrão sumiu, entrada permanece): exit 0" \
	"exit=0" "$(printf '%s\n' "$R8" | head -n1)"
check "install.sh (alvo padrão sumiu, entrada permanece): não duplica a entrada" \
	"1" "$(git config --file "$H8/.gitconfig" --get-all include.path 2>/dev/null | grep -cxF "$H8/$XDG_ALIASES_REL")"
check "install.sh (alvo padrão sumiu, entrada permanece): avisa, sem recriar o arquivo sozinho" \
	"nao" "$([ -f "$H8/$XDG_ALIASES_REL" ] && echo sim || echo nao)"

# --- 9. symlink quebrado no caminho padrão do XDG: não tenta exportar por
#        cima (o que abortaria o script), cai no mesmo aviso de "sem
#        cabeçalho" em vez de estourar um erro cru de mktemp/git config ---
H9="$SB/deadlink"
mkdir -p "$H9/.config/git"
ln -s "$H9/.config/git/alvo-que-nao-existe" "$H9/$XDG_ALIASES_REL"
R9="$(run_install "$H9")"
check "install.sh (symlink quebrado no caminho padrão): exit 0, não aborta" \
	"exit=0" "$(printf '%s\n' "$R9" | head -n1)"
check "install.sh (symlink quebrado no caminho padrão): não entra no include.path" \
	"nao" "$(git config --file "$H9/.gitconfig" --get-all include.path 2>/dev/null | grep -qxF "$H9/$XDG_ALIASES_REL" && echo sim || echo nao)"
check "install.sh (symlink quebrado no caminho padrão): avisa" \
	"sim" "$(printf '%s\n' "$R9" | grep -q "PENDENTE.*$H9/$XDG_ALIASES_REL" && echo sim || echo nao)"

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
