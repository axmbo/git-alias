#!/usr/bin/env sh
# Liga os mecanismos que fazem o git-alias entrar em vigor:
#   1. include.path  -> garante um arquivo de aliases versionado no ~/.gitconfig global
#   2. PATH          -> expõe bin/ para o Git achar o subcomando "git alias"
# Idempotente: pode rodar quantas vezes quiser.

set -eu

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="$REPO_DIR/bin"
COMPLETIONS_DIR="$REPO_DIR/completions"

# Alvo do include.path quando NENHUM arquivo de aliases é detectado (ponto
# 1 abaixo): fora do clone, de propósito — sobrevive a um reclone/git pull
# da ferramenta, no espírito do layout XDG.
DEFAULT_ALIASES_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/git/aliases.gitconfig"

# Resolve um token de include.path como o Git faz para a camada --global —
# mesma regra de resolve_include_token em bin/git-alias, duplicada aqui de
# propósito: install.sh precisa funcionar mesmo antes de bin/ estar no
# PATH (ponto 2), então não pode chamar "git alias" para isso.
resolve_include_token() {
	# Os "~" abaixo são patterns de case (casam o literal que o git grava em
	# include.path), não tentativas de expandir til — a expansão para $HOME
	# é feita à mão no corpo do ramo. Mesma nota de bin/git-alias.
	# shellcheck disable=SC2088
	case "$1" in
	/*) printf '%s\n' "$1" ;;
	'~') printf '%s\n' "$HOME" ;;
	'~/'*) printf '%s\n' "$HOME/${1#'~/'}" ;;
	*) printf '%s\n' "$HOME/$1" ;;
	esac
}

# Ecoa o primeiro arquivo já detectado no include.path do --global (mesmo
# critério de bin/git-alias: cabeçalho "# Gerado por: git alias --export"
# nas 3 primeiras linhas — MESMA checagem, sem "2>/dev/null" no head, para
# não divergir do comportamento de alias_file() lá), ou nada se nenhum
# casar. Não confundir com um arquivo qualquer no caminho padrão — só conta
# o que o include.path realmente referencia.
detect_aliases_file() {
	git config --global --get-all include.path 2>/dev/null \
		| while IFS= read -r tok; do
			p="$(resolve_include_token "$tok")"
			[ -f "$p" ] || continue
			if head -n 3 "$p" | grep -qF '# Gerado por: git alias --export'; then
				printf '%s\n' "$p"
				break
			fi
		done
	return 0
}

# Avisa (não corrige — o Git ignora em silêncio uma entrada de include.path
# que não resolve a um arquivo, e este script não decide sozinho remover a
# entrada de outra pessoa nem afirma a causa) sobre toda entrada de
# include.path que não resolve a um arquivo existente. Deliberadamente
# neutro sobre a causa: pode ser um include opcional legítimo sem relação
# nenhuma com o git-alias (ex.: um "~/.gitconfig.local" que só existe em
# algumas máquinas, de propósito), ou um arquivo de aliases que ficou para
# trás (reclone/pull moveu ou apagou o arquivo) — sem isto, o 2º caso fica
# mudo e o passo 1 abaixo criaria um arquivo NOVO (só com o que sobrevive
# no --global), perdendo em silêncio os aliases que só existiam no arquivo
# órfão. "git alias --doctor" já sabe diagnosticar essa entrada em detalhe;
# aponta para lá em vez de duplicar esse diagnóstico aqui.
warn_stale_include_entries() {
	git config --global --get-all include.path 2>/dev/null \
		| while IFS= read -r tok; do
			p="$(resolve_include_token "$tok")"
			[ -f "$p" ] && continue
			echo "PENDENTE: include.path tem uma entrada que não resolve a um arquivo existente: '$tok' (esperado em $p)."
			echo "          Pode ser um include opcional sem relação com o git-alias, ou um"
			echo "          arquivo de aliases que ficou para trás. Rode 'git alias --doctor'"
			echo "          para o diagnóstico completo dessa entrada."
		done
	return 0
}

# 1. include.path — não mexe se já há um arquivo de aliases detectado (em
#    QUALQUER caminho: outro reclone, um dotfiles pessoal que versiona o
#    seu, etc.); senão, cria um a partir do que você já tem no --global
#    (git alias --export) no caminho padrão e adiciona ao include.path — a
#    menos que esse caminho padrão já esteja listado (ainda que não
#    resolva agora: reexecutar não pode duplicar a entrada).
warn_stale_include_entries
DETECTED_ALIASES_FILE="$(detect_aliases_file)"
if [ -n "$DETECTED_ALIASES_FILE" ]; then
	echo "ok: include.path já aponta para um arquivo de aliases detectado — $DETECTED_ALIASES_FILE"
elif git config --global --get-all include.path 2>/dev/null | grep -qxF "$DEFAULT_ALIASES_FILE"; then
	echo "PENDENTE: include.path já tem a entrada padrão ($DEFAULT_ALIASES_FILE), mas ela"
	echo "          não resolve a um arquivo com o cabeçalho esperado agora (ver aviso"
	echo "          acima) — não adicionada de novo. Resolva a entrada antes de continuar."
else
	mkdir -p "$(dirname -- "$DEFAULT_ALIASES_FILE")"
	# "-e" sozinho trata um symlink quebrado como ausente e o "--export"
	# escreveria através dele; "-L" cobre esse caso também, caindo no ramo
	# "já existe, sem cabeçalho" abaixo em vez de tentar exportar por cima.
	if [ ! -e "$DEFAULT_ALIASES_FILE" ] && [ ! -L "$DEFAULT_ALIASES_FILE" ]; then
		"$BIN_DIR/git-alias" --export "$DEFAULT_ALIASES_FILE"
	fi
	# O "--export" acima só roda se o arquivo ainda não existisse (nem como
	# symlink quebrado); se já existia (de outra origem, ou um link morto)
	# mas sem o cabeçalho, não é seguro incluí-lo como se fosse o arquivo
	# versionado — recusa e avisa, em vez de gravar no include.path algo
	# que o próprio bin/git-alias nunca reconheceria de volta (alias_file()
	# usa o mesmo cabeçalho para detectar). "2>/dev/null" aqui cobre
	# justamente o symlink quebrado (sem equivalente em bin/git-alias: lá
	# alias_file() já filtra por "-f" antes de chamar head, então esse
	# caminho nunca é alcançado com um alvo inexistente).
	if head -n 3 "$DEFAULT_ALIASES_FILE" 2>/dev/null | grep -qF '# Gerado por: git alias --export'; then
		git config --global --add include.path "$DEFAULT_ALIASES_FILE"
		echo "add: include.path -> $DEFAULT_ALIASES_FILE"
	else
		echo "PENDENTE: $DEFAULT_ALIASES_FILE já existe, mas sem o cabeçalho de"
		echo "          'git alias --export'; não foi adicionado ao include.path."
		echo "          Mova-o ou rode 'git alias --export $DEFAULT_ALIASES_FILE' para"
		echo "          substituí-lo por um arquivo reconhecido."
	fi
fi

# 2. PATH (não editamos seu shell rc; só instruímos)
case ":${PATH}:" in
*":$BIN_DIR:"*)
	echo "ok: PATH já contém $BIN_DIR"
	;;
*)
	echo
	echo "PENDENTE: acrescente ao seu shell rc (~/.bashrc, ~/.zshrc) e reabra o shell:"
	echo
	echo "    export PATH=\"$BIN_DIR:\$PATH\""
	echo
	;;
esac

# 3. O alias inline antigo tem precedência sobre o script; avisa se ainda existe.
if git config --global --get alias.alias >/dev/null 2>&1; then
	echo "PENDENTE: 'alias.alias' ainda existe no git config e tem precedência"
	echo "          sobre bin/git-alias. Remova com:"
	echo
	echo "    git config --global --unset alias.alias"
	echo
fi

# 4. Completions de shell (bash e zsh). Symlink para os arquivos do repo, no
#    mesmo espírito de include.path/PATH: a árvore de trabalho continua sendo
#    a fonte da verdade. Idempotente; qualquer entrada pré-existente que não
#    seja exatamente o nosso symlink (arquivo regular OU symlink para outro
#    alvo) é deixada intacta, com um PENDENTE — nunca reposta em silêncio.
link_completion() { # <arquivo-fonte> <dir-destino> <nome-no-destino>
	lc_src="$1"
	lc_dir="$2"
	lc_dst="$2/$3"
	if [ -L "$lc_dst" ]; then
		lc_cur="$(readlink "$lc_dst")"
		if [ "$lc_cur" = "$lc_src" ]; then
			echo "ok: completion $3 já aponta para $lc_src"
			return 0
		fi
		echo "PENDENTE: $lc_dst já é um symlink para $lc_cur; não foi tocado."
		echo "          Remova-o e rode de novo para apontá-lo a $lc_src"
		return 0
	fi
	if [ -e "$lc_dst" ]; then
		echo "PENDENTE: $lc_dst já existe e não é um symlink; não foi tocado."
		echo "          Remova-o e rode de novo para apontá-lo a $lc_src"
		return 0
	fi
	mkdir -p "$lc_dir"
	ln -s "$lc_src" "$lc_dst"
	echo "add: completion $3 -> $lc_dst"
}

if command -v bash >/dev/null 2>&1; then
	# Diretório que o dynamic loader do bash-completion consulta ao completar
	# um comando pela primeira vez — nada a acrescentar ao ~/.bashrc.
	BASH_COMP_DIR="${BASH_COMPLETION_USER_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/bash-completion}/completions"
	link_completion "$COMPLETIONS_DIR/git-alias.bash" "$BASH_COMP_DIR" "git-alias"
fi

if command -v zsh >/dev/null 2>&1; then
	ZSH_FPATH_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/zsh/site-functions"
	link_completion "$COMPLETIONS_DIR/git-alias.zsh" "$ZSH_FPATH_DIR" "_git-alias"
	# Este script roda em sh e não enxerga o $fpath do zsh interativo; oriente
	# o usuário a incluir o diretório antes do compinit.
	case ":${FPATH:-}:" in
	*":$ZSH_FPATH_DIR:"*)
		echo "ok: \$fpath já contém $ZSH_FPATH_DIR"
		;;
	*)
		echo
		echo "PENDENTE (zsh): garanta que este diretório está no \$fpath ANTES do"
		echo "               'compinit', no seu ~/.zshrc, e reabra o shell:"
		echo
		echo "    fpath=(\"$ZSH_FPATH_DIR\" \$fpath)"
		echo
		;;
	esac
fi

echo "install.sh: concluído."
