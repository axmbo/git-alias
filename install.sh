#!/usr/bin/env sh
# Liga os dois mecanismos que fazem os dotfiles entrarem em vigor:
#   1. include.path  -> carrega git/aliases.gitconfig no ~/.gitconfig global
#   2. PATH          -> expõe git/bin para o Git achar o subcomando "git alias"
# Idempotente: pode rodar quantas vezes quiser.

set -eu

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"
ALIASES_FILE="$DOTFILES_DIR/git/aliases.gitconfig"
BIN_DIR="$DOTFILES_DIR/git/bin"
COMPLETIONS_DIR="$DOTFILES_DIR/completions"

# 1. include.path
if git config --global --get-all include.path 2>/dev/null | grep -qxF "$ALIASES_FILE"; then
	echo "ok: include.path já aponta para $ALIASES_FILE"
else
	git config --global --add include.path "$ALIASES_FILE"
	echo "add: include.path -> $ALIASES_FILE"
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
	echo "          sobre git/bin/git-alias. Remova com:"
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
