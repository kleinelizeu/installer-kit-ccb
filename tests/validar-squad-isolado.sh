#!/usr/bin/env bash
# validar-squad-isolado.sh — Valida AO VIVO o passo_squad + checks_extra REAIS do kit
# (Ruflo) num perfil descartável. Isolado, teardown sempre (inclui npm uninstall -g ruflo),
# não toca em default/automateflow.  Uso (NA VPS): bash validar-squad-isolado.sh <PRODUTO_DIR> [PROFILE]
set -uo pipefail
PRODUTO_DIR="${1:?caminho do produto squad vendorizado na VPS}"
PROFILE="${2:-ccbsquad}"
PROFDIR="/root/.hermes/profiles/$PROFILE"
ALIAS="/root/.local/bin/$PROFILE"
sec(){ printf '\n\033[36m\033[1m== %s ==\033[0m\n' "$*"; }

teardown(){
  sec "TEARDOWN"
  hermes profile delete -y "$PROFILE" >/dev/null 2>&1 || true
  rm -rf "$PROFDIR" "$ALIAS" 2>/dev/null
  npm uninstall -g ruflo >/dev/null 2>&1 || true
  command -v ruflo >/dev/null 2>&1 && echo "  ! ruflo global ainda presente" || echo "  ruflo global removido"
  [[ -d "$PROFDIR" ]] && echo "  ! restou $PROFILE" || echo "  perfil $PROFILE removido"
  systemctl is-active --quiet hermes-gateway-automateflow && echo "  automateflow ATIVO ✔" || echo "  ! automateflow"
}
trap teardown EXIT
[[ -e "$PROFDIR" || -e "$ALIAS" ]] && { echo "ABORT: $PROFILE já existe"; trap - EXIT; exit 3; }

sec "1) perfil descartável (sem clone)"
hermes profile create "$PROFILE" --no-skills --description "validacao squad" </dev/null >/dev/null 2>&1
[[ -d "$PROFDIR" ]] && echo "  perfil criado" || echo "  FALHA criar perfil"

sec "2) carregar motor + chamar passo_squad REAL do kit"
export BASE_DIR="$PRODUTO_DIR"
# shellcheck source=/dev/null
source "$PRODUTO_DIR/produto.conf"
for f in "$PRODUTO_DIR"/lib/*.sh; do source "$f"; done
# shellcheck disable=SC2034
{ MODO=nativo; PERFIL="$PROFILE"; PERFIL_DIR="$PROFDIR"; PERFIL_BIN="$ALIAS"
  ENV_FILE="$PROFDIR/.env"; CONFIG_FILE="$PROFDIR/config.yaml"; GATEWAY_SVC=""
  ESTADO_DIR="/root/.ccb-squad-tmp"; BOT_USERNAME="(spike)"; }
mkdir -p "$ESTADO_DIR"
declare -F passo_squad >/dev/null && echo "  passo_squad existe (lib/80-ruflo.sh vendorizado)" || echo "  ✘ passo_squad ausente"
passo_squad </dev/null 2>&1 | tail -8

sec "3) ruflo no mcp list do perfil?"
hermes -p "$PROFILE" mcp list 2>&1 | grep -i ruflo && echo "  ✔ ruflo registrado" || echo "  ✘ ruflo não registrado"

sec "4) checks_extra REAL do doctor (Node + Ruflo)"
DOC_FALHAS=0
declare -F checks_extra >/dev/null && checks_extra || echo "  ✘ checks_extra ausente"
echo "  -> DOC_FALHAS=$DOC_FALHAS (0 = esquadrão ok)"

sec "FIM"
