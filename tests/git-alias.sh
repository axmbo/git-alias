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
# Impede que o "git describe" novo (usado por --version) escape do sandbox e
# encontre um repositório real acima de /tmp.
export GIT_CEILING_DIRECTORIES="$SB"
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

check "--unset sem arquivo incluído: remove do --global com aviso" \
	"Alias 'foo' removido do git config --global (nenhum arquivo de aliases incluído encontrado)." \
	"$("$SCRIPT" --unset foo)"
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

# --- valor de alias multilinha não corrompe --export --------------------
git config --global alias.mlfunc "$(printf '!f() {\n  git push\n}\nf')"
MLX="$SB/ml.gitconfig"
"$SCRIPT" --export "$MLX" 2>/dev/null || true
check "--export com alias multilinha: não aborta, gera o arquivo" \
	"sim" "$([ -s "$MLX" ] && echo sim || echo nao)"
check "--export com alias multilinha: valor preservado no round-trip" \
	"$(git config --get alias.mlfunc)" \
	"$(git config --file "$MLX" --get alias.mlfunc 2>/dev/null || true)"
check "--export com alias multilinha: sem alias bogus a partir do corpo" \
	"co gone mlfunc" \
	"$(git config --file "$MLX" --name-only --get-regexp '^alias\.' 2>/dev/null | sed 's/^alias\.//' | LC_ALL=C sort | paste -sd' ' -)"
git config --global --unset alias.mlfunc

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

# cria alias que já tinha cópia obsoleta no --global (usuário vindo da versão
# anterior do script, que sempre gravava lá): a cópia órfã é removida.
git config --global alias.comshadow '!echo antigo-global'
"$SCRIPT" comshadow '!echo do-arquivo' >/dev/null
check "cria alias: cópia obsoleta sai do ~/.gitconfig" \
	"" "$(git config --file "$GIT_CONFIG_GLOBAL" alias.comshadow 2>/dev/null || true)"
check "cria alias: valor efetivo passa a ser o do arquivo" \
	"!echo do-arquivo" "$(git config alias.comshadow)"
check "cria alias: mensagem avisa remoção da cópia obsoleta" \
	"Alias 'shadowmsg' gravado em $AF (cópia obsoleta em git config --global removida)." \
	"$(git config --global alias.shadowmsg x; "$SCRIPT" shadowmsg '!echo z')"

check "--unset remove do arquivo incluído" \
	"Alias 'novo' removido de $AF." "$("$SCRIPT" --unset novo)"
check "--unset: alias sai do arquivo incluído" \
	"" "$(git config --file "$AF" alias.novo 2>/dev/null || true)"
check "--unset de alias só no --global, com arquivo incluído presente" \
	"Alias 'sonoglobal' removido do git config --global (não estava no arquivo de aliases)." \
	"$(git config --global alias.sonoglobal x; "$SCRIPT" --unset sonoglobal)"
check "--unset: arquivo incluído segue ordenado e com cabeçalho" \
	"# Gerado por: git alias --export|comshadow outro shadowmsg zz" \
	"$(head -n1 "$AF")|$(git config --file "$AF" --get-regexp '^alias\.' | cut -d. -f2- | cut -d' ' -f1 | paste -sd' ' -)"

git config --file "$AF" alias.dupe '!echo do-arquivo'
git config --global alias.dupe '!echo do-global'
check "--unset das duas cópias: mensagem cita arquivo e --global" \
	"Alias 'dupe' removido de $AF e do git config --global." "$("$SCRIPT" --unset dupe)"
check "--unset remove a cópia do arquivo e a do --global" \
	"|" "$(git config --file "$AF" alias.dupe 2>/dev/null || true)|$(git config --file "$GIT_CONFIG_GLOBAL" alias.dupe 2>/dev/null || true)"

mode_of() { stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"; }

# --- arquivo incluído comum: gravação preserva o modo do arquivo ---------
PLAIN="$SB/plain-aliases.gitconfig"
printf '%s\n' '# Gerado por: git alias --export' '# x' '' '[alias]' >"$PLAIN"
chmod 0644 "$PLAIN"
git config --global --unset-all include.path
git config --global --add include.path "$PLAIN"
"$SCRIPT" viaplain '!echo p' >/dev/null
check "gravação em arquivo comum preserva o modo 0644" \
	"644" "$(mode_of "$PLAIN")"

# --- destino do include.path é uma cadeia de symlinks (layout de dotfiles) --
mkdir -p "$SB/real"
REAL="$SB/real/aliases.gitconfig"
printf '%s\n' \
	'# Gerado por: git alias --export' \
	'# Nao edite a mao; rode o comando novamente para atualizar.' \
	'' \
	'[alias]' >"$REAL"
chmod 0644 "$REAL"
LINK="$SB/linked-aliases.gitconfig"
LINK2="$SB/linked2-aliases.gitconfig"
ln -s "$REAL" "$LINK"
ln -s "$LINK" "$LINK2"
git config --global --unset-all include.path
git config --global --add include.path "$LINK2"

"$SCRIPT" viasym '!echo sym' >/dev/null
check "gravação via cadeia de symlinks preserva o 1º link" \
	"symlink" "$([ -L "$LINK2" ] && echo symlink || echo regular)"
check "gravação via cadeia de symlinks preserva o 2º link" \
	"symlink" "$([ -L "$LINK" ] && echo symlink || echo regular)"
check "gravação chega no arquivo real ao fim da cadeia" \
	"!echo sym" "$(git config --file "$REAL" alias.viasym)"
check "gravação via symlink preserva o modo 0644 do arquivo real" \
	"644" "$(mode_of "$REAL")"
check "arquivo real segue com cabeçalho após gravar via symlink" \
	"# Gerado por: git alias --export" "$(head -n1 "$REAL")"
check "gravação via symlink não deixa temporário para trás" \
	"" "$(find "$SB" -name 'git-alias.*' 2>/dev/null)"

# --export para um alvo que é symlink: preserva o link e o modo do alvo
EXPLINK="$SB/exp-link.gitconfig"
EXPREAL="$SB/real/exp-real.gitconfig"
: >"$EXPREAL"
chmod 0644 "$EXPREAL"
ln -s "$EXPREAL" "$EXPLINK"
"$SCRIPT" --export "$EXPLINK" 2>/dev/null
check "--export para symlink preserva o link" \
	"symlink" "$([ -L "$EXPLINK" ] && echo symlink || echo regular)"
check "--export para symlink escreve no arquivo real" \
	"checkout" "$(git config --file "$EXPREAL" alias.co)"
check "--export para symlink preserva o modo 0644 do alvo" \
	"644" "$(mode_of "$EXPREAL")"

# --- include.path relativo (git o resolve contra o dir do ~/.gitconfig) --
mkdir -p "$SB/relat-dir"
RELF="$SB/relat-dir/aliases.gitconfig"
printf '%s\n' '# Gerado por: git alias --export' '# x' '' '[alias]' >"$RELF"
git config --global --unset-all include.path
git config --global --add include.path "relat-dir/aliases.gitconfig"
( cd "$SB/real" && "$SCRIPT" relat '!echo r' >/dev/null )
check "include.path relativo é detectado (grava no arquivo incluído)" \
	"!echo r" "$(git config --file "$RELF" alias.relat 2>/dev/null || true)"
check "include.path relativo: nada foi para o ~/.gitconfig cru" \
	"" "$(git config --file "$GIT_CONFIG_GLOBAL" alias.relat 2>/dev/null || true)"

# --- git alias --version / -v ------------------------------------------------
# Cópia do script fora de qualquer repositório git: exercita o caminho em que
# git describe não é fonte (só a constante VERSION é impressa).
mkdir -p "$SB/pathbin"
cp "$SCRIPT" "$SB/pathbin/git-alias"
chmod +x "$SB/pathbin/git-alias"
BARE="$("$SB/pathbin/git-alias" --version)"
check "--version fora de um checkout imprime só X.Y.Z" \
	"sim" "$(printf '%s' "$BARE" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' && echo sim || echo nao)"
check "-v é sinônimo de --version" \
	"$BARE" "$("$SB/pathbin/git-alias" -v)"

# Cópia num checkout git de mentira (hermético — não depende de como esta
# suíte foi obtida): --version anexa o "git describe" desse repo, verbatim.
# Tag no HEAD e árvore limpa => o describe é exatamente o nome da tag.
mkdir -p "$SB/checkout/git/bin"
cp "$SCRIPT" "$SB/checkout/git/bin/git-alias"
chmod +x "$SB/checkout/git/bin/git-alias"
(
	cd "$SB/checkout"
	git init -q .
	git add -A
	git commit -q -m v0
	git tag marco
) 2>/dev/null
check "--version de dentro de um checkout anexa o git describe" \
	"$BARE (marco)" "$("$SB/checkout/git/bin/git-alias" --version)"

# O Git NÃO intercepta "--version" de um subcomando externo (ao contrário de
# "--help", que ele desvia para a man page inexistente "git-alias"): com o
# script no PATH, "git alias --version" executa o próprio script. Guarda de
# regressão contra mudança de comportamento entre versões do Git.
VIA_GIT="$(PATH="$SB/pathbin:$PATH" git alias --version 2>&1 || true)"
check "git não intercepta --version de subcomando externo" \
	"$BARE" "${VIA_GIT%% (*}"

# --- marcador de formato no cabeçalho gerado (ADR-0003) --------------------
FMT="$SB/fmt.gitconfig"
"$SCRIPT" --export "$FMT" 2>/dev/null
check "cabeçalho gerado declara '# Formato: 1' na 3ª linha" \
	"# Formato: 1" "$(sed -n '3p' "$FMT")"
check "'# Formato: 1' cabe na janela de detecção (3 primeiras linhas)" \
	"# Formato: 1" "$(head -n 3 "$FMT" | grep -F '# Formato:')"

# Arquivo com o cabeçalho antigo (2 linhas) continua sendo detectado como
# incluído e ganha o marcador ao ser reescrito.
LEGACY="$SB/legacy.gitconfig"
printf '%s\n' \
	'# Gerado por: git alias --export' \
	'# Nao edite a mao; rode o comando novamente para atualizar.' \
	'' \
	'[alias]' >"$LEGACY"
git config --global --unset-all include.path
git config --global --add include.path "$LEGACY"
"$SCRIPT" legado '!echo l' >/dev/null
check "arquivo com cabeçalho antigo (2 linhas) ainda é detectado como incluído" \
	"!echo l" "$(git config --file "$LEGACY" alias.legado)"
check "arquivo com cabeçalho antigo ganha '# Formato: 1' ao ser reescrito" \
	"# Formato: 1" "$(sed -n '3p' "$LEGACY")"

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
