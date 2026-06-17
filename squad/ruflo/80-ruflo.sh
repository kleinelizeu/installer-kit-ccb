#!/usr/bin/env bash
# 80-ruflo.sh — Passo extra do esquadrão (squad) com Ruflo (ruvnet/ruflo).
# Vendorizado SÓ em produtos squad/Ruflo (ex.: imobiliaria-squad-ccb), via kit-sync.
#
# Modelo: o Hermes já é cliente MCP (usa o Zernio). O Ruflo expõe um MCP server
# (`npx ruflo@latest mcp start`). Registramos o Ruflo como um SEGUNDO MCP, com o
# mesmo padrão best-effort + fallback manual do 30-mcp.sh. O agente passa a poder
# orquestrar o swarm (captar -> qualificar -> agendar visita).
#
# ⚠️ Requer validação na VPS (spike): Node>=20, `ruflo mcp start` não-interativo,
# o agente conseguir invocar uma tool do Ruflo e sobreviver a restart do gateway.

RUFLO_NODE_MIN=20

passo_squad() {
  passo "MONTANDO O ESQUADRÃO (RUFLO)"

  _ruflo_garantir_node || return 1

  if _ruflo_ja_registrado; then
    ok "O Ruflo já está conectado ao seu agente."
    return 0
  fi

  if hermes_cli mcp --help 2>/dev/null | grep -q ' add'; then
    info "Tentando conectar o Ruflo automaticamente..."
    yes 2>/dev/null | hermes_cli mcp add ruflo --command npx \
         --args -y ruflo@latest mcp start >/dev/null 2>&1 || true
    if _ruflo_ja_registrado; then
      _reiniciar_gateway
      ok "Ruflo conectado!"
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

_ruflo_ja_registrado() {
  hermes_cli mcp list 2>/dev/null | grep -qi ruflo
}

_ruflo_manual() {
  titulo "Conecte o Ruflo pelo Telegram (1 minuto):"
  info "1. Abra a conversa com o seu bot @${BOT_USERNAME:-seu_bot}"
  info "2. Copie e mande a mensagem abaixo:"
  copiavel "Configure um servidor MCP chamado \"ruflo\" com o comando:

npx -y ruflo@latest mcp start

Depois liste minhas ferramentas do Ruflo para confirmar que conectou."
  info "3. Espere o agente confirmar as ferramentas do Ruflo."
  confirmar "Já mandou e o agente confirmou a conexão?" s || \
    dica "Tudo bem, você pode conferir depois com '${CLI_NAME} doctor'."
}
