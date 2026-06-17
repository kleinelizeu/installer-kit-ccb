#!/usr/bin/env bash
# validar-vps-isolado.sh — Valida AO VIVO o pipeline de webhook de um produto
# numa VPS de produção COMPARTILHADA, de forma ISOLADA e segura:
#   - perfil descartável (SEM --clone → não copia segredos de produção)
#   - Telegram desligado (perfil novo não tem token)
#   - webhook em porta ALTERNATIVA (não colide com a produção)
#   - exercita as FUNÇÕES REAIS do kit (_habilitar_plataforma_webhook) e o
#     webhook.py patcheado, no Hermes real
#   - evidência objetiva: POST assinado -> 202/200 ; assinatura errada -> 401
#   - TEARDOWN sempre (trap) — nunca deixa artefato; nunca toca em default/automateflow
#
# Uso (NA VPS):  bash validar-vps-isolado.sh <PRODUTO_DIR> [PROFILE] [PORT]
set -uo pipefail

PRODUTO_DIR="${1:?caminho do produto vendorizado na VPS (ex.: /tmp/clinica-ccb)}"
PROFILE="${2:-ccbvalida}"
PORT="${3:-8645}"
PROFDIR="/root/.hermes/profiles/$PROFILE"
ALIAS="/root/.local/bin/$PROFILE"
GWLOG="/tmp/${PROFILE}-gw.log"
STATEDIR="/root/.ccb-valida-tmp"
GWPID=""
FAIL=0
sec(){ printf '\n\033[36m\033[1m== %s ==\033[0m\n' "$*"; }
okk(){ printf '  \033[32m✔\033[0m %s\n' "$*"; }
bad(){ printf '  \033[31m✘\033[0m %s\n' "$*"; FAIL=1; }

teardown() {
  sec "TEARDOWN (removendo tudo do perfil descartável)"
  [[ -n "$GWPID" ]] && kill "$GWPID" 2>/dev/null
  pkill -f "hermes -p $PROFILE gateway" 2>/dev/null
  sleep 1
  hermes profile delete -y "$PROFILE" >/dev/null 2>&1 || true
  rm -rf "$PROFDIR" "$ALIAS" "$STATEDIR" "$GWLOG" 2>/dev/null
  [[ -d "$PROFDIR" || -e "$ALIAS" ]] && echo "  ! restou algo de $PROFILE (verifique)" || okk "perfil $PROFILE removido"
  sec "PRODUÇÃO intacta?"
  systemctl is-active --quiet hermes-gateway-automateflow 2>/dev/null && okk "gateway automateflow ATIVO" || echo "  ! automateflow não-ativo (verifique)"
  ss -tlnp 2>/dev/null | grep -q ':8644' && okk "porta 8644 (produção) ainda escutando" || echo "  ! 8644 sumiu (verifique)"
  [[ -d /root/.hermes/profiles/automateflow ]] && okk "perfil automateflow intacto"
}
trap teardown EXIT

# Guard: não clobberar um perfil existente.
if [[ -e "$PROFDIR" || -e "$ALIAS" ]]; then echo "ABORT: perfil '$PROFILE' já existe — escolha outro nome."; trap - EXIT; exit 3; fi

sec "0) Produção ANTES"
systemctl is-active --quiet hermes-gateway-automateflow && okk "automateflow ATIVO (vou preservar)"
ss -tlnp 2>/dev/null | grep -q ':8644' && okk "8644 ocupado pela produção (uso $PORT)"

sec "1) Perfil isolado (SEM --clone)"
hermes profile create "$PROFILE" --no-skills --description "validacao CCB descartavel" </dev/null >/dev/null 2>&1
[[ -d "$PROFDIR" ]] && okk "perfil criado: $PROFDIR" || bad "perfil não criado"
if grep -qi 'TELEGRAM_BOT_TOKEN' "$PROFDIR/.env" 2>/dev/null; then bad "herdou token Telegram (não deveria)"; else okk "sem token Telegram (isolado, sem poller paralelo)"; fi

sec "2) Habilitar webhook via FUNÇÃO REAL DO KIT (porta $PORT)"
SECRET="ccbtest_$(head -c16 /dev/urandom | od -An -tx1 | tr -d ' \n')"
export BASE_DIR="$PRODUTO_DIR"
# shellcheck source=/dev/null
source "$PRODUTO_DIR/produto.conf"
for f in "$PRODUTO_DIR"/lib/*.sh; do source "$f"; done
# Estas variáveis são consumidas pelas FUNÇÕES do kit sourçadas acima (hermes_cli,
# _habilitar_plataforma_webhook, etc.) — shellcheck não enxerga esse uso.
# shellcheck disable=SC2034
MODO=nativo
CONFIG_FILE="$PROFDIR/config.yaml"
ENV_FILE="$PROFDIR/.env"
PERFIL="$PROFILE"
PERFIL_DIR="$PROFDIR"
PERFIL_BIN="$ALIAS"
WEBHOOK_HOST=127.0.0.1
WEBHOOK_PORT="$PORT"
WEBHOOK_SECRET="$SECRET"
WEBHOOK_PY=/usr/local/lib/hermes-agent/gateway/platforms/webhook.py
ESTADO_DIR="$STATEDIR"; mkdir -p "$ESTADO_DIR"
_habilitar_plataforma_webhook >/dev/null 2>&1
if grep -qE '^[[:space:]]+webhook:' "$CONFIG_FILE" && grep -q "port: $PORT" "$CONFIG_FILE"; then okk "plataforma webhook habilitada (porta $PORT)"; else bad "config webhook não aplicado"; fi

sec "3) Patch X-Zernio-Signature: idempotência no arquivo REAL"
b=$(grep -c 'X-Zernio-Signature' "$WEBHOOK_PY" 2>/dev/null || echo 0)
python3 "$PRODUTO_DIR/modelos/apply_zernio_patch.py" "$WEBHOOK_PY" >/dev/null 2>&1 || true
a=$(grep -c 'X-Zernio-Signature' "$WEBHOOK_PY" 2>/dev/null || echo 0)
[[ "$b" -ge 1 && "$a" == "$b" ]] && okk "patch idempotente (marcador estável em $a)" || bad "patch não idempotente (antes=$b depois=$a)"

sec "4) Rota do webhook (deliver log — sem Telegram)"
hermes -p "$PROFILE" webhook subscribe zernio --secret "$SECRET" --deliver log \
  --prompt "$(cat "$PRODUTO_DIR/modelos/prompt-rota-webhook.txt")" </dev/null >/dev/null 2>&1
hermes -p "$PROFILE" webhook list 2>/dev/null | grep -qi zernio && okk "rota 'zernio' criada" || bad "rota não criada"

sec "5) Subir o gateway do perfil (foreground, só webhook)"
setsid bash -c "hermes -p $PROFILE gateway run >$GWLOG 2>&1" </dev/null &
GWPID=$!
for _ in $(seq 1 25); do ss -tlnp 2>/dev/null | grep -q ":$PORT" && break; sleep 1; done
if ss -tlnp 2>/dev/null | grep -q ":$PORT"; then okk "listener no ar na porta $PORT"; else bad "listener não subiu"; tail -15 "$GWLOG" 2>/dev/null | sed 's/^/    /'; fi

sec "6) EVIDÊNCIA: assinado->202 ; errado->401 ; sem-assinatura->401"
BODY='{"ping":true}'
SIG=$(printf '%s' "$BODY" | openssl dgst -sha256 -hmac "$SECRET" -hex | awk '{print $NF}')
URL="http://127.0.0.1:$PORT/webhooks/zernio"
C_OK=$(curl -so /dev/null -w '%{http_code}' --max-time 15 -X POST "$URL" -H 'Content-Type: application/json' -H "X-Zernio-Signature: $SIG" -d "$BODY" 2>/dev/null || echo 000)
C_BAD=$(curl -so /dev/null -w '%{http_code}' --max-time 15 -X POST "$URL" -H 'Content-Type: application/json' -H "X-Zernio-Signature: deadbeefdeadbeef" -d "$BODY" 2>/dev/null || echo 000)
C_NONE=$(curl -so /dev/null -w '%{http_code}' --max-time 15 -X POST "$URL" -H 'Content-Type: application/json' -d "$BODY" 2>/dev/null || echo 000)
echo "    assinado=$C_OK  errado=$C_BAD  sem-assinatura=$C_NONE"
{ [[ "$C_OK" == 202 || "$C_OK" == 200 ]]; } && okk "POST assinado aceito ($C_OK)" || bad "assinado deu $C_OK (esperado 202/200)"
[[ "$C_BAD" == 401 ]] && okk "assinatura errada rejeitada (401)" || bad "assinatura errada deu $C_BAD (esperado 401)"
[[ "$C_NONE" == 401 ]] && okk "sem assinatura rejeitada (401)" || echo "    (sem-assinatura=$C_NONE)"

sec "RESULTADO"
[[ "$FAIL" == 0 ]] && echo "  VALIDACAO AO VIVO: OK" || echo "  VALIDACAO AO VIVO: FALHOU"
# teardown roda no trap EXIT; preserva o código de saída
exit "$FAIL"
