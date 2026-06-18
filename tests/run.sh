#!/usr/bin/env bash
# tests/run.sh — Gate local do installer-kit-ccb (sem VPS).
#   1) shellcheck + bash -n no motor
#   2) build de um produto fake via kit-sync + kit-validate
#   3) teste dinâmico do questionário data-driven (parser + geração de contexto)
#
# Requer bash 4+. Em macOS, instale:  brew install bash shellcheck
set -uo pipefail

# Re-exec sob um bash 4+ se o atual for antigo (macOS /bin/bash = 3.2).
if (( BASH_VERSINFO[0] < 4 )); then
  for b in /opt/homebrew/bin/bash /usr/local/bin/bash; do
    if [[ -x "$b" ]]; then exec "$b" "$0" "$@"; fi
  done
  echo "ERRO: precisa de bash 4+ (instale: brew install bash)"; exit 2
fi

KIT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
FALHAS=0
ok()  { printf '  \033[32m✔\033[0m %s\n' "$*"; }
bad() { printf '  \033[31m✘\033[0m %s\n' "$*"; FALHAS=$((FALHAS+1)); }
sec() { printf '\n\033[36m\033[1m%s\033[0m\n' "$*"; }

sec "Ambiente"
ok "bash $(bash --version | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"

sec "1) shellcheck + bash -n (motor)"
mapfile -t SHFILES < <(find "$KIT_DIR/lib" "$KIT_DIR/squad" -name '*.sh' 2>/dev/null; \
                       echo "$KIT_DIR/templates/instalar.sh"; echo "$KIT_DIR/templates/doctor.sh"; \
                       echo "$KIT_DIR/bin/kit-sync"; echo "$KIT_DIR/bin/kit-validate")
for f in "${SHFILES[@]}"; do
  [[ -e "$f" ]] || continue
  bash -n "$f" 2>/dev/null && ok "bash -n $(basename "$f")" || bad "sintaxe: $(basename "$f")"
done
if command -v shellcheck >/dev/null 2>&1; then
  if shellcheck -S error -e SC1090,SC1091 "${SHFILES[@]}" 2>/tmp/kit-sc.out; then
    ok "shellcheck (sem erros)"
  else
    bad "shellcheck:"; sed 's/^/      /' /tmp/kit-sc.out
  fi
else
  bad "shellcheck não instalado (brew install shellcheck)"
fi

sec "2) build de produto fake (kit-sync) + kit-validate"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/nicho" "$TMP/docs/imagens"
cat > "$TMP/produto.conf" <<'CONF'
PRODUTO="fake-ccb"
PRODUTO_NOME="Hermes Fake by CCB"
CLI_NAME="hermes-fake"
PERFIL_PADRAO="fake"
NICHO="fake"
TRACK="solo"
SQUAD_FRAMEWORK=""
ESTADO_DIR="/root/.${PRODUTO}"
REPO_URL="https://github.com/kleinelizeu/fake-ccb.git"
RAW_BASE="https://raw.githubusercontent.com/kleinelizeu/fake-ccb/main"
BANNER_FILE="banner.txt"
EXEMPLO_BOT_NOME="Atendente Fake"
CONF
cp "$KIT_DIR/templates/nicho/negocio.perguntas.tmpl"            "$TMP/nicho/negocio.perguntas"
cp "$KIT_DIR/templates/nicho/business-context.template.md.tmpl" "$TMP/nicho/business-context.template.md"
cp "$KIT_DIR/templates/banner.txt.tmpl"                         "$TMP/banner.txt"

if "$KIT_DIR/bin/kit-sync" "$TMP" >/tmp/kit-sync.out 2>&1; then ok "kit-sync"; else bad "kit-sync falhou:"; sed 's/^/      /' /tmp/kit-sync.out; fi
# install.sh deve ter sido renderizado sem placeholders
grep -qE '__[A-Z_]+__' "$TMP/install.sh" && bad "install.sh com placeholder" || ok "install.sh renderizado"
# vendorizou lib + modelos
[[ -f "$TMP/lib/00-core.sh" && -f "$TMP/modelos/apply_zernio_patch.py" ]] && ok "lib/ + modelos/ vendorizados" || bad "vendoring incompleto"
if "$KIT_DIR/bin/kit-validate" "$TMP" >/tmp/kit-val.out 2>&1; then ok "kit-validate (produto fake)"; else bad "kit-validate falhou:"; sed 's/^/      /' /tmp/kit-val.out; fi

sec "3) questionário data-driven (parser + contexto)"
(
  BASE_DIR="$TMP"
  # shellcheck source=/dev/null
  source "$TMP/produto.conf"
  # shellcheck source=/dev/null
  source "$TMP/lib/00-core.sh"
  # shellcheck source=/dev/null
  source "$TMP/lib/11-negocio.sh"

  _carregar_perguntas "$TMP/nicho/negocio.perguntas" || { echo "PARSE_FAIL"; exit 1; }
  echo "PERG_N=$PERG_N"
  printf 'PH=%s\n' "${PERG_PLACEHOLDER[@]}"

  # Preenche valores e gera o contexto.
  NOME_NEGOCIO="Clínica Teste"; O_QUE_VENDE="consultas"; CLIENTE_IDEAL="pacientes"
  FAIXA_PRECO="R\$ 100"; INSTAGRAM_HANDLE="@teste"
  TOM_DE_VOZ_DESCRICAO="Fale com acolhimento."; RESTRICOES="Nada de diagnóstico online."
  REGRA_PRECO="Convide pro Direct."
  ESTADO_CONTEXTO="$TMP/contexto.out"
  _gerar_contexto >/dev/null 2>&1
  if grep -q '{{' "$ESTADO_CONTEXTO"; then echo "TEMPLATE_LEFTOVER"; else echo "CONTEXT_OK"; fi
  grep -q "Clínica Teste" "$ESTADO_CONTEXTO" && echo "SUBST_OK" || echo "SUBST_FAIL"
) >/tmp/kit-dyn.out 2>&1
DYN="$(cat /tmp/kit-dyn.out)"
echo "$DYN" | sed 's/^/      /'
n="$(echo "$DYN" | sed -n 's/^PERG_N=//p')"
[[ "$n" == "8" ]] && ok "questionário arquétipo: 8 perguntas" || bad "esperava 8 perguntas, veio '$n'"
echo "$DYN" | grep -q '^CONTEXT_OK$' && ok "sem {{placeholder}} sobrando no contexto" || bad "placeholders não resolvidos"
echo "$DYN" | grep -q '^SUBST_OK$'   && ok "substituição aplicada (Clínica Teste)" || bad "substituição falhou"

sec "4) lógica do conector de agenda (gcal_mcp.py, offline)"
if python3 "$KIT_DIR/tests/test_gcal_logic.py" >/tmp/kit-gcal.out 2>&1; then
  ok "gcal_mcp.py: chamadas à API do Google corretas (criar_evento/freebusy/list)"
else
  bad "test_gcal_logic falhou:"; sed 's/^/      /' /tmp/kit-gcal.out
fi

sec "Resultado"
if (( FALHAS == 0 )); then printf '\033[32m✔ KIT OK (%d verificações).\033[0m\n' "$(( ${#SHFILES[@]} + 10 ))"; exit 0
else printf '\033[31m✘ %d falha(s).\033[0m\n' "$FALHAS"; exit 1; fi
