# Arquitetura — Game Mode 0.1.0

- **Monitor**: identifica jogo pelo processo com amostragem periódica e histerese na saída.
- **Process scanner**: captura consumo de CPU/RAM, janela, árvore de processos e associação a serviços; produz diagnóstico local.
- **Decision policy**: separa uso de recursos de evidência de segurança. O estado inicial é somente observação de processos de fundo, sem encerramento.
- **Optimizer**: altera apenas Game Mode, captura, plano disponível e prioridade `Normal → AboveNormal` quando autorizada.
- **Restore**: salva snapshot antes de aplicar alterações, restaura o estado anterior e permite recuperação no próximo início.

Os perfis JSON só definem detecção do jogo e requisitos de compatibilidade; **não contêm listas de programas para fechar**.

A instalação é por usuário e sem elevação automática; uma tarefa no logon inicia `src/GameMode.ps1`, que é copiado para `%LOCALAPPDATA%\GameMode`. Não altera nenhum serviço do Windows.

## Fluxo de estados

`IDLE → DETECTED → SNAPSHOT_SAVED → OPTIMIZED → EXIT_WAIT → RESTORED → IDLE`

Uma queda inesperada do monitor pode deixar mudanças temporárias até a próxima execução. O estado persistido é recuperado antes de aceitar um novo jogo.

## Limitações da primeira versão

- O inventário pode ter dados indisponíveis para processos protegidos pelo Windows.
- A classificação é apenas informativa; não faz atribuição confiável de que um programa pode ser fechado sem perder dados.
- Perfis identificam processos pelo nome; identidade completa do executável será adicionada antes de políticas avançadas.
- O scanner não mede FPS. Testes A/B com PresentMon serão separados da otimização.
