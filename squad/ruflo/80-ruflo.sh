#!/usr/bin/env bash
# 80-ruflo.sh — Passo extra do esquadrão (squad) com Ruflo (ruvnet/ruflo).
# Vendorizado SÓ em produtos squad/Ruflo (ex.: imobiliaria-squad-ccb), via kit-sync.
#
# Modelo: o Hermes já é cliente MCP (usa o Zernio). O Ruflo expõe um MCP server
# (`ruflo mcp start`). Registramos o Ruflo como um SEGUNDO MCP. O agente passa a
# orquestrar o swarm (captar -> qualificar -> agendar visita) usando as tools do Ruflo.
#
# Validado na VPS (Hermes v0.15.1, spike): com o Ruflo instalado GLOBAL,
# `hermes mcp add ruflo --command ruflo --args mcp start` conecta e habilita 302 tools.
# IMPORTANTE (aprendido no spike):
#   - NÃO use `--command npx --args -y ruflo@latest mcp start`: o `-y` quebra o argparse.
#     Instale o ruflo GLOBAL e use `--command ruflo --args mcp start` (args sem '-' no início).
#   - O `mcp add` pergunta "Enable all tools?" — respondemos com `yes` (sem redirecionar stdin).
#   - O 1º `ruflo mcp start` baixa um modelo ONNX (~23MB); a 1ª resposta pode demorar mais.

RUFLO_NODE_MIN=20

passo_squad() {
  passo "MONTANDO O ESQUADRÃO (RUFLO)"

  _ruflo_garantir_node      || return 1
  _ruflo_garantir_instalado || return 1

  if _ruflo_ja_registrado; then
    ok "O Ruflo já está conectado ao seu agente."
    return 0
  fi

  if hermes_cli mcp --help 2>/dev/null | grep -q ' add'; then
    info "Conectando o Ruflo ao seu agente (pode baixar um modelo na 1ª vez)..."
    # NÃO redirecionar stdin de /dev/null: o 'yes' responde ao prompt "Enable all tools?".
    yes 2>/dev/null | hermes_cli mcp add ruflo --command ruflo --args mcp start >/dev/null 2>&1 || true
    if _ruflo_ja_registrado; then
      _reiniciar_gateway
      ok "Ruflo conectado! (esquadrão pronto)"
      return 0
    fi
    dica "A conexão automática não confirmou — vamos pelo jeito manual (é rápido)."
  fi

  _ruflo_manual
}

# Garante Node >= RUFLO_NODE_MIN (Ruflo exige Node 20+). Instala via NodeSource se faltar.
_ruflo_garantir_node() {
  local v=""
  command -v node >/dev/null 2>&1 && v="$(node -v 2>/dev/null | grep -oE '[0-9]+' | head -1)"
  if [[ -n "$v" && "$v" -ge "$RUFLO_NODE_MIN" ]]; then
    ok "Node $(node -v) presente (>= ${RUFLO_NODE_MIN})."
    return 0
  fi
  info "Instalando o Node ${RUFLO_NODE_MIN} (necessário para o Ruflo)..."
  if command -v apt-get >/dev/null 2>&1; then
    curl -fsSL "https://deb.nodesource.com/setup_${RUFLO_NODE_MIN}.x" 2>/dev/null | bash - >/dev/null 2>&1 || true
    apt-get install -y nodejs >/dev/null 2>&1 || true
  fi
  command -v node >/dev/null 2>&1 && v="$(node -v 2>/dev/null | grep -oE '[0-9]+' | head -1)"
  if [[ -n "$v" && "$v" -ge "$RUFLO_NODE_MIN" ]]; then
    ok "Node $(node -v) instalado."
  else
    erro "Não consegui garantir o Node ${RUFLO_NODE_MIN}+ (preciso dele para o Ruflo)."
    dica "Instale o Node ${RUFLO_NODE_MIN}+ manualmente e rode '${CLI_NAME}' de novo."
    return 1
  fi
}

# Instala o ruflo GLOBAL (npm -g). Idempotente: pula se já houver o comando 'ruflo'.
_ruflo_garantir_instalado() {
  if command -v ruflo >/dev/null 2>&1; then
    ok "Ruflo já instalado ($(ruflo --version 2>/dev/null | grep -oE 'v?[0-9.]+' | head -1))."
    return 0
  fi
  info "Instalando o Ruflo (npm -g, pode demorar — pacote grande)..."
  if npm install -g ruflo@latest >/dev/null 2>&1 && command -v ruflo >/dev/null 2>&1; then
    ok "Ruflo instalado."
  else
    erro "Não consegui instalar o Ruflo automaticamente."
    dica "Rode manualmente:  npm install -g ruflo@latest   e depois '${CLI_NAME}' de novo."
    return 1
  fi
}

_ruflo_ja_registrado() {
  hermes_cli mcp list 2>/dev/null | grep -qi ruflo
}

_ruflo_manual() {
  titulo "Conecte o Ruflo pelo Telegram (1 minuto):"
  info "1. Garanta que o Ruflo está instalado:  npm install -g ruflo@latest"
  info "2. Abra a conversa com o seu bot @${BOT_USERNAME:-seu_bot} e mande a mensagem abaixo:"
  copiavel "Configure um servidor MCP chamado \"ruflo\" com o comando \"ruflo\" e o argumento \"mcp start\" (transporte stdio).

Depois liste minhas ferramentas do Ruflo para confirmar que conectou."
  info "3. Espere o agente confirmar as ferramentas do Ruflo."
  confirmar "Já mandou e o agente confirmou a conexão?" s || \
    dica "Tudo bem, você pode conferir depois com '${CLI_NAME} doctor'."
}
