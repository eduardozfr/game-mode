# Adicionar jogos

1. Consulte no Gerenciador de Tarefas o nome **exato** do processo, sem `.exe`.
2. Copie um arquivo em `profiles/` com outro nome.
3. Edite `id`, `name`, `processName` e `notes`.
4. Use `enabled: true`; `policy` apenas documenta requisitos e preservação.
5. Rode `VERIFICAR.cmd` e reinstale com `INSTALAR.cmd` para atualizar os arquivos.

Exemplo:

```json
{
  "id": "novo-jogo",
  "name": "Novo Jogo",
  "processName": "NovoJogo",
  "notes": "Preservar o launcher e os controles",
  "enabled": true,
  "policy": {
    "unknownProcesses": "preserve",
    "interactiveProcesses": "preserve",
    "externalGameHelpers": "preserve"
  }
}
```

**Não insira listas de aplicativos para matar ou serviços para parar.** O motor rejeita essas propriedades na versão inicial.
