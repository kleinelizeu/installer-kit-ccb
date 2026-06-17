# ECC — squad (SPIKE, ainda NÃO construir)

O ECC (`affaan-m/ecc`) é um plugin/runtime **centrado no Claude Code** (`/multi-plan`,
`/multi-execute` + `npx ccg-workflow`). Diferente do Ruflo, **não expõe um MCP server**
que o Hermes possa registrar como cliente. Por isso, rodar o ECC como esquadrão sob o
Hermes-na-VPS é um experimento, não um produto pronto.

## O que o spike na VPS precisa PROVAR (gate antes de qualquer build)

1. **Headless/root:** ECC e `ccg-workflow` instalam e rodam de forma não-interativa,
   como root, numa Ubuntu limpa (sem TUI do Claude Code aberto).
2. **Interface programática:** existe um jeito do Hermes entregar uma tarefa ao
   esquadrão ECC e receber o resultado de volta SEM um humano no terminal
   (MCP? HTTP? CLI com saída capturável?).
3. **Auth scriptável e idempotente:** as credenciais (Claude Code / API keys) podem
   ser configuradas por script e o passo pode rodar 2x sem quebrar (contrato do `executar_passo`).
4. **Persistência:** sobrevive a reboot/restart do gateway, e o doctor consegue verificar.

## Decisão (travada com o usuário)

- Marketing/agências **publica como SOLO agora** (mesmo padrão Zernio-SDR, conteúdo de marketing).
- O esquadrão ECC fica **gated** neste spike. Se (2) ou (3) falharem, **arquivar** o squad ECC
  e manter Marketing como solo. Se passar, criar `marketing-squad-ccb` (= solo + passo squad ECC).

Enquanto o spike não passar, `kit-sync` **recusa** `TRACK=squad` + `SQUAD_FRAMEWORK=ecc`.
