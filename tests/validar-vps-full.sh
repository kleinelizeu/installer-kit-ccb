#!/usr/bin/env bash
# validar-vps-full.sh — Valida o fluxo NATIVO quase completo de um produto SOLO,
# isolado numa VPS de produção. Vai além do validar-vps-completo.sh: testa também o
# --clone REAL (com os tokens de bot NEUTRALIZADOS p/ não conflitar com a produção),
# a geração de contexto, o registro do Zernio MCP, o doctor e a idempotência (2x).
# Telegram fica DESLIGADO (sem token) — "bot responde no Telegram" não é coberto aqui.
#
# Segurança: perfil descartável; STRIP de todos os tokens de bot do clone e ABORT se
# sobrar algum antes de subir o gateway; teardown sempre; nunca toca default/automateflow.
#
# Uso (NA VPS): bash validar-vps-full.sh <PRODUTO_DIR> <ZERNIO_KEY> [PROFILE] [PORT]
set -uo pipefail
PRODUTO_DIR="${1:?caminho do produto vendorizado}"
ZK="${2:-}"
PROFILE="${3:-ccbfull}"
PORT="${4:-8645}"
PROFDIR="/root/.hermes/profiles/$PROFILE"
ALIAS="/root/.local/bin/$PROFILE"
STATEDIR="/root/.ccb-full-tmp"
TUNIT="cloudflared-${PROFILE}"
TLOG="/var/log/${TUNIT}.log"
GSVC=""
FAIL=0
sec(){ printf '\n\033[36m\033[1m== %s ==\033[0m\n' "$*"; }
okk(){ printf '  \033[32m✔\033[0m %s\n' "$*"; }
bad(){ printf '  \033[31m✘\033[0m %s\n' "$*"; FAIL=1; }
inf(){ printf '  %s\n' "$*"; }

teardown(){
  sec "TEARDOWN"
  systemctl stop "$TUNIT" 2>/dev/null; systemctl disable "$TUNIT" 2>/dev/null
  rm -f "/etc/systemd/system/${TUNIT}.service" "$TLOG" 2>/dev/null
  yes 2>/dev/null | "$ALIAS" gateway uninstall 2>/dev/null || true
  [[ -n "$GSVC" ]] && { systemctl stop "$GSVC" 2>/dev/null; systemctl disable "$GSVC" 2>/dev/null; rm -f "/etc/systemd/system/${GSVC}" 2>/dev/null; }
  pkill -f "hermes -p $PROFILE gateway" 2>/dev/null
  systemctl daemon-reload 2>/dev/null
  hermes profile delete -y "$PROFILE" >/dev/null 2>&1 || true
  rm -rf "$PROFDIR" "$ALIAS" "$STATEDIR" 2>/dev/null   # remove os segredos clonados
  { [[ -d "$PROFDIR" || -e "$ALIAS" ]] && echo "  ! restou algo de $PROFILE"; } || okk "perfil $PROFILE + segredos clonados removidos"
  sec "PRODUÇÃO intacta?"
  systemctl is-active --quiet hermes-gateway-automateflow && okk "automateflow ATIVO" || echo "  ! automateflow não-ativo (verifique)"
  ss -tlnp 2>/dev/null | grep -q ':8644' && okk "porta 8644 (produção) escutando" || echo "  ! 8644 sumiu"
}
trap teardown EXIT
[[ -e "$PROFDIR" || -e "$ALIAS" || -e "/etc/systemd/system/${TUNIT}.service" ]] && { echo "ABORT: '$PROFILE'/'$TUNIT' já existe"; trap - EXIT; exit 3; }

sec "0) Produção ANTES"
systemctl is-active --quiet hermes-gateway-automateflow && okk "automateflow ATIVO (preservar)"

sec "1) --clone REAL + verificar clone-leak + NEUTRALIZAR tokens de bot"
hermes profile create "$PROFILE" --clone </dev/null >/dev/null 2>&1
[[ -d "$PROFDIR" ]] && okk "perfil clonado (--clone)" || bad "clone falhou"
ENVF="$PROFDIR/.env"
if grep -qiE '(TELEGRAM|DISCORD|SLACK|WHATSAPP|WEIXIN)[A-Z_]*TOKEN=' "$ENVF" 2>/dev/null; then
  inf "clone-leak confirmado: o --clone trouxe token(s) de bot (esperado; é o que a reconfig conserta)"
fi
# STRIP de TODOS os tokens de bot/mensageria do clone (segurança: nada de poller paralelo).
if [[ -f "$ENVF" ]]; then
  tmp="$(mktemp)"; grep -viE '(TELEGRAM|DISCORD|SLACK|WHATSAPP|WEIXIN)[A-Z_]*TOKEN=' "$ENVF" > "$tmp" 2>/dev/null || true
  mv "$tmp" "$ENVF"; chmod 600 "$ENVF"
fi
# Também desliga a plataforma telegram no config.yaml, se houver.
CFG="$PROFDIR/config.yaml"
[[ -f "$CFG" ]] && python3 - "$CFG" <<'PY' 2>/dev/null || true
import sys,re
p=sys.argv[1]; s=open(p,encoding="utf-8").read()
s=re.sub(r'(\n  telegram:\n(?:    .*\n)*?    enabled:\s*)true', r'\1false', s)
open(p,"w",encoding="utf-8").write(s)
PY
# ABORT se sobrou QUALQUER token de bot antes de subir o gateway.
if grep -qiE '(TELEGRAM|DISCORD|SLACK|WHATSAPP|WEIXIN)[A-Z_]*TOKEN=.+' "$ENVF" 2>/dev/null; then
  bad "ainda há token de bot no perfil — ABORTANDO antes de subir o gateway (segurança)"; exit 1
fi
okk "tokens de bot neutralizados (gateway do clinica não fará polling de Telegram)"

sec "2) Carregar motor + variáveis isoladas"
SECRET="ccbtest_$(head -c16 /dev/urandom | od -An -tx1 | tr -d ' \n')"
export BASE_DIR="$PRODUTO_DIR"
# shellcheck source=/dev/null
source "$PRODUTO_DIR/produto.conf"
for f in "$PRODUTO_DIR"/lib/*.sh; do source "$f"; done
# shellcheck disable=SC2034
{ MODO=nativo; PERFIL="$PROFILE"; PERFIL_DIR="$PROFDIR"; PERFIL_BIN="$ALIAS"; ENV_FILE="$ENVF"
  CONFIG_FILE="$CFG"; WEBHOOK_HOST=127.0.0.1; WEBHOOK_PORT="$PORT"; WEBHOOK_SECRET="$SECRET"
  WEBHOOK_PY=/usr/local/lib/hermes-agent/gateway/platforms/webhook.py; TELEGRAM_CHAT_ID="987443079"
  TUNEL_UNIT="$TUNIT"; TUNEL_LOG="$TLOG"; ESTADO_DIR="$STATEDIR"; ZERNIO_API_KEY="$ZK"; BOT_USERNAME="(sem telegram)"
  ESTADO_CONFIG="$STATEDIR/config"; ESTADO_PASSOS="$STATEDIR/passos"; ESTADO_CONTEXTO="$STATEDIR/business-context.md"; }
mkdir -p "$ESTADO_DIR"; init_estado 2>/dev/null || true
# Popula o estado (o doctor lê daqui; normalmente o wizard interativo grava isto).
for kv in "MODO nativo" "PERFIL $PROFILE" "PERFIL_DIR $PROFDIR" "PERFIL_BIN $ALIAS" \
          "CONFIG_FILE $CFG" "ENV_FILE $ENVF" "WEBHOOK_PY $WEBHOOK_PY" "WEBHOOK_HOST 127.0.0.1" \
          "WEBHOOK_PORT $PORT" "WEBHOOK_SECRET $SECRET" "TELEGRAM_CHAT_ID 987443079"; do
  salvar_var "${kv%% *}" "${kv#* }"
done
okk "motor carregado (porta $PORT)"

sec "3) Contexto do negócio (gerar com respostas de exemplo)"
NOME_NEGOCIO="Clínica Validação"; O_QUE_VENDE="procedimentos estéticos"; CLIENTE_IDEAL="pacientes locais"
FAIXA_PRECO="(sob avaliação)"; INSTAGRAM_HANDLE="@validacao"; TOM_DE_VOZ_DESCRICAO="Acolhedor."
RESTRICOES="Nada de diagnóstico online."; REGRA_PRECO="Convide para avaliação."
_carregar_perguntas "$PRODUTO_DIR/nicho/negocio.perguntas" >/dev/null 2>&1
_gerar_contexto >/dev/null 2>&1
[[ -f "$ESTADO_CONTEXTO" ]] && ! grep -q '{{' "$ESTADO_CONTEXTO" && okk "contexto gerado (sem {{ }})" || bad "contexto não gerado"

sec "4) Webhook: habilitar + patch idempotente + rota"
_habilitar_plataforma_webhook >/dev/null 2>&1
grep -qE '^[[:space:]]+webhook:' "$CFG" && grep -q "port: $PORT" "$CFG" && okk "webhook habilitado ($PORT)" || bad "webhook não habilitado"
hermes -p "$PROFILE" webhook subscribe zernio --secret "$SECRET" --deliver log \
  --prompt "$(cat "$PRODUTO_DIR/modelos/prompt-rota-webhook.txt")" </dev/null >/dev/null 2>&1
hermes -p "$PROFILE" webhook list 2>/dev/null | grep -qi zernio && okk "rota zernio criada" || bad "rota não criada"

sec "5) Zernio MCP (registrar com a chave real) — testa o caminho do 30-mcp"
if [[ -n "$ZK" ]]; then
  yes 2>/dev/null | timeout 120 hermes -p "$PROFILE" mcp add zernio --command npx --args -y mcp-remote@latest https://mcp.zernio.com/mcp --header "Authorization: Bearer $ZK" >/tmp/zadd.out 2>&1 || true
  if hermes -p "$PROFILE" mcp list 2>/dev/null | grep -qi zernio; then okk "Zernio MCP registrado (forma npx)"
  else
    inf "forma npx falhou (esperado p/ 0.15.1: '-y' quebra argparse). Tentando forma nativa --url/--auth..."
    yes 2>/dev/null | timeout 120 hermes -p "$PROFILE" mcp add zernio --url https://mcp.zernio.com/mcp --auth header --env "Authorization=Bearer $ZK" >/tmp/zadd2.out 2>&1 || true
    if hermes -p "$PROFILE" mcp list 2>/dev/null | grep -qi zernio; then okk "Zernio MCP registrado (forma --url/--auth)"
    else inf "ATENÇÃO: nenhuma forma de CLI registrou o Zernio (cai no fallback manual do wizard). Ver /tmp/zadd*.out"; fi
  fi
else
  inf "(sem chave Zernio — pulando MCP)"
fi

sec "6) Gateway-install systemd (só webhook, Telegram off)"
_instalar_servico_nativo >/dev/null 2>&1 || true
GSVC="$(_descobrir_unit)"
[[ -n "$GSVC" ]] && salvar_var GATEWAY_SVC "$GSVC"
[[ -n "$GSVC" ]] && systemctl is-active --quiet "$GSVC" && okk "gateway systemd ativo: $GSVC" || bad "gateway systemd não subiu ('$GSVC')"
for _ in $(seq 1 45); do ss -tlnp 2>/dev/null | grep -q ":$PORT" && break; sleep 1; done
ss -tlnp 2>/dev/null | grep -q ":$PORT" && okk "listener na porta $PORT" || bad "porta $PORT não escuta (após 45s)"
# SEGURANÇA: confirmar que o clinica NÃO está fazendo polling do Telegram (sem conflito c/ o case)
sleep 2
if journalctl -u "$GSVC" --no-pager -n 50 2>/dev/null | grep -qiE 'telegram.*(polling|getUpdates|started)'; then
  bad "clinica parece estar com Telegram ativo — risco ao case! (investigar)"
else
  okk "clinica sem polling de Telegram (case protegido)"
fi

sec "7) Túnel + 202/401 (local e público)"
_instalar_cloudflared >/dev/null 2>&1 || true
_instalar_servico_tunel >/dev/null 2>&1 || true
_capturar_url_tunel >/dev/null 2>&1 || true
BODY='{"ping":true}'; SIG=$(printf '%s' "$BODY" | openssl dgst -sha256 -hmac "$SECRET" -hex | awk '{print $NF}')
LURL="http://127.0.0.1:$PORT/webhooks/zernio"
L_OK=$(curl -so /dev/null -w '%{http_code}' --max-time 15 -X POST "$LURL" -H "X-Zernio-Signature: $SIG" -d "$BODY" 2>/dev/null||echo 000)
L_BAD=$(curl -so /dev/null -w '%{http_code}' --max-time 15 -X POST "$LURL" -H "X-Zernio-Signature: bad" -d "$BODY" 2>/dev/null||echo 000)
echo "    local: assinado=$L_OK errado=$L_BAD"
[[ "$L_OK" =~ ^20[02]$ ]] && okk "local 202" || bad "local assinado=$L_OK"
[[ "$L_BAD" == 401 ]] && okk "local 401" || bad "local errado=$L_BAD"
if [[ -n "${WEBHOOK_URL:-}" ]]; then
  okk "túnel: $WEBHOOK_URL"; sleep 3
  P_OK=$(curl -so /dev/null -w '%{http_code}' --max-time 25 -X POST "$WEBHOOK_URL" -H "X-Zernio-Signature: $SIG" -d "$BODY" 2>/dev/null||echo 000)
  P_BAD=$(curl -so /dev/null -w '%{http_code}' --max-time 25 -X POST "$WEBHOOK_URL" -H "X-Zernio-Signature: bad" -d "$BODY" 2>/dev/null||echo 000)
  echo "    público: assinado=$P_OK errado=$P_BAD"
  [[ "$P_OK" =~ ^20[02]$ ]] && okk "público 202 (ponta-a-ponta)" || bad "público assinado=$P_OK"
  [[ "$P_BAD" == 401 ]] && okk "público 401" || bad "público errado=$P_BAD"
else bad "túnel sem URL"; fi

sec "8) DOCTOR (real) — telegram-bot vermelho é ESPERADO (sem token)"
rodar_doctor 2>&1 | grep -E '✔|✘|⚙|atenção|pronto' | sed 's/^/    /'

sec "9) IDEMPOTÊNCIA — re-rodar passos não duplica"
before_wh=$(grep -c 'webhook:' "$CFG"); _habilitar_plataforma_webhook >/dev/null 2>&1; after_wh=$(grep -c 'webhook:' "$CFG")
[[ "$before_wh" == "$after_wh" ]] && okk "habilitar webhook idempotente (sem duplicar)" || bad "webhook duplicou ($before_wh->$after_wh)"
before_rt=$(hermes -p "$PROFILE" webhook list 2>/dev/null | grep -ci zernio); _criar_rota >/dev/null 2>&1; after_rt=$(hermes -p "$PROFILE" webhook list 2>/dev/null | grep -ci zernio)
[[ "$before_rt" == "$after_rt" ]] && okk "criar rota idempotente" || bad "rota duplicou ($before_rt->$after_rt)"
marcar_concluido teste_idem; out=$(executar_passo teste_idem "passo teste" true 2>&1); echo "$out" | grep -qi 'já feito' && okk "executar_passo pula passo já concluído" || bad "idempotência de passo falhou"

sec "RESULTADO"
[[ "$FAIL" == 0 ]] && echo "  VALIDACAO FULL (sem telegram ao vivo): OK" || echo "  VALIDACAO: $FAIL falha(s)"
exit "$FAIL"
