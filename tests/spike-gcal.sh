#!/usr/bin/env bash
# spike-gcal.sh — SPIKE do MCP de calendário PRÓPRIO da CCB (modelos/gcal_mcp.py via uv run).
# Service account SEM delegation (agenda compartilhada). Isolado, teardown sempre.
# SA FAKE (estrutura válida) só prova que o server sobe e o Hermes descobre as 3 tools
# (auth é lazy — só chamadas reais à API precisam de SA verdadeiro).
# Uso (NA VPS): bash spike-gcal.sh <SCRIPT_PY> [PROFILE]
set -uo pipefail
SCRIPT="${1:?caminho do gcal_mcp.py na VPS}"
PROFILE="${2:-ccbgcal}"
PROFDIR="/root/.hermes/profiles/$PROFILE"; ALIAS="/root/.local/bin/$PROFILE"
FAKE="/tmp/gcal-fake-sa.json"
UV="$(command -v uv || echo /root/.local/bin/uv)"
sec(){ printf '\n\033[36m\033[1m== %s ==\033[0m\n' "$*"; }

teardown(){
  sec "TEARDOWN"
  hermes profile delete -y "$PROFILE" >/dev/null 2>&1 || true
  rm -rf "$PROFDIR" "$ALIAS" "$FAKE" 2>/dev/null
  systemctl is-active --quiet hermes-gateway-automateflow && echo "  automateflow ATIVO ✔" || echo "  ! automateflow"
}
trap teardown EXIT
[[ -e "$PROFDIR" || -e "$ALIAS" ]] && { echo "ABORT: $PROFILE existe"; trap - EXIT; exit 3; }

sec "0) uv + SA fake"
echo "  uv: $UV  ($("$UV" --version 2>&1 | head -1))"
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out /tmp/gk.pem 2>/dev/null
KEY="$(awk '{printf "%s\\n",$0}' /tmp/gk.pem)"; rm -f /tmp/gk.pem
cat > "$FAKE" <<JSON
{"type":"service_account","project_id":"ccb-spike","private_key_id":"fake123","private_key":"$KEY","client_email":"ccb-spike@ccb-spike.iam.gserviceaccount.com","client_id":"123","token_uri":"https://oauth2.googleapis.com/token"}
JSON
python3 -c "import json;json.load(open('$FAKE'));print('  SA fake é JSON válido')"

sec "1) uv run instala as deps (PEP 723) e sobe o server? (1ª vez baixa; ~90s)"
timeout 120 sh -c "GOOGLE_APPLICATION_CREDENTIALS=$FAKE GOOGLE_CALENDAR_ID=test@example.com $UV run $SCRIPT </dev/null" >/tmp/gcal-start.log 2>&1 || true
if grep -qiE 'Traceback|Error|ModuleNotFound' /tmp/gcal-start.log; then
  echo "  ⚠️ saída com erro:"; tail -15 /tmp/gcal-start.log | sed 's/^/    /'
else
  echo "  ✔ subiu sem traceback (deps instaladas, FastMCP ok)"; tail -4 /tmp/gcal-start.log | sed 's/^/    /'
fi

sec "2) perfil descartável + registrar gcal no Hermes (uv run, sem args com '-')"
hermes profile create "$PROFILE" --no-skills --description "spike gcal" </dev/null >/dev/null 2>&1
echo "  hermes mcp add gcal --command $UV --args run $SCRIPT --env GOOGLE_APPLICATION_CREDENTIALS=... --env GOOGLE_CALENDAR_ID=..."
yes 2>/dev/null | timeout 200 hermes -p "$PROFILE" mcp add gcal --command "$UV" --args run "$SCRIPT" \
  --env "GOOGLE_APPLICATION_CREDENTIALS=$FAKE" --env "GOOGLE_CALENDAR_ID=test@example.com" 2>&1 | tail -12

sec "3) mcp list"
hermes -p "$PROFILE" mcp list 2>&1 | tail -12

sec "4) mcp test gcal (descobre criar_evento / consultar_disponibilidade / listar_eventos?)"
timeout 150 hermes -p "$PROFILE" mcp test gcal </dev/null 2>&1 | tail -25 || echo "  (mcp test erro/timeout)"

sec "FIM — gcal conectou? as 3 tools de agenda aparecem?"
