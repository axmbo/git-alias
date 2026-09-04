# Como cortar uma release

Processo de release do `git-alias`. A política de versionamento (o que é
MAJOR/MINOR/PATCH, a fase `0.y`, os dois eixos de versão) está no
[ADR-0003](adr/0003-politica-de-versionamento-e-release.md); aqui é só o
passo a passo mecânico.

## Pré-requisitos

- `main` limpa, com tudo o que entra na release já mergeado.
- Suíte verde nos dois shells e `shellcheck` limpo:

  ```sh
  SHELL_UNDER_TEST=dash sh tests/run.sh
  SHELL_UNDER_TEST=bash sh tests/run.sh
  shellcheck bin/git-alias install.sh tests/*.sh
  ```

## Passos

1. **Escolha o número** `X.Y.Z` conforme o ADR-0003. Enquanto o projeto
   estiver na série `0.y`, uma quebra de comando ou de formato incrementa
   MINOR (`0.1.0` → `0.2.0`); a primeira release estável é `1.0.0`.

2. **Bump da constante** em [`bin/git-alias`](../bin/git-alias):

   ```sh
   VERSION='X.Y.Z'
   ```

   É a fonte única da verdade — nada mais no código repete o número.

3. **Atualize o `CHANGELOG.md`**:
   - Renomeie a seção `## [Não lançado]` para `## [X.Y.Z] - AAAA-MM-DD`
     (data de hoje).
   - Crie uma nova `## [Não lançado]` vazia no topo.
   - Revise os itens sob `### Adicionado` / `### Mudado` / `### Corrigido`
     etc. — devem descrever o que muda para quem usa, não o diff.

4. **Rode a suíte** (os dois shells) e o `shellcheck`. `tests/version.sh`
   confirma que a constante `VERSION` bate com o cabeçalho de versão mais
   recente do `CHANGELOG.md`; se você esqueceu de um dos dois, falha aqui.

5. **Commit** dos passos 2–3 numa branch (`chore/release-X.Y.Z`), PR e
   merge em `main`, como qualquer outra mudança.

6. **Tag anotada** no commit de release já em `main`:

   ```sh
   git checkout main && git pull   # quando houver remote
   git tag -a vX.Y.Z -m 'vX.Y.Z'
   ```

   A tag é sempre `vX.Y.Z`, com o `v` — é o prefixo que `git describe
   --tags` procura para montar o detalhe do `git alias --version`.

7. **Push da tag** — quando o repositório tiver um remote:

   ```sh
   git push origin main --follow-tags
   ```

   Hoje o repositório é local e sem remote: a tag fica só na máquina até
   isso mudar. O número em `git alias --version` já vale sem a tag; o que a
   tag acrescenta é o sufixo `(vX.Y.Z-N-g…)` quando se roda de dentro do
   checkout.

8. **Confira**: de dentro do checkout,

   ```sh
   git alias --version      # -> X.Y.Z (vX.Y.Z)  logo após taggear
   ```

## Sobre o marcador `# Formato: N`

O cabeçalho gerado do `aliases.gitconfig` traz `# Formato: 1`. Esse número
**não** acompanha a versão da ferramenta: só muda se o formato do arquivo
mudar de forma incompatível, e nesse caso a release é obrigatoriamente
MAJOR (ver ADR-0003). Numa release comum não se toca nele.
