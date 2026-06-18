#!/usr/bin/env python3
"""Chama uma ferramenta do conector gcal_mcp.py DIRETO via MCP stdio (sem LLM).

Determinístico: prova que o conector lê as credenciais dos ARGUMENTOS (arg1=SA, arg2=agenda)
e chama a API do Google. Com um service account FAKE → erro de AUTENTICAÇÃO do Google
(prova que chegou na API, não "arquivo não encontrado"). Com um SA REAL → cria o evento.

Uso:  python3 connector-call.py <uv> <gcal_mcp.py> <sa.json> <calendar_id> [criar|listar]
"""
import json
import subprocess
import sys
import time

uv, script, sa, cal = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
acao = sys.argv[5] if len(sys.argv) > 5 else "criar"

proc = subprocess.Popen([uv, "run", script, sa, cal],
                        stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE, text=True, bufsize=1)


def send(obj):
    proc.stdin.write(json.dumps(obj) + "\n")
    proc.stdin.flush()


def read_reply(want_id, timeout=90):
    end = time.time() + timeout
    while time.time() < end:
        line = proc.stdout.readline()
        if not line:
            break
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except Exception:
            continue
        if msg.get("id") == want_id:
            return msg
    return None


rc = 1
try:
    send({"jsonrpc": "2.0", "id": 1, "method": "initialize",
          "params": {"protocolVersion": "2024-11-05", "capabilities": {},
                     "clientInfo": {"name": "ccb-test", "version": "1"}}})
    init = read_reply(1)
    if not init:
        print("✘ sem resposta de initialize"); raise SystemExit(1)
    print("✔ handshake MCP ok")
    send({"jsonrpc": "2.0", "method": "notifications/initialized"})

    if acao == "criar":
        args = {"titulo": "Teste CCB — pode apagar",
                "inicio_iso": "2026-06-20T15:00:00-03:00",
                "fim_iso": "2026-06-20T15:45:00-03:00",
                "descricao": "Teste automático CCB"}
        tool = "criar_evento"
    else:
        args = {"inicio_iso": "2026-06-20T00:00:00-03:00", "fim_iso": "2026-06-21T00:00:00-03:00"}
        tool = "consultar_disponibilidade"

    send({"jsonrpc": "2.0", "id": 2, "method": "tools/call",
          "params": {"name": tool, "arguments": args}})
    rep = read_reply(2, timeout=90)
    if not rep:
        print("✘ sem resposta da tool"); raise SystemExit(1)

    # extrai texto do resultado / erro
    txt = json.dumps(rep, ensure_ascii=False)
    if "result" in rep:
        try:
            txt = rep["result"]["content"][0]["text"]
        except Exception:
            pass
    print(f"--- resposta de {tool} ---")
    print(txt)
    low = txt.lower()
    if "evento criado" in low or "htmllink" in low or "google.com/calendar" in low:
        print("\n✔✔ EVENTO REAL CRIADO (conector → Google → evento).")
        rc = 0
    elif any(k in low for k in ["invalid_grant", "jwt", "oauth", "credential", "permission",
                                 "forbidden", "not found", "disabled", "api has not", "403", "401",
                                 "unauthorized", "could not", "access"]):
        print("\n✔ Conector LEU as credenciais dos argumentos e CHAMOU a API do Google "
              "(erro só pela credencial fake/permite — com SA real, cria o evento).")
        rc = 0
    elif "service account não informado" in low or "inexistente" in low:
        print("\n✘ Conector NÃO recebeu o caminho do SA (bug de passagem de credencial).")
        rc = 1
    else:
        print("\n? resposta inesperada — ver acima.")
        rc = 2
finally:
    try:
        proc.terminate()
    except Exception:
        pass
sys.exit(rc)
