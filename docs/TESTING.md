# Testes e homologação

## Estruturais

Execute `VERIFICAR.cmd` em Windows PowerShell 5.1. O comando confere a análise sintática PowerShell e a validade dos JSON.

## Funcionais — ainda pendentes

1. Instalar, confirmar tarefa de usuário e iniciar monitor sem janela.
2. Abrir CS2, RDR2 e MSFS 2024, separadamente, verificando logs de detecção.
3. Conferir que nenhum aplicativo nem serviço é encerrado.
4. Testar mudança e restauração das preferências e do plano de energia.
5. Simular interrupção do monitor e verificar recuperação pelo snapshot.
6. Testar restauração manual e desinstalação.
7. Medir FPS médio, 1% low e frametime por teste A/B equivalente; não inferir ganho apenas por memória livre.

O GitHub Actions não foi tratado como validação funcional: os runners não iniciaram nas tentativas anteriores.
