#!/usr/bin/env bash
# validar-vps-completo.sh — Valida AO VIVO quase TODO o fluxo nativo de um produto,
# de forma ISOLADA numa VPS de produção compartilhada. Vai além do validar-vps-isolado.sh:
# exercita as FUNÇÕES REAIS do kit para gateway-install (systemd) e túnel Cloudflare,
# e prova 202/401 TANTO no localhost QUANTO através do TÚNEL público real (como o Zernio).
#
# Continua seguro: perfil descartável SEM --clone (sem segredos de produção), Telegram off,
# porta/unit ALTERNATIVOS, teardown sempre (trap), nunca toca em default/automateflow.
#
# NÃO cobre (precisa de VPS limpa + credenciais reais do aluno): --clone, reconfig do
# Telegram do aluno, painel do Zernio, wizard 2x interativo.
#
# Uso (NA VPS):  bash validar-vps-completo.sh <PRODUTO_DIR> [PROFILE] [PORT]
set -uo pipefail

PRODUTO_DIR="${1:?caminho do produto vendorizado na VPS}"
PROFILE="${2:-ccbvalida}"
PORT="${3:-8645}"
PROFDIR="/root/.hermes/profiles/$PROFILE"
ALIAS="/root/.local/bin/$PROFILE"
STATEDIR="/root/.ccb-valida-tmp"
TUNIT="cloudflared-${PROFILE}"
TLOG="/var/log/${TUNIT}.log"
GSVC=""        # unit do gateway (descoberto)
FAIL=0
sec(){ printf '\n\033[36m\033[1m== %s ==\033[0m\n' "$*"; }
okk(){ printf '  \033[32m✔\033[0m %s\n' "$*"; }
bad(){ printf '  \033[31m✘\033[0m %s\n' "$*"; FAIL=1; }

teardown() {
  sec "TEARDOWN"
  systemctl stop "$TUNIT" 2>/dev/null; systemctl disable "$TUNIT" 2>/dev/null
  rm -f "/etc/systemd/system/${TUNIT}.service" "$TLOG" 2>/dev/null
  # gateway do perfil: tenta uninstall do kit e força remoção da unit
  yes 2>/dev/null | "$ALIAS" gateway uninstall 2>/dev/null || true
  [[ -n "$GSVC" ]] && { systemctl stop "$GSVC" 2>/dev/null; systemctl disable "$GSVC" 2>/dev/null; rm -f "/etc/systemd/system/${GSVC}" "/etc/systemd/system/${GSVC}.service" 2>/dev/null; }
  pkill -f "hermes -p $PROFILE gateway" 2>/dev/null
  systemctl daemon-reload 2>/dev/null
  hermes profile delete -y "$PROFILE" >/dev/null 2>&1 || true
  rm -rf "$PROFDIR" "$ALIAS" "$STATEDIR" 2>/dev/null
  { [[ -d "$PROFDIR" || -e "$ALIAS" ]] && echo "  ! restou algo de $PROFILE"; } || okk "perfil $PROFILE + units removidos"
  sec "PRODUÇÃO intacta?"
  systemctl is-active --quiet hermes-gateway-automateflow && okk "automateflow ATIVO" || echo "  ! automateflow não-ativo (verifique)"
  ss -tlnp 2>/dev/null | grep -q ':8644' && okk "porta 8644 (produção) escutando" || echo "  ! 8644 sumiu (verifique)"
  systemctl is-active --quiet cloudflared-mission-control && okk "túnel mission-control (produção) ATIVO" || echo "  (mission-control não-ativo)"
}
trap teardown EXIT

if [[ -e "$PROFDIR" || -e "$ALIAS" || -e "/etc/systemd/system/${TUNIT}.service" ]]; then
  echo "ABORT: '$PROFILE' ou unit '$TUNIT' já existe."; trap - EXIT; exit 3
fi

sec "0) Produção ANTES"
systemctl is-active --quiet hermes-gateway-automateflow && okk "automateflow ATIVO (preservar)"

sec "1) Perfil isolado (SEM --clone)"
hermes profile create "$PROFILE" --no-skills --description "validacao CCB descartavel" </dev/null >/dev/null 2>&1
[[ -d "$PROFDIR" ]] && okk "perfil criado" || bad "perfil não criado"
grep -qi 'TELEGRAM_BOT_TOKEN' "$PROFDIR/.env" 2>/dev/null && bad "herdou token (não deveria)" || okk "sem token Telegram (isolado)"

sec "2) Carregar motor do kit + variáveis isoladas"
SECRET="ccbtest_$(head -c16 /dev/urandom | od -An -tx1 | tr -d ' \n')"
export BASE_DIR="$PRODUTO_DIR"
# shellcheck source=/dev/null
source "$PRODUTO_DIR/produto.conf"
for f in "$PRODUTO_DIR"/lib/*.sh; do source "$f"; done
# overrides isolados (consumidos pelas funções do kit):
# shellcheck disable=SC2034
{ MODO=nativo; CONFIG_FILE="$PROFDIR/config.yaml"; ENV_FILE="$PROFDIR/.env"; PERFIL="$PROFILE"
  PERFIL_DIR="$PROFDIR"; PERFIL_BIN="$ALIAS"; WEBHOOK_HOST=127.0.0.1; WEBHOOK_PORT="$PORT"
  WEBHOOK_SECRET="$SECRET"; WEBHOOK_PY=/usr/local/lib/hermes-agent/gateway/platforms/webhook.py
  TUNEL_UNIT="$TUNIT"; TUNEL_LOG="$TLOG"; ESTADO_DIR="$STATEDIR"; }
mkdir -p "$ESTADO_DIR"
okk "motor carregado (porta $PORT, unit túnel $TUNIT)"

sec "3) Habilitar webhook (função do kit)"
_habilitar_plataforma_webhook >/dev/null 2>&1
grep -qE '^[[:space:]]+webhook:' "$CONFIG_FILE" && grep -q "port: $PORT" "$CONFIG_FILE" && okk "webhook habilitado (porta $PORT)" || bad "config webhook não aplicado"

sec "4) Rota (deliver log, sem Telegram)"
hermes -p "$PROFILE" webhook subscribe zernio --secret "$SECRET" --deliver log \
  --prompt "$(cat "$PRODUTO_DIR/modelos/prompt-rota-webhook.txt")" </dev/null >/dev/null 2>&1
hermes -p "$PROFILE" webhook list 2>/dev/null | grep -qi zernio && okk "rota criada" || bad "rota não criada"

sec "5) GATEWAY-INSTALL via systemd (função do kit _instalar_servico_nativo)"
_instalar_servico_nativo >/dev/null 2>&1 || true
GSVC="$(_descobrir_unit)"
if [[ -n "$GSVC" ]] && systemctl is-active --quiet "$GSVC"; then okk "gateway systemd ativo: $GSVC"; else bad "gateway systemd não subiu (unit='$GSVC')"; fi
for _ in $(seq 1 20); do ss -tlnp 2>/dev/null | grep -q ":$PORT" && break; sleep 1; done
ss -tlnp 2>/dev/null | grep -q ":$PORT" && okk "listener na porta $PORT" || bad "porta $PORT não escuta"

sec "6) 202/401 no localhost"
BODY='{"ping":true}'; URLL="http://127.0.0.1:$PORT/webhooks/zernio"
SIG=$(printf '%s' "$BODY" | openssl dgst -sha256 -hmac "$SECRET" -hex | awk '{print $NF}')
L_OK=$(curl -so /dev/null -w '%{http_code}' --max-time 15 -X POST "$URLL" -H "X-Zernio-Signature: $SIG" -d "$BODY" 2>/dev/null||echo 000)
L_BAD=$(curl -so /dev/null -w '%{http_code}' --max-time 15 -X POST "$URLL" -H "X-Zernio-Signature: bad" -d "$BODY" 2>/dev/null||echo 000)
echo "    local: assinado=$L_OK errado=$L_BAD"
{ [[ "$L_OK" =~ ^20[02]$ ]] && okk "local assinado $L_OK"; } || bad "local assinado $L_OK"
[[ "$L_BAD" == 401 ]] && okk "local errado 401" || bad "local errado $L_BAD"

sec "7) TÚNEL Cloudflare (funções do kit) + 202/401 PÚBLICO"
_instalar_cloudflared >/dev/null 2>&1 || true
_instalar_servico_tunel >/dev/null 2>&1 || true
_capturar_url_tunel >/dev/null 2>&1 || true
if [[ -n "${WEBHOOK_URL:-}" ]]; then
  okk "túnel no ar: $WEBHOOK_URL"
  sleep 3
  SIG2=$(printf '%s' "$BODY" | openssl dgst -sha256 -hmac "$SECRET" -hex | awk '{print $NF}')
  P_OK=$(curl -so /dev/null -w '%{http_code}' --max-time 25 -X POST "$WEBHOOK_URL" -H "X-Zernio-Signature: $SIG2" -d "$BODY" 2>/dev/null||echo 000)
  P_BAD=$(curl -so /dev/null -w '%{http_code}' --max-time 25 -X POST "$WEBHOOK_URL" -H "X-Zernio-Signature: bad" -d "$BODY" 2>/dev/null||echo 000)
  echo "    público: assinado=$P_OK errado=$P_BAD"
  { [[ "$P_OK" =~ ^20[02]$ ]] && okk "PÚBLICO assinado $P_OK (ponta-a-ponta como o Zernio)"; } || bad "público assinado $P_OK"
  [[ "$P_BAD" == 401 ]] && okk "público errado 401" || bad "público errado $P_BAD"
else
  bad "túnel não retornou URL (a captura tem timeout; pode reprovar por lentidão da rede)"
fi

sec "RESULTADO"
[[ "$FAIL" == 0 ]] && echo "  VALIDACAO COMPLETA (isolada): OK" || echo "  VALIDACAO: FALHOU"
exit "$FAIL"
