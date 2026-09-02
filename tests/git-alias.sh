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

# Achado na 7ª revisão: ao restringir a interceptação de "help" a "sem
# segundo argumento" (F6, para permitir "git alias help '<cmd>'" cair na
# guarda de nome reservado), "git alias help <a> <b>" (3+ args, nenhuma
# forma reconhecida) passou a cair no "usage; return 2" final em vez do
# antigo "usage; return 0" — mudança de exit code não documentada.
# Comportamento mantido deliberadamente (é "erro de uso" de verdade,
# consistente com o contrato 0/1/2 desta branch); travado aqui e anotado
# no CHANGELOG.
st=0
"$SCRIPT" help foo bar >/dev/null 2>&1 || st=$?
check "'git alias help' com argumentos extras: erro de uso (exit 2), não sucesso" \
	"2" "$st"

# Achado na 13ª revisão: -h/--help e --version/-v casavam independente de
# $#, então argumento extra era descartado em silêncio (exit 0) —
# inconsistente com "help"/--rename/--unset, que já recusam (exit 2) o
# mesmo tipo de entrada malformada.
st=0
"$SCRIPT" -h foo bar >/dev/null 2>&1 || st=$?
check "'-h' com argumentos extras: erro de uso (exit 2)" "2" "$st"
st=0
"$SCRIPT" --version foo bar >/dev/null 2>&1 || st=$?
check "'--version' com argumentos extras: erro de uso (exit 2)" "2" "$st"

check "consulta alias existente" \
	"co = checkout" "$("$SCRIPT" co)"
check "consulta alias inexistente" \
	"Aviso: O alias 'nada' não foi encontrado." "$("$SCRIPT" nada 2>&1)"
# Achado na 10ª revisão: a mensagem ia para stdout, inconsistente com toda
# outra mensagem "Aviso:"/"Erro:" do script (inclusive a análoga do
# --rename) — polui a saída de dados mesmo com o exit code já correto.
check "consulta alias inexistente: mensagem vai para stderr, não stdout" \
	"" "$("$SCRIPT" nada 2>/dev/null)"
st=0
"$SCRIPT" nada >/dev/null 2>&1 || st=$?
check "consulta alias inexistente: exit code 1" "1" "$st"
# Achado na revisão da branch: um alias com valor "" é um alias existente
# (mesma lição já aplicada ao --rename); a consulta não pode se basear em
# "a string do valor não é vazia" para decidir se o alias existe.
git config --global alias.vazioquery ''
st=0
out="$("$SCRIPT" vazioquery 2>&1)" || st=$?
check "consulta alias com valor vazio: não trata como inexistente" \
	"vazioquery = " "$out"
check "consulta alias com valor vazio: exit code 0" "0" "$st"
git config --global --unset-all alias.vazioquery

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
	"Aviso: O alias 'foo' não existe ou já foi removido." "$("$SCRIPT" --unset foo 2>&1)"
check "--unset de alias ausente: mensagem vai para stderr, não stdout" \
	"" "$("$SCRIPT" --unset foo 2>/dev/null)"
st=0
"$SCRIPT" --unset foo >/dev/null 2>&1 || st=$?
check "--unset de alias ausente: exit code 1" "1" "$st"
check "--unset sem nome erra" \
	"Erro: Informe o nome do atalho para remover. Ex: git alias --unset <nome>" \
	"$("$SCRIPT" --unset 2>&1 || true)"

# Achado na 9ª revisão: --unset só lia $2, nunca checava $# — um
# argumento extra era descartado em silêncio e o alias era removido mesmo
# assim, em vez de recusar como erro de uso.
git config --global alias.comextra '!echo x'
st=0
out="$("$SCRIPT" --unset comextra argumento-extra 2>&1)" || st=$?
check "--unset com argumento extra: erro de uso, não sucesso silencioso" \
	"2" "$st"
check "--unset com argumento extra: alias não foi removido" \
	"!echo x" "$(git config --get alias.comextra)"
git config --global --unset-all alias.comextra 2>/dev/null || true

# Achado GRAVE na 14ª revisão: --unset nunca chamava is_reserved_alias_name
# — "git alias --unset alias" apagava silenciosamente a entrada real
# "alias.alias" no --global (a que faz "git alias" funcionar como
# subcomando do Git), a mesma classe de acidente que a guarda de F6 foi
# criada para evitar em create/--rename, mas nunca foi plugada aqui.
git config --global alias.alias '!git-alias'
alias_dispatcher_val="$(git config --global --get alias.alias)"
st=0
out="$("$SCRIPT" --unset alias 2>&1)" || st=$?
check "--unset de 'alias' é recusado (não apaga o dispatcher)" \
	"Erro: 'alias' é reservado (usado pelo próprio dispatcher do git alias); escolha outro nome." "$out"
check "--unset de 'alias': exit code 2" "2" "$st"
check "--unset de 'alias': alias.alias (dispatcher) continua intacto" \
	"$alias_dispatcher_val" "$(git config --global --get alias.alias)"

st=0
out="$("$SCRIPT" --unset help 2>&1)" || st=$?
check "--unset de 'help' é recusado" \
	"Erro: 'help' é reservado (usado pelo próprio dispatcher do git alias); escolha outro nome." "$out"
check "--unset de 'help': exit code 2" "2" "$st"

# --export (alias.alias ainda presente, deve ser omitido)
check "--export stdout tem cabeçalho" \
	"# Gerado por: git alias --export" "$("$SCRIPT" --export | head -1)"
check "--export stdout tem seção [alias]" \
	"[alias]" "$("$SCRIPT" --export | grep -F '[alias]')"

# Achado na 13ª revisão: --export não checava "$#" — argumento extra era
# descartado em silêncio (exit 0), mesma classe de bug já corrigida para
# --rename/--unset na 9ª revisão.
st=0
"$SCRIPT" --export "$SB/out-extra.gitconfig" argumento-extra >/dev/null 2>&1 || st=$?
check "--export com argumento extra: erro de uso (exit 2)" "2" "$st"

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

# --- corpo de alias com "alias.X " embutido não corrompe --list ----------
# O parsing antigo de --list ("--get-regexp | sed") substituía qualquer
# ocorrência de "alias.<nome> " em qualquer ponto da linha, inclusive dentro
# do corpo de outro alias — corrompendo o valor listado.
git config --global alias.mlbody "$(printf '!f() {\n  git commit -m alias.evil hack\n}\nf')"
check "--list não interpreta 'alias.X ' embutido no corpo como novo alias" \
	"nao" "$("$SCRIPT" --list | grep -qx 'evil = hack' && echo sim || echo nao)"
check "--list preserva o corpo original com 'alias.X ' embutido" \
	"sim" "$("$SCRIPT" --list | grep -qF 'git commit -m alias.evil hack' && echo sim || echo nao)"
git config --global --unset alias.mlbody

# Achado na 14ª revisão: --list faz um "git config --get" por nome (a
# migração do F5 que corrigiu o parsing de valor multilinha), mas isso
# reduz um alias.X genuinamente MULTIVALORADO (ex.: "git config --add"
# usado por fora do git-alias) ao seu último valor, sem nenhuma pista de
# que os demais existem — a mesma anomalia que --rename recusa citando
# "--get-all" (F4), mas que --list, o comando de descoberta, escondia em
# silêncio.
git config --global --add alias.dup foo
git config --global --add alias.dup bar
check "--list mostra o último valor de um alias multivalorado" \
	"dup = bar" "$("$SCRIPT" --list 2>/dev/null | grep '^dup ')"
check "--list avisa (stderr) sobre a multiplicidade escondida" \
	"Aviso: 'dup' tem mais de um valor (veja: git config --get-all alias.dup); mostrando o último." \
	"$("$SCRIPT" --list 2>&1 >/dev/null)"
git config --global --unset-all alias.dup 2>/dev/null || true

# Achado GRAVE na 15ª revisão: a checagem de multiplicidade acima
# (introduzida na 14ª) contava o config MESCLADO inteiro quando não há
# "--file" — isso inclui o arquivo incluído E qualquer cópia dele no
# ~/.gitconfig como occorrências separadas de "--get-all", mesmo quando
# a segunda é só a sombra obsoleta que create/--rename/--unset já
# tratam corretamente (e já limpam) em outros pontos deste script. Falso
# positivo: "foo" aqui tem UM valor por camada (nenhuma ambiguidade
# real), mas --list avisava "tem mais de um valor" mesmo assim —
# enquanto --rename, no mesmíssimo estado, prossegue em silêncio por
# saber que é sombra, não multivalor. Reproduzido antes deste fix.
AFSHADOW="$SB/shadow.gitconfig"
printf '%s\n' \
	'# Gerado por: git alias --export' \
	'# Nao edite a mao; rode o comando novamente para atualizar.' \
	'' \
	'[alias]' \
	'	shadowed = !echo do-arquivo' >"$AFSHADOW"
git config --global --add include.path "$AFSHADOW"
git config --global alias.shadowed '!echo global-obsoleto'
SHADOW_ERR="$("$SCRIPT" --list 2>&1 >/dev/null)"
check "--list não confunde sombra obsoleta (arquivo + cópia no --global) com multivalor real" \
	"nao" "$(printf '%s' "$SHADOW_ERR" | grep -q shadowed && echo sim || echo nao)"
git config --global --unset-all alias.shadowed 2>/dev/null || true
git config --global --unset-all --fixed-value include.path "$AFSHADOW" 2>/dev/null || true

# Achado na 14ª revisão: sob "set -eu" em dash/bash, uma falha do "git
# config --get" dentro do "while read" que consome a saída de
# alias_names (lado direito de um pipe) mata o subshell do loop na hora
# — sem terminar a listagem e sem o exit code 0 documentado para --list.
# Reproduzido isoladamente (dash e bash): "val=\"\$(false)\"" dentro de
# um "while read" assim aborta o script inteiro, sem alcançar as
# iterações seguintes nem o código após o loop. Aqui simula-se essa
# janela (nome enumerado, mas cuja consulta individual falha — o mesmo
# efeito de um TOCTOU real) com um "git" fake no PATH, para o teste ser
# determinístico em vez de depender de uma corrida de fato.
REALGIT="$(command -v git)"
mkdir -p "$SB/fakebin"
cat >"$SB/fakebin/git" <<FAKEGIT
#!/bin/sh
if [ "\$1" = "config" ] && [ "\$2" = "--get" ] && [ "\$3" = "alias.racefail" ]; then
	exit 1
fi
exec "$REALGIT" "\$@"
FAKEGIT
chmod +x "$SB/fakebin/git"
git config --global alias.ok1 '!true'
git config --global alias.racefail '!true'
git config --global alias.zzzultimo '!true'
st=0
out="$(PATH="$SB/fakebin:$PATH" "$SCRIPT" --list 2>/dev/null)" || st=$?
check "--list sobrevive a uma consulta individual que falha: continua listando os posteriores" \
	"sim" "$(printf '%s\n' "$out" | grep -qx 'zzzultimo = !true' && echo sim || echo nao)"
check "--list sobrevive a uma consulta individual que falha: exit code continua 0" \
	"0" "$st"
git config --global --unset-all alias.ok1 2>/dev/null || true
git config --global --unset-all alias.racefail 2>/dev/null || true
git config --global --unset-all alias.zzzultimo 2>/dev/null || true

# --- --list --file sem arquivo de aliases incluído detectado --------------
ERRF="$SB/list-file-err.txt"
st=0
out="$("$SCRIPT" --list --file 2>"$ERRF")" || st=$?
check "--list --file sem arquivo: stdout vazio" "" "$out"
check "--list --file sem arquivo: avisa" \
	"Aviso: nenhum arquivo de aliases incluído encontrado." "$(cat "$ERRF")"
check "--list --file sem arquivo: exit code 1" "1" "$st"

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

check "--list --file mostra só os aliases do arquivo incluído" \
	"novo outro zz" \
	"$("$SCRIPT" --list --file | sed -n 's/^\([a-zA-Z0-9-]*\) = .*/\1/p' | LC_ALL=C sort -u | paste -sd' ' -)"
check "--list --file omite aliases que só existem no --global" \
	"" "$("$SCRIPT" --list --file | grep -x 'co = checkout' || true)"

# --- --list --origin / -o marca a origem de cada alias --------------------
check "--list --origin marca alias do arquivo incluído" \
	"arquivo:$AF" "$("$SCRIPT" --list --origin | grep -F 'novo = !echo novo' | cut -f1)"
check "--list --origin marca alias do --global" \
	"--global" "$("$SCRIPT" --list --origin | grep -F 'co = checkout' | cut -f1)"
check "-o é sinônimo de --origin" \
	"arquivo:$AF" "$("$SCRIPT" --list -o | grep -F 'novo = !echo novo' | cut -f1)"
check "--list --file --origin combina: tudo vem do arquivo" \
	"arquivo:$AF" "$("$SCRIPT" --list --file --origin | grep -F 'novo = !echo novo' | cut -f1)"

# Achado na 15ª revisão: o formato "rótulo\tnome = valor" de --origin só
# prefixava a 1ª linha física de um valor multilinha — as linhas de
# continuação do corpo saíam cruas, sem rótulo nem tab, quebrando o
# parsing por "cut -f1" que os próprios testes desta suíte usam.
git config --global alias.mlorigin "$(printf 'linha1\nlinha2\nlinha3')"
TAB="$(printf '\t')"
MLBLOCK="$("$SCRIPT" --list --origin | grep -A2 -F 'mlorigin = linha1')"
check "--list --origin rotula toda linha de um valor multilinha, não só a 1ª" \
	"3" "$(printf '%s\n' "$MLBLOCK" | grep -c "^--global${TAB}")"
git config --global --unset-all alias.mlorigin 2>/dev/null || true

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

# --- git alias --rename: caminho feliz -------------------------------------
check "--rename dentro do arquivo incluído: mensagem" \
	"Alias 'zz' renomeado para 'zzrenamed' em $AF." \
	"$("$SCRIPT" --rename zz zzrenamed)"
check "--rename dentro do arquivo incluído: valor preservado" \
	"!echo zz" "$(git config --file "$AF" alias.zzrenamed)"
check "--rename dentro do arquivo incluído: nome antigo sai do arquivo" \
	"" "$(git config --file "$AF" alias.zz 2>/dev/null || true)"
check "--rename dentro do arquivo incluído: consultável pelo novo nome" \
	"zzrenamed = !echo zz" "$("$SCRIPT" zzrenamed)"

# alias que só existia no --global: com arquivo incluído detectado, o
# renomeado segue a mesma regra de "git alias <nome> '<cmd>'" e vai para lá.
git config --global alias.gonly '!echo gonly'
# Achado na revisão da branch: --global era a ÚNICA fonte de "gonly" (não
# havia cópia no arquivo) — chamar a remoção de "cópia obsoleta" seria
# enganoso, como se houvesse uma duplicata; é só a relocação normal para
# o arquivo, a mesma regra de "git alias <nome> '<cmd>'".
check "--rename de alias só no --global (com arquivo incluído): vai para o arquivo, sem alegar duplicata" \
	"Alias 'gonly' renomeado para 'gonlyfile' em $AF." \
	"$("$SCRIPT" --rename gonly gonlyfile)"
check "--rename de alias só no --global: nome antigo sai do --global" \
	"" "$(git config --file "$GIT_CONFIG_GLOBAL" alias.gonly 2>/dev/null || true)"
check "--rename de alias só no --global: novo nome está no arquivo" \
	"!echo gonly" "$(git config --file "$AF" alias.gonlyfile)"

# valor multilinha sobrevive ao rename (mesma técnica do alias_render: --get
# exato, nunca "cut").
git config --file "$AF" alias.mlrename "$(printf '!f() {\n  git push\n}\nf')"
"$SCRIPT" --rename mlrename mlrenamed >/dev/null
check "--rename preserva valor multilinha" \
	"$(printf '!f() {\n  git push\n}\nf')" \
	"$(git config --file "$AF" --get alias.mlrenamed)"

# Achado na revisão da branch: se o alias existir tanto no arquivo quanto
# como cópia obsoleta no --global posicionada depois do [include] (a mesma
# situação de "sombra" que os testes de --unset acima já cobrem), o valor
# mesclado que "git config --get" enxerga é o do --global, não o do
# arquivo. --rename não pode usar esse valor mesclado como "o" valor do
# alias — perderia o valor canônico (o do arquivo) ao gravar o renomeado.
git config --file "$AF" alias.dupe2 '!echo do-arquivo'
# Anexado cru (não via "git config --global") para garantir que a cópia
# fique posicionada DEPOIS do "[include]" no ~/.gitconfig — só assim ela
# faz sombra (git config: a entrada mais recente no arquivo vence); usar
# "git config --global" aqui cairia na seção [alias] já existente no topo
# do arquivo (antes do include), sem reproduzir a sombra.
printf '[alias]\n\tdupe2 = !echo do-global-obsoleto\n' >>"$GIT_CONFIG_GLOBAL"
dupe2out="$("$SCRIPT" --rename dupe2 dupe2renamed)"
check "--rename de alias com cópia obsoleta no --global: usa o valor do arquivo, não o mesclado" \
	"!echo do-arquivo" "$(git config --file "$AF" --get alias.dupe2renamed)"
check "--rename de alias com cópia obsoleta: cópia obsoleta some do --global" \
	"" "$(git config --file "$GIT_CONFIG_GLOBAL" alias.dupe2 2>/dev/null || true)"
# Achado na revisão da branch: "cópia obsoleta" só é uma palavra honesta
# quando o --global tinha MESMO uma cópia redundante (o valor de verdade
# já estava garantido no arquivo, como aqui) — não quando --global era a
# ÚNICA fonte (ver teste de "gonly" acima, que não deve usar essa frase).
check "--rename de alias com cópia obsoleta: mensagem chama a cópia de obsoleta (é, de fato)" \
	"Alias 'dupe2' renomeado para 'dupe2renamed' em $AF (cópia obsoleta de 'dupe2' em git config --global também removida)." \
	"$dupe2out"

# Achado na 11ª revisão: a checagem de multiplicidade contava o --global
# mesmo quando <velho> já tinha valor garantidamente único no ARQUIVO
# (old_src = $f) — uma sombra multivalorada no --global, que vai ser
# removida por inteiro de qualquer forma (--unset-all não liga para
# quantos valores há), não é ambiguidade nenhuma sobre QUAL valor
# preservar, já que o valor de verdade nunca veio de lá.
git config --file "$AF" alias.clean 'status'
printf '[alias]\n\tclean = shadow1\n\tclean = shadow2\n' >>"$GIT_CONFIG_GLOBAL"
st=0
out="$("$SCRIPT" --rename clean cleanrenamed 2>&1)" || st=$?
check "--rename com valor único no arquivo e sombra multivalorada irrelevante no --global: não recusa" \
	"0" "$st"
check "--rename com sombra multivalorada irrelevante: valor do arquivo preservado certo" \
	"status" "$(git config --file "$AF" --get alias.cleanrenamed)"
check "--rename com sombra multivalorada irrelevante: sombra some do --global" \
	"" "$(git config --file "$GIT_CONFIG_GLOBAL" alias.clean 2>/dev/null || true)"

# Achado na revisão da branch: um alias com valor vazio ("") é um alias
# existente para o git config (variável definida, ainda que vazia); a
# checagem de existência não pode se basear em "a string do valor não é
# vazia".
git config --global alias.vazio ''
st=0
out="$("$SCRIPT" --rename vazio vaziorenamed 2>&1)" || st=$?
check "--rename de alias com valor vazio: não trata como inexistente" \
	"0" "$st"
st2=0
git config --get-regexp '^alias\.vaziorenamed$' >/dev/null 2>&1 || st2=$?
check "--rename de alias com valor vazio: chave nova existe (mesmo vazia)" \
	"0" "$st2"

# Achado na revisão da branch: uma chave "alias.X" pode ter mais de um
# valor no git config (ex.: "git config --add" usado fora do git-alias, ou
# um gitconfig editado à mão). "git config --get" simples enxerga só o
# último; ler esse valor como "o" valor de <velho> e depois fazer
# --unset-all descartaria os demais valores para sempre. --rename deve
# recusar em vez de perder dado em silêncio. A contagem usa
# "--null --get-all" + NULs, não linhas: um alias multilinha legítimo (um
# valor só, com \n embutido) não pode ser confundido com múltiplos valores.
git config --global --add alias.dupval foo
git config --global --add alias.dupval bar
st=0
out="$("$SCRIPT" --rename dupval dupvalrenamed 2>&1)" || st=$?
check "--rename de alias com múltiplos valores: recusa em vez de perder dado" \
	"2" "$(git config --get-all alias.dupval 2>/dev/null | wc -l | tr -d '[:space:]')"
check "--rename de alias com múltiplos valores: exit code 1" "1" "$st"
check "--rename de alias com múltiplos valores: nada foi criado com o novo nome" \
	"" "$(git config --get alias.dupvalrenamed 2>/dev/null || true)"
git config --global --unset-all alias.dupval 2>/dev/null || true
git config --global --unset-all alias.dupvalrenamed 2>/dev/null || true

# Achado na revisão da branch: a checagem acima ficou larga demais — conta
# ocorrências no config MESCLADO inteiro, então um alias definido tanto no
# --system quanto no --global (duas camadas DIFERENTES, sem ambiguidade
# nenhuma: "git config --get" já resolve para o valor do --global, que é
# exatamente o que rodaria de verdade) também é recusado. --rename só
# altera --global e o arquivo incluído — nunca --system —, então
# multiplicidade só nessas duas camadas oferece risco real de perda; nas
# demais, o pior caso é o alias "ressurgir" com o valor antigo depois do
# rename, já coberto pelo aviso de "ainda existe em outra fonte".
SYSCFG="$SB/gitconfig-system"
st=0
rensysout="$(
	GIT_CONFIG_SYSTEM="$SYSCFG"
	export GIT_CONFIG_SYSTEM
	git config --system alias.stsys status
	git config --global alias.stsys 'status -sb'
	"$SCRIPT" --rename stsys stsysrenamed
)" || st=$?
check "--rename de alias definido em camadas diferentes (--system + --global): não recusa" \
	"0" "$st"
check "--rename entre camadas diferentes: mensagem confirma a renomeação" \
	"sim" "$(printf '%s' "$rensysout" | grep -qF "Alias 'stsys' renomeado para 'stsysrenamed'" && echo sim || echo nao)"
check "--rename entre camadas diferentes: preserva o valor efetivo (--global vence)" \
	"status -sb" "$(GIT_CONFIG_SYSTEM="$SYSCFG" git config --get alias.stsysrenamed 2>/dev/null || true)"

# --- git alias --rename: caminhos de erro -----------------------------------
st=0
out="$("$SCRIPT" --rename naoexiste destino 2>&1)" || st=$?
check "--rename de alias inexistente: mensagem" \
	"Aviso: O alias 'naoexiste' não existe; nada para renomear." "$out"
check "--rename de alias inexistente: exit code 1" "1" "$st"

st=0
out="$("$SCRIPT" --rename outro shadowmsg 2>&1)" || st=$?
check "--rename para nome já existente: recusa, não sobrescreve" \
	"!echo outro" "$(git config --file "$AF" alias.outro)"
check "--rename para nome já existente: exit code 1" "1" "$st"
check "--rename para nome já existente (arquivo/--global): sugere --unset que de fato funciona" \
	"sim" "$(printf '%s' "$out" | grep -qF "remova-o antes com 'git alias --unset shadowmsg'" && echo sim || echo nao)"

# Achado na 11ª revisão: quando <novo> já existe só numa camada que
# --unset não alcança (--system, aqui), a mensagem sugeria
# "git alias --unset <novo>" incondicionalmente — seguir a sugestão dá
# "Aviso: não existe", deixando o usuário sem entender por quê.
SYSONLY="$SB/gitconfig-system-sysonly"
st=0
sysonlyout="$(
	GIT_CONFIG_SYSTEM="$SYSONLY"
	export GIT_CONFIG_SYSTEM
	git config --system alias.sysonly '!echo sys'
	"$SCRIPT" --rename outro sysonly 2>&1
)" || st=$?
check "--rename para nome já existente só em --system: exit code 1" "1" "$st"
check "--rename para nome já existente só em --system: não sugere --unset (não funcionaria)" \
	"nao" "$(printf '%s' "$sysonlyout" | grep -qF "git alias --unset sysonly" && echo sim || echo nao)"
check "--rename para nome já existente só em --system: explica que está fora do alcance" \
	"sim" "$(printf '%s' "$sysonlyout" | grep -qF "fora do arquivo incluído e do --global" && echo sim || echo nao)"

st=0
out="$("$SCRIPT" --rename outro 2>&1)" || st=$?
check "--rename sem <novo>: erro de uso" \
	"Erro: uso: git alias --rename <velho> <novo>" "$out"
check "--rename sem <novo>: exit code 2" "2" "$st"

# Achado na 9ª revisão: --rename só lia $2/$3, nunca checava $# — um
# argumento extra era descartado em silêncio e a operação prosseguia como
# se nada tivesse acontecido, em vez de recusar como erro de uso
# (contrato documentado no README: "2 = Flag ou argumento
# inválido/faltando").
st=0
out="$("$SCRIPT" --rename outro terceiro argumento-extra 2>&1)" || st=$?
check "--rename com argumento extra: erro de uso, não sucesso silencioso" \
	"2" "$st"
check "--rename com argumento extra: nada foi renomeado" \
	"!echo outro" "$(git config --file "$AF" alias.outro)"

# Achado na revisão da branch: renomear um alias para o próprio nome caía
# no ramo de "<novo> já existe" (já que <novo> é <velho>), cuja mensagem
# manda rodar "git alias --unset <novo>" antes — o que destruiria o
# próprio alias que o usuário queria manter. Deve ser um no-op inofensivo.
st=0
out="$("$SCRIPT" --rename outro outro 2>&1)" || st=$?
check "--rename para o próprio nome: no-op, sem sugerir --unset de si mesmo" \
	"Aviso: 'outro' já tem esse nome; nada para renomear." "$out"
check "--rename para o próprio nome: exit code 0" "0" "$st"
check "--rename para o próprio nome: alias não é afetado" \
	"!echo outro" "$(git config --file "$AF" alias.outro)"

# Achado na 6ª revisão: a comparação "$old" = "$new" e a checagem de
# "<novo> já existe" eram sensíveis a maiúsculas, mas chaves do git config
# são a MESMA para o git independente de caixa — renomear só a caixa
# (Foo -> foo) caía no ramo de "já existe" (a própria chave!), cuja
# mensagem sugere "--unset foo", que apagaria o alias que o usuário queria
# manter.
git config --file "$AF" alias.CaseTest '!echo x'
st=0
out="$("$SCRIPT" --rename CaseTest casetest 2>&1)" || st=$?
check "--rename só de caixa (mesma chave): no-op, não 'já existe'" \
	"Aviso: 'CaseTest' já tem esse nome; nada para renomear." "$out"
check "--rename só de caixa: exit code 0" "0" "$st"
check "--rename só de caixa: alias não foi alterado" \
	"!echo x" "$(git config --file "$AF" --get alias.CaseTest)"

# Achado na 6ª revisão: a checagem de múltiplos valores rodava ANTES da de
# "mesmo nome", então "--rename dup dup" (alias multivalorado renomeado
# para si mesmo — nada seria escrito ou removido de qualquer forma) caía
# em "não sei qual preservar" em vez de no-op.
git config --global --add alias.selfdup foo
git config --global --add alias.selfdup bar
st=0
out="$("$SCRIPT" --rename selfdup selfdup 2>&1)" || st=$?
check "--rename para o próprio nome com alias multivalorado: no-op" \
	"Aviso: 'selfdup' já tem esse nome; nada para renomear." "$out"
check "--rename selfdup selfdup: exit code 0" "0" "$st"
git config --global --unset-all alias.selfdup 2>/dev/null || true

# Achado na 6ª revisão: a mensagem de no-op ia para stdout; toda outra
# mensagem "Aviso:" do script vai para stderr.
errout="$("$SCRIPT" --rename outro outro 2>&1 >/dev/null)"
check "--rename para o próprio nome: mensagem vai para stderr" \
	"Aviso: 'outro' já tem esse nome; nada para renomear." "$errout"

# --- F6: guarda de nome reservado/inválido ao criar ou renomear ------------
st=0
out="$("$SCRIPT" alias '!true' 2>&1)" || st=$?
check "criar alias chamado 'alias' é recusado" \
	"Erro: 'alias' é reservado (usado pelo próprio dispatcher do git alias); escolha outro nome." "$out"
check "criar alias chamado 'alias': exit code 2" "2" "$st"
check "criar alias chamado 'alias': nada foi gravado no arquivo incluído" \
	"" "$(git config --file "$AF" alias.alias 2>/dev/null || true)"

# Achado na revisão da branch: nomes de chave do git config são
# case-insensitive tanto na leitura quanto na escrita — "git config
# alias.Alias v" sobrescreve de fato "alias.alias" (mesma chave para o
# git). A guarda usava "case" sensível a maiúsculas e deixava passar
# variações de caixa do nome reservado, permitindo sobrescrever o
# dispatcher do próprio script com um typo de maiúscula.
git config --global alias.alias '!echo dispatcher-original'
st=0
out="$("$SCRIPT" Alias '!evil' 2>&1)" || st=$?
check "criar alias chamado 'Alias' (maiúscula) também é recusado" \
	"Erro: 'Alias' é reservado (usado pelo próprio dispatcher do git alias); escolha outro nome." "$out"
check "criar alias chamado 'Alias': exit code 2" "2" "$st"
check "criar alias chamado 'Alias': dispatcher original não foi afetado" \
	"!echo dispatcher-original" "$(git config --get alias.alias)"
git config --global --unset-all alias.alias 2>/dev/null || true

st=0
out="$("$SCRIPT" HELP '!evil' 2>&1)" || st=$?
check "criar alias chamado 'HELP' (maiúsculas) também é recusado" \
	"Erro: 'HELP' é reservado (usado pelo próprio dispatcher do git alias); escolha outro nome." "$out"
check "criar alias chamado 'HELP': exit code 2" "2" "$st"

st=0
out="$("$SCRIPT" --rename outro alias 2>&1)" || st=$?
check "--rename para o nome reservado 'alias' é recusado" \
	"Erro: 'alias' é reservado (usado pelo próprio dispatcher do git alias); escolha outro nome." "$out"
check "--rename para 'alias': exit code 2" "2" "$st"
check "--rename para 'alias': o velho não foi alterado" \
	"!echo outro" "$(git config --file "$AF" alias.outro)"

# Achado na revisão da branch: o dispatcher intercepta "git alias help ..."
# ANTES da guarda de nome rodar (case "$1" in help | -h | --help)...), então
# "git alias help '<cmd>'" seria um no-op silencioso (imprime a sintaxe de
# uso, sai 0, mas alias.help nunca é gravado) em vez de gravar ou recusar
# com uma mensagem clara. "help" é, na prática, tão reservado quanto
# "alias" e precisa da mesma guarda.
st=0
out="$("$SCRIPT" help '!true' 2>&1)" || st=$?
check "criar alias chamado 'help' é recusado (não um no-op silencioso)" \
	"Erro: 'help' é reservado (usado pelo próprio dispatcher do git alias); escolha outro nome." "$out"
check "criar alias chamado 'help': exit code 2" "2" "$st"

st=0
out="$("$SCRIPT" --rename outro help 2>&1)" || st=$?
check "--rename para o nome reservado 'help' é recusado" \
	"Erro: 'help' é reservado (usado pelo próprio dispatcher do git alias); escolha outro nome." "$out"
check "--rename para 'help': exit code 2" "2" "$st"
check "--rename para 'help': o velho não foi alterado" \
	"!echo outro" "$(git config --file "$AF" alias.outro)"

# Achado GRAVE na 13ª revisão: validate_alias_name só era chamada em <novo>,
# nunca em <velho> — "git alias --rename alias foo" não era recusado, e
# como "alias" existe de verdade no --global (a própria entrada
# "alias.alias" que faz o dispatcher funcionar), a operação prosseguia:
# gravava "foo" com o valor do dispatcher e APAGAVA "alias.alias" na
# limpeza normal de <velho> — quebrando "git alias" como subcomando do git
# até o usuário recriar a entrada manualmente. Reproduzido antes do fix.
git config --global alias.alias '!git-alias'
alias_dispatcher_val="$(git config --global --get alias.alias)"
st=0
out="$("$SCRIPT" --rename alias fromalias 2>&1)" || st=$?
check "--rename de <velho>='alias' é recusado (não apaga o dispatcher)" \
	"Erro: 'alias' é reservado (usado pelo próprio dispatcher do git alias); escolha outro nome." "$out"
check "--rename de <velho>='alias': exit code 2" "2" "$st"
check "--rename de <velho>='alias': alias.alias (dispatcher) continua intacto" \
	"$alias_dispatcher_val" "$(git config --global --get alias.alias)"
check "--rename de <velho>='alias': nada foi criado com o novo nome" \
	"" "$(git config --get alias.fromalias 2>/dev/null || true)"

st=0
out="$("$SCRIPT" --rename help fromhelp 2>&1)" || st=$?
check "--rename de <velho>='help' é recusado" \
	"Erro: 'help' é reservado (usado pelo próprio dispatcher do git alias); escolha outro nome." "$out"
check "--rename de <velho>='help': exit code 2" "2" "$st"
git config --global --unset-all alias.alias 2>/dev/null || true

st=0
out="$("$SCRIPT" 'nome invalido.' '!true' 2>&1)" || st=$?
check "criar alias com nome inválido (espaço e ponto): mensagem amigável" \
	"Erro: nome de alias inválido: 'nome invalido.'. Use letras minúsculas, números e hífen, começando por uma letra." "$out"
check "criar alias com nome inválido: exit code 2" "2" "$st"

st=0
out="$("$SCRIPT" --rename outro 'nome invalido.' 2>&1)" || st=$?
check "--rename para nome inválido: mensagem amigável" \
	"Erro: nome de alias inválido: 'nome invalido.'. Use letras minúsculas, números e hífen, começando por uma letra." "$out"
check "--rename para nome inválido: exit code 2" "2" "$st"

# Achado na revisão da branch: a checagem original só rejeitava caractere
# proibido em QUALQUER posição, não a exigência do git config de que a chave
# comece por uma letra — nome começando por dígito ou hífen (ou vazio)
# escapava da validação e batia no erro cru do "git config".
st=0
out="$("$SCRIPT" 1x '!true' 2>&1)" || st=$?
check "criar alias começando por dígito: mensagem amigável (não o erro cru do git config)" \
	"Erro: nome de alias inválido: '1x'. Use letras minúsculas, números e hífen, começando por uma letra." "$out"
check "criar alias começando por dígito: exit code 2" "2" "$st"

st=0
out="$("$SCRIPT" -x '!true' 2>&1)" || st=$?
check "criar alias começando por hífen: mensagem amigável" \
	"Erro: nome de alias inválido: '-x'. Use letras minúsculas, números e hífen, começando por uma letra." "$out"
check "criar alias começando por hífen: exit code 2" "2" "$st"

st=0
out="$("$SCRIPT" '' '!true' 2>&1)" || st=$?
check "criar alias com nome vazio: mensagem amigável" \
	"Erro: nome de alias inválido: ''. Use letras minúsculas, números e hífen, começando por uma letra." "$out"
check "criar alias com nome vazio: exit code 2" "2" "$st"

# Achado grave na 8ª revisão: o git config normaliza TODA chave para
# minúsculas em qualquer modo de enumeração ("--list", "--get-regexp",
# "--name-only" — mesmo sem --name-only), não é peculiaridade de uma
# flag específica. Isso não afeta só a exibição do --list: como toda
# gravação no arquivo incluído dispara normalize_or_warn (que reconstrói
# a seção [alias] inteira via alias_names(), que usa esse mesmo tipo de
# enumeração), criar QUALQUER alias reescreve o arquivo e renomeia
# silenciosamente para minúsculas todo alias com maiúscula que já
# estivesse lá — mesmo um alias que a operação nem tocou. Fecha o
# problema na raiz: nomes com maiúscula deixam de ser aceitos na
# criação (git não tem como preservar a caixa em nenhuma enumeração;
# tentar contornar isso exigiria fazer parsing manual do arquivo
# gitconfig, exatamente o que o F5 evitou).
st=0
out="$("$SCRIPT" MinhaFuncao '!echo x' 2>&1)" || st=$?
check "criar alias com maiúscula é recusado (git normaliza p/ minúscula em qualquer enumeração)" \
	"Erro: nome de alias inválido: 'MinhaFuncao'. Use letras minúsculas, números e hífen, começando por uma letra." "$out"
check "criar alias com maiúscula: exit code 2" "2" "$st"

# --- --rename: alias só existe fora de --global/arquivo (ex.: config local),
# sem arquivo de aliases incluído — não pode crashar, e (achado na 7ª
# revisão) não pode mais tratar isso como "encontrado via --global": o
# fallback antigo lia o valor via "git config --get" MESCLADO, que resolve
# por --local (precedência maior que --global) sem checar de onde veio de
# fato. --rename só gerencia arquivo incluído e --global (ADR-0001); um
# alias que só existe em --local está fora do alcance e deve ser recusado
# com mensagem clara, não "encontrado" por acidente via o mesclado.
git config --global --unset-all include.path 2>/dev/null || true
mkdir -p "$SB/localrepo"
(cd "$SB/localrepo" && git init -q . && git config user.email t@t && git config user.name t && git config --local alias.localonly '!echo local') >/dev/null
st=0
errout="$( ( cd "$SB/localrepo" && "$SCRIPT" --rename localonly renamed >/dev/null ) 2>&1 )" || st=$?
check "--rename de alias só em config local, sem arquivo incluído: recusa (fora do alcance)" \
	"1" "$st"
check "--rename de alias só em config local: nada foi criado no --global" \
	"" "$(git config --get alias.renamed 2>/dev/null || true)"
check "--rename de alias só em config local: velho continua intacto no config local" \
	"!echo local" "$(cd "$SB/localrepo" && git config --local --get alias.localonly)"
check "--rename de alias só em config local: mensagem explica que está fora do alcance" \
	"sim" "$(printf '%s' "$errout" | grep -qF "'localonly'" && echo sim || echo nao)"

# Achado na 7ª revisão, cenário A: --global e --local com valores
# DIFERENTES para a mesma chave, sem arquivo incluído. O fallback mesclado
# lia o valor do --local (que vence por precedência) e gravava ESSE valor
# sob <novo> no --global, depois apagava alias.foo do --global — destruindo
# de vez o valor distinto que só existia lá. Com o fix, <velho> É
# encontrado no --global (tem valor lá) e a operação prossegue usando o
# valor do --global — nunca o do --local, que fica intocado e alheio.
git config --global alias.foo 'status --global-version'
(cd "$SB/localrepo" && git config --local alias.foo 'status --local-version')
st=0
out="$( ( cd "$SB/localrepo" && "$SCRIPT" --rename foo foorenamed 2>&1 ) )" || st=$?
check "--rename com --global e --local divergentes: usa o valor do --global, não recusa" \
	"0" "$st"
check "--rename com --global e --local divergentes: novo nome tem o valor do --global (não o do --local)" \
	"status --global-version" "$(git config --global --get alias.foorenamed)"
check "--rename com --global e --local divergentes: alias.foo do --global foi removido (renomeado de verdade)" \
	"" "$(git config --global --get alias.foo 2>/dev/null || true)"
check "--rename com --global e --local divergentes: cópia distinta do --local não foi tocada" \
	"status --local-version" "$(cd "$SB/localrepo" && git config --local --get alias.foo)"
git config --global --unset-all alias.foorenamed 2>/dev/null || true

# Achado na 7ª revisão, cenário B: com arquivo incluído presente, alias só
# em --local (nem no arquivo, nem no --global) — o fallback mesclado
# resolvia mesmo assim e, como há arquivo, o valor (repo-específico) era
# copiado para dentro do arquivo COMPARTILHADO e versionado, vazando
# config local de uma máquina para o arquivo que outras máquinas também
# usam.
git config --global --add include.path "$AF"
(cd "$SB/localrepo" && git config --local alias.secreto 'status --so-neste-repo')
st=0
errout="$( ( cd "$SB/localrepo" && "$SCRIPT" --rename secreto vazado >/dev/null ) 2>&1 )" || st=$?
check "--rename de alias só em --local, com arquivo incluído: recusa em vez de vazar para o arquivo" \
	"1" "$st"
check "--rename de alias só em --local: nada vazou para o arquivo compartilhado" \
	"" "$(git config --file "$AF" --get alias.vazado 2>/dev/null || true)"
check "--rename de alias só em --local: velho continua intacto no config local" \
	"status --so-neste-repo" "$(cd "$SB/localrepo" && git config --local --get alias.secreto)"

# Achado GRAVE na 19ª revisão (2): a checagem de "remoção falhou de
# verdade" que a 18ª revisão adicionou ao --unset ("elif git config --get
# ... falhou") não distingue "existe numa camada que --unset nunca
# tentou tocar" (--system/--local, fora do alcance por ADR-0001) de
# "existe na camada que --unset TENTOU limpar, mas a limpeza falhou de
# verdade" — as duas caem na mesma mensagem "a remoção falhou", mesmo
# que --unset nunca tenha tentado nada ali. --rename já distingue os
# dois casos corretamente (mensagem "ainda existe em outra fonte de
# configuração"); --unset nunca ganhou essa mesma distinção.
git config --global --unset-all include.path 2>/dev/null || true
st=0
errout="$( ( cd "$SB/localrepo" && "$SCRIPT" --unset localonly >/dev/null ) 2>&1 )" || st=$?
check "--unset de alias só em --local: exit code 1 (fora do alcance, não removido)" \
	"1" "$st"
check "--unset de alias só em --local: mensagem correta (ainda existe em outra fonte), não 'remoção falhou'" \
	"nao" "$(printf '%s' "$errout" | grep -qi "remoção de 'localonly' falhou" && echo sim || echo nao)"
check "--unset de alias só em --local: velho continua intacto no config local" \
	"!echo local" "$(cd "$SB/localrepo" && git config --local --get alias.localonly)"
git config --global --add include.path "$AF"

# --- --list --origin: fallback XDG do config global (achado na revisão) ---
# Sem GIT_CONFIG_GLOBAL e sem ~/.gitconfig, o Git usa
# $XDG_CONFIG_HOME/git/config (default ~/.config/git/config) como config
# --global. A classificação de origem comparava só contra
# "${GIT_CONFIG_GLOBAL:-$HOME/.gitconfig}", rotulando erroneamente esse
# caso como "outro:..." em vez de "--global".
XDGHOME="$SB/xdghome"
mkdir -p "$XDGHOME/.config/git"
: >"$XDGHOME/.config/git/config"
xdgline="$(
	HOME="$XDGHOME"
	unset GIT_CONFIG_GLOBAL
	export HOME
	cd "$XDGHOME"
	git config --global user.email t@t
	git config --global user.name t
	git config --global alias.xdgtest checkout
	"$SCRIPT" --list --origin | grep 'xdgtest = checkout'
)"
check "--list --origin reconhece o fallback XDG do config global (~/.config/git/config)" \
	"--global" "$(printf '%s' "$xdgline" | cut -f1)"

# --- --unset/--rename: mesmo fallback XDG, achado GRAVE na 16ª revisão ----
# "git config --global --get"/"--unset-all" (nesta versão instalada do
# Git) não enxergam o arquivo de fallback XDG quando ~/.gitconfig existe
# — mesmo com ambos os arquivos existindo e a leitura MESCLADA (usada por
# --list) enxergando os dois corretamente. Isso deixa --unset e --rename
# cegos para um alias que só existe no fallback XDG, embora ele more
# genuinamente na camada --global que a ferramenta diz gerenciar
# (ADR-0001). Diferente do teste de --origin acima (que usa só o
# fallback XDG, sem ~/.gitconfig), aqui ambos os arquivos existem — a
# condição real que dispara o bug.
XDGHOME2="$SB/xdghome2"
mkdir -p "$XDGHOME2/.config/git"
: >"$XDGHOME2/.config/git/config"
: >"$XDGHOME2/.gitconfig"

UNSET_XDG="$(
	HOME="$XDGHOME2"
	unset GIT_CONFIG_GLOBAL
	export HOME
	cd "$XDGHOME2"
	git config --global user.email t@t
	git config --global user.name t
	git config --file "$XDGHOME2/.config/git/config" alias.xdgunset '!echo xdg'
	st=0
	"$SCRIPT" --unset xdgunset >/dev/null 2>&1 || st=$?
	still="$(git config --get alias.xdgunset 2>/dev/null || true)"
	printf 'exit=%s ainda=%s' "$st" "$still"
)"
check "--unset remove alias que só existe no fallback XDG do --global" \
	"exit=0 ainda=" "$UNSET_XDG"

RENAME_VELHO_XDG="$(
	HOME="$XDGHOME2"
	unset GIT_CONFIG_GLOBAL
	export HOME
	cd "$XDGHOME2"
	git config --global user.email t@t
	git config --global user.name t
	git config --file "$XDGHOME2/.config/git/config" alias.xdgvelho '!echo xdg'
	st=0
	err="$("$SCRIPT" --rename xdgvelho xdgnovo 2>&1 >/dev/null)" || st=$?
	novo="$(git config --get alias.xdgnovo 2>/dev/null || true)"
	printf 'exit=%s novo=%s err=%s' "$st" "$novo" "$err"
)"
check "--rename encontra <velho> que só existe no fallback XDG do --global" \
	"exit=0 novo=!echo xdg err=" "$RENAME_VELHO_XDG"

RENAME_NOVO_XDG="$(
	HOME="$XDGHOME2"
	unset GIT_CONFIG_GLOBAL
	export HOME
	cd "$XDGHOME2"
	git config --global user.email t@t
	git config --global user.name t
	git config --global alias.xdgorigem '!echo origem'
	git config --file "$XDGHOME2/.config/git/config" alias.xdgocupado '!echo ja-existe'
	st=0
	err="$("$SCRIPT" --rename xdgorigem xdgocupado 2>&1 >/dev/null)" || st=$?
	printf 'exit=%s err=%s' "$st" "$err"
)"
check "--rename detecta <novo> que só existe no fallback XDG do --global (mensagem correta)" \
	"exit=1 err=Erro: já existe um alias 'xdgocupado'. Escolha outro nome ou remova-o antes com 'git alias --unset xdgocupado'." \
	"$RENAME_NOVO_XDG"

# Achado GRAVÍSSIMO na 19ª revisão (1): global_value_count()/global_get()
# só verificam UM dos dois arquivos (--global; XDG só como fallback
# quando --global não acha NADA) — mas quando os DOIS definem a MESMA
# chave alias.X com valores DIFERENTES ao mesmo tempo (cenário real: um
# ~/.gitconfig com valor A e um fallback XDG com valor B, situação que
# "git config --get-all" mesclado enxerga corretamente como 2 valores),
# a guarda de multiplicidade do --rename só contava o lado do
# ~/.gitconfig (1), nunca somava o do XDG — --rename gravava só o valor
# de ~/.gitconfig sob o novo nome e apagava os dois (global_unset_all
# alcança ambos corretamente), perdendo o valor do XDG para sempre.
XDGHOME3="$SB/xdghome3"
mkdir -p "$XDGHOME3/.config/git"
RENAME_DUPBOTH="$(
	HOME="$XDGHOME3"
	unset GIT_CONFIG_GLOBAL
	export HOME
	cd "$XDGHOME3"
	git config --global user.email t@t
	git config --global user.name t
	git config --global alias.dupboth 'from-gitconfig'
	git config --file "$XDGHOME3/.config/git/config" alias.dupboth 'from-xdg'
	st=0
	err="$("$SCRIPT" --rename dupboth dupboth2 2>&1 >/dev/null)" || st=$?
	val="$(git config --get alias.dupboth2 2>/dev/null || true)"
	printf 'exit=%s val=%s err=%s' "$st" "$val" "$err"
)"
check "--rename recusa alias com valores diferentes em ~/.gitconfig E no fallback XDG (não perde dado)" \
	"exit=1 val= err=Erro: 'dupboth' tem mais de um valor no arquivo incluído ou no git config --global — --rename não sabe qual preservar. Resolva manualmente (git config --get-all alias.dupboth) antes de renomear." \
	"$RENAME_DUPBOTH"

# Achado GRAVE na 20ª revisão (1): o fix da 19ª revisão (somar a
# contagem de ~/.gitconfig com a do fallback XDG) conta o XDG DUAS
# VEZES quando ~/.gitconfig NÃO EXISTE de jeito nenhum — nesse estado,
# "git config --global" já lê o arquivo XDG transparentemente (é ele
# quem vira "o" --global quando ~/.gitconfig está ausente), então
# "alias_value_count ... --global" já inclui o valor do XDG; somar a
# contagem do XDG de novo por cima dobra a contagem de um alias com UM
# valor só, disparando um falso "tem mais de um valor".
XDGHOME4="$SB/xdghome4"
mkdir -p "$XDGHOME4/.config/git"
: >"$XDGHOME4/.config/git/config"
RENAME_XDGONLY_SINGLE="$(
	HOME="$XDGHOME4"
	unset GIT_CONFIG_GLOBAL
	export HOME
	cd "$XDGHOME4"
	git config --global user.email t@t
	git config --global user.name t
	git config --global alias.xdgsingle checkout
	st=0
	err="$("$SCRIPT" --rename xdgsingle xdgsingle2 2>&1 >/dev/null)" || st=$?
	val="$(git config --get alias.xdgsingle2 2>/dev/null || true)"
	printf 'exit=%s val=%s err=%s' "$st" "$val" "$err"
)"
check "--rename não confunde alias com 1 valor só (sem ~/.gitconfig) com multivalor" \
	"exit=0 val=checkout err=" "$RENAME_XDGONLY_SINGLE"

# Achado GRAVÍSSIMO na 17ª revisão (1): a guarda de multiplicidade do
# --rename (alias_value_count "alias.$old" --global) tem o MESMO blind
# spot de XDG que global_get/global_unset_all foram criados para corrigir
# na 16ª — mas nunca foi atualizada para usá-los. Um alias com dois
# valores só no fallback XDG passa pela guarda sem ser detectado (conta 0
# em vez de 2): --rename grava só o ÚLTIMO valor (capturado por
# global_get) sob o novo nome e remove TODOS os valores do XDG (via
# global_unset_all, que alcança lá corretamente) — o primeiro valor é
# perdido para sempre, com "sucesso" reportado. Pior que antes da 16ª
# revisão, que ao menos falhava de forma limpa (não via o alias no XDG).
RENAME_DUPXDG="$(
	HOME="$XDGHOME2"
	unset GIT_CONFIG_GLOBAL
	export HOME
	cd "$XDGHOME2"
	git config --global user.email t@t
	git config --global user.name t
	git config --file "$XDGHOME2/.config/git/config" --add alias.dupxdg valor1
	git config --file "$XDGHOME2/.config/git/config" --add alias.dupxdg valor2
	st=0
	err="$("$SCRIPT" --rename dupxdg dupxdg2 2>&1 >/dev/null)" || st=$?
	valores="$(git config --get-all alias.dupxdg2 2>/dev/null | LC_ALL=C sort | paste -sd, -)"
	printf 'exit=%s valores=%s err=%s' "$st" "$valores" "$err"
)"
check "--rename recusa alias com múltiplos valores só no fallback XDG (não perde dado)" \
	"exit=1 valores= err=Erro: 'dupxdg' tem mais de um valor no arquivo incluído ou no git config --global — --rename não sabe qual preservar. Resolva manualmente (git config --get-all alias.dupxdg) antes de renomear." \
	"$RENAME_DUPXDG"

# Achado GRAVE na 18ª revisão (1): global_get/global_unset_all/
# global_value_count testavam "[ -n "${GIT_CONFIG_GLOBAL:-}" ]" para
# decidir se tentam o fallback XDG — isso trata GIT_CONFIG_GLOBAL="" (uma
# string vazia, definida de propósito) como se fosse INDEFINIDA. Mas o
# git de verdade trata GIT_CONFIG_GLOBAL="" como "nenhuma fonte --global
# alguma" (nem ~/.gitconfig, nem XDG) — quem exporta essa variável vazia
# de propósito para isolar o git (técnica real de sandboxing) tem esse
# isolamento quebrado silenciosamente: --unset ainda alcança e apaga o
# arquivo XDG do $HOME real, mesmo com --list (que usa "git config --get"
# sem essa lógica própria) corretamente não vendo nada.
GCG_EMPTY_RESULT="$(
	GCGHOME="$(mktemp -d)"
	HOME="$GCGHOME"
	GIT_CONFIG_GLOBAL=""
	export HOME GIT_CONFIG_GLOBAL
	GIT_CONFIG_SYSTEM=/dev/null
	export GIT_CONFIG_SYSTEM
	mkdir -p "$GCGHOME/.config/git"
	git config --file "$GCGHOME/.config/git/config" alias.gcgtest '!echo xdg'
	st=0
	"$SCRIPT" --unset gcgtest >/dev/null 2>&1 || st=$?
	ainda="$(git config --file "$GCGHOME/.config/git/config" --get alias.gcgtest 2>/dev/null || true)"
	rm -rf "$GCGHOME"
	printf 'exit=%s ainda=%s' "$st" "$ainda"
)"
check "GIT_CONFIG_GLOBAL=\"\" isola --unset do fallback XDG, como isola o git real" \
	"exit=1 ainda=!echo xdg" "$GCG_EMPTY_RESULT"

# Achado GRAVE na 16ª revisão (3): a remoção de <velho> no ARQUIVO
# (dentro do ramo "if [ -n "$f" ]") nunca era checada quanto a sucesso —
# só a remoção da cópia no --global entrava na decisão da mensagem. Se
# essa remoção falhar por um motivo genuíno (lock, permissão — não só
# "chave não existe"), o script mesmo assim anunciava sucesso, deixando
# <velho> E <novo> duplicados no arquivo sem avisar. Simulado
# deterministicamente com um "git" fake que falha só nesse "unset-all"
# específico, sem depender de concorrência real.
FAILHOME="$SB/renamefailhome"
mkdir -p "$FAILHOME/fakebin"
AF2="$FAILHOME/aliases.gitconfig"
printf '%s\n' \
	'# Gerado por: git alias --export' \
	'# Nao edite a mao; rode o comando novamente para atualizar.' \
	'' \
	'[alias]' \
	'	renamefail = !echo original' >"$AF2"
REALGIT2="$(command -v git)"
cat >"$FAILHOME/fakebin/git" <<FAKEGIT2
#!/bin/sh
if [ "\$1" = "config" ] && [ "\$2" = "--file" ] && [ "\$4" = "--unset-all" ] && [ "\$5" = "alias.renamefail" ]; then
	exit 1
fi
exec "$REALGIT2" "\$@"
FAKEGIT2
chmod +x "$FAILHOME/fakebin/git"
RENFAIL_RESULT="$(
	HOME="$FAILHOME"
	export HOME
	GIT_CONFIG_GLOBAL="$FAILHOME/.gitconfig"
	export GIT_CONFIG_GLOBAL
	GIT_CONFIG_SYSTEM=/dev/null
	export GIT_CONFIG_SYSTEM
	GIT_CEILING_DIRECTORIES="$FAILHOME"
	export GIT_CEILING_DIRECTORIES
	cd "$FAILHOME"
	git config --global user.email t@t
	git config --global user.name t
	git config --global --add include.path "$AF2"
	err="$(PATH="$FAILHOME/fakebin:$PATH" "$SCRIPT" --rename renamefail renamefail2 2>&1 >/dev/null)" || true
	velho="$(git config --file "$AF2" --get alias.renamefail 2>/dev/null || true)"
	novo="$(git config --file "$AF2" --get alias.renamefail2 2>/dev/null || true)"
	avisou="$(printf '%s' "$err" | grep -qi renamefail && echo sim || echo nao)"
	printf 'velho=%s novo=%s avisou=%s\n%s' "$velho" "$novo" "$avisou" "$err"
)"
check "--rename com falha na remoção de <velho> no arquivo: velho continua, novo é criado, e avisa" \
	"velho=!echo original novo=!echo original avisou=sim" "$(printf '%s' "$RENFAIL_RESULT" | head -n1)"
# Achado 3 da 16ª revisão, mensagem: o aviso genérico de fim de --rename
# ("ainda existe em outra fonte de configuração...") é factualmente
# errado neste cenário — "$old" não está em "outra fonte", está DENTRO
# do próprio arquivo cuja remoção acabou de falhar. A causa real é essa
# falha específica, não uma camada fora do alcance da ferramenta.
check "--rename com falha na remoção de <velho> no arquivo: mensagem aponta a causa real" \
	"Aviso: a remoção de 'renamefail' de $AF2 falhou — 'renamefail' e 'renamefail2' agora coexistem nesse arquivo. Resolva manualmente (git config --file $AF2 --unset-all alias.renamefail)." \
	"$(printf '%s' "$RENFAIL_RESULT" | tail -n +2)"

# Achados 2 e 3 da 17ª revisão: quando <velho> vem do arquivo (old_src=$f,
# remoção do arquivo funciona) mas a limpeza OPORTUNISTA da sombra no
# --global falha de verdade (lock/permissão), a checagem "old_still_at_
# origin" da rodada 16 só olha old_src (o arquivo) — nunca a sombra no
# --global que essa mesma limpeza tentou remover. Resultado: (2) exit
# code continuava 0 mesmo com a sombra remanescente, contradizendo o
# contrato 0/1/2 documentado nesta branch; (3) a mensagem final caía na
# genérica "outra fonte de configuração (fora do --global...)" —
# factualmente errada, já que a cópia remanescente está literalmente no
# --global.
FAILHOME2="$SB/renamefailhome2"
mkdir -p "$FAILHOME2/fakebin"
AF4="$FAILHOME2/aliases.gitconfig"
printf '%s\n' \
	'# Gerado por: git alias --export' \
	'# Nao edite a mao; rode o comando novamente para atualizar.' \
	'' \
	'[alias]' \
	'	shadowfail2 = !echo do-arquivo' >"$AF4"
REALGIT4="$(command -v git)"
cat >"$FAILHOME2/fakebin/git" <<FAKEGIT4
#!/bin/sh
# A limpeza da sombra no --global agora passa por "git config --file
# <arquivo global> --unset-all" (helper global_unset_all, iterando
# global_backing_files), não mais por "git config --global --unset-all".
# Falha só essa remoção no arquivo global — a remoção de <velho> do
# arquivo de aliases incluído (outro --file) tem de continuar funcionando.
if [ "\$1" = "config" ] && [ "\$2" = "--file" ] && [ "\$3" = "$FAILHOME2/.gitconfig" ] && [ "\$4" = "--unset-all" ] && [ "\$5" = "alias.shadowfail2" ]; then
	exit 1
fi
exec "$REALGIT4" "\$@"
FAKEGIT4
chmod +x "$FAILHOME2/fakebin/git"
SHADOWFAIL_RESULT="$(
	HOME="$FAILHOME2"
	export HOME
	GIT_CONFIG_GLOBAL="$FAILHOME2/.gitconfig"
	export GIT_CONFIG_GLOBAL
	GIT_CONFIG_SYSTEM=/dev/null
	export GIT_CONFIG_SYSTEM
	GIT_CEILING_DIRECTORIES="$FAILHOME2"
	export GIT_CEILING_DIRECTORIES
	cd "$FAILHOME2"
	git config --global user.email t@t
	git config --global user.name t
	git config --global --add include.path "$AF4"
	git config --global alias.shadowfail2 '!echo sombra-obsoleta'
	st=0
	err="$(PATH="$FAILHOME2/fakebin:$PATH" "$SCRIPT" --rename shadowfail2 shadowfail3 2>&1 >/dev/null)" || st=$?
	printf 'exit=%s err=%s' "$st" "$err"
)"
check "--rename com falha na limpeza da sombra --global: exit code 1, não 0" \
	"exit=1" "$(printf '%s' "$SHADOWFAIL_RESULT" | grep -o '^exit=[0-9]*')"
check "--rename com falha na limpeza da sombra --global: mensagem aponta --global, não 'outra fonte'" \
	"exit=1 err=Aviso: a remoção de 'shadowfail2' do git config --global falhou — 'shadowfail2' e 'shadowfail3' agora coexistem. Resolva manualmente (git config --global --unset-all alias.shadowfail2)." \
	"$SHADOWFAIL_RESULT"

# Achado GRAVE na 18ª revisão (2): mesma classe de bug dos achados 2/3 da
# 17ª revisão (--rename), mas em create: se a limpeza OPORTUNISTA da
# sombra no --global falhar de verdade (lock/permissão) ao criar um
# alias no arquivo incluído, o script anunciava sucesso puro e simples
# ("Alias '<nome>' gravado em <arquivo>.") sem avisar que a cópia antiga
# no --global continua lá — e, por vir depois do [include] no
# ~/.gitconfig, ela GANHA da nova entrada na resolução mesclada do git:
# o alias recém-criado fica silenciosamente sombreado pelo antigo.
FAILHOME3="$SB/createfailhome"
mkdir -p "$FAILHOME3/fakebin"
AF5="$FAILHOME3/aliases.gitconfig"
printf '%s\n' \
	'# Gerado por: git alias --export' \
	'# Nao edite a mao; rode o comando novamente para atualizar.' \
	'' \
	'[alias]' >"$AF5"
REALGIT5="$(command -v git)"
cat >"$FAILHOME3/fakebin/git" <<FAKEGIT5
#!/bin/sh
# Idem ao fake da --rename acima: a limpeza da sombra no --global agora é
# "git config --file <arquivo global> --unset-all" (global_unset_all sobre
# global_backing_files), não "git config --global --unset-all".
if [ "\$1" = "config" ] && [ "\$2" = "--file" ] && [ "\$3" = "$FAILHOME3/.gitconfig" ] && [ "\$4" = "--unset-all" ] && [ "\$5" = "alias.createshadow" ]; then
	exit 1
fi
exec "$REALGIT5" "\$@"
FAKEGIT5
chmod +x "$FAILHOME3/fakebin/git"
CREATEFAIL_RESULT="$(
	HOME="$FAILHOME3"
	export HOME
	GIT_CONFIG_GLOBAL="$FAILHOME3/.gitconfig"
	export GIT_CONFIG_GLOBAL
	GIT_CONFIG_SYSTEM=/dev/null
	export GIT_CONFIG_SYSTEM
	GIT_CEILING_DIRECTORIES="$FAILHOME3"
	export GIT_CEILING_DIRECTORIES
	cd "$FAILHOME3"
	git config --global user.email t@t
	git config --global user.name t
	git config --global --add include.path "$AF5"
	git config --global alias.createshadow '!echo sombra-antiga'
	st=0
	out="$(PATH="$FAILHOME3/fakebin:$PATH" "$SCRIPT" createshadow '!echo novo' 2>&1)" || st=$?
	efetivo="$(git config --get alias.createshadow 2>/dev/null || true)"
	printf 'exit=%s efetivo=%s\n%s' "$st" "$efetivo" "$out"
)"
check "create com falha na limpeza da sombra --global: git ainda resolveria a cópia antiga (não a nova)" \
	"exit=1 efetivo=!echo sombra-antiga" "$(printf '%s' "$CREATEFAIL_RESULT" | head -n1)"
check "create com falha na limpeza da sombra --global: avisa que o novo alias ficou sombreado" \
	"sim" "$(printf '%s' "$CREATEFAIL_RESULT" | tail -n +2 | grep -qi "Aviso.*sombr\|sombr.*Aviso" && echo sim || echo nao)"

# Achado GRAVE na 18ª revisão (3): --unset conflava "nunca existiu em
# nenhuma camada" com "existe, mas a remoção falhou de verdade" (lock,
# permissão) na MESMA mensagem genérica ("não existe ou já foi
# removido") — diferente de --rename, que ganhou old_still_at_origin/
# shadow_still_at_global para essa exata distinção nas rodadas 16/17.
# Um usuário vendo essa mensagem acredita que o alias já se foi, quando
# na verdade ele nunca se moveu.
FAILHOME4="$SB/unsetfailhome"
mkdir -p "$FAILHOME4/fakebin"
AF6="$FAILHOME4/aliases.gitconfig"
printf '%s\n' \
	'# Gerado por: git alias --export' \
	'# Nao edite a mao; rode o comando novamente para atualizar.' \
	'' \
	'[alias]' \
	'	unsetfail = !echo intacto' >"$AF6"
REALGIT6="$(command -v git)"
cat >"$FAILHOME4/fakebin/git" <<FAKEGIT6
#!/bin/sh
if [ "\$1" = "config" ] && [ "\$2" = "--file" ] && [ "\$4" = "--unset-all" ] && [ "\$5" = "alias.unsetfail" ]; then
	exit 1
fi
exec "$REALGIT6" "\$@"
FAKEGIT6
chmod +x "$FAILHOME4/fakebin/git"
UNSETFAIL_RESULT="$(
	HOME="$FAILHOME4"
	export HOME
	GIT_CONFIG_GLOBAL="$FAILHOME4/.gitconfig"
	export GIT_CONFIG_GLOBAL
	GIT_CONFIG_SYSTEM=/dev/null
	export GIT_CONFIG_SYSTEM
	GIT_CEILING_DIRECTORIES="$FAILHOME4"
	export GIT_CEILING_DIRECTORIES
	cd "$FAILHOME4"
	git config --global user.email t@t
	git config --global user.name t
	git config --global --add include.path "$AF6"
	st=0
	err="$(PATH="$FAILHOME4/fakebin:$PATH" "$SCRIPT" --unset unsetfail 2>&1 >/dev/null)" || st=$?
	ainda="$(git config --get alias.unsetfail 2>/dev/null || true)"
	printf 'exit=%s ainda=%s\n%s' "$st" "$ainda" "$err"
)"
check "--unset com falha genuína na remoção: alias continua intacto (não some)" \
	"exit=1 ainda=!echo intacto" "$(printf '%s' "$UNSETFAIL_RESULT" | head -n1)"
check "--unset com falha genuína na remoção: mensagem não diz 'não existe' (seria falso)" \
	"nao" "$(printf '%s' "$UNSETFAIL_RESULT" | tail -n +2 | grep -qi "não existe" && echo sim || echo nao)"

# --- F6: aviso (não recusa) ao sombrear um comando builtin do Git ----------
errout="$("$SCRIPT" status '!echo x' 2>&1 >/dev/null)"
check "criar alias que sombreia um builtin do Git avisa" \
	"sim" "$(printf '%s' "$errout" | grep -qF "'status'" && echo sim || echo nao)"
check "criar alias que sombreia um builtin: grava mesmo assim" \
	"status = !echo x" "$("$SCRIPT" status)"

# Achado na 6ª revisão: warn_if_builtin_shadow comparava com sensibilidade a
# maiúsculas — corrigido para normalizar antes de comparar. Essa
# normalização continua no código como defesa em profundidade (por
# exemplo, se um futuro chamador não passar por validate_alias_name
# antes), mas deixou de ser exercitável por um nome digitado com
# maiúscula: a 8ª revisão fechou a criação para exigir minúscula (git não
# preserva caixa em nenhuma enumeração — ver o teste "criar alias com
# maiúscula é recusado" acima), então todo nome que chega em
# warn_if_builtin_shadow por um caminho do script já está garantidamente
# em minúsculas antes disso.

# Achado na 6ª revisão: a interceptação de "help" (mostrar ajuda sem um
# segundo argumento) comparava só a forma minúscula, inconsistente com
# validate_alias_name (que já trata "help" como reservado
# case-insensitive). "git alias HELP" (maiúsculas, um argumento só) caía
# na consulta normal em vez de mostrar a ajuda.
check "'git alias HELP' (maiúsculas) mostra a ajuda, como 'help'" \
	"Sintaxe de uso:" "$("$SCRIPT" HELP | head -1)"

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
