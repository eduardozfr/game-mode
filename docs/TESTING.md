# Testes

## Automatizados

No Windows, rode `VERIFICAR.cmd` para validar a sintaxe dos arquivos PowerShell e JSON.

Em uma maquina com Python 3:

```bash
python -m unittest discover -s tests -v
```

As checagens estruturais nao substituem testes funcionais no Windows.

## Checklist manual (pendente)

1. Instalar como administrador e confirmar tarefa no Agendador.
2. Abrir/fechar CS2 e confirmar prioridade, Game Mode, plano e restauracao.
3. Repetir com RDR2 e Flight Simulator 2024.
4. Abrir os launchers, controle Logitech, audio e servicos online.
5. Testar `RESTAURAR.cmd`, `REATIVAR.cmd`, `DESINSTALAR.cmd`.
6. Simular parada brusca do monitor, reabrir e confirmar recuperacao de estado.
7. Medir FPS, 1% low e frametimes com as mesmas configuracoes e cenas, antes/depois.

**Estado:** validacao estatica disponivel; nao houve homologacao ponta a ponta no Windows.
