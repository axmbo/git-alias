# Roteiro pré-1.0 — abrir `git alias` como código aberto

> **Status deste documento: concluído/arquivado (2026-09-04).** Os 10 passos
> do roteiro pré-1.0 estão feitos — `v1.0.0` publicada em
> [axmbo/git-alias](https://github.com/axmbo/git-alias). O backlog v1.1
> virou issues do GitHub (passo 11); trabalho novo é rastreado por lá, não
> mais neste arquivo. Mantido só como referência histórica do
> planejamento. Origem: brainstorming de 2026-08-30.

## Legenda

- `[ ]` a fazer · `[~]` em andamento · `[x]` feito
- **v1.0** = precisa estar na primeira tag pública · **v1.1** = backlog pós-lançamento

---

## Decisões em aberto

### D1 — Repositório próprio ou permanecer no `dotfiles`? · **decidido 2026-08-30**

**Resultado: repositório próprio.** Como o repo atual já é 100% `git-alias`,
ele mesmo vira o repositório da ferramenta (rename, sem extração de
histórico). Uma coleção de dotfiles pessoais, se existir, será repo separado
que consome o `git-alias`. Ver
[docs/adr/0002-repositorio-proprio-para-o-git-alias.md](adr/0002-repositorio-proprio-para-o-git-alias.md).

### D2 — Licença · **decidido 2026-08-30**

**Resultado: MIT.** Titular "Alexandre Leite", ano 2026. Arquivo `LICENSE` na
raiz + identificador SPDX no README (e opcionalmente cabeçalho
`# SPDX-License-Identifier: MIT` no script).

---

## Features pedidas pelo autor

### F1 — Número de versão · **v1.0** · ADR-0003

- [x] Constante `VERSION="X.Y.Z"` no topo de `git-alias`, fonte única da verdade.
      (`VERSION='0.1.0'`, série `0.y` até a tag `v1.0.0` — ver ADR-0003.)
- [x] `git alias --version` (e `-v`): imprime a constante; se rodando dentro do
      checkout, anexa detalhe do `git describe` (`1.0.0 (v1.0.0-3-gabc1234)`).
      Não depender de `git describe` como fonte primária (script pode ser
      copiado para fora de um repo git).
- [x] Teste: confirmar que o git **não** intercepta `--version` de subcomando
      externo (diferente de `--help`); nota no README no mesmo espírito da
      nota do `--help`.
- [x] ADR-0003 "Política de versionamento e release": SemVer ancorado na
      superfície de comandos **e** no formato do `aliases.gitconfig`.
      MAJOR = quebra de comando ou de formato; MINOR = comando/flag novo
      compatível; PATCH = correção.
- [x] `CHANGELOG.md` (formato *Keep a Changelog*), seed com `[Não lançado]` e
      `[0.1.0]`.
- [x] Teste estático determinístico no `tests/`: `VERSION` == cabeçalho de
      versão mais recente do `CHANGELOG.md` (no espírito do teste de README
      único). — `tests/version.sh`
- [x] `docs/releasing.md`: passo a passo (bump da constante → seção no
      changelog → tag `vX.Y.Z` → push da tag).
- [x] Marcador de formato no cabeçalho gerado do `aliases.gitconfig`
      (`# Formato: 1`). Barato agora; mudar o cabeçalho depois é quebra de
      compat que import/export precisa detectar.

### F2 — Import de alias · **v1.0** · ADR-0004

- [x] `git alias --import <arquivo>` (`-` = stdin): lê `alias.*` da fonte,
      funde na seção `[alias]` do arquivo versionado, renormaliza.
- [x] Colisão (fonte e arquivo definem o mesmo nome com valor diferente):
      **pular e reportar** por padrão
      (`"4 importados; 2 já existentes com valor diferente: co, st (use --overwrite)"`).
      Valor idêntico dos dois lados = no-op silencioso.
- [x] `--overwrite`: na colisão, a fonte vence.
- [x] `--dry-run`: mostra o que mudaria sem gravar.
- [x] Omitir `alias.alias` (igual ao `--export`).
- [x] **Não** tocar no `git config --global` (import de fonte externa é só
      isso).
- [x] Nota de segurança (README + saída do comando): alias com `!` executa
      shell; importar de fonte não confiável = executar comando arbitrário ao
      invocar o alias.
- [x] ADR-0004 "Semântica de merge do --import": merge não-destrutivo,
      skip-on-collision, `--overwrite`, `--dry-run`. (Squash `73747b5`;
      entrada `alias.*` reservada/inválida/multivalorada na fonte **ou** no
      arquivo é ignorada com aviso; escrita que falha de verdade → exit 1;
      KI-1 anotada para o `--import`. `tests/git-alias.sh`: 307 asserções.)
- [ ] (v1.1) `git alias --import <src> <nome>...`: subconjunto nomeado.
- [ ] (v1.1) `git alias --adopt`: "adotar do `--global`" — funde os aliases do
      `~/.gitconfig` no arquivo **e** limpa as cópias redundantes; mexe em
      massa no `~/.gitconfig`, então exige confirmação. (Hoje o `--export`
      para o arquivo já cobre boa parte disso, pois lê config mesclado.)

---

## Features adicionais (do brainstorming)

### F3 — `git alias --doctor` · **v1.0**

- [x] Relatório read-only: o arquivo de aliases está no `include.path`? é
      detectado (cabeçalho ok)? há aliases no `--global` fora do arquivo
      (não-versionados / risco de sombra)? `git/bin` no `PATH`? `alias.alias`
      antigo ainda presente? É o `install.sh` invertido, como diagnóstico.

### F4 — `git alias --rename <velho> <novo>` · **v1.0**

- [x] Um comando no lugar de `git alias novo "$(...)" && git alias --unset
      velho`. Preserva o valor exato; trata arquivo + limpeza de shadow de
      forma consistente.

### F5 — Corrigir e ampliar `--list` · **v1.0**

- [x] Migrar o parsing de `--list` para `git config --name-only --get-regexp`
      + lookup por chave (mesmo bug de valor multilinha já corrigido no
      `alias_render`).
- [x] `git alias --list --file`: só os aliases do arquivo versionado.
- [x] Marcação de origem (arquivo vs `--global` vs outro), tipo
      `git config --show-origin`. (Opt-in via `--list --origin`/`-o`.)

### F6 — Guardas no `set` · **v1.0** (pequeno)

- [x] Recusar/avisar `git alias alias '...'` (sombrearia o script).
- [x] Avisar quando `<cmd>` sombreia um comando builtin do git (que o git
      ignora silenciosamente). (`git --list-cmds=builtins`; o grupo
      `parseopt` citado na doc do próprio Git não é aceito nesta versão.)
- [x] Mensagem amigável para nome inválido, no lugar do erro cru do
      `git config`.

### F7 — Contrato de exit codes · **v1.0** (polish, não feature)

- [x] Revisar e documentar 0/1/2. Hoje `--unset` de alias ausente imprime
      "Aviso" e retorna 0 — discutível para scripting. Definir e testar.
      (0 sucesso, 1 falha esperada, 2 erro de uso; tabela no README.)

### F8 — Completions bash/zsh · **v1.0**

- [x] Completar nomes de alias em `git alias <TAB>` e `git alias --unset
      <TAB>`, e as flags. (Também: `--rename <velho> <TAB>`, `--file`/
      `--origin`/`-o` em `--list`, `--overwrite`/`--dry-run` em `--import`,
      nomes de arquivo em `--export`/`--import`.)
- [x] `completions/git-alias.bash` (função `_git_alias`, via git-completion.bash)
      + `.zsh` (função `_git-alias`, via `_git` nativo do zsh); `install.sh`
      liga por symlink (4º passo). `tests/completions.sh` cobre existência,
      sintaxe e cobertura de subcomandos/flags. 5 rodadas de `/code-review`.

### F9 — Man page · v1.1

- [ ] Enviar `git-alias.1` e fazer o `install.sh` colocá-la no `MANPATH` →
      `git alias --help` **passa a funcionar** (vira feature em vez de wart
      documentado). Fonte em markdown ou roff.

### F10 — `git alias --edit` · v1.1

- [ ] Abre o arquivo no `$EDITOR` e renormaliza ao salvar — edição em massa
      sem violar o "não edite à mão".

### F11 — `git alias --sync` / `--normalize` · v1.1

- [ ] Reescreve o arquivo detectado a partir do config mesclado num tiro só
      (reparo). Complementa o `--doctor`.

### F12 — `git alias --local <nome> <cmd>` · v1.1+

- [ ] Grava deliberadamente no `--global` depois do include (vence o arquivo)
      para alias específico de máquina — o inverso da limpeza de shadow.
      Workflow real: laptop do trabalho vs pessoal.

---

## Prontidão para open source (plumbing, não-feature)

### v1.0

- [x] **Reestruturar para repo de ferramenta** (ADR-0002): layout achatado
      `git/bin/git-alias` → `bin/git-alias`; `git/aliases.gitconfig` vira
      amostra (`examples/aliases.gitconfig`); `install.sh` deriva o alvo do
      `include.path` fora do clone (XDG), sem pressupor `~/Dev/dotfiles`.
      `~/.claude/CLAUDE.md` global conferido — já não tinha menções a
      `~/Dev/dotfiles`/dotfiles (só a outro projeto); nada a ajustar.
      **Falta só o rename do repositório no GitHub** — D-d: fica para o
      passo 10, junto da criação do remote/publicação. Squash
      `437036a`.
- [x] **`LICENSE`** (ver D2). MIT, titular "Alexandre Leite", 2026.
- [x] **`CONTRIBUTING.md`**: como rodar os testes; expectativa de TDD;
      Conventional Commits; processo de ADR; shellcheck.
- [x] **CI (GitHub Actions)**: `.github/workflows/ci.yml` — `tests/run.sh`
      em push/PR sob **`dash` e `bash`**, cruzado com **duas versões de
      git** (piso `2.9.0`, compilado do tarball oficial verificado por
      SHA256, e a mais nova do runner); job **macOS** (`macos-latest`, BSD
      `stat`/`readlink`/`mktemp`); `shellcheck` em `bin/git-alias`,
      `install.sh`, `tests/*.sh` e `completions/git-alias.bash`. Squash
      `c1ce453`.
- [x] **Teste de README único**: check determinístico no `tests/` de que
      existe exatamente um `README.md`, na raiz (exigência do fluxo de
      trabalho do autor). `tests/repo.sh`, rodado pelo `tests/run.sh` —
      ganhou também a checagem de layout (`bin/git-alias`, sem `git/`).
- [x] **`.editorconfig`**: travar indentação com tab (script e `tests/`).
- [x] **README**: tirou o hardcode de `~/Dev/dotfiles` da prosa; seções
      "Requisitos" (POSIX sh, git ≥ 2.9, coreutils **ou** BSD) e
      "Desinstalação" novas; quickstart de instalação sem pressupor
      caminho de clone; reposicionado de "dotfiles pessoais" para
      "ferramenta que se instala".
- [x] **Templates** `.github/ISSUE_TEMPLATE/` (bug pede `git alias --version` +
      `git --version` + OS) e PR template. Squash `de157c8`.
- [x] **Auditoria de portabilidade**: `docs/portabilidade.md` — `mktemp`
      com template, flags de `stat`, `readlink` sem `-f`, `head -n`,
      ausência de `sed -i`, `LC_COLLATE`. Coberta pelo runner macOS do CI.

---

## Sequência proposta

1. [x] **D1** — decidido: repositório próprio (ADR-0002).
2. [x] **D2** — decidido: MIT.
3. [x] Plumbing sem ADR: `LICENSE` (MIT), `CONTRIBUTING`, `.editorconfig`,
       teste de README único, CI básico (dash/bash/shellcheck). (A matriz
       maior do CI — versões de git, runner macOS — fecha no passo 9, junto
       da auditoria de portabilidade.)
4. [x] **ADR-0003** → F1 (`--version` + CHANGELOG + teste de consistência +
       `docs/releasing.md`).
5. [x] Lote de polish pequeno: F5 (`--list`), F4 (`--rename`), F6 (guardas),
       F7 (exit codes).
6. [x] F3 (`--doctor`).
7. [x] **ADR-0004** → F2 (`--import`).
8. [x] F8 (completions).
9. [x] Reestruturar para repo de ferramenta + reescrever README (ADR-0002);
       fechar o CI (matriz de versões de git + runner macOS) junto da
       auditoria de portabilidade; templates de issue/PR. 4 sub-branches
       (build/shellcheck-debt `c195c64`; refactor/layout-ferramenta
       `437036a`; ci/matriz-git-macos `c1ce453`; chore/templates-github
       `de157c8`), cada uma com `/code-review` até estabilizar.
10. [x] Tag **`v1.0.0`**, publicar. Bump da constante + CHANGELOG em
        `chore/release-1.0.0` (squash `c547dcd`, PR
        [#1](https://github.com/axmbo/git-alias/pull/1)); achados da 1ª
        execução real do CI corrigidos em `test/isola-xdg-config-home-na-suite`
        (squash `a2aa997`, PR
        [#2](https://github.com/axmbo/git-alias/pull/2), mergeada antes do
        bump para o release commit já nascer com CI verde) — isolamento de
        `XDG_CONFIG_HOME`, `--fixed-value`/`GIT_CONFIG_SYSTEM` incompatíveis
        com o piso git 2.9.0, build do git-floor poluindo o checkout.
        Repositório renomeado/publicado em
        [axmbo/git-alias](https://github.com/axmbo/git-alias) (público);
        tag anotada `v1.0.0` e
        [Release pública](https://github.com/axmbo/git-alias/releases/tag/v1.0.0)
        a partir dela, notas reaproveitando a seção `[1.0.0]` do
        `CHANGELOG.md`. `git alias --version` confirmado: `1.0.0 (v1.0.0)`,
        sem sufixo de commits à frente. CI real (matriz de git, dash/bash,
        shellcheck, macOS) 6/6 verde em `main` após as correções — 1ª vez
        que essa rede de segurança roda de verdade (2026-09-04). Verificação
        manual de zsh (`zsh -n` + `git alias <TAB>` interativo) segue
        pendente — nenhuma sessão até agora teve zsh disponível.
11. [x] Backlog v1.1 virou issues do GitHub, agora que o issue tracker existe
        de verdade:
        [F9 — man page](https://github.com/axmbo/git-alias/issues/3),
        [F10 — `--edit`](https://github.com/axmbo/git-alias/issues/4),
        [F11 — `--sync`](https://github.com/axmbo/git-alias/issues/5),
        [F2/adopt](https://github.com/axmbo/git-alias/issues/6),
        [F2/subconjunto](https://github.com/axmbo/git-alias/issues/7),
        [F12 — `--local`](https://github.com/axmbo/git-alias/issues/8). Lista
        completa: [axmbo/git-alias/issues](https://github.com/axmbo/git-alias/issues).

---

Roteiro pré-1.0 concluído (passos 1–10). Este arquivo pode ser arquivado —
ou mantido só como referência histórica — a critério de quem mantém o
projeto; o trabalho ativo passa a ser rastreado pelas issues do GitHub.
