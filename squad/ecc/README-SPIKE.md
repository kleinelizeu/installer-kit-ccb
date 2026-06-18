# ECC — squad (SPIKE: ARQUIVADO)

## Veredito (2026-06-17): ARQUIVADO. Marketing fica SOLO.

O spike de pesquisa concluiu que o **ECC não pode ser dirigido headless pelo Hermes**.

### Por quê
O ECC (`affaan-m/ecc`) é, na essência, um **plugin do Claude Code** (skills, commands, hooks, rules).
- **Não expõe MCP server, HTTP API nem daemon** para orquestração externa (ele empacota MCP *clients*, não um "ECC-as-a-service"). Diferente do Ruflo, que expõe `ruflo mcp start`.
- Os comandos `/multi-plan`, `/multi-execute`, etc. **exigem o `ccg-workflow`** (`npx ccg-workflow`) e rodam **dentro de uma sessão do Claude Code** (`~/.claude/bin/codeagent-wrapper`, `~/.claude/.ccg/prompts/*`) — não como um serviço que o Hermes possa chamar.
- Conclusão: uma plataforma self-hosted (Hermes, controlado por Telegram) **não tem interface programática** para entregar uma tarefa ao swarm do ECC e receber o resultado sem um humano/Claude Code dirigindo.

Construir um `marketing-squad-ccb` sobre o ECC exigiria embarcar um **Claude Code separado** + uma ponte indefinida — o que quebra o modelo "um agente Hermes, instalação em 1 comando".

### Decisão
- **Marketing permanece SOLO** (publicado em `marketing-ccb`), no padrão Zernio-SDR comprovado.
- O squad ECC fica **arquivado** até (se algum dia) o ECC expor uma interface de servidor (MCP/HTTP) que o Hermes possa consumir como faz com Zernio/Ruflo.
- `kit-sync` **recusa** `TRACK=squad` + `SQUAD_FRAMEWORK=ecc` (guard já no kit-sync).

### Fontes
- https://github.com/affaan-m/ecc (README / arquitetura: harness-native, plugin de Claude Code)
- https://deepwiki.com/affaan-m/ECC/1.1-getting-started-and-installation (`/plugin install ecc@ecc` + `npx ccg-workflow`)
