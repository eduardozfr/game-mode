# V8 — Scanner adaptativo e motor de decisões

> **Status:** proposta de arquitetura. A V7 implementa listas fixas; **ela ainda não contém este scanner**.
> Não instalar a V8 como otimização automatizada antes da homologação no Windows.

## Objetivo

O Game Mode deverá detectar CS2, RDR2 e MSFS 2024 sem pedir que o usuário execute perfis, mas decidir o que **não** precisa ser executado com base no estado da máquina, nos requisitos do jogo e em uma política de segurança. **Processo ocioso ≠ processo dispensável. Processo pesado ≠ processo seguro para encerramento.**

A V7 não atende a esse critério: `src/GameMode.ps1` utiliza `AllowedApps` e `Close-KnownApps`, enquanto `profiles/*.json` contém `closeApps`, `stopWSL` e `stopServices`. Esses campos devem ser removidos da versão adaptativa, após implantação do substituto.

## Pipeline proposto

1. **Detect:** detectar o jogo real em execução pelo executável, caminho e árvore dos processos, distinguindo game, launcher e auxiliares. Um nome de executável isolado é insuficiente para justificar encerramento de outro processo.
2. **Snapshot:** capturar recursos, processos, serviços e preferências do Windows **antes** de qualquer intervenção.
3. **Inventory:** consultar processos da sessão do usuário, pai/filhos, caminho quando disponível, assinatura digital/editor, janela visível, foco atual, serviços hospedados, CPU em duas ou mais amostras, working set/private memory, I/O por intervalo e histórico de atividade. Tratar falta de dados/permissão como **desconhecido**.
4. **Protect:** construir conjunto de proteção: processos críticos do Windows, drivers, segurança, anti-cheat, áudio, GPU, rede, energia/térmica, periféricos, serviços de jogos, dependências do launcher, ferramentas externas requeridas pelo simulador, interações do usuário e processos cujo encerramento pode afetar trabalho.
5. **Classify:** atribuir **duas dimensões independentes** a cada processo: pressão sobre os recursos e evidência de que seu fechamento é seguro. Ausência de uso de CPU não prova segurança; assinatura Microsoft não significa dispensabilidade, e ausência de janela não prova ausência de dados não salvos.
6. **Decide:** o padrão é **preservar**. Com exceção de programas sob política local de confiança, só agir automaticamente quando existir mecanismo explícito e testável de encerramento seguro. Fechamento gracioso é preferido; se não funcionar, registrar, **não** forçar.
7. **Apply:** aplicar otimizações reversíveis de energia/registro/prioridade; registrar decisão, evidência e resultado. Não interromper processos durante recálculos periódicos apenas porque mudaram de categoria.
8. **Restore:** quando o jogo termina, recuperar configurações salvas de energia, serviços e prioridade com operações idempotentes e recuperação após falha. Programas encerrados não são reabertos; esse limite precisa ser documentado.

## Classificação

| Classe | Exemplos de evidência | Política padrão |
| --- | --- | --- |
| `essential` | Processo de sistema ou componente de driver, segurança, rede, áudio, térmica/energia | Nunca interromper |
| `game-dependency` | Launcher, serviço de autenticação, anti-cheat, overlay/periférico, dependência conhecida do jogo | Preservar |
| `interactive-or-unknown` | Janela aberta, possibilidade de documento não salvo, dependência incerta, identidade não verificável | Preservar |
| `background-candidate` | Processo de usuário não essencial, com baixo risco demonstrado e sem dependência do jogo | Apenas avaliação adicional |

**Nenhuma classe, sozinha, autoriza `Stop-Process -Force`.** O resultado dos scores não substitui uma prova de encerramento seguro.

## Política local de decisões aprendidas

Para operações totalmente automáticas, permitir que o usuário **autorize uma categoria específica de ação uma vez** (ex.: encerrar graciosamente determinado aplicativo em segundo plano, condicionado a não estar com janela/documento aberto). A autorização é armazenada apenas no PC e vinculada à identidade do executável/editor, não a um PID nem somente ao nome do processo.

- O consentimento aprendido pode ser restrito por jogo e revogado.
- Uma atualização significativa de identidade/caminho/editor do aplicativo provoca reavaliação.
- Falhas de inspeção, privilégios insuficientes, processo desconhecido e cadeia de dependências ambígua resultam em **não encerrar**.
- Aplicativos que possam possuir dados não salvos não serão encerrados em modo 100% automático sem sinalização explícita e segura do próprio aplicativo.
- **Não** incluir listas fixas de apps para matar nos perfis. Listas mínimas de funções/processos protegidos do sistema permanecem necessárias como barreira de segurança e não são uma lista de fechamento.

## Serviços Windows e subsistemas

- Descoberta pode ser dinâmica; **parada automática nunca deve ser deduzida apenas do consumo ou da aparente ociosidade**.
- Consultar tipo de inicialização, dependentes ativos, permissões e participação no jogo; serviços compartilhados por `svchost` não podem ser tratados como aplicativos comuns.
- Parada de serviços deve exigir política separada, específica e reversível; padrão: não parar.
- Não desligar Windows Defender, firewall, Windows Update, áudio, rede, segurança, anti-cheat, GPU/Intel/NVIDIA, Dell/Alienware ou Xbox/Microsoft Store no MSFS.
- Docker/WSL contêm máquinas, sessões ou serviços de trabalho; **não** executar `wsl --shutdown` somente por detecção de consumo.
- Não mudar BIOS, BCD, temporizadores, integridade da memória, clocks nem prioridade `Realtime`.

## Novo modelo dos perfis

Exemplo **conceitual**, sujeito à implementação:

```json
{
  "id": "msfs2024",
  "displayName": "Microsoft Flight Simulator 2024",
  "detection": {
    "imageNames": ["FlightSimulator2024.exe"],
    "optionalLaunchers": ["Steam", "Xbox"]
  },
  "requirements": {
    "onlineServices": true,
    "preserveExternalTools": true,
    "preserveControllers": true
  },
  "policy": {
    "mode": "observe",
    "interactiveProcesses": "protect",
    "unknownProcesses": "protect",
    "closeWithoutApprovedRule": false
  }
}
```

`imageNames` serve apenas para detectar o jogo. `optionalLaunchers` são informações de compatibilidade, **não** processos a encerrar. Não misturar regras gerais de segurança com o perfil de um jogo.

## Interface e telemetria

- `Observe`: coleta leve e relatório de oportunidades, sem fechar apps (primeiro estágio).
- `Adaptive`: aplica apenas ações validadas ou previamente autorizadas; não deve interromper aplicativos com trabalho em andamento.
- `Status`: mostra jogo, modo, decisões tomadas, processos preservados e justificativas.
- `Restore`: restaura estado; pode ser acionado a qualquer momento.
- `Diagnostics`: coleta detalhada/PresentMon **separada**, sob demanda, para benchmarking; não adicionar coleta de frames permanente ao modo leve.

Relatório local deve registrar timestamp, PID e hora de início do processo, decisão, justificativa, ação e resultado. Evitar registrar linhas de comando inteiras, caminhos pessoais, tokens, títulos de janelas, URLs e dados sensíveis. Esses relatórios nunca são enviados ao repositório.

## Regras para evitar falsos positivos

- MSFS com navegador/chart tool aberto: **preservar**, mesmo se houver consumo significativo.
- CS2 com navegador aberto contendo trabalho não salvo: **preservar** por padrão.
- Dois `node.exe` com papéis diferentes: não tratá-los como um único aplicativo.
- Processo com o mesmo nome que um conhecido mas outro caminho/editor: **desconhecido**.
- Processo filho de Steam, Rockstar, Xbox, anti-cheat, Logitech ou módulo áudio: **não decidir pelo nome isolado**.
- CPU 0% durante uma janela de amostragem: não é justificativa para encerramento.
- Drivers/serviços sem janela visível: preservar.
- Aplicativo já fechado/serviço já parado ao iniciar o jogo: não criar restauração artificial.
- Queda do monitor ou encerramento inesperado: restaurar no próximo lançamento sem perder o snapshot.

## Etapas de implementação

1. Separar `ProcessInventory`, `SafetyClassifier`, `DecisionPolicy`, `ActionExecutor` e `StateRestore` em módulos testáveis.
2. Introduzir `Observe` com logs/auditoria e casos simulados de classificação; a V7 continua inalterada.
3. Remover `closeApps`, `AllowedApps` e `Close-KnownApps` da nova implementação e migrar perfis.
4. Implementar política adaptativa com opt-ins locais explícitos, fallback seguro e fechamento gracioso.
5. Testar Windows 11 com os três jogos, inicialização, saídas abruptas, permissões limitadas e restaurador.
6. Medir impacto com cenário A/B reproduzível (FPS, 1% low, frametimes, CPU, GPU, memória); não atribuir ganho a serviços desativados sem evidência.

## Critérios de aceite

- Sem kill-list estática por jogo e sem encerramento automático de processos desconhecidos.
- Toda ação automatizada deve ter justificativa audível e identidade do processo verificada.
- Perfis descrevem requisitos e exceções do jogo; não são tabelas de executáveis a matar.
- Serviços críticos preservados e restauração idempotente verificada.
- `Observe` é o modo inicial seguro da V8; `Adaptive` só após testes.
- Nenhuma afirmação de ganho de FPS sem dados reais.
