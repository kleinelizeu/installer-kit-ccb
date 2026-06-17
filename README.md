# installer-kit-ccb

Núcleo testado dos instaladores de agente da **CCB** (extraído do `hermes-sdr-ccb`, validado em VPS real).
Cada produto de nicho (clínica, restaurante, advocacia, marketing, imobiliária…) é um repo próprio que
**vendoriza** este motor e adiciona só o conteúdo do nicho.

> Para o aluno final, nada muda: ele roda `curl -fsSL <raw>/install.sh | sudo bash`. Este repo é para
> quem **monta** os produtos.

## O que é genérico (mora aqui) × o que é do nicho (overlay)

| Genérico (motor — `lib/`, `modelos/`, `templates/`) | Do nicho (overlay, autoral) |
|---|---|
| Estado/idempotência/UI/validadores (`lib/00-core.sh`) | `produto.conf` (identidade) |
| Detecção Docker×nativo (`lib/01-deteccao.sh`) | `nicho/negocio.perguntas` (questionário) |
| Credenciais, perfil, Zernio MCP, webhook+patch, exposição, doctor | `nicho/business-context.template.md` |
| Questionário **data-driven** (`lib/11-negocio.sh` lê `nicho/negocio.perguntas`) | `banner.txt`, `README.md`, `docs/` |

A identidade (`PRODUTO`, `CLI_NAME`, `PERFIL_PADRAO`, `ESTADO_DIR`, `TRACK`, …) vem do **`produto.conf`**,
sourçado antes de tudo. Nenhum literal de produto fica hardcoded no motor.

## Como criar um produto de nicho

```bash
# 1. Crie o repo do nicho e copie os esqueletos do kit
mkdir -p clinica-ccb/nicho clinica-ccb/docs/imagens
cp installer-kit-ccb/templates/produto.conf.tmpl                       clinica-ccb/produto.conf
cp installer-kit-ccb/templates/banner.txt.tmpl                         clinica-ccb/banner.txt
cp installer-kit-ccb/templates/README.md.tmpl                          clinica-ccb/README.md
cp installer-kit-ccb/templates/docs/COMO-FUNCIONA.md.tmpl              clinica-ccb/docs/COMO-FUNCIONA.md
cp installer-kit-ccb/templates/docs/CASOS-DE-USO.md.tmpl               clinica-ccb/docs/CASOS-DE-USO.md
cp installer-kit-ccb/templates/docs/PROBLEMAS-COMUNS.md.tmpl           clinica-ccb/docs/PROBLEMAS-COMUNS.md
cp installer-kit-ccb/templates/nicho/negocio.perguntas.tmpl           clinica-ccb/nicho/negocio.perguntas
cp installer-kit-ccb/templates/nicho/business-context.template.md.tmpl clinica-ccb/nicho/business-context.template.md

# 2. Preencha produto.conf + nicho/* + README/docs (sem __PLACEHOLDERS__)

# 3. Vendorize o motor (gera install.sh/instalar.sh/doctor.sh, copia lib/ + modelos/, carimba KIT_VERSION)
installer-kit-ccb/bin/kit-sync ./clinica-ccb

# 4. Lint estrutural (sem precisar de VPS)
installer-kit-ccb/bin/kit-validate ./clinica-ccb

# 5. (Squad) produto.conf com TRACK=squad e SQUAD_FRAMEWORK=ruflo → kit-sync anexa lib/80-ruflo.sh + lib/95-checks-extra.sh
```

## Manutenção (vendoring)
- Cada produto guarda `KIT_VERSION` (de qual kit foi vendorizado).
- Bugfix no motor → bump `KIT_VERSION` aqui → `kit-sync` em cada repo de nicho → revalidar na VPS → tag.
- **Não** editar `lib/`/`modelos/` à mão dentro de um repo de nicho: mudança de motor vem sempre pelo kit.

## Testes
```bash
bash tests/run.sh        # shellcheck + bash -n no motor; build de um produto fake; parse do questionário
```

## Reconciliação com o Hermes
Validado com **Hermes nativo v0.16.x** (`VERSAO_TESTADA="0.16"` em `lib/01-deteccao.sh`). Cobre Docker (Traefik)
e nativo (Cloudflare Tunnel). Evidência objetiva no doctor: POST assinado → **202**; assinatura errada → **401**.
