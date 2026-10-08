# Como adicionar um novo jogo

1. Identifique o nome real do executavel pelo Gerenciador de Tarefas, sem `.exe`.
2. Copie `profiles/rdr2.json` para `profiles/novo-jogo.json`.
3. Altere `id`, `displayName`, `processName` e `enabled`.
4. Defina apenas os aplicativos/servicos dispensaveis especificamente nesse jogo.
5. Rode `powershell.exe -NoProfile -File .\src\GameMode.ps1 -Action Validate` no diretorio instalado.
6. Execute `RESTAURAR.cmd`, atualize o perfil no diretorio instalado e use `REATIVAR.cmd`.

## Restricoes

- `stopServices` aceita somente `WSearch` e `Spooler`.
- `closeApps` exige nomes autorizados pelo motor e `mode: graceful` ou `force`.
- `stopWSL: true` pode interromper sessoes WSL nao recuperaveis automaticamente.
- `enabled: false` desabilita o perfil.
- O programa prioriza seguranca: nomes arbitrarios de processos e servicos sao recusados.
- Perfis devem ser versionados; dados reais de sessao, caminhos privados e logs nao.
