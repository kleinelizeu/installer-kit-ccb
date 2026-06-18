#!/usr/bin/env bash
# demo-agent-booking-real.sh — DEMO AO VIVO: o AGENTE Hermes marca um evento REAL no Google Calendar.
#
# Isolado e seguro: clona o perfil ativo só p/ herdar o MODELO, REMOVE os MCPs herdados
# (zernio/zapier/codegraph) p/ o --yolo não tocar em nada real, faz STRIP dos tokens de bot
# (sem poller paralelo), e registra SÓ o gcal com SA + agenda REAIS. Roda um one-shot de
# agendamento, CONFIRMA via API que o evento foi criado de verdade, APAGA o evento (cleanup)
# e faz teardown do perfil. NUNCA toca em default/automateflow (produção).
#
# Uso (NA VPS):  bash demo-agent-booking-real.sh <gcal_mcp.py> <sa.json> <calendar_id> [profile]
set -uo pipefail
export PATH="/root/.local/bin:/usr/local/bin:$PATH"
SCRIPT="${1:?caminho do gcal_mcp.py}"; SA="${2:?caminho do sa.json}"; CAL="${3:?calendar_id}"
PROFILE="${4:-ccbdemo}"
PROFDIR="/root/.hermes/profiles/$PROFILE"; ALIAS="/root/.local/bin/$PROFILE"
UV="$(command -v uv || echo /root/.local/bin/uv)"
TITULO="Hermes Demo - agendou sozinho"
sec(){ printf '\n\033[36m\033[1m== %s ==\033[0m\n' "$*"; }

teardown(){
  sec "TEARDOWN"
  hermes profile delete -y "$PROFILE" >/dev/null 2>&1 || true
  rm -rf "$PROFDIR" "$ALIAS" /tmp/agdemo.out /tmp/ccb-verify.py 2>/dev/null
  if systemctl is-active --quiet hermes-gateway-automateflow; then echo "  automateflow (producao) ATIVO ✔"; else echo "  ! automateflow nao-ativo (verificar)"; fi
}
trap teardown EXIT
[[ -e "$PROFDIR" || -e "$ALIAS" ]] && { echo "ABORT: perfil $PROFILE ja existe"; trap - EXIT; exit 3; }

sec "1) clonar (p/ herdar o modelo) + neutralizar (sem tocar em nada real)"
hermes profile create "$PROFILE" --clone </dev/null >/dev/null 2>&1
[[ -d "$PROFDIR" ]] || { echo "✘ clone falhou"; exit 1; }
ENVF="$PROFDIR/.env"
[[ -f "$ENVF" ]] && { tmp=$(mktemp); grep -viE '(TELEGRAM|DISCORD|SLACK|WHATSAPP|WEIXIN)[A-Z_]*TOKEN=' "$ENVF" >"$tmp" 2>/dev/null||true; mv "$tmp" "$ENVF"; chmod 600 "$ENVF"; }
for m in zernio zapier codegraph; do hermes -p "$PROFILE" mcp remove "$m" >/dev/null 2>&1 || true; done
echo "  MCPs apos limpeza:"; hermes -p "$PROFILE" mcp list 2>&1 | grep -iE 'zernio|zapier|codegraph|gcal|No MCP' | sed 's/^/    /' || true

sec "2) registrar SÓ o gcal (SA + agenda REAIS, como o wizard faz)"
yes 2>/dev/null | timeout 240 hermes -p "$PROFILE" mcp add gcal --command "$UV" --args run "$SCRIPT" "$SA" "$CAL" >/dev/null 2>&1 || true
hermes -p "$PROFILE" mcp list 2>&1 | grep -qi gcal && echo "  ✔ gcal registrado (3 tools)" || { echo "  ✘ gcal nao registrou"; exit 1; }

sec "3) AGENTE one-shot: marcar amanha 16h (modelo free e LENTO, pode levar minutos)"
DAY="$(date -d tomorrow +%Y-%m-%d 2>/dev/null || date -v+1d +%Y-%m-%d)"
PROMPT="Voce e o atendente e TEM ferramentas reais de Google Agenda: consultar_disponibilidade, listar_eventos e criar_evento. Um cliente quer marcar uma reuniao AMANHA (${DAY}) as 16:00, durando 30 minutos. Use AGORA a ferramenta criar_evento DE VERDADE (nao apenas descreva): titulo '${TITULO}', inicio_iso '${DAY}T16:00:00-03:00', fim_iso '${DAY}T16:30:00-03:00', fuso America/Sao_Paulo. Depois responda com o link do evento criado."
timeout 540 hermes -p "$PROFILE" --yolo --accept-hooks -z "$PROMPT" >/tmp/agdemo.out 2>&1 || echo "  (one-shot encerrou por timeout/erro — ver analise abaixo)"
echo "  --- ultimas linhas da saida do agente ---"; tail -25 /tmp/agdemo.out | sed 's/^/    /'

sec "4) CONFIRMAR (sem LLM) que o evento REAL existe na agenda + cleanup"
cat > /tmp/ccb-verify.py <<'PY'
# /// script
# requires-python = ">=3.10"
# dependencies = ["google-api-python-client>=2.100","google-auth>=2.30"]
# ///
import sys
from google.oauth2 import service_account
from googleapiclient.discovery import build
SA, CAL, DAY, TITULO = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
creds = service_account.Credentials.from_service_account_file(SA, scopes=["https://www.googleapis.com/auth/calendar"])
svc = build("calendar", "v3", credentials=creds, cache_discovery=False)
resp = svc.events().list(calendarId=CAL, timeMin=DAY+"T00:00:00-03:00",
                         timeMax=DAY+"T23:59:59-03:00", singleEvents=True, q=TITULO).execute()
achados = [e for e in resp.get("items", []) if TITULO.split(" -")[0] in e.get("summary", "")]
if not achados:
    print("  ✘ NAO encontrei o evento criado pelo agente (ver saida do agente acima).")
    sys.exit(1)
e = achados[0]
ini = e.get("start", {}).get("dateTime", "?")
print(f"  ✔✔ EVENTO REAL CONFIRMADO: '{e.get('summary')}' em {ini}")
print(f"     id:   {e.get('id')}")
print(f"     link: {e.get('htmlLink')}")
svc.events().delete(calendarId=CAL, eventId=e["id"]).execute()
print("  ✔ evento de demo REMOVIDO (cleanup — nao deixa lixo na agenda).")
PY
"$UV" run /tmp/ccb-verify.py "$SA" "$CAL" "$DAY" "$TITULO" 2>&1 | grep -vE '^(Installed|Resolved|Prepared|Downloaded|Downloading|Audited|Building|Built| *[+~-] )'

sec "FIM"
