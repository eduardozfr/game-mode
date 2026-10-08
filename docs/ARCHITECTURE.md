# Arquitetura

## Fluxo

1. O instalador verifica a sintaxe PowerShell/JSON, copia o codigo para `%ProgramFiles%\PersonalGameModeV7` e cria a tarefa `PersonalGameModeV7` no logon do usuario com RunLevel Highest.
2. `src/GameMode.ps1 -Action Monitor` usa um mutex por usuario e verifica processos pelo nome a cada `pollSeconds`.
3. Ao detectar um jogo, salva `data/state.json` antes de alterar energia, Registro, servicos ou prioridade.
4. Ativa apenas as regras especificas do perfil; programas encerrados nao sao reiniciados.
5. Quando o processo termina, aguarda `exitGraceSeconds` e restaura os valores anteriores.
6. Ao encontrar estado pendente apos encerramento inesperado, a proxima inicializacao tenta restaurar antes de aceitar nova sessao.

## Limites

- So um perfil ativo por vez.
- Sem alteracao de BIOS, BCD, seguranca, clocks ou drivers.
- Processos protegidos, allowlist de apps e allowlist de servicos ficam no motor, nao no JSON.
- Dados de estado e logs ficam somente no PC local.
- Desligamento abrupto exige nova execucao para restaurar.
- O monitor nao mede FPS; use benchmarks externos em modo separado.

## Arquivos

- `config.json`: intervalo de verificacao e politica de energia.
- `profiles/*.json`: regra de cada jogo.
- `src/GameMode.ps1`: deteccao, snapshot, aplicacao, restauracao.
- `scripts/*.ps1`: instalacao, inicio, recuperacao e desinstalacao.
- `data/`: estado e logs locais ignorados pelo Git.
