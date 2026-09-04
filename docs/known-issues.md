# Bugs conhecidos

Bugs reais mas de baixa probabilidade de disparo na prática, registrados
aqui em vez de corrigidos de imediato. Cada entrada descreve o sintoma, a
causa, a condição exata de disparo e o contorno. Ao corrigir uma, mover a
nota para o `CHANGELOG.md` (seção `[Não lançado]`) e removê-la daqui.

Um bug de segurança, perda de dado com disparo fácil, ou regressão de
comportamento documentado **não** entra aqui — vai direto para correção.

---

## KI-1 — `git alias` colapsa um alias multivalorado do arquivo incluído ao reordenar

**Sintoma.** Um `alias.X` com mais de um valor no arquivo de aliases
versionado (arquivo incluído) perde todos os valores menos o último, sem aviso, na
primeira vez que `git alias` grava nesse arquivo por qualquer motivo —
inclusive uma operação sem relação nenhuma com `X` (criar outro alias,
`--unset` de outro, `--rename` de outro, `--import` de outros). O
`--import` guarda o nome que ele mesmo está importando (entra em
"ignoradas"), mas um `X` multivalorado que a fonte nem menciona ainda é
colapsado pela renormalização pós-merge — apesar do texto do `--import`
prometer "não destrói o que já está lá", que vale para as entradas que o
merge de fato toca.

**Causa.** Toda gravação no arquivo incluído chama `normalize_or_warn` →
`alias_render`, que reconstrói a seção `[alias]` re-emitindo cada chave
como `git config --file <tmp> alias.<nome> "$(gc <from> --get alias.<nome>)"`.
`git config --get` (sem `--get-all`) devolve só o último valor, então a
reconstrução grava só esse. É o mesmo colapso de multivalor que o `--list`
(avisa) e o `--rename` (recusa) já tratam — o caminho de escrita
(`alias_render`) nunca ganhou a guarda equivalente.

**Condição de disparo.** O arquivo incluído precisa ter um `alias.X`
multivalorado, estado que `git alias` nunca produz sozinho (ele sempre
grava valor único). Só chega lá por `git config --add alias.X ... --file
<arquivo>` rodado à mão, ou edição manual do arquivo. Não é regressão de
nenhuma branch: `alias_render` sempre foi assim (está em `main`).

**Contorno.** Antes de deixar `git alias` tocar no arquivo, resolver a
multiplicidade à mão: `git config --file <arquivo-de-aliases> --get-all
alias.X` para ver os valores, e reduzir a um só (ou mover os demais para
onde forem pertencer).

**Se/quando corrigir.** A correção consistente com o resto da ferramenta é
`alias_render` **recusar** (sair com código de erro) ao detectar uma chave
multivalorada na fonte, deixando `normalize_or_warn` cair no aviso "gravado
mas não consegui reordenar; rode `git alias --export`". Preservar todos os
valores exigiria parsing NUL-safe (`--get-all --null`, por causa de corpos
multilinha), inviável em POSIX sh puro sem `read -d ''`.
