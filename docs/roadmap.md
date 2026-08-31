# Roteiro pré-1.0 — abrir `git alias` como código aberto

> **Status deste documento:** planejamento, transitório. Cada item vira uma
> *issue* no GitHub assim que a decisão D1 (abaixo) definir onde as issues
> vão morar. Enquanto isso, este é o roteiro e a lista de tarefas. Origem:
> brainstorming de 2026-08-30.

## Legenda

- `[ ]` a fazer · `[~]` em andamento · `[x]` feito
- **v1.0** = precisa estar na primeira tag pública · **v1.1** = backlog pós-lançamento

---

## Decisões em aberto

### D1 — Repositório próprio ou permanecer no `dotfiles`?

Bloqueia quase todo o resto (tags, CI, README, onde ficam as issues).

- **Repo próprio** (`git-alias`): melhor descoberta ("git alias manager"),
  release/tag/CHANGELOG próprios, CI dedicado. O `dotfiles` consome como
  submódulo ou cópia. Toda a documentação e o `docs/` viajam junto.
- **Permanecer no `dotfiles`**: menos cerimônia agora; o roadmap e os ADRs já
  estão no lugar. Custo: o `dotfiles` cresce e mistura escopos; tag do
  `dotfiles` não é tag do `git-alias`.
- Recomendação do brainstorming: **separar**. Confirmar antes de prosseguir.

### D2 — Licença

MIT é o default para dotfiles/CLI pequeno. Escolha do autor. Sem `LICENSE` não
é código aberto.

---

## Features pedidas pelo autor

### F1 — Número de versão · **v1.0** · ADR-0002

- [ ] Constante `VERSION="X.Y.Z"` no topo de `git-alias`, fonte única da verdade.
- [ ] `git alias --version` (e `-v`): imprime a constante; se rodando dentro do
      checkout, anexa detalhe do `git describe` (`1.0.0 (v1.0.0-3-gabc1234)`).
      Não depender de `git describe` como fonte primária (script pode ser
      copiado para fora de um repo git).
- [ ] Teste: confirmar que o git **não** intercepta `--version` de subcomando
      externo (diferente de `--help`); nota no README no mesmo espírito da
      nota do `--help`.
- [ ] ADR-0002 "Política de versionamento e release": SemVer ancorado na
      superfície de comandos **e** no formato do `aliases.gitconfig`.
      MAJOR = quebra de comando ou de formato; MINOR = comando/flag novo
      compatível; PATCH = correção.
- [ ] `CHANGELOG.md` (formato *Keep a Changelog*), seed com `[Unreleased]` e
      `[1.0.0]`.
- [ ] Teste estático determinístico no `tests/`: `VERSION` == cabeçalho de
      versão mais recente do `CHANGELOG.md` (no espírito do teste de README
      único).
- [ ] `docs/releasing.md`: passo a passo (bump da constante → seção no
      changelog → tag `vX.Y.Z` → push da tag).
- [ ] Marcador de formato no cabeçalho gerado do `aliases.gitconfig`
      (`# Formato: 1`). Barato agora; mudar o cabeçalho depois é quebra de
      compat que import/export precisa detectar.

### F2 — Import de alias · **v1.0** · ADR-0003

- [ ] `git alias --import <arquivo>` (`-` = stdin): lê `alias.*` da fonte,
      funde na seção `[alias]` do arquivo versionado, renormaliza.
- [ ] Colisão (fonte e arquivo definem o mesmo nome com valor diferente):
      **pular e reportar** por padrão
      (`"4 importados; 2 já existentes com valor diferente: co, st (use --overwrite)"`).
      Valor idêntico dos dois lados = no-op silencioso.
- [ ] `--overwrite`: na colisão, a fonte vence.
- [ ] `--dry-run`: mostra o que mudaria sem gravar.
- [ ] Omitir `alias.alias` (igual ao `--export`).
- [ ] **Não** tocar no `git config --global` (import de fonte externa é só
      isso).
- [ ] Nota de segurança (README + saída do comando): alias com `!` executa
      shell; importar de fonte não confiável = executar comando arbitrário ao
      invocar o alias.
- [ ] ADR-0003 "Semântica de merge do --import": merge não-destrutivo,
      skip-on-collision, `--overwrite`, `--dry-run`.
- [ ] (v1.1) `git alias --import <src> <nome>...`: subconjunto nomeado.
- [ ] (v1.1) `git alias --adopt`: "adotar do `--global`" — funde os aliases do
      `~/.gitconfig` no arquivo **e** limpa as cópias redundantes; mexe em
      massa no `~/.gitconfig`, então exige confirmação. (Hoje o `--export`
      para o arquivo já cobre boa parte disso, pois lê config mesclado.)

---

## Features adicionais (do brainstorming)

### F3 — `git alias --doctor` · **v1.0**

- [ ] Relatório read-only: o arquivo de aliases está no `include.path`? é
      detectado (cabeçalho ok)? há aliases no `--global` fora do arquivo
      (não-versionados / risco de sombra)? `git/bin` no `PATH`? `alias.alias`
      antigo ainda presente? É o `install.sh` invertido, como diagnóstico.

### F4 — `git alias --rename <velho> <novo>` · **v1.0**

- [ ] Um comando no lugar de `git alias novo "$(...)" && git alias --unset
      velho`. Preserva o valor exato; trata arquivo + limpeza de shadow de
      forma consistente.

### F5 — Corrigir e ampliar `--list` · **v1.0**

- [ ] Migrar o parsing de `--list` para `git config --name-only --get-regexp`
      + lookup por chave (mesmo bug de valor multilinha já corrigido no
      `alias_render`).
- [ ] `git alias --list --file`: só os aliases do arquivo versionado.
- [ ] Marcação de origem (arquivo vs `--global` vs outro), tipo
      `git config --show-origin`.

### F6 — Guardas no `set` · **v1.0** (pequeno)

- [ ] Recusar/avisar `git alias alias '...'` (sombrearia o script).
- [ ] Avisar quando `<cmd>` sombreia um comando builtin do git (que o git
      ignora silenciosamente).
- [ ] Mensagem amigável para nome inválido, no lugar do erro cru do
      `git config`.

### F7 — Contrato de exit codes · **v1.0** (polish, não feature)

- [ ] Revisar e documentar 0/1/2. Hoje `--unset` de alias ausente imprime
      "Aviso" e retorna 0 — discutível para scripting. Definir e testar.

### F8 — Completions bash/zsh · **v1.0**

- [ ] Completar nomes de alias em `git alias <TAB>` e `git alias --unset
      <TAB>`, e as flags.
- [ ] `completions/git-alias.bash` + `.zsh`; `install.sh` liga (ou documenta).

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

- [ ] **`LICENSE`** (ver D2).
- [ ] **`CONTRIBUTING.md`**: como rodar os testes; expectativa de TDD;
      Conventional Commits; processo de ADR; shellcheck.
- [ ] **CI (GitHub Actions)**: `tests/git-alias.sh` em push/PR sob **`dash` e
      `bash`**; `shellcheck`; **matriz de versões do git** (uma antiga + a
      mais nova — dependemos de `--name-only` do git ≥ 2.9 e do last-wins do
      `git config --get`); runner **macOS** (BSD `stat`, `readlink` sem `-f`,
      `mktemp`).
- [ ] **Teste de README único**: check determinístico no `tests/` de que
      existe exatamente um `README.md`, na raiz (exigência do fluxo de
      trabalho do autor).
- [ ] **`.editorconfig`**: travar indentação com tab (script e `tests/`).
- [ ] **README**: tirar o hardcode de `~/Dev/dotfiles` da prosa (o
      `install.sh` já deriva o diretório de `$0`); adicionar "Requisitos"
      (POSIX sh, git ≥ 2.9, coreutils **ou** BSD), "Desinstalação", quickstart
      sem pressupor caminho.
- [ ] **Templates** `.github/ISSUE_TEMPLATE/` (bug pede `git alias --version` +
      `git --version` + OS) e PR template.
- [ ] **Auditoria de portabilidade**: `mktemp` com template, flags de `stat`,
      `readlink` sem `-f`, `head -n`, ausência de `sed -i`. Cobrir com o
      runner macOS do CI.

---

## Sequência proposta

1. [ ] **D1** — decidir repo próprio vs. permanecer no `dotfiles`.
2. [ ] Plumbing sem ADR: `LICENSE`, `CONTRIBUTING`, `.editorconfig`, teste de
       README único, CI básico (dash/bash/shellcheck).
3. [ ] **ADR-0002** → F1 (`--version` + CHANGELOG + teste de consistência +
       `docs/releasing.md`).
4. [ ] Lote de polish pequeno: F5 (`--list`), F4 (`--rename`), F6 (guardas),
       F7 (exit codes).
5. [ ] F3 (`--doctor`).
6. [ ] **ADR-0003** → F2 (`--import`).
7. [ ] F8 (completions).
8. [ ] Tag **`v1.0.0`**, publicar.
9. [ ] Backlog v1.1: F9 (man page), F10 (`--edit`), F11 (`--sync`), F2/adopt,
       F2/subconjunto, F12 (`--local`).
