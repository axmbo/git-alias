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
# Refere o global do sandbox pelo caminho literal ($SB/.gitconfig, fixado no
# topo), não por "$GIT_CONFIG_GLOBAL": os blocos de simulação de falha acima
# reatribuem essa variável dentro de $(...), e lê-la aqui faria o shellcheck
# apontar SC2030/SC2031 (a modificação em subshell é intencional e local a
# cada bloco, mas o par assign-em-subshell / leitura-no-escopo-externo é o
# gatilho do aviso).
check "include.path relativo: nada foi para o ~/.gitconfig cru" \
	"" "$(git config --file "$SB/.gitconfig" alias.relat 2>/dev/null || true)"

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

# =========================================================================
# git alias --doctor (F3): relatório read-only de diagnóstico da instalação.
# Cada teste roda num HOME/GIT_CONFIG_GLOBAL isolado (não herda os aliases e
# o include.path acumulados acima) — mesmo idioma dos testes de fallback XDG.
# =========================================================================

# --- guarda de uso -------------------------------------------------------
D_USAGE="$(
	DH="$SB/doctor-usage"
	mkdir -p "$DH"
	HOME="$DH"
	GIT_CONFIG_GLOBAL="$DH/.gitconfig"
	export HOME GIT_CONFIG_GLOBAL
	cd "$DH"
	out="$("$SCRIPT" --doctor 2>&1)" || true
	notfound="$(printf '%s' "$out" | grep -qi "não foi encontrado" && echo sim || echo nao)"
	st=0
	msg="$("$SCRIPT" --doctor argumento-extra 2>&1 >/dev/null)" || st=$?
	printf 'notfound=%s st=%s msg=%s' "$notfound" "$st" "$msg"
)"
check "--doctor: reconhecido como subcomando e recusa argumento extra (exit 2)" \
	"notfound=nao st=2 msg=Erro: uso: git alias --doctor" \
	"$D_USAGE"

# Diretório do próprio script — posto no PATH nos testes de seção abaixo para
# que a seção "[git/bin no PATH]" reporte "ok:" e não contamine o exit code
# da seção que está sendo exercitada.
DSCRIPT_DIR="$(dirname "$SCRIPT")"

# --- [arquivo de aliases versionado]: sem include.path -------------------
D_NOINC="$(
	DH="$SB/doctor-noinc"
	mkdir -p "$DH"
	HOME="$DH"
	GIT_CONFIG_GLOBAL="$DH/.gitconfig"
	export HOME GIT_CONFIG_GLOBAL
	cd "$DH"
	st=0
	out="$(PATH="$DSCRIPT_DIR:$PATH" "$SCRIPT" --doctor)" || st=$?
	printf 'st=%s\n%s' "$st" "$out"
)"
check "--doctor sem include.path: seção [arquivo de aliases versionado] presente" \
	"sim" "$(printf '%s\n' "$D_NOINC" | grep -qF '[arquivo de aliases versionado]' && echo sim || echo nao)"
check "--doctor sem include.path: aviso citando include.path" \
	"sim" "$(printf '%s\n' "$D_NOINC" | grep -Eq 'aviso:.*include\.path|include\.path.*aviso:' && echo sim || echo nao)"
check "--doctor sem include.path (git/bin no PATH, sem alias.alias legado): exit 0" \
	"st=0" "$(printf '%s\n' "$D_NOINC" | grep -E '^st=')"

# --- [arquivo de aliases versionado]: arquivo detectado -----------------
D_DETECT="$(
	DH="$SB/doctor-detect"
	mkdir -p "$DH"
	HOME="$DH"
	GIT_CONFIG_GLOBAL="$DH/.gitconfig"
	export HOME GIT_CONFIG_GLOBAL
	cd "$DH"
	AFD="$DH/aliases.gitconfig"
	printf '%s\n' \
		'# Gerado por: git alias --export' \
		'# Nao edite a mao; rode o comando novamente para atualizar.' \
		'# Formato: 1' \
		'' \
		'[alias]' \
		'	co = checkout' >"$AFD"
	git config --global --add include.path "$AFD"
	st=0
	out="$(PATH="$DSCRIPT_DIR:$PATH" "$SCRIPT" --doctor)" || st=$?
	printf 'st=%s\n%s' "$st" "$out"
)"
check "--doctor com arquivo detectado: linha ok: traz o caminho do arquivo" \
	"sim" "$(printf '%s\n' "$D_DETECT" | grep -F "$SB/doctor-detect/aliases.gitconfig" | grep -q 'ok:' && echo sim || echo nao)"
check "--doctor com arquivo detectado: a lista de entradas é rotulada como include.path" \
	"sim" "$(printf '%s\n' "$D_DETECT" | sed -n '/\[arquivo de aliases versionado\]/,/^\[/p' | grep -qi 'include\.path' && echo sim || echo nao)"
check "--doctor com arquivo detectado: aponta o cabeçalho como motivo da detecção" \
	"sim" "$(printf '%s\n' "$D_DETECT" | grep -qF '# Gerado por: git alias --export' && echo sim || echo nao)"
check "--doctor com arquivo detectado: exit 0" \
	"st=0" "$(printf '%s\n' "$D_DETECT" | grep -E '^st=')"

# --- [arquivo de aliases versionado]: include.path aponta p/ arquivo sem
#     o cabeçalho (existe, mas não é reconhecido) --------------------------
D_NOHDR="$(
	DH="$SB/doctor-nohdr"
	mkdir -p "$DH"
	HOME="$DH"
	GIT_CONFIG_GLOBAL="$DH/.gitconfig"
	export HOME GIT_CONFIG_GLOBAL
	cd "$DH"
	PLAINF="$DH/plain.gitconfig"
	printf '%s\n' '[alias]' '	co = checkout' >"$PLAINF"
	git config --global --add include.path "$PLAINF"
	st=0
	out="$(PATH="$DSCRIPT_DIR:$PATH" "$SCRIPT" --doctor)" || st=$?
	printf 'st=%s\n%s' "$st" "$out"
)"
check "--doctor: arquivo de include.path que existe mas não tem o cabeçalho é sinalizado" \
	"sim" "$(printf '%s\n' "$D_NOHDR" | grep -qi 'sem o cabeçalho' && echo sim || echo nao)"
check "--doctor: arquivo sem cabeçalho — a linha cita o caminho da entrada" \
	"sim" "$(printf '%s\n' "$D_NOHDR" | grep -F "$SB/doctor-nohdr/plain.gitconfig" | grep -qv 'ok:' && echo sim || echo nao)"
check "--doctor: arquivo sem cabeçalho — sem erro, só aviso (exit 0)" \
	"st=0" "$(printf '%s\n' "$D_NOHDR" | grep -E '^st=')"

# --- [arquivo de aliases versionado]: entrada inexistente e classificação
#     do token (absoluto / relativo a HOME / cadeia de symlinks) ----------
D_CLASSIFY="$(
	DH="$SB/doctor-classify"
	mkdir -p "$DH/sub"
	HOME="$DH"
	GIT_CONFIG_GLOBAL="$DH/.gitconfig"
	export HOME GIT_CONFIG_GLOBAL
	cd "$DH"
	# token relativo, apontando p/ um caminho que não existe
	git config --global --add include.path "nao-existe/aliases.gitconfig"
	st=0
	out="$(PATH="$DSCRIPT_DIR:$PATH" "$SCRIPT" --doctor)" || st=$?
	printf 'st=%s\n%s' "$st" "$out"
)"
check "--doctor: entrada de include.path inexistente é marcada 'NÃO existe'" \
	"sim" "$(printf '%s\n' "$D_CLASSIFY" | grep -F 'nao-existe/aliases.gitconfig' | grep -q 'NÃO existe' && echo sim || echo nao)"
check "--doctor: token relativo é classificado como relativo a HOME" \
	"sim" "$(printf '%s\n' "$D_CLASSIFY" | grep -F 'nao-existe/aliases.gitconfig' | grep -q 'relativo a HOME' && echo sim || echo nao)"

# cadeia de links: elo2 -> elo1 -> alvo real (arquivo de aliases de verdade).
# Diretório sem a palavra "symlink" no nome, para o grep abaixo não casar o
# próprio caminho do sandbox.
D_SLINK="$(
	DH="$SB/doctor-cadeia"
	mkdir -p "$DH/real"
	HOME="$DH"
	GIT_CONFIG_GLOBAL="$DH/.gitconfig"
	export HOME GIT_CONFIG_GLOBAL
	cd "$DH"
	REALF="$DH/real/aliases.gitconfig"
	printf '%s\n' \
		'# Gerado por: git alias --export' \
		'# x' \
		'# Formato: 1' \
		'' \
		'[alias]' >"$REALF"
	ln -s "$REALF" "$DH/elo1"
	ln -s "$DH/elo1" "$DH/elo2"
	git config --global --add include.path "$DH/elo2"
	st=0
	out="$(PATH="$DSCRIPT_DIR:$PATH" "$SCRIPT" --doctor)" || st=$?
	printf 'st=%s\n%s' "$st" "$out"
)"
check "--doctor: detectado via cadeia de symlinks — exit 0" \
	"st=0" "$(printf '%s\n' "$D_SLINK" | grep -E '^st=')"
check "--doctor: detectado via symlink — aponta o arquivo real ao fim da cadeia" \
	"sim" "$(printf '%s\n' "$D_SLINK" | grep -qF "$SB/doctor-cadeia/real/aliases.gitconfig" && echo sim || echo nao)"
check "--doctor: detectado via symlink — sinaliza a travessia de symlink" \
	"sim" "$(printf '%s\n' "$D_SLINK" | grep -qi 'via symlink' && echo sim || echo nao)"

# --- [git config --global: aliases fora do arquivo]: nada fora do arquivo
D_GCLEAN="$(
	DH="$SB/doctor-gclean"
	mkdir -p "$DH"
	HOME="$DH"
	GIT_CONFIG_GLOBAL="$DH/.gitconfig"
	export HOME GIT_CONFIG_GLOBAL
	cd "$DH"
	AFD="$DH/aliases.gitconfig"
	printf '%s\n' \
		'# Gerado por: git alias --export' \
		'# x' \
		'# Formato: 1' \
		'' \
		'[alias]' \
		'	co = checkout' >"$AFD"
	git config --global --add include.path "$AFD"
	st=0
	out="$(PATH="$DSCRIPT_DIR:$PATH" "$SCRIPT" --doctor)" || st=$?
	printf 'st=%s\n%s' "$st" "$out"
)"
check "--doctor: seção [git config --global: aliases fora do arquivo] presente" \
	"sim" "$(printf '%s\n' "$D_GCLEAN" | grep -qF 'aliases fora do arquivo' && echo sim || echo nao)"
check "--doctor: sem aliases no --global fora do arquivo — linha ok:" \
	"sim" "$(printf '%s\n' "$D_GCLEAN" | grep -E 'ok:.*(fora do arquivo|nenhum alias)' >/dev/null && echo sim || echo nao)"
check "--doctor: instalação limpa (arquivo detectado, nada solto no --global): exit 0" \
	"st=0" "$(printf '%s\n' "$D_GCLEAN" | grep -E '^st=')"

# --- [git config --global: aliases fora do arquivo]: com aliases soltos --
D_GLOOSE="$(
	DH="$SB/doctor-gloose"
	mkdir -p "$DH"
	HOME="$DH"
	GIT_CONFIG_GLOBAL="$DH/.gitconfig"
	export HOME GIT_CONFIG_GLOBAL
	cd "$DH"
	AFD="$DH/aliases.gitconfig"
	printf '%s\n' \
		'# Gerado por: git alias --export' \
		'# x' \
		'# Formato: 1' \
		'' \
		'[alias]' \
		'	co = checkout' >"$AFD"
	git config --global --add include.path "$AFD"
	git config --global alias.ci commit
	git config --global alias.st status
	git config --global alias.alias '!git-alias'
	st=0
	out="$(PATH="$DSCRIPT_DIR:$PATH" "$SCRIPT" --doctor)" || st=$?
	# só a seção 2, p/ os greps não pegarem "ci"/"st" de outras linhas
	sec="$(printf '%s\n' "$out" | sed -n '/aliases fora do arquivo/,/^\[/p')"
	printf 'st=%s\n%s' "$st" "$sec"
)"
check "--doctor: aliases soltos no --global — linha aviso:" \
	"sim" "$(printf '%s\n' "$D_GLOOSE" | grep -q 'aviso:' && echo sim || echo nao)"
check "--doctor: aliases soltos no --global — lista 'ci' como item" \
	"sim" "$(printf '%s\n' "$D_GLOOSE" | grep -Eq '^ *- ci( |$)' && echo sim || echo nao)"
check "--doctor: aliases soltos no --global — lista 'st' como item" \
	"sim" "$(printf '%s\n' "$D_GLOOSE" | grep -Eq '^ *- st( |$)' && echo sim || echo nao)"
check "--doctor: aliases soltos no --global — NÃO lista o dispatcher 'alias' como item" \
	"nao" "$(printf '%s\n' "$D_GLOOSE" | grep -Eq '^ *- alias( |$)' && echo sim || echo nao)"
check "--doctor: aliases soltos no --global são aviso, não erro (sem 'erro:' na seção)" \
	"nao" "$(printf '%s\n' "$D_GLOOSE" | grep -q 'erro:' && echo sim || echo nao)"

# --- seção 2: distingue sombra (também no arquivo) de não-versionado -----
D_GSHADOW="$(
	DH="$SB/doctor-gshadow"
	mkdir -p "$DH"
	HOME="$DH"
	GIT_CONFIG_GLOBAL="$DH/.gitconfig"
	export HOME GIT_CONFIG_GLOBAL
	cd "$DH"
	AFD="$DH/aliases.gitconfig"
	printf '%s\n' \
		'# Gerado por: git alias --export' \
		'# x' \
		'# Formato: 1' \
		'' \
		'[alias]' \
		'	co = checkout' \
		'	dup = !echo do-arquivo' >"$AFD"
	git config --global --add include.path "$AFD"
	git config --global alias.dup '!echo do-global'
	git config --global alias.solto '!echo solto'
	st=0
	out="$(PATH="$DSCRIPT_DIR:$PATH" "$SCRIPT" --doctor)" || st=$?
	sec="$(printf '%s\n' "$out" | sed -n '/aliases fora do arquivo/,/^\[/p')"
	printf 'st=%s\n%s' "$st" "$sec"
)"
check "--doctor seção 2: 'dup' (também no arquivo) é marcado como sombra" \
	"sim" "$(printf '%s\n' "$D_GSHADOW" | grep -E '^ *- dup( |$)' | grep -qi 'sombra\|também no arquivo' && echo sim || echo nao)"
check "--doctor seção 2: 'solto' (só no --global) é marcado como não versionado" \
	"sim" "$(printf '%s\n' "$D_GSHADOW" | grep -E '^ *- solto( |$)' | grep -qi 'não versionado' && echo sim || echo nao)"
check "--doctor seção 2: sombra/não-versionado ainda são aviso (exit 0)" \
	"st=0" "$(printf '%s\n' "$D_GSHADOW" | grep -E '^st=')"

# --- [git/bin no PATH]: diretório do script no PATH ---------------------
D_PATH_OK="$(
	DH="$SB/doctor-pathok"
	mkdir -p "$DH"
	HOME="$DH"
	GIT_CONFIG_GLOBAL="$DH/.gitconfig"
	export HOME GIT_CONFIG_GLOBAL
	cd "$DH"
	AFD="$DH/aliases.gitconfig"
	printf '%s\n' '# Gerado por: git alias --export' '# x' '# Formato: 1' '' '[alias]' >"$AFD"
	git config --global --add include.path "$AFD"
	st=0
	out="$(PATH="$DSCRIPT_DIR:$PATH" "$SCRIPT" --doctor)" || st=$?
	sec="$(printf '%s\n' "$out" | sed -n '/\[git\/bin no PATH\]/,/^\[/p')"
	printf 'st=%s\n%s' "$st" "$sec"
)"
check "--doctor: seção [git/bin no PATH] presente" \
	"sim" "$(printf '%s\n' "$D_PATH_OK" | grep -qF '[git/bin no PATH]' && echo sim || echo nao)"
check "--doctor: diretório do script no PATH — linha ok: com o caminho" \
	"sim" "$(printf '%s\n' "$D_PATH_OK" | grep 'ok:' | grep -qF "$DSCRIPT_DIR" && echo sim || echo nao)"
check "--doctor: diretório do script no PATH — exit 0" \
	"st=0" "$(printf '%s\n' "$D_PATH_OK" | grep -E '^st=')"

# --- [git/bin no PATH]: diretório do script FORA do PATH ---------------
# PATH depurado do dir do script (o ambiente de quem roda a suíte pode
# tê-lo — install.sh instrui isso — mas o CI não): teste determinístico
# nos dois. git continua acessível pelos demais componentes.
D_PATH_ERR="$(
	DH="$SB/doctor-patherr"
	mkdir -p "$DH"
	HOME="$DH"
	GIT_CONFIG_GLOBAL="$DH/.gitconfig"
	export HOME GIT_CONFIG_GLOBAL
	cd "$DH"
	AFD="$DH/aliases.gitconfig"
	printf '%s\n' '# Gerado por: git alias --export' '# x' '# Formato: 1' '' '[alias]' >"$AFD"
	git config --global --add include.path "$AFD"
	CLEANPATH="$(printf '%s\n' "$PATH" | tr ':' '\n' | grep -vxF "$DSCRIPT_DIR" | paste -sd: -)"
	st=0
	out="$(PATH="$CLEANPATH" "$SCRIPT" --doctor)" || st=$?
	sec="$(printf '%s\n' "$out" | sed -n '/\[git\/bin no PATH\]/,/^\[/p')"
	printf 'st=%s\n%s' "$st" "$sec"
)"
check "--doctor: script fora do PATH — linha erro:" \
	"sim" "$(printf '%s\n' "$D_PATH_ERR" | grep -Eq 'erro:.*PATH|não está no PATH' && echo sim || echo nao)"
check "--doctor: script fora do PATH — exit 1" \
	"st=1" "$(printf '%s\n' "$D_PATH_ERR" | grep -E '^st=')"

# --- [git/bin no PATH]: script alcançável por symlink dentro de um dir do
#     PATH (layout stow/dotbot) — instalação VÁLIDA, não pode dar erro ----
# ~/bin/git-alias -> <script real>, com ~/bin no PATH e o dir real FORA
# dele. "git alias" funciona; --doctor não pode alegar que está quebrado.
D_PATH_SYMLINK="$(
	DH="$SB/doctor-pathsym"
	mkdir -p "$DH/bin"
	HOME="$DH"
	GIT_CONFIG_GLOBAL="$DH/.gitconfig"
	export HOME GIT_CONFIG_GLOBAL
	cd "$DH"
	AFD="$DH/aliases.gitconfig"
	printf '%s\n' '# Gerado por: git alias --export' '# x' '# Formato: 1' '' '[alias]' >"$AFD"
	git config --global --add include.path "$AFD"
	ln -s "$SCRIPT" "$DH/bin/git-alias"
	CLEANPATH="$(printf '%s\n' "$PATH" | tr ':' '\n' | grep -vxF "$DSCRIPT_DIR" | paste -sd: -)"
	# (a) invocado via o symlink no PATH, como o Git despacharia
	st=0
	sa="$(PATH="$DH/bin:$CLEANPATH" git-alias --doctor)" || st=$?
	via_sym="$(printf '%s\n' "$sa" | sed -n '/\[git\/bin no PATH\]/,/^\[/p' | grep -q 'ok:' && echo ok || echo nao)"
	# (b) invocado pelo caminho real, sendo o symlink no PATH o setup real
	st2=0
	sb="$(PATH="$DH/bin:$CLEANPATH" "$SCRIPT" --doctor)" || st2=$?
	via_real="$(printf '%s\n' "$sb" | sed -n '/\[git\/bin no PATH\]/,/^\[/p' | grep -q 'ok:' && echo ok || echo nao)"
	printf 'st=%s sym=%s st2=%s real=%s' "$st" "$via_sym" "$st2" "$via_real"
)"
check "--doctor: script alcançável por symlink num dir do PATH — ok, exit 0 (nos dois modos de invocação)" \
	"st=0 sym=ok st2=0 real=ok" "$D_PATH_SYMLINK"

# --- [alias.alias legado]: sem alias.alias -----------------------------
D_AA_OK="$(
	DH="$SB/doctor-aaok"
	mkdir -p "$DH"
	HOME="$DH"
	GIT_CONFIG_GLOBAL="$DH/.gitconfig"
	export HOME GIT_CONFIG_GLOBAL
	cd "$DH"
	AFD="$DH/aliases.gitconfig"
	printf '%s\n' '# Gerado por: git alias --export' '# x' '# Formato: 1' '' '[alias]' >"$AFD"
	git config --global --add include.path "$AFD"
	st=0
	out="$(PATH="$DSCRIPT_DIR:$PATH" "$SCRIPT" --doctor)" || st=$?
	sec="$(printf '%s\n' "$out" | sed -n '/\[alias\.alias legado\]/,$p')"
	printf 'st=%s\n%s' "$st" "$sec"
)"
check "--doctor: seção [alias.alias legado] presente" \
	"sim" "$(printf '%s\n' "$D_AA_OK" | grep -qF '[alias.alias legado]' && echo sim || echo nao)"
check "--doctor: sem alias.alias — linha ok:" \
	"sim" "$(printf '%s\n' "$D_AA_OK" | grep -q 'ok:' && echo sim || echo nao)"
check "--doctor: instalação sã completa — exit 0" \
	"st=0" "$(printf '%s\n' "$D_AA_OK" | grep -E '^st=')"

# --- [alias.alias legado]: alias.alias presente ----------------------
D_AA_ERR="$(
	DH="$SB/doctor-aaerr"
	mkdir -p "$DH"
	HOME="$DH"
	GIT_CONFIG_GLOBAL="$DH/.gitconfig"
	export HOME GIT_CONFIG_GLOBAL
	cd "$DH"
	AFD="$DH/aliases.gitconfig"
	printf '%s\n' '# Gerado por: git alias --export' '# x' '# Formato: 1' '' '[alias]' >"$AFD"
	git config --global --add include.path "$AFD"
	git config --global alias.alias '!f() { echo velho; }; f'
	st=0
	out="$(PATH="$DSCRIPT_DIR:$PATH" "$SCRIPT" --doctor)" || st=$?
	sec="$(printf '%s\n' "$out" | sed -n '/\[alias\.alias legado\]/,$p')"
	printf 'st=%s\n%s' "$st" "$sec"
)"
check "--doctor: alias.alias presente — linha erro:" \
	"sim" "$(printf '%s\n' "$D_AA_ERR" | grep -q 'erro:' && echo sim || echo nao)"
check "--doctor: alias.alias presente — instrui a remoção" \
	"sim" "$(printf '%s\n' "$D_AA_ERR" | grep -qF 'git config --global --unset alias.alias' && echo sim || echo nao)"
check "--doctor: alias.alias presente — exit 1" \
	"st=1" "$(printf '%s\n' "$D_AA_ERR" | grep -E '^st=')"

# --- vários erros ao mesmo tempo: exit 1 (nunca 2), todos reportados ----
D_MULTI="$(
	DH="$SB/doctor-multi"
	mkdir -p "$DH"
	HOME="$DH"
	GIT_CONFIG_GLOBAL="$DH/.gitconfig"
	export HOME GIT_CONFIG_GLOBAL
	cd "$DH"
	AFD="$DH/aliases.gitconfig"
	printf '%s\n' '# Gerado por: git alias --export' '# x' '# Formato: 1' '' '[alias]' >"$AFD"
	git config --global --add include.path "$AFD"
	git config --global alias.alias '!git-alias'
	CLEANPATH="$(printf '%s\n' "$PATH" | tr ':' '\n' | grep -vxF "$DSCRIPT_DIR" | paste -sd: -)"
	st=0
	out="$(PATH="$CLEANPATH" "$SCRIPT" --doctor)" || st=$?
	nerr="$(printf '%s\n' "$out" | grep -c 'erro:')"
	printf 'st=%s nerr=%s' "$st" "$nerr"
)"
check "--doctor com erro de PATH e de alias.alias: exit 1 (não 2), dois 'erro:'" \
	"st=1 nerr=2" "$D_MULTI"

# --- read-only: --doctor não altera arquivo de aliases nem o git config -
D_READONLY="$(
	DH="$SB/doctor-ro"
	mkdir -p "$DH"
	HOME="$DH"
	GIT_CONFIG_GLOBAL="$DH/.gitconfig"
	export HOME GIT_CONFIG_GLOBAL
	cd "$DH"
	AFD="$DH/aliases.gitconfig"
	printf '%s\n' \
		'# Gerado por: git alias --export' '# x' '# Formato: 1' '' \
		'[alias]' '	co = checkout' >"$AFD"
	git config --global --add include.path "$AFD"
	git config --global alias.solto '!echo x'
	git config --global alias.alias '!git-alias'
	before_af="$(cat "$AFD")"
	before_gc="$(cat "$DH/.gitconfig")"
	PATH="$DSCRIPT_DIR:$PATH" "$SCRIPT" --doctor >/dev/null 2>&1 || true
	af_igual="$([ "$before_af" = "$(cat "$AFD")" ] && echo sim || echo nao)"
	gc_igual="$([ "$before_gc" = "$(cat "$DH/.gitconfig")" ] && echo sim || echo nao)"
	printf 'af=%s gc=%s' "$af_igual" "$gc_igual"
)"
check "--doctor é read-only: não toca no arquivo de aliases nem no ~/.gitconfig" \
	"af=sim gc=sim" "$D_READONLY"

# =========================================================================
# git alias --import (F2): funde as entradas alias.* de uma fonte gitconfig
# na seção [alias] do arquivo de aliases versionado detectado, sem destruir
# o que já está lá (o inverso não-destrutivo do --export). Cada teste roda
# num HOME/GIT_CONFIG_GLOBAL isolado, mesmo idioma dos testes de --doctor.
# =========================================================================

# --- funde aliases novos, preservando os que já existem ------------------
I_BASIC="$(
	IH="$SB/import-basic"
	mkdir -p "$IH"
	HOME="$IH"
	GIT_CONFIG_GLOBAL="$IH/.gitconfig"
	export HOME GIT_CONFIG_GLOBAL
	cd "$IH"
	AFI="$IH/aliases.gitconfig"
	printf '%s\n' \
		'# Gerado por: git alias --export' \
		'# Nao edite a mao; rode o comando novamente para atualizar.' \
		'# Formato: 1' \
		'' \
		'[alias]' \
		'	zz = !echo zz' >"$AFI"
	git config --global --add include.path "$AFI"
	SRC="$IH/fonte.gitconfig"
	printf '%s\n' '[alias]' '	co = checkout' '	ci = commit' >"$SRC"
	st=0
	out="$("$SCRIPT" --import "$SRC" 2>/dev/null)" || st=$?
	printf 'exit=%s\n' "$st"
	printf 'nomes=%s\n' "$(git config --file "$AFI" --name-only --get-regexp '^alias\.' | sed 's/^alias\.//' | LC_ALL=C sort | paste -sd' ' -)"
	printf 'hdr=%s\n' "$(head -n1 "$AFI")"
	printf 'zzval=%s\n' "$(git config --file "$AFI" --get alias.zz)"
	printf 'coval=%s\n' "$(git config --file "$AFI" --get alias.co)"
	printf 'report=%s\n' "$out"
)"
check "--import: aliases novos entram no arquivo versionado, ordenados, junto dos que já havia" \
	"nomes=ci co zz" "$(printf '%s\n' "$I_BASIC" | grep '^nomes=')"
check "--import: exit 0" \
	"exit=0" "$(printf '%s\n' "$I_BASIC" | grep '^exit=')"
check "--import: cabeçalho do arquivo preservado" \
	"hdr=# Gerado por: git alias --export" "$(printf '%s\n' "$I_BASIC" | grep '^hdr=')"
check "--import: alias pré-existente não é tocado" \
	"zzval=!echo zz" "$(printf '%s\n' "$I_BASIC" | grep '^zzval=')"
check "--import: valor do alias importado bate com a fonte" \
	"coval=checkout" "$(printf '%s\n' "$I_BASIC" | grep '^coval=')"
check "--import: relatório em stdout conta os importados" \
	"report=2 importados" "$(printf '%s\n' "$I_BASIC" | grep '^report=')"

# --- colisão de valor: pula e relata; sem --overwrite não sobrescreve -----
I_COLLIDE="$(
	IH="$SB/import-collide"
	mkdir -p "$IH"
	HOME="$IH"
	GIT_CONFIG_GLOBAL="$IH/.gitconfig"
	export HOME GIT_CONFIG_GLOBAL
	cd "$IH"
	AFI="$IH/aliases.gitconfig"
	printf '%s\n' \
		'# Gerado por: git alias --export' \
		'# Nao edite a mao; rode o comando novamente para atualizar.' \
		'# Formato: 1' \
		'' \
		'[alias]' \
		'	co = checkout' \
		'	st = status' >"$AFI"
	git config --global --add include.path "$AFI"
	SRC="$IH/fonte.gitconfig"
	printf '%s\n' '[alias]' '	co = checkout -q' '	st = status' '	ci = commit' >"$SRC"
	st=0
	out="$("$SCRIPT" --import "$SRC" 2>/dev/null)" || st=$?
	printf 'exit=%s\n' "$st"
	printf 'coval=%s\n' "$(git config --file "$AFI" --get alias.co)"
	printf 'cival=%s\n' "$(git config --file "$AFI" --get alias.ci)"
	printf 'report=%s\n' "$out"
)"
check "--import: colisão de valor sem --overwrite não sobrescreve o alias do arquivo" \
	"coval=checkout" "$(printf '%s\n' "$I_COLLIDE" | grep '^coval=')"
check "--import: aliases novos entram mesmo havendo colisão em outro nome" \
	"cival=commit" "$(printf '%s\n' "$I_COLLIDE" | grep '^cival=')"
check "--import: relatório lista os importados e a colisão pulada" \
	"report=1 importado; 1 já existente com valor diferente: co (use --overwrite)" \
	"$(printf '%s\n' "$I_COLLIDE" | grep '^report=')"
check "--import: colisão pulada não é falha (exit 0)" \
	"exit=0" "$(printf '%s\n' "$I_COLLIDE" | grep '^exit=')"

# --- valor idêntico dos dois lados: no-op silencioso, arquivo intacto ----
I_NOOP="$(
	IH="$SB/import-noop"
	mkdir -p "$IH"
	HOME="$IH"
	GIT_CONFIG_GLOBAL="$IH/.gitconfig"
	export HOME GIT_CONFIG_GLOBAL
	cd "$IH"
	AFI="$IH/aliases.gitconfig"
	printf '%s\n' \
		'# Gerado por: git alias --export' \
		'# Nao edite a mao; rode o comando novamente para atualizar.' \
		'# Formato: 1' \
		'' \
		'[alias]' \
		'	co = checkout' >"$AFI"
	git config --global --add include.path "$AFI"
	SRC="$IH/fonte.gitconfig"
	printf '%s\n' '[alias]' '	co = checkout' >"$SRC"
	before="$(cat "$AFI")"
	st=0
	out="$("$SCRIPT" --import "$SRC" 2>/dev/null)" || st=$?
	printf 'exit=%s\n' "$st"
	printf 'igual=%s\n' "$([ "$before" = "$(cat "$AFI")" ] && echo sim || echo nao)"
	printf 'report=%s\n' "$out"
)"
check "--import: valor idêntico não reescreve o arquivo (no-op)" \
	"igual=sim" "$(printf '%s\n' "$I_NOOP" | grep '^igual=')"
check "--import: nada a importar (só valor idêntico): relatório '0 importados'" \
	"report=0 importados" "$(printf '%s\n' "$I_NOOP" | grep '^report=')"
check "--import: no-op silencioso — exit 0" \
	"exit=0" "$(printf '%s\n' "$I_NOOP" | grep '^exit=')"

# --- --overwrite: na colisão de valor, a fonte vence --------------------
I_OVER="$(
	IH="$SB/import-over"
	mkdir -p "$IH"
	HOME="$IH"
	GIT_CONFIG_GLOBAL="$IH/.gitconfig"
	export HOME GIT_CONFIG_GLOBAL
	cd "$IH"
	AFI="$IH/aliases.gitconfig"
	printf '%s\n' \
		'# Gerado por: git alias --export' \
		'# Nao edite a mao; rode o comando novamente para atualizar.' \
		'# Formato: 1' \
		'' \
		'[alias]' \
		'	co = checkout' \
		'	st = status' >"$AFI"
	git config --global --add include.path "$AFI"
	SRC="$IH/fonte.gitconfig"
	printf '%s\n' '[alias]' '	co = checkout -q' '	st = status' '	br = branch' >"$SRC"
	st=0
	out="$("$SCRIPT" --import --overwrite "$SRC" 2>/dev/null)" || st=$?
	printf 'exit=%s\n' "$st"
	printf 'coval=%s\n' "$(git config --file "$AFI" --get alias.co)"
	printf 'brval=%s\n' "$(git config --file "$AFI" --get alias.br)"
	printf 'report=%s\n' "$out"
)"
check "--import --overwrite: colisão de valor grava o valor da fonte" \
	"coval=checkout -q" "$(printf '%s\n' "$I_OVER" | grep '^coval=')"
check "--import --overwrite: aliases novos continuam entrando" \
	"brval=branch" "$(printf '%s\n' "$I_OVER" | grep '^brval=')"
check "--import --overwrite: relatório separa importados de sobrescritos" \
	"report=1 importado; 1 sobrescrito" "$(printf '%s\n' "$I_OVER" | grep '^report=')"
check "--import --overwrite: exit 0" \
	"exit=0" "$(printf '%s\n' "$I_OVER" | grep '^exit=')"

# a flag também vale depois do <arquivo>
I_OVER2="$(
	IH="$SB/import-over2"
	mkdir -p "$IH"
	HOME="$IH"
	GIT_CONFIG_GLOBAL="$IH/.gitconfig"
	export HOME GIT_CONFIG_GLOBAL
	cd "$IH"
	AFI="$IH/aliases.gitconfig"
	printf '%s\n' '# Gerado por: git alias --export' '# x' '# Formato: 1' '' \
		'[alias]' '	co = checkout' >"$AFI"
	git config --global --add include.path "$AFI"
	SRC="$IH/fonte.gitconfig"
	printf '%s\n' '[alias]' '	co = switch' >"$SRC"
	"$SCRIPT" --import "$SRC" --dry-run >/dev/null 2>&1 || true
	"$SCRIPT" --import "$SRC" --overwrite >/dev/null 2>&1 || true
	printf 'coval=%s\n' "$(git config --file "$AFI" --get alias.co)"
)"
check "--import: --overwrite/--dry-run também são aceitos depois do <arquivo>" \
	"coval=switch" "$(printf '%s\n' "$I_OVER2" | grep '^coval=')"

# --- --dry-run: mostra o resumo, não grava nada ------------------------
I_DRY="$(
	IH="$SB/import-dry"
	mkdir -p "$IH"
	HOME="$IH"
	GIT_CONFIG_GLOBAL="$IH/.gitconfig"
	export HOME GIT_CONFIG_GLOBAL
	cd "$IH"
	AFI="$IH/aliases.gitconfig"
	printf '%s\n' \
		'# Gerado por: git alias --export' \
		'# Nao edite a mao; rode o comando novamente para atualizar.' \
		'# Formato: 1' \
		'' \
		'[alias]' \
		'	co = checkout' >"$AFI"
	git config --global --add include.path "$AFI"
	SRC="$IH/fonte.gitconfig"
	printf '%s\n' '[alias]' '	co = checkout -q' '	ci = commit' '	br = branch' >"$SRC"
	before_af="$(cat "$AFI")"
	before_gc="$(cat "$IH/.gitconfig")"
	st=0
	out="$("$SCRIPT" --import "$SRC" --dry-run 2>/dev/null)" || st=$?
	printf 'exit=%s\n' "$st"
	printf 'af_igual=%s\n' "$([ "$before_af" = "$(cat "$AFI")" ] && echo sim || echo nao)"
	printf 'gc_igual=%s\n' "$([ "$before_gc" = "$(cat "$IH/.gitconfig")" ] && echo sim || echo nao)"
	printf 'ci_ausente=%s\n' "$(git config --file "$AFI" --get alias.ci >/dev/null 2>&1 && echo nao || echo sim)"
	printf 'report=%s\n' "$out"
)"
check "--import --dry-run: não altera o arquivo de aliases" \
	"af_igual=sim" "$(printf '%s\n' "$I_DRY" | grep '^af_igual=')"
check "--import --dry-run: não altera o ~/.gitconfig" \
	"gc_igual=sim" "$(printf '%s\n' "$I_DRY" | grep '^gc_igual=')"
check "--import --dry-run: alias que entraria não foi gravado" \
	"ci_ausente=sim" "$(printf '%s\n' "$I_DRY" | grep '^ci_ausente=')"
check "--import --dry-run: relatório prefixado com [dry-run]" \
	"report=[dry-run] 2 importados; 1 já existente com valor diferente: co (use --overwrite)" \
	"$(printf '%s\n' "$I_DRY" | grep '^report=')"
check "--import --dry-run: exit 0" \
	"exit=0" "$(printf '%s\n' "$I_DRY" | grep '^exit=')"

# --- "-" lê o gitconfig da entrada padrão ------------------------------
I_STDIN="$(
	IH="$SB/import-stdin"
	mkdir -p "$IH"
	HOME="$IH"
	GIT_CONFIG_GLOBAL="$IH/.gitconfig"
	TMPDIR="$IH"
	export HOME GIT_CONFIG_GLOBAL TMPDIR
	cd "$IH"
	AFI="$IH/aliases.gitconfig"
	printf '%s\n' \
		'# Gerado por: git alias --export' \
		'# Nao edite a mao; rode o comando novamente para atualizar.' \
		'# Formato: 1' \
		'' \
		'[alias]' \
		'	zz = !echo zz' >"$AFI"
	git config --global --add include.path "$AFI"
	st=0
	out="$(printf '[alias]\n\tco = checkout\n\tci = commit\n' | "$SCRIPT" --import - 2>/dev/null)" || st=$?
	printf 'exit=%s\n' "$st"
	printf 'nomes=%s\n' "$(git config --file "$AFI" --name-only --get-regexp '^alias\.' | sed 's/^alias\.//' | LC_ALL=C sort | paste -sd' ' -)"
	printf 'report=%s\n' "$out"
	printf 'temp_sobrou=%s\n' "$(find "$IH" -name 'git-alias-import.*' 2>/dev/null | grep -c . || true)"
)"
check "--import -: lê da entrada padrão e funde no arquivo versionado" \
	"nomes=ci co zz" "$(printf '%s\n' "$I_STDIN" | grep '^nomes=')"
check "--import -: relatório normal" \
	"report=2 importados" "$(printf '%s\n' "$I_STDIN" | grep '^report=')"
check "--import -: exit 0" \
	"exit=0" "$(printf '%s\n' "$I_STDIN" | grep '^exit=')"
check "--import -: não deixa o temporário da stdin para trás" \
	"temp_sobrou=0" "$(printf '%s\n' "$I_STDIN" | grep '^temp_sobrou=')"

# --- alias.alias omitido; entrada reservada/inválida/multivalor ignorada -
I_SKIP="$(
	IH="$SB/import-skip"
	mkdir -p "$IH"
	HOME="$IH"
	GIT_CONFIG_GLOBAL="$IH/.gitconfig"
	export HOME GIT_CONFIG_GLOBAL
	cd "$IH"
	AFI="$IH/aliases.gitconfig"
	printf '%s\n' \
		'# Gerado por: git alias --export' \
		'# Nao edite a mao; rode o comando novamente para atualizar.' \
		'# Formato: 1' \
		'' \
		'[alias]' >"$AFI"
	git config --global --add include.path "$AFI"
	SRC="$IH/fonte.gitconfig"
	printf '%s\n' \
		'[alias]' \
		'	co = checkout' \
		'	alias = !git-alias' \
		'	help = mostra-ajuda' \
		'	ci = commit' \
		'	dup = um' \
		'	dup = dois' \
		'[alias "sub"]' \
		'	foo = bar' >"$SRC"
	st=0
	out="$("$SCRIPT" --import "$SRC" 2>/dev/null)" || st=$?
	printf 'exit=%s\n' "$st"
	printf 'nomes=%s\n' "$(git config --file "$AFI" --name-only --get-regexp '^alias\.' | sed 's/^alias\.//' | LC_ALL=C sort | paste -sd' ' -)"
	printf 'alias_ausente=%s\n' "$(git config --file "$AFI" --get alias.alias >/dev/null 2>&1 && echo nao || echo sim)"
	printf 'help_ausente=%s\n' "$(git config --file "$AFI" --get alias.help >/dev/null 2>&1 && echo nao || echo sim)"
	printf 'report=%s\n' "$out"
)"
check "--import: só os nomes válidos entram (alias.alias omitido, reservado/inválido/multivalor pulados)" \
	"nomes=ci co" "$(printf '%s\n' "$I_SKIP" | grep '^nomes=')"
check "--import: alias.alias da fonte não é gravado (como no --export)" \
	"alias_ausente=sim" "$(printf '%s\n' "$I_SKIP" | grep '^alias_ausente=')"
check "--import: nome reservado 'help' da fonte não é gravado" \
	"help_ausente=sim" "$(printf '%s\n' "$I_SKIP" | grep '^help_ausente=')"
check "--import: relatório conta importados e ignorados (alias.alias fora da conta)" \
	"report=2 importados; 3 ignoradas (nome reservado/inválido ou múltiplos valores): dup, help, sub.foo" \
	"$(printf '%s\n' "$I_SKIP" | grep '^report=')"
check "--import: entrada problemática não bloqueia as boas (exit 0)" \
	"exit=0" "$(printf '%s\n' "$I_SKIP" | grep '^exit=')"

# --- sem arquivo de aliases versionado detectado: erro, sem fallback ----
I_NOFILE="$(
	IH="$SB/import-nofile"
	mkdir -p "$IH"
	HOME="$IH"
	GIT_CONFIG_GLOBAL="$IH/.gitconfig"
	export HOME GIT_CONFIG_GLOBAL
	cd "$IH"
	git config --global user.email t@t
	git config --global user.name t
	SRC="$IH/fonte.gitconfig"
	printf '%s\n' '[alias]' '	co = checkout' >"$SRC"
	before_gc="$(cat "$IH/.gitconfig")"
	st=0
	err="$("$SCRIPT" --import "$SRC" 2>&1 >/dev/null)" || st=$?
	printf 'exit=%s\n' "$st"
	printf 'gc_igual=%s\n' "$([ "$before_gc" = "$(cat "$IH/.gitconfig")" ] && echo sim || echo nao)"
	printf 'co_no_global=%s\n' "$(git config --global --get alias.co >/dev/null 2>&1 && echo sim || echo nao)"
	printf 'orienta=%s\n' "$(printf '%s' "$err" | grep -qi 'install.sh\|--export' && echo sim || echo nao)"
)"
check "--import sem arquivo versionado detectado: exit 1" \
	"exit=1" "$(printf '%s\n' "$I_NOFILE" | grep '^exit=')"
check "--import sem arquivo versionado: NÃO cai no git config --global" \
	"co_no_global=nao" "$(printf '%s\n' "$I_NOFILE" | grep '^co_no_global=')"
check "--import sem arquivo versionado: ~/.gitconfig intacto" \
	"gc_igual=sim" "$(printf '%s\n' "$I_NOFILE" | grep '^gc_igual=')"
check "--import sem arquivo versionado: mensagem orienta install.sh / --export" \
	"orienta=sim" "$(printf '%s\n' "$I_NOFILE" | grep '^orienta=')"

# --- fonte inexistente / inválida / válida mas sem [alias] -------------
I_SRCERR="$(
	IH="$SB/import-srcerr"
	mkdir -p "$IH"
	HOME="$IH"
	GIT_CONFIG_GLOBAL="$IH/.gitconfig"
	export HOME GIT_CONFIG_GLOBAL
	cd "$IH"
	AFI="$IH/aliases.gitconfig"
	printf '%s\n' \
		'# Gerado por: git alias --export' \
		'# Nao edite a mao; rode o comando novamente para atualizar.' \
		'# Formato: 1' \
		'' \
		'[alias]' \
		'	zz = !echo zz' >"$AFI"
	git config --global --add include.path "$AFI"
	before_af="$(cat "$AFI")"

	st1=0
	"$SCRIPT" --import "$IH/nao-existe.gitconfig" >/dev/null 2>&1 || st1=$?

	BAD="$IH/bad.gitconfig"
	printf '%s\n' 'isto nao e um gitconfig valido' '= = =' >"$BAD"
	st2=0
	"$SCRIPT" --import "$BAD" >/dev/null 2>&1 || st2=$?

	EMPTY="$IH/semalias.gitconfig"
	printf '%s\n' '[core]' '	pager = less' >"$EMPTY"
	st3=0
	out3="$("$SCRIPT" --import "$EMPTY" 2>/dev/null)" || st3=$?

	printf 'inexistente=%s\n' "$st1"
	printf 'invalida=%s\n' "$st2"
	printf 'semalias_exit=%s\n' "$st3"
	printf 'semalias_report=%s\n' "$out3"
	printf 'af_igual=%s\n' "$([ "$before_af" = "$(cat "$AFI")" ] && echo sim || echo nao)"
)"
check "--import de fonte inexistente: exit 1" \
	"inexistente=1" "$(printf '%s\n' "$I_SRCERR" | grep '^inexistente=')"
check "--import de fonte com sintaxe gitconfig inválida: exit 1" \
	"invalida=1" "$(printf '%s\n' "$I_SRCERR" | grep '^invalida=')"
check "--import de fonte válida mas sem [alias]: exit 0" \
	"semalias_exit=0" "$(printf '%s\n' "$I_SRCERR" | grep '^semalias_exit=')"
check "--import de fonte sem [alias]: relatório diz que não há nada a importar" \
	"semalias_report=nenhum alias na fonte; nada a importar." \
	"$(printf '%s\n' "$I_SRCERR" | grep '^semalias_report=')"
check "--import: fonte problemática/vazia não altera o arquivo versionado" \
	"af_igual=sim" "$(printf '%s\n' "$I_SRCERR" | grep '^af_igual=')"

# --- nota de segurança: só quando algo com "!" foi de fato importado ----
I_BANG="$(
	IH="$SB/import-bang"
	mkdir -p "$IH"
	HOME="$IH"
	GIT_CONFIG_GLOBAL="$IH/.gitconfig"
	export HOME GIT_CONFIG_GLOBAL
	cd "$IH"
	AFI="$IH/aliases.gitconfig"
	printf '%s\n' \
		'# Gerado por: git alias --export' \
		'# Nao edite a mao; rode o comando novamente para atualizar.' \
		'# Formato: 1' \
		'' \
		'[alias]' \
		'	danger = !echo ja-existia' >"$AFI"
	git config --global --add include.path "$AFI"

	# (a) importa um alias com "!" -> nota aparece
	S1="$IH/s1.gitconfig"
	printf '%s\n' '[alias]' '	gone = !git branch -D' >"$S1"
	e1="$("$SCRIPT" --import "$S1" 2>&1 >/dev/null)" || true
	printf 'a_tem_nota=%s\n' "$(printf '%s' "$e1" | grep -qi "shell\|arbitrário" && echo sim || echo nao)"

	# (b) nada com "!" -> sem nota
	S2="$IH/s2.gitconfig"
	printf '%s\n' '[alias]' '	co = checkout' >"$S2"
	e2="$("$SCRIPT" --import "$S2" 2>&1 >/dev/null)" || true
	printf 'b_sem_nota=%s\n' "$(printf '%s' "$e2" | grep -qi "shell\|arbitrário" && echo nao || echo sim)"

	# (c) "!" só numa colisão pulada (não importada) -> sem nota
	S3="$IH/s3.gitconfig"
	printf '%s\n' '[alias]' '	danger = !rm -rf /' >"$S3"
	e3="$("$SCRIPT" --import "$S3" 2>&1 >/dev/null)" || true
	printf 'c_sem_nota=%s\n' "$(printf '%s' "$e3" | grep -qi "shell\|arbitrário" && echo nao || echo sim)"
)"
check "--import: alias com '!' importado dispara a nota de segurança (stderr)" \
	"a_tem_nota=sim" "$(printf '%s\n' "$I_BANG" | grep '^a_tem_nota=')"
check "--import: sem nenhum '!' importado, não imprime a nota" \
	"b_sem_nota=sim" "$(printf '%s\n' "$I_BANG" | grep '^b_sem_nota=')"
check "--import: '!' só numa colisão pulada não dispara a nota (nada foi importado)" \
	"c_sem_nota=sim" "$(printf '%s\n' "$I_BANG" | grep '^c_sem_nota=')"

# --- erros de uso do --import: exit 2 ---------------------------------
st=0
out="$("$SCRIPT" --import 2>&1)" || st=$?
check "--import sem <arquivo>: erro de uso" \
	"Erro: uso: git alias --import <arquivo> [--overwrite] [--dry-run]" "$out"
check "--import sem <arquivo>: exit 2" "2" "$st"

st=0
out="$("$SCRIPT" --import --overwrite 2>&1)" || st=$?
check "--import só com flag, sem <arquivo>: exit 2" "2" "$st"

st=0
out="$("$SCRIPT" --import --bogus "$SB/x" 2>&1)" || st=$?
check "--import com opção desconhecida: mensagem" \
	"Erro: opção desconhecida para --import: --bogus" "$out"
check "--import com opção desconhecida: exit 2" "2" "$st"

st=0
out="$("$SCRIPT" --import a b 2>&1)" || st=$?
check "--import com dois <arquivo>: erro de uso" \
	"Erro: uso: git alias --import <arquivo> [--overwrite] [--dry-run]" "$out"
check "--import com dois <arquivo>: exit 2" "2" "$st"

# --- valor multilinha da fonte é importado exato ----------------------
I_ML="$(
	IH="$SB/import-ml"
	mkdir -p "$IH"
	HOME="$IH"
	GIT_CONFIG_GLOBAL="$IH/.gitconfig"
	export HOME GIT_CONFIG_GLOBAL
	cd "$IH"
	AFI="$IH/aliases.gitconfig"
	printf '%s\n' \
		'# Gerado por: git alias --export' \
		'# Nao edite a mao; rode o comando novamente para atualizar.' \
		'# Formato: 1' \
		'' \
		'[alias]' >"$AFI"
	git config --global --add include.path "$AFI"
	SRC="$IH/fonte.gitconfig"
	git config --file "$SRC" alias.func "$(printf '!f() {\n  git push\n}\nf')"
	git config --file "$SRC" alias.co checkout
	st=0
	out="$("$SCRIPT" --import "$SRC" 2>/dev/null)" || st=$?
	printf 'exit=%s\n' "$st"
	printf 'report=%s\n' "$out"
	printf 'nomes=%s\n' "$(git config --file "$AFI" --name-only --get-regexp '^alias\.' | sed 's/^alias\.//' | LC_ALL=C sort | paste -sd' ' -)"
	printf 'match=%s\n' "$([ "$(git config --file "$AFI" --get alias.func)" = "$(printf '!f() {\n  git push\n}\nf')" ] && echo sim || echo nao)"
)"
check "--import: valor multilinha da fonte gravado exato no arquivo" \
	"match=sim" "$(printf '%s\n' "$I_ML" | grep '^match=')"
check "--import: valor multilinha não gera alias espúrio a partir do corpo" \
	"nomes=co func" "$(printf '%s\n' "$I_ML" | grep '^nomes=')"
check "--import: valor multilinha — relatório e exit normais" \
	"exit=0 report=2 importados" \
	"$(printf '%s\n' "$I_ML" | grep -E '^(exit|report)=' | paste -sd' ' -)"

# --- escrita que falha de verdade: não conta como importada, sai 1 -------
# git fake que falha só o "set" de alias.* no arquivo de aliases (lock,
# permissão, disco), deixando toda leitura e o resto funcionarem.
I_WRITEFAIL="$(
	IH="$SB/import-writefail"
	mkdir -p "$IH/fakebin"
	HOME="$IH"
	GIT_CONFIG_GLOBAL="$IH/.gitconfig"
	GIT_CONFIG_SYSTEM=/dev/null
	GIT_CEILING_DIRECTORIES="$IH"
	export HOME GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GIT_CEILING_DIRECTORIES
	cd "$IH"
	AFI="$IH/aliases.gitconfig"
	printf '%s\n' \
		'# Gerado por: git alias --export' \
		'# Nao edite a mao; rode o comando novamente para atualizar.' \
		'# Formato: 1' \
		'' \
		'[alias]' \
		'	zz = !echo zz' >"$AFI"
	git config --global user.email t@t
	git config --global user.name t
	git config --global --add include.path "$AFI"
	REALGIT="$(command -v git)"
	cat >"$IH/fakebin/git" <<FAKEGIT
#!/bin/sh
# Falha só a gravação de um valor de alias.* no arquivo de aliases (config
# --file <AFI> alias.<x> <valor>); leitura (--get, --get-regexp, --get-all)
# e --unset-all seguem normais.
if [ "\$1" = config ] && [ "\$2" = --file ] && [ "\$3" = "$AFI" ] && [ -n "\$5" ]; then
	case "\$4" in
	alias.*) echo "fake: gravação recusada" >&2; exit 1 ;;
	esac
fi
exec "$REALGIT" "\$@"
FAKEGIT
	chmod +x "$IH/fakebin/git"
	SRC="$IH/fonte.gitconfig"
	printf '%s\n' '[alias]' '	co = checkout' '	ci = commit' >"$SRC"
	st=0
	out="$(PATH="$IH/fakebin:$PATH" "$SCRIPT" --import "$SRC" 2>/dev/null)" || st=$?
	printf 'exit=%s\n' "$st"
	printf 'co_ausente=%s\n' "$(git config --file "$AFI" --get alias.co >/dev/null 2>&1 && echo nao || echo sim)"
	printf 'importados0=%s\n' "$(printf '%s' "$out" | grep -q '^0 importados' && echo sim || echo nao)"
	printf 'cita_falha=%s\n' "$(printf '%s' "$out" | grep -qi 'falha' && echo sim || echo nao)"
)"
check "--import: escrita que falha de verdade não persiste o alias" \
	"co_ausente=sim" "$(printf '%s\n' "$I_WRITEFAIL" | grep '^co_ausente=')"
check "--import: escrita que falha não é contada como importada" \
	"importados0=sim" "$(printf '%s\n' "$I_WRITEFAIL" | grep '^importados0=')"
check "--import: relatório sinaliza a falha de gravação" \
	"cita_falha=sim" "$(printf '%s\n' "$I_WRITEFAIL" | grep '^cita_falha=')"
check "--import: falha genuína de escrita — exit 1" \
	"exit=1" "$(printf '%s\n' "$I_WRITEFAIL" | grep '^exit=')"

# --- multivalor no DESTINO: ignora o nome, simétrico ao guard da fonte ---
I_DESTMULTI="$(
	IH="$SB/import-destmulti"
	mkdir -p "$IH"
	HOME="$IH"
	GIT_CONFIG_GLOBAL="$IH/.gitconfig"
	export HOME GIT_CONFIG_GLOBAL
	cd "$IH"
	AFI="$IH/aliases.gitconfig"
	# arquivo versionado editado à mão: alias.co com dois valores
	printf '%s\n' \
		'# Gerado por: git alias --export' \
		'# Nao edite a mao; rode o comando novamente para atualizar.' \
		'# Formato: 1' \
		'' \
		'[alias]' \
		'	co = checkout' \
		'	co = switch' >"$AFI"
	git config --global --add include.path "$AFI"
	SRC="$IH/fonte.gitconfig"
	printf '%s\n' '[alias]' '	co = log --oneline' '	ci = commit' >"$SRC"
	st=0
	out="$("$SCRIPT" --import "$SRC" 2>/dev/null)" || st=$?
	printf 'exit=%s\n' "$st"
	printf 'report=%s\n' "$out"
	printf 'ci_ok=%s\n' "$(git config --file "$AFI" --get alias.ci)"
	printf 'co_nao_e_fonte=%s\n' "$([ "$(git config --file "$AFI" --get alias.co 2>/dev/null)" != "log --oneline" ] && echo sim || echo nao)"
)"
check "--import: nome multivalorado no arquivo versionado entra em 'ignoradas'" \
	"report=1 importado; 1 ignorada (nome reservado/inválido ou múltiplos valores): co" \
	"$(printf '%s\n' "$I_DESTMULTI" | grep '^report=')"
check "--import: multivalor no destino não é falha de gravação (exit 0)" \
	"exit=0" "$(printf '%s\n' "$I_DESTMULTI" | grep '^exit=')"
check "--import: os outros nomes entram normalmente apesar do multivalor no destino" \
	"ci_ok=commit" "$(printf '%s\n' "$I_DESTMULTI" | grep '^ci_ok=')"
check "--import: multivalor no destino — a fonte não sobrescreve esse nome" \
	"co_nao_e_fonte=sim" "$(printf '%s\n' "$I_DESTMULTI" | grep '^co_nao_e_fonte=')"

# --- fonte com nome de subseção: espaço não é word-split, "*" não é glob --
I_SUBSEC="$(
	IH="$SB/import-subsec"
	mkdir -p "$IH"
	HOME="$IH"
	GIT_CONFIG_GLOBAL="$IH/.gitconfig"
	export HOME GIT_CONFIG_GLOBAL
	cd "$IH"
	AFI="$IH/aliases.gitconfig"
	printf '%s\n' \
		'# Gerado por: git alias --export' \
		'# Nao edite a mao; rode o comando novamente para atualizar.' \
		'# Formato: 1' \
		'' \
		'[alias]' >"$AFI"
	git config --global --add include.path "$AFI"
	SRC="$IH/fonte.gitconfig"
	printf '%s\n' \
		'[alias]' \
		'	co = checkout' \
		'[alias "a b"]' \
		'	foo = bar' \
		'[alias "*"]' \
		'	g = h' >"$SRC"
	# isca: se "*.g" sofrer glob no CWD do relatório, casaria este arquivo
	: >"$IH/zzz.g"
	st=0
	out="$("$SCRIPT" --import "$SRC" 2>/dev/null)" || st=$?
	printf 'exit=%s\n' "$st"
	printf 'report=%s\n' "$out"
	printf 'a_ausente=%s\n' "$(git config --file "$AFI" --get alias.a >/dev/null 2>&1 && echo nao || echo sim)"
	printf 'co_ok=%s\n' "$(git config --file "$AFI" --get alias.co)"
)"
check "--import: nome de subseção com espaço/'*' é listado literal e inteiro em 'ignoradas'" \
	"report=1 importado; 2 ignoradas (nome reservado/inválido ou múltiplos valores): *.g, a b.foo" \
	"$(printf '%s\n' "$I_SUBSEC" | grep '^report=')"
check "--import: word-split de 'a b.foo' não cria um alias 'a'" \
	"a_ausente=sim" "$(printf '%s\n' "$I_SUBSEC" | grep '^a_ausente=')"
check "--import: apesar das subseções, o alias válido entra normalmente" \
	"co_ok=checkout" "$(printf '%s\n' "$I_SUBSEC" | grep '^co_ok=')"
check "--import: subseções na fonte não são falha (exit 0)" \
	"exit=0" "$(printf '%s\n' "$I_SUBSEC" | grep '^exit=')"

# --- --dry-run não mascara as pré-condições que valem 1 nos dois modos ---
I_DRYPRE="$(
	IH="$SB/import-drypre"
	mkdir -p "$IH"
	HOME="$IH"
	GIT_CONFIG_GLOBAL="$IH/.gitconfig"
	export HOME GIT_CONFIG_GLOBAL
	cd "$IH"
	git config --global user.email t@t
	git config --global user.name t
	SRC="$IH/fonte.gitconfig"
	printf '%s\n' '[alias]' '	co = checkout' >"$SRC"
	# (a) sem arquivo versionado detectado
	st1=0
	"$SCRIPT" --import "$SRC" --dry-run >/dev/null 2>&1 || st1=$?
	# (b) fonte inexistente
	st2=0
	"$SCRIPT" --import "$IH/nao-existe" --dry-run >/dev/null 2>&1 || st2=$?
	printf 'sem_arquivo=%s\n' "$st1"
	printf 'fonte_inexistente=%s\n' "$st2"
)"
check "--import --dry-run sem arquivo versionado: exit 1 (igual ao modo real)" \
	"sem_arquivo=1" "$(printf '%s\n' "$I_DRYPRE" | grep '^sem_arquivo=')"
check "--import --dry-run de fonte inexistente: exit 1 (igual ao modo real)" \
	"fonte_inexistente=1" "$(printf '%s\n' "$I_DRYPRE" | grep '^fonte_inexistente=')"

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
