# Personal Game Mode — V7

Otimizador **pessoal, modular e reversivel** para Windows 11, implementado em PowerShell 5.1. Detecta jogos pelo processo, ativa regras de limpeza especificas e restaura energia, Registro e servicos ao terminar. **Nao promete mais FPS**: cada ganho precisa ser validado em teste A/B.

## Perfis iniciais

| Jogo | Executavel observado | Perfil |
| --- | --- | --- |
| Counter-Strike 2 | `cs2.exe` | `profiles/cs2.json` |
| Red Dead Redemption 2 | `RDR2.exe` | `profiles/rdr2.json` |
| Microsoft Flight Simulator 2024 | `FlightSimulator2024.exe` | `profiles/msfs2024.json` |

## Uso rapido

1. **Restaure/desative scripts antigos V5/V6**, caso ainda estejam ativos.
2. Salve documentos e atividades em andamento: perfis podem fechar aplicativos e parar o WSL.
3. Extraia este projeto numa pasta normal no Windows 11.
4. Execute **`INSTALAR.cmd`** e autorize a elevacao de administrador. A instalacao ocorre em `%ProgramFiles%\PersonalGameModeV7`, pasta protegida contra alteracoes sem administrador.
5. A V7 comeca a monitorar imediatamente e sera carregada automaticamente no proximo logon. Abra um jogo normalmente.
6. Execute **`STATUS.cmd`** para inspecionar perfil, agendamento e ultimos eventos.
7. **`RESTAURAR.cmd`** para interromper o monitor e restaurar configuracoes sem reiniciar. `REATIVAR.cmd` para retomar.
8. **`DESINSTALAR.cmd`** remove a tarefa e restaura as configuracoes, mantendo arquivos e logs para conferencia.

**Importante:** o monitor fecha programas **uma vez** quando detecta o processo do jogo (nao fica encerrando apps continuamente). Apps fechados nao sao reabertos automaticamente. O encerramento de `node.exe` e do WSL pode interromper ferramentas de trabalho e sessoes abertas. Somente use o modo automatico se aceitar essa consequencia.

## O que muda e o que NAO muda

**Reversivel e temporario:** Game Mode (preferencia existente em HKCU), Game DVR, plano Alto Desempenho se disponivel, prioridade `AboveNormal`, parada seletiva de `Spooler` e `WSearch` (se estiverem ativos e sem dependencias em execucao).

**Fechamento de apps:** perfis usam `graceful` (solicita encerramento ao app com janela) ou `force` (encerra sem pedir, somente em processos expressamente permitidos). Consulte e personalize os JSON antes da instalacao. Se o fechamento suave nao finalizar um aplicativo, a V7 **nao forcara** a saida dele.

**Preservado:** Steam, Logitech G HUB, servicos NVIDIA/Intel, controles Dell/Alienware, audio, jogos, Windows Defender, firewall, Windows Update, drivers, Xbox/Microsoft Store, e rede. Nao altera BIOS, HPET, hypervisor, BCD, configuracoes de seguranca, clocks ou limites de potencia. A V7 nao utiliza telemetria pesada.

A V7 **nao mata tudo que nao e jogo**: isso quebraria o Windows. Regras permitidas ficam limitadas por uma lista de seguranca no motor, e nao por nomes arbitrarios em perfis.

## Desempenho e estabilidade

- Monitor simples com verificacao de processos a cada 4 segundos; nao captura FPS.
- Prioridade `AboveNormal` (evita `Realtime`/`High`).
- Histerese de 12 segundos na saida do jogo para evitar restauracoes em carregamentos breves.
- Estado salvo **antes** das alteracoes em `data/state.json`.
- Recuperacao do estado pendente na proxima inicializacao caso o processo seja encerrado inesperadamente. Caso o PC seja desligado, a restauracao ocorre no proximo logon (nao durante o desligamento).
- Logs privados em `%ProgramFiles%\PersonalGameModeV7\data\game-mode.log`.

## Limites atuais

- Somente **um perfil ativo por vez**; se dois jogos estiverem abertos, a escolha segue a ordem alfabetica dos arquivos de perfil.
- Os nomes dos executaveis precisam corresponder aos encontrados no PC. O perfil MSFS nao exige Steam e preserva componentes Xbox.
- O Windows pode reiniciar alguns servicos automaticamente; a V7 nao os derruba em repeticao.
- Algumas otimizacoes somente entram em vigor se forem suportadas pelo Windows e pela permissao do processo.
- Nao houve teste de execucao real no Windows nesta entrega: validar instalacao, jogo e restauracao antes de uso continuo.

## Codigo publico

MIT License. Arquivos de sessao, dados de hardware, logs, configs locais e relatórios nao devem ser incluidos em commits. `.gitignore` ignora `data/` e formatos de logs. Nenhuma dependencia de nuvem, conta externa ou marca corporativa.

Documentacao: [Arquitetura](docs/ARCHITECTURE.md), [Adicionar jogos](docs/ADDING_GAMES.md), [Seguranca](docs/SAFETY.md), [Testes](docs/TESTING.md) e [GitHub](docs/PUBLISHING.md).