# Política de processos

## Dois critérios independentes

**Impacto:** quanto CPU, memória ou E/S o processo usa agora.

**Segurança:** se a interrupção é segura para o usuário, o jogo, seus serviços e o Windows.

Um processo consumir muita CPU ou RAM **não autoriza** seu encerramento. Não existir janela, ter CPU ociosa, rodar em background ou possuir assinatura de editor conhecido também não basta.

## Classificação informativa

| Categoria | Regra |
| --- | --- |
| `protected` | Serviço do Windows, componente do sistema, serviço hospedado, ambiente protegido ou informação insuficiente |
| `game-related` | Processo do jogo, parente ou descendente identificado |
| `interactive` | Processo com janela visível que pode conter dados do usuário |
| `review-only` | Processo de usuário em segundo plano, sem evidência de dependência do jogo; *não equivale a ser seguro para fechar* |

Por padrão, todos são **preservados**. A lista de processos conhecidos pode ser usada exclusivamente para proteções, jamais para encerramento.

## Futuras ações adaptativas

Antes de criar qualquer ação automática de encerramento, exigir: identificação robusta do binário, editor/assinatura, vínculo à sessão, exclusões contextuais, mecanismo gracioso de desligamento e permissão explícita para aplicativos que possam conter trabalho. Quando isso não puder ser demonstrado, preservar.

Serviços não devem ser desativados por falta de uso aparente. Docker, WSL e navegadores podem conter tarefas e documentos essenciais.

A auditoria é local, sem envio automático a serviços externos.
