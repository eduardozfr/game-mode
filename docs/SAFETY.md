# Seguranca e recuperacao

## Politicas

- Defender, firewall, Windows Update, rede, audio, drivers, Nvidia, Steam, Logitech G HUB, Xbox e controles termicos Dell/Alienware nao sao desligados.
- Nenhum servico fora de `Spooler` ou `WSearch` e elegivel a parada.
- Nao altera HPET, BIOS, BCD, afinidade, frequencias, overclock ou prioridade Realtime/High.
- Fechamento forcado requer aplicativo da allowlist e regra explicita em cada perfil.
- Apps fechados podem perder trabalho nao salvo; pare o monitor antes de editar arquivos.
- WSL encerrado nao e restaurado automaticamente. A configuracao `stopWSL` e optativa.

## Recuperacao

1. Feche o jogo.
2. Execute `RESTAURAR.cmd` como administrador.
3. Verifique `STATUS.cmd` e `%ProgramFiles%\PersonalGameModeV7\data\game-mode.log`.
4. Se houver erro, preserve `data/state.json` para nova restauracao.
5. Execute `DESINSTALAR.cmd` quando nao precisar mais da automacao.

Nao execute simultaneamente os scripts manuais V5/V6 e este monitor.
