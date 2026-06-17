#!/usr/bin/env bash
# tests/reconstruct.sh — Prova que a parametrização não regrediu o que já funciona:
# reconstitui um produto "hermes-sdr-ccb" a partir do kit e compara o contexto gerado
# com o do gerador ORIGINAL do repo de referência (mesmo cenário de respostas).
#
# Uso:  tests/reconstruct.sh /caminho/para/hermes-sdr-ccb
set -uo pipefail
if (( BASH_VERSINFO[0] < 4 )); then
  for b in /opt/homebrew/bin/bash /usr/local/bin/bash; do [[ -x "$b" ]] && exec "$b" "$0" "$@"; done
  echo "ERRO: precisa de bash 4+"; exit 2
fi

KIT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
REF="${1:-/Users/kleinelizeu/Documents/hermes-sdr-ccb}"
FALHAS=0
ok()  { printf '  \033[32m✔\033[0m %s\n' "$*"; }
bad() { printf '  \033[31m✘\033[0m %s\n' "$*"; FALHAS=$((FALHAS+1)); }
sec() { printf '\n\033[36m\033[1m%s\033[0m\n' "$*"; }

[[ -d "$REF" ]] || { echo "Repo de referência não encontrado: $REF"; exit 2; }

# Cenário fixo de respostas (idêntico nos dois geradores).
S_NOME="Doce Encanto"
S_VENDE="Bolos artesanais sob encomenda."
S_CLIENTE="Mães da minha cidade."
S_PRECO="R\$ 80 a R\$ 350"
S_INSTA="@doceencanto"
S_TOM_TXT="Fale como um amigo próximo: leve, divertido, linguagem do dia a dia, sem formalidade."   # tom=1
S_REGRA_TXT="Responda o preço (dentro da faixa abaixo) e convide a pessoa a continuar no Direct ou WhatsApp."  # regra=1
S_RESTR="Nunca dar desconto pra influencer."

sec "1) Gerador ORIGINAL (referência)"
REF_OUT="$(mktemp)"
(
  BASE_DIR="$REF"
  # shellcheck source=/dev/null
  source "$REF/lib/00-core.sh"
  # shellcheck source=/dev/null
  source "$REF/lib/11-negocio.sh"
  ESTADO_CONTEXTO="$REF_OUT"
  NEG_NOME="$S_NOME" NEG_VENDE="$S_VENDE" NEG_CLIENTE="$S_CLIENTE" NEG_PRECO="$S_PRECO"
  NEG_INSTAGRAM="$S_INSTA" NEG_TOM="1" NEG_REGRA_PRECO="1" NEG_RESTRICOES="$S_RESTR"
  _gerar_contexto >/dev/null 2>&1
) && ok "contexto da referência gerado" || bad "falha ao gerar contexto da referência"

sec "2) Produto RECONSTITUÍDO do kit"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP" "$REF_OUT"' EXIT
mkdir -p "$TMP/nicho"
cat > "$TMP/produto.conf" <<'CONF'
PRODUTO="hermes-sdr-ccb"
PRODUTO_NOME="Hermes SDR by CCB"
CLI_NAME="hermes-sdr"
PERFIL_PADRAO="sdr"
NICHO="sdr"
TRACK="solo"
SQUAD_FRAMEWORK=""
ESTADO_DIR="/root/.${PRODUTO}"
REPO_URL="https://github.com/kleinelizeu/hermes-sdr-ccb.git"
RAW_BASE="https://raw.githubusercontent.com/kleinelizeu/hermes-sdr-ccb/main"
BANNER_FILE="banner.txt"
EXEMPLO_BOT_NOME="SDR da Minha Loja"
CONF
# O arquétipo do kit reproduz o questionário da referência.
cp "$KIT_DIR/templates/nicho/negocio.perguntas.tmpl"             "$TMP/nicho/negocio.perguntas"
cp "$KIT_DIR/templates/nicho/business-context.template.md.tmpl"  "$TMP/nicho/business-context.template.md"
cp "$KIT_DIR/templates/banner.txt.tmpl"                          "$TMP/banner.txt"
"$KIT_DIR/bin/kit-sync" "$TMP" >/dev/null 2>&1 && ok "kit-sync" || bad "kit-sync falhou"

KIT_OUT="$(mktemp)"
(
  BASE_DIR="$TMP"
  # shellcheck source=/dev/null
  source "$TMP/produto.conf"
  # shellcheck source=/dev/null
  source "$TMP/lib/00-core.sh"
  # shellcheck source=/dev/null
  source "$TMP/lib/11-negocio.sh"
  _carregar_perguntas "$TMP/nicho/negocio.perguntas" >/dev/null 2>&1
  ESTADO_CONTEXTO="$KIT_OUT"
  NOME_NEGOCIO="$S_NOME" O_QUE_VENDE="$S_VENDE" CLIENTE_IDEAL="$S_CLIENTE" FAIXA_PRECO="$S_PRECO"
  INSTAGRAM_HANDLE="$S_INSTA" TOM_DE_VOZ_DESCRICAO="$S_TOM_TXT" REGRA_PRECO="$S_REGRA_TXT" RESTRICOES="$S_RESTR"
  _gerar_contexto >/dev/null 2>&1
) && ok "contexto do kit gerado" || bad "falha ao gerar contexto do kit"

sec "3) Comparação (devem ser idênticos)"
if diff -u "$REF_OUT" "$KIT_OUT" >/tmp/kit-reconstruct.diff; then
  ok "business-context.md IDÊNTICO ao da referência"
else
  bad "diferenças encontradas:"; sed 's/^/      /' /tmp/kit-reconstruct.diff
fi

sec "4) install.sh reconstituído aponta para o raw correto"
if grep -q 'raw.githubusercontent.com/kleinelizeu/hermes-sdr-ccb/main/install.sh' "$TMP/install.sh"; then
  ok "one-liner curl com a URL correta"
else
  bad "URL do one-liner não confere"
fi

sec "Resultado"
(( FALHAS == 0 )) && { printf '\033[32m✔ Reconstituição idêntica — parametrização não regrediu.\033[0m\n'; exit 0; } \
                  || { printf '\033[31m✘ %d falha(s).\033[0m\n' "$FALHAS"; exit 1; }
