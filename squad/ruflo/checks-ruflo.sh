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

  # Ruflo registrado como MCP no agente.
  if hermes_cli mcp list 2>/dev/null | grep -qi ruflo; then
    _chk "Ruflo conectado (MCP)."
  else
    _bad "Ruflo não aparece conectado. Veja a mensagem para colar no bot com '${CLI_NAME}' (passo do esquadrão)."
  fi
}
