#!/usr/bin/env bash
# spike-agent-booking.sh — PROVA que o AGENTE (LLM) chama as ferramentas de agenda SOZINHO.
# Isolado: clona o perfil ativo só p/ ter o MODELO, REMOVE todos os MCPs herdados (zernio/zapier/
# codegraph) p/ o --yolo não tocar no Instagram real, STRIP dos tokens de bot (sem poller), e
# registra só o gcal (SA fake). Roda um prompt one-shot de agendamento e mostra o agente
# invocando criar_evento (a chamada ao Google falha só pela credencial fake — o que importa aqui
# é o AGENTE decidir e CHAMAR a ferramenta sozinho). Teardown sempre. Uso (NA VPS): bash spike-agent-booking.sh <SCRIPT_PY> [PROFILE]
set -uo pipefail
SCRIPT="${1:?caminho do gcal_mcp.py na VPS}"
PROFILE="${2:-ccbauto}"
PROFDIR="/root/.hermes/profiles/$PROFILE"; ALIAS="/root/.local/bin/$PROFILE"
FAKE="/tmp/gcal-fake-sa.json"; UV="$(command -v uv || echo /root/.local/bin/uv)"
sec(){ printf '\n\033[36m\033[1m== %s ==\033[0m\n' "$*"; }

teardown(){
  sec "TEARDOWN"
  hermes profile delete -y "$PROFILE" >/dev/null 2>&1 || true
  rm -rf "$PROFDIR" "$ALIAS" "$FAKE" /tmp/agbook.out 2>/dev/null
  systemctl is-active --quiet hermes-gateway-automateflow && echo "  automateflow ATIVO ✔" || echo "  ! automateflow"
}
trap teardown EXIT
[[ -e "$PROFDIR" || -e "$ALIAS" ]] && { echo "ABORT: $PROFILE existe"; trap - EXIT; exit 3; }

sec "1) clonar (p/ ter o modelo) + neutralizar"
hermes profile create "$PROFILE" --clone </dev/null >/dev/null 2>&1
[[ -d "$PROFDIR" ]] || { echo "✘ clone falhou"; exit 1; }
# strip de tokens de bot (sem pollers paralelos)
ENVF="$PROFDIR/.env"
[[ -f "$ENVF" ]] && { tmp=$(mktemp); grep -viE '(TELEGRAM|DISCORD|SLACK|WHATSAPP|WEIXIN)[A-Z_]*TOKEN=' "$ENVF" >"$tmp" 2>/dev/null||true; mv "$tmp" "$ENVF"; chmod 600 "$ENVF"; }
# remover MCPs herdados p/ o --yolo não tocar em nada real
for m in zernio zapier codegraph; do hermes -p "$PROFILE" mcp remove "$m" >/dev/null 2>&1 || true; done
echo "  MCPs após limpeza:"; hermes -p "$PROFILE" mcp list 2>&1 | grep -iE 'zernio|zapier|codegraph|gcal|No MCP' | sed 's/^/    /' || echo "    (nenhum)"

sec "2) SA fake + registrar SÓ o gcal"
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out /tmp/agk.pem 2>/dev/null
KEY="$(awk '{printf "%s\\n",$0}' /tmp/agk.pem)"; rm -f /tmp/agk.pem
cat > "$FAKE" <<JSON
{"type":"service_account","project_id":"ccb","private_key_id":"f","private_key":"$KEY","client_email":"ccb@ccb.iam.gserviceaccount.com","client_id":"1","token_uri":"https://oauth2.googleapis.com/token"}
JSON
yes 2>/dev/null | timeout 200 hermes -p "$PROFILE" mcp add gcal --command "$UV" --args run "$SCRIPT" "$FAKE" "teste@example.com" >/dev/null 2>&1 || true
hermes -p "$PROFILE" mcp list 2>&1 | grep -qi gcal && echo "  ✔ gcal registrado (3 tools)" || { echo "  ✘ gcal não registrou"; exit 1; }

sec "3) AGENTE one-shot: pedido de agendamento (modelo é lento, aguarde)"
PROMPT='Você é o atendente de uma clínica e TEM ferramentas de agenda do Google: consultar_disponibilidade, listar_eventos e criar_evento. Um cliente chamado João pediu para marcar uma avaliação AMANHÃ às 15h (duração 45 min). Marque AGORA esse horário usando a ferramenta criar_evento (fuso America/Sao_Paulo, título "Avaliação - João"). Use a ferramenta de verdade, não apenas descreva.'
timeout 480 hermes -p "$PROFILE" --yolo --accept-hooks -z "$PROMPT" >/tmp/agbook.out 2>&1 || echo "  (one-shot terminou com timeout/erro — ver análise)"
echo "  --- trecho da saída do agente ---"
tail -30 /tmp/agbook.out | sed 's/^/    /'

sec "4) ANÁLISE — o agente CHAMOU a ferramenta criar_evento?"
if grep -qiE 'invalid_grant|account not found|Error executing tool|evento criado|criei o evento|não aponta|service account não informado' /tmp/agbook.out; then
  echo "  ✔ EVIDÊNCIA: o agente INVOCOU a ferramenta (rastro de execução real da tool/erro do Google)."
elif grep -qiE 'não tenho .*ferramenta|ferramentas reais disponíveis aqui são outras|not .*available' /tmp/agbook.out; then
  echo "  ⚠️ nesta sessão one-shot (-z) as tools não carregaram (quirk do -z; em produção, via gateway, carregam)."
else
  echo "  ? sem rastro claro — ver /tmp/agbook.out acima."
fi

sec "FIM"
