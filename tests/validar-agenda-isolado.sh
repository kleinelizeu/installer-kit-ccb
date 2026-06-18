#!/usr/bin/env bash
# validar-agenda-isolado.sh — Valida AO VIVO o código REAL do passo da agenda do kit
# (_agenda_registrar_mcp + check_agenda) num perfil descartável. Isolado, teardown sempre.
# SA FAKE (estrutura válida) prova o registro do gcal MCP no Hermes (auth lazy).
# Uso (NA VPS): bash validar-agenda-isolado.sh <PRODUTO_DIR> [PROFILE]
set -uo pipefail
PRODUTO_DIR="${1:?caminho do produto vendorizado}"
PROFILE="${2:-ccbagenda}"
PROFDIR="/root/.hermes/profiles/$PROFILE"; ALIAS="/root/.local/bin/$PROFILE"
STATEDIR="/root/.ccb-agenda-tmp"
FAIL=0
sec(){ printf '\n\033[36m\033[1m== %s ==\033[0m\n' "$*"; }
okk(){ printf '  \033[32m✔\033[0m %s\n' "$*"; }
bad(){ printf '  \033[31m✘\033[0m %s\n' "$*"; FAIL=1; }

teardown(){
  sec "TEARDOWN"
  hermes profile delete -y "$PROFILE" >/dev/null 2>&1 || true
  rm -rf "$PROFDIR" "$ALIAS" "$STATEDIR" 2>/dev/null
  [[ -d "$PROFDIR" ]] && echo "  ! restou $PROFILE" || okk "perfil $PROFILE removido"
  systemctl is-active --quiet hermes-gateway-automateflow && okk "automateflow ATIVO" || echo "  ! automateflow"
}
trap teardown EXIT
[[ -e "$PROFDIR" || -e "$ALIAS" ]] && { echo "ABORT: $PROFILE existe"; trap - EXIT; exit 3; }

sec "1) perfil descartável + SA fake"
hermes profile create "$PROFILE" --no-skills --description "validacao agenda" </dev/null >/dev/null 2>&1
mkdir -p "$STATEDIR"; chmod 700 "$STATEDIR"
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out /tmp/agk.pem 2>/dev/null
KEY="$(awk '{printf "%s\\n",$0}' /tmp/agk.pem)"; rm -f /tmp/agk.pem
cat > "$STATEDIR/gcal-sa.json" <<JSON
{"type":"service_account","project_id":"ccb","private_key_id":"f","private_key":"$KEY","client_email":"ccb@ccb.iam.gserviceaccount.com","client_id":"1","token_uri":"https://oauth2.googleapis.com/token"}
JSON
chmod 600 "$STATEDIR/gcal-sa.json"; okk "SA fake gravado"

sec "2) chamar a FUNÇÃO REAL do kit (_agenda_registrar_mcp)"
export BASE_DIR="$PRODUTO_DIR"
# shellcheck source=/dev/null
source "$PRODUTO_DIR/produto.conf"
for f in "$PRODUTO_DIR"/lib/*.sh; do source "$f"; done
# shellcheck disable=SC2034
{ MODO=nativo; PERFIL="$PROFILE"; PERFIL_DIR="$PROFDIR"; PERFIL_BIN="$ALIAS"; GATEWAY_SVC=""
  ESTADO_DIR="$STATEDIR"; ESTADO_CONFIG="$STATEDIR/config"; ESTADO_PASSOS="$STATEDIR/passos"
  GCAL_SA_PATH="$STATEDIR/gcal-sa.json"; GCAL_ID="teste@example.com"; }
init_estado 2>/dev/null || true
declare -F passo_agenda >/dev/null && okk "passo_agenda/_agenda_* definidos (lib/36-agenda.sh)" || bad "lib/36-agenda.sh ausente"
_agenda_registrar_mcp 2>&1 | sed 's/^/    /'

sec "3) gcal no mcp list?"
hermes -p "$PROFILE" mcp list 2>&1 | grep -i gcal && okk "gcal registrado" || bad "gcal não registrado"

sec "4) check_agenda REAL do doctor"
DOC_FALHAS=0
check_agenda
echo "  -> DOC_FALHAS=$DOC_FALHAS (0 = agenda ok)"
[[ "$DOC_FALHAS" == 0 ]] || bad "check_agenda acusou falha"

sec "RESULTADO"
[[ "$FAIL" == 0 ]] && echo "  AGENDA (código do kit) AO VIVO: OK" || echo "  FALHOU"
exit "$FAIL"
