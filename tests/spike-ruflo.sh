#!/usr/bin/env bash
# spike-ruflo.sh — SPIKE: o Hermes consegue registrar e conversar com o Ruflo (MCP)?
# Isolado: perfil descartável (sem --clone), teardown sempre (inclui npm uninstall -g ruflo),
# não toca em default/automateflow.
#
# Aprendizado do 1º spike: `--command npx --args -y ruflo@latest mcp start` QUEBRA no argparse
# do Hermes 0.15.1 (o `-y` é lido como flag). Solução: instalar ruflo GLOBAL e usar
# `--command ruflo --args mcp start` (sem args com '-' no começo).
#
# Uso (NA VPS): bash spike-ruflo.sh [PROFILE]
set -uo pipefail
PROFILE="${1:-ccbruflo}"
PROFDIR="/root/.hermes/profiles/$PROFILE"
ALIAS="/root/.local/bin/$PROFILE"
sec(){ printf '\n\033[36m\033[1m== %s ==\033[0m\n' "$*"; }

teardown(){
  sec "TEARDOWN"
  hermes profile delete -y "$PROFILE" >/dev/null 2>&1 || true
  rm -rf "$PROFDIR" "$ALIAS" 2>/dev/null
  npm uninstall -g ruflo >/dev/null 2>&1 || true
  [[ -d "$PROFDIR" || -e "$ALIAS" ]] && echo "  ! restou algo de $PROFILE" || echo "  perfil $PROFILE removido"
  command -v ruflo >/dev/null 2>&1 && echo "  ! ruflo global ainda presente" || echo "  ruflo global removido"
  systemctl is-active --quiet hermes-gateway-automateflow && echo "  automateflow ATIVO ✔" || echo "  ! automateflow não-ativo"
}
trap teardown EXIT
[[ -e "$PROFDIR" || -e "$ALIAS" ]] && { echo "ABORT: $PROFILE já existe"; trap - EXIT; exit 3; }

sec "0a) instalar ruflo GLOBAL (pode demorar — pacote grande)"
echo "  node: $(node -v 2>/dev/null)"
timeout 360 npm install -g ruflo@latest >/tmp/ruflo-npm.log 2>&1 && echo "  npm install -g ruflo: OK" || { echo "  npm install FALHOU/timeout:"; tail -8 /tmp/ruflo-npm.log; }
echo "  ruflo bin: $(command -v ruflo 2>/dev/null || echo 'ausente')"
timeout 30 ruflo --version </dev/null 2>&1 | tail -3 || echo "  (ruflo --version erro)"

sec "0b) 'ruflo mcp start' existe? roda como server stdio?"
ruflo mcp --help </dev/null 2>&1 | sed -n '1,12p' || echo "  (ruflo mcp --help erro)"
echo "  -- tentando subir 'ruflo mcp start' por ~10s (stdin aberto) --"
timeout 12 sh -c 'printf "" | ruflo mcp start' >/tmp/ruflo-start.log 2>&1 || true
echo "  saída inicial:"; head -12 /tmp/ruflo-start.log 2>/dev/null | sed 's/^/    /'

sec "1) perfil descartável (SEM --clone)"
hermes profile create "$PROFILE" --no-skills --description "spike ruflo descartavel" </dev/null >/dev/null 2>&1
[[ -d "$PROFDIR" ]] && echo "  perfil criado" || echo "  FALHA ao criar perfil"

sec "2) registrar Ruflo como MCP (--command ruflo --args mcp start)"
# NÃO redirecionar stdin de /dev/null: o 'yes' precisa responder ao prompt "Enable all tools?".
yes 2>/dev/null | timeout 300 hermes -p "$PROFILE" mcp add ruflo --command ruflo --args mcp start 2>&1 | tail -8

sec "3) MCPs configurados no perfil"
hermes -p "$PROFILE" mcp list 2>&1 | tail -15

sec "4) testar conexão Hermes <-> Ruflo (descobre tools?)"
timeout 180 hermes -p "$PROFILE" mcp test ruflo </dev/null 2>&1 | tail -30 || echo "  (mcp test: erro/timeout)"

sec "FIM — interpretar: ruflo conectou? quantas tools no mcp list/test?"
