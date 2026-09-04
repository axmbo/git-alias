## O que muda

<!-- Resumo curto. Se fecha uma issue: "Closes #N". -->

## Checklist

- [ ] `sh tests/run.sh` passa sob `dash` **e** `bash`
      (`SHELL_UNDER_TEST=dash|bash sh tests/run.sh`)
- [ ] `shellcheck bin/git-alias install.sh tests/*.sh completions/git-alias.bash`
      sem achados (veja a versão fixada em [CONTRIBUTING.md](../CONTRIBUTING.md#shellcheck-limpo))
- [ ] Documentação (README, `CHANGELOG.md` em `[Não lançado]`, ADR se for
      decisão de arquitetura) atualizada **antes** do código correspondente,
      nesta mesma branch — ver [CONTRIBUTING.md](../CONTRIBUTING.md)
- [ ] Segue TDD (red → green → refactor) ou é um dos casos isentos listados
      em [CONTRIBUTING.md](../CONTRIBUTING.md#tdd)
- [ ] Conventional Commits (`tipo(escopo): descrição em português`)

## Notas para quem revisar

<!-- Algo que não é óbvio pelo diff: por que essa abordagem, o que foi
     considerado e descartado, achados de code review já endereçados. -->
