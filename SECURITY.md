# Política de segurança

## Versões com suporte

O `git-alias` é um utilitário de linha de comando distribuído como script.
Só recebem correção de segurança:

- a última versão publicada (a tag mais recente em
  <https://github.com/axmbo/git-alias/releases>);
- o branch `main`.

Não há backport para tags anteriores.

## Como reportar uma vulnerabilidade

Use o canal privado do GitHub — **Security › Advisories › Report a
vulnerability**:
<https://github.com/axmbo/git-alias/security/advisories/new>. Ele abre uma
conversa privada entre você e os mantenedores.

Não abra issue pública para falha de segurança. Se preferir e-mail:
`contact@axmbo.dev`.

No relato, inclua o que conseguir: a versão (`git alias --version`), o
sistema operacional e o shell, um passo a passo mínimo para reproduzir e o
impacto que você enxerga.

**Resposta esperada:** confirmação de recebimento em até 7 dias e uma
avaliação inicial em até 30 dias. O projeto é mantido por uma pessoa em
tempo não integral; o prazo de correção varia com a severidade.

## Fora de escopo

- **Alias que executa shell.** Um alias do Git cujo valor começa com `!` é
  executado pelo shell quando invocado — é assim que o Git funciona. O
  `git-alias` só grava no arquivo de aliases o que você mandou gravar;
  rodar depois um alias `!` que você mesmo importou de uma fonte não
  confiável não é uma falha do `git-alias`. Veja a nota **Segurança** na
  seção `--import` do [README](README.md).
- Qualquer coisa que dependa de o atacante já ter permissão de escrita no
  seu `~/.gitconfig`, no arquivo de aliases versionado do seu projeto ou no
  `PATH` — nesse ponto o `git-alias` não é a superfície relevante.
