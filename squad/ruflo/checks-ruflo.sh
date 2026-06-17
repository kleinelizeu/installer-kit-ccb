#!/usr/bin/env bash
# checks-ruflo.sh — Checagens extras do doctor para o esquadrão Ruflo.
# Vendorizado como lib/95-checks-extra.sh em produtos squad/Ruflo (via kit-sync).
# Usa os helpers _chk/_fix/_bad e o contador DOC_FALHAS do 90-checks.sh.

checks_extra() {
  titulo "Esquadrão (Ruflo)"

  # Node >= 20 (Ruflo precisa).
  local v=""
  command -v node >/dev/null 2>&1 && v="$(node -v 2>/dev/null | grep -oE '[0-9]+' | head -1)"
  if [[ -n "$v" && "$v" -ge 20 ]]; then
    _chk "Node $(node -v) presente (>= 20)."
  else
    _bad "Node 20+ ausente — o Ruflo não roda. Rode '${CLI_NAME}' para instalar."
  fi

  # Ruflo instalado (global).
  if command -v ruflo >/dev/null 2>&1; then
    _chk "Ruflo instalado ($(ruflo --version 2>/dev/null | grep -oE 'v?[0-9.]+' | head -1))."
  else
    _bad "Ruflo não está instalado. Rode '${CLI_NAME}' (passo do esquadrão) ou: npm install -g ruflo@latest"
  fi

  # Ruflo registrado como MCP no agente.
  if hermes_cli mcp list 2>/dev/null | grep -qi ruflo; then
    _chk "Ruflo conectado (MCP)."
  else
    _bad "Ruflo não aparece conectado. Rode '${CLI_NAME}' (passo do esquadrão) para reconectar."
  fi
}
