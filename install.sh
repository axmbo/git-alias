#!/usr/bin/env sh
# Liga os dois mecanismos que fazem os dotfiles entrarem em vigor:
#   1. include.path  -> carrega git/aliases.gitconfig no ~/.gitconfig global
#   2. PATH          -> expõe git/bin para o Git achar o subcomando "git alias"
# Idempotente: pode rodar quantas vezes quiser.

set -eu

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"
ALIASES_FILE="$DOTFILES_DIR/git/aliases.gitconfig"
BIN_DIR="$DOTFILES_DIR/git/bin"

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

echo "install.sh: concluído."
