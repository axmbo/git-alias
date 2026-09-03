#compdef git-alias
# Completion de "git alias" para zsh.
#
# O _git nativo do zsh despacha "git alias <args>" para a função _git-alias
# (ele procura _git-<subcomando>). A tag #compdef acima também cobre a
# chamada direta de "git-alias". Nos dois casos o 1º argumento do subcomando
# cai em words[2] / CURRENT==2. Não usa bashcompinit — é uma função de
# completion zsh de verdade.

# Preenche o array `_gaa` (declarado no chamador) com os nomes de alias já
# definidos — mesma fonte que alias_names() em git/bin/git-alias: chaves
# alias.* do config, sem o dispatcher "alias.alias". Chamada só nos ramos que
# de fato usam a lista. Expansão sem aspas: campos vazios são descartados.
# (Ao contrário do lado bash, não há um wrapper que replique -C/--git-dir da
# linha; aliases são quase sempre --global, então a visão mesclada coincide.)
_git_alias_names() {
  _gaa=( ${(f)"$(
    command git config --name-only --get-regexp '^alias\.' 2>/dev/null \
      | command sed -e 's/^alias\.//' -e '/^alias$/d' | command sort -u
  )"} )
}

_git-alias() {
  local -a _gaa

  if (( CURRENT == 2 )); then
    _git_alias_names
    _alternative \
      'commands:subcomando:(help --version -v --list --export --import --unset --rename --doctor)' \
      'aliases:alias existente:compadd -a _gaa'
    return
  fi

  case ${words[2]} in
    --list)
      _arguments \
        '--file[restringe a listagem ao arquivo de aliases incluído]' \
        '(--origin -o)'{--origin,-o}'[marca a origem de cada alias]'
      ;;
    --import)
      # '*:' (posicional não numerado): dentro de _git-alias a numeração de
      # posicionais do _arguments parte de words[2] (o próprio --import), e
      # acertar o índice do <arquivo> é frágil sem um zsh para verificar.
      # '*:' completa arquivo em qualquer posicional — pode ofertar um 2º
      # nome que o script recusa (só cosmético; o lado bash guarda a posição).
      _arguments \
        '--overwrite[na colisão de valor, a fonte vence]' \
        '--dry-run[mostra o resumo sem gravar nada]' \
        '*:arquivo gitconfig:_files'
      ;;
    --export)
      # '*:' pela mesma razão do --import acima; --export aceita no máximo um
      # <arquivo> (pode ofertar um 2º nome — cosmético).
      _arguments '*:arquivo de destino:_files'
      ;;
    --unset)
      # Só o 1º argumento é um alias; o script recusa "--unset a b".
      if (( CURRENT == 3 )); then
        _git_alias_names
        _describe -t aliases 'alias a remover' _gaa
      fi
      ;;
    --rename)
      if (( CURRENT == 3 )); then
        _git_alias_names
        _describe -t aliases 'alias a renomear' _gaa
      elif (( CURRENT == 4 )); then
        _message 'novo nome do alias'
      fi
      ;;
    --version|-v|--doctor|help)
      ;;
    *)
      _message "definição do alias (ex.: 'log --oneline')"
      ;;
  esac
}

_git-alias "$@"
