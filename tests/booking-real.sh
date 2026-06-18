#!/usr/bin/env bash
# booking-real.sh — PROVA REAL do agendamento: cria (confirma e apaga) um evento de teste
# no Google Calendar do negócio, usando a MESMA auth (service account) + as MESMAS chamadas
# de API do conector modelos/gcal_mcp.py. É o único passo que depende de uma credencial do
# usuário (Google exige login interativo p/ criar o service account).
#
# Uso (NA VPS):  bash booking-real.sh <CAMINHO_DO_SA_JSON> <CALENDAR_ID>
#   ex.: bash booking-real.sh /root/.gcal-sa.json minha-agenda@gmail.com
set -uo pipefail
SA="${1:?caminho do JSON do service account}"
CAL="${2:?id/e-mail da agenda (compartilhada com o e-mail do service account)}"
UV="$(command -v uv || echo /root/.local/bin/uv)"
[[ -f "$SA" ]] || { echo "✘ JSON não encontrado: $SA"; exit 1; }

PY="$(mktemp --suffix=.py)"
trap 'rm -f "$PY"' EXIT
cat > "$PY" <<'PYEOF'
# /// script
# requires-python = ">=3.10"
# dependencies = ["google-api-python-client>=2.100","google-auth>=2.30"]
# ///
import os, sys, datetime as dt
from google.oauth2 import service_account
from googleapiclient.discovery import build
cal = os.environ["GOOGLE_CALENDAR_ID"]
creds = service_account.Credentials.from_service_account_file(
    os.environ["GOOGLE_APPLICATION_CREDENTIALS"],
    scopes=["https://www.googleapis.com/auth/calendar"])
svc = build("calendar", "v3", credentials=creds, cache_discovery=False)
start = (dt.datetime.now() + dt.timedelta(days=1)).replace(hour=15, minute=0, second=0, microsecond=0)
end = start + dt.timedelta(minutes=45)
body = {"summary": "Teste CCB — pode apagar",
        "description": "Teste automático de agendamento (CCB). Criado e apagado pelo validador.",
        "start": {"dateTime": start.isoformat(), "timeZone": "America/Sao_Paulo"},
        "end": {"dateTime": end.isoformat(), "timeZone": "America/Sao_Paulo"}}
try:
    ev = svc.events().insert(calendarId=cal, body=body).execute()
except Exception as e:
    print("✘ FALHOU ao criar o evento:", e)
    print("  Dicas: a agenda foi COMPARTILHADA com o e-mail do service account (permissão 'fazer alterações')?")
    print("         a 'Google Calendar API' está ATIVADA no projeto?")
    sys.exit(1)
print("✔ EVENTO REAL CRIADO:", ev.get("htmlLink"))
got = svc.events().get(calendarId=cal, eventId=ev["id"]).execute()
print("✔ CONFIRMADO na agenda:", got.get("summary"), "@", got["start"]["dateTime"])
svc.events().delete(calendarId=cal, eventId=ev["id"]).execute()
print("✔ APAGADO (era só teste — agendamento real comprovado ponta a ponta).")
PYEOF

echo "→ Criando um evento de teste real na agenda '$CAL' (cria, confirma e apaga)..."
GOOGLE_APPLICATION_CREDENTIALS="$SA" GOOGLE_CALENDAR_ID="$CAL" "$UV" run "$PY"
