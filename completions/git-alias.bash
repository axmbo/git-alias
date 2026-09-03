# shellcheck shell=bash
# bash completion para o subcomando "git alias" (git/bin/git-alias).
#
# NÃO é um script source-ável genérico. A completion do próprio Git
# (git-completion.bash, que acompanha o Git) despacha "git alias …" para uma
# função shell chamada _git_alias; ao não encontrá-la, o dynamic loader do
# bash-completion carrega este arquivo (instalado como "git-alias" no
# diretório de completions do usuário) e passa a encontrá-la. Dentro de
# _git_alias, o git-completion.bash já deixou no escopo do chamador as
# variáveis cur/prev/cword/words e os helpers __gitcomp/__gitcomp_nl/_filedir.

# Nomes de alias já definidos, um por linha — mesma fonte que alias_names()
# em git/bin/git-alias: chaves alias.* do config mesclado, sem o dispatcher
# "alias.alias". "--name-only" exige git >= 2.9 (já é dependência do script).
# Usa o wrapper __git do git-completion.bash (não "git" puro) para respeitar
# -C / --git-dir da linha de comando.
__git_alias_names ()
{
	__git config --name-only --get-regexp '^alias\.' 2>/dev/null \
		| sed -e 's/^alias\.//' -e '/^alias$/d' | sort -u
}

# shellcheck disable=SC2154  # cur/cword/words são preenchidas pelo git-completion.bash no escopo do chamador
_git_alias ()
{
	# Índice de "alias" em words[]: o git-completion.bash o exporta em
	# __git_cmd_idx (as funções nativas, _git_checkout/_git_stash…, usam-no).
	# Sem ele (git < ~2.30), 1 é o palpite certo para "git alias" sem opção
	# global antes do subcomando — o caso comum.
	local cmd_i="${__git_cmd_idx:-1}"
	local c=$((cmd_i + 1)) subcmd=''

	# Primeiro token conhecido depois de "git alias": o subcomando em vigor.
	while [ "$c" -lt "$cword" ]; do
		case "${words[c]}" in
		help | --version | -v | --list | --export | --import | --unset | --rename | --doctor)
			subcmd="${words[c]}"
			break
			;;
		esac
		c=$((c + 1))
	done

	case "$subcmd" in
	--list)
		__gitcomp "--file --origin -o"
		return
		;;
	--import)
		case "$cur" in
		--*)
			__gitcomp "--overwrite --dry-run"
			;;
		*)
			# <arquivo> é único (as flags podem vir antes ou depois dele);
			# só ofereça um nome se nenhum não-flag foi dado ainda.
			local i=$((c + 1)) got_file=0
			while [ "$i" -lt "$cword" ]; do
				case "${words[i]}" in
				--*) ;;             # flag (--overwrite/--dry-run)
				*) got_file=1 ;;    # <arquivo> — inclui "-" (stdin)
				esac
				i=$((i + 1))
			done
			[ "$got_file" -eq 0 ] && _filedir
			;;
		esac
		return
		;;
	--export)
		# --export aceita no máximo um <arquivo>.
		if [ "$((cword - c))" -eq 1 ]; then
			_filedir
		fi
		return
		;;
	--unset | --rename)
		# Só o 1º argumento (<nome> / <velho>) é um alias existente. O 2º
		# argumento é nome novo em --rename (<novo>) e não existe em --unset
		# (o script recusa "--unset a b") — nada a completar depois do 1º.
		if [ "$((cword - c))" -eq 1 ]; then
			__gitcomp_nl "$(__git_alias_names)"
		fi
		return
		;;
	help | --version | -v | --doctor)
		return
		;;
	esac

	# Nenhum subcomando reconhecido ainda. Na 1ª posição, ofereça os
	# subcomandos + os nomes de alias (para "git alias <nome>" e
	# "git alias <nome> '<cmd>'"). Depois disso ("git alias <nome> <TAB>") o
	# argumento é o corpo do alias, texto livre — nada a completar.
	# Lista única separada por newline via __gitcomp_nl: um nome de subseção
	# ([alias "a b"]) não é quebrado em dois candidatos, como seria num
	# __gitcomp separado por espaço.
	if [ "$cword" -eq "$((cmd_i + 1))" ]; then
		__gitcomp_nl "$(
			printf '%s\n' help --version -v --list --export --import --unset --rename --doctor
			__git_alias_names
		)"
	fi
}
