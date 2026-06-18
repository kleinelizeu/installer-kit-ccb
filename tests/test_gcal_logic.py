#!/usr/bin/env python3
"""Teste OFFLINE da lógica do conector de agenda (modelos/gcal_mcp.py).

Prova, sem rede e sem credencial real, que as ferramentas constroem as chamadas CERTAS
à API do Google Calendar e retornam o resultado esperado — em particular que `criar_evento`
chama events().insert(calendarId=..., body={summary,start,end,...}) e devolve o link do evento.
Mocka google.oauth2.service_account, googleapiclient.discovery.build e mcp.server.fastmcp,
então a única coisa NÃO coberta aqui é a chamada de rede real ao Google (que depende do
service account do usuário). Roda com: python3 tests/test_gcal_logic.py
"""
import importlib.util
import json
import os
import sys
import tempfile
import types

CALLS = {}


def _install_fakes():
    # google.oauth2.service_account
    google = types.ModuleType("google")
    oauth2 = types.ModuleType("google.oauth2")
    sa = types.ModuleType("google.oauth2.service_account")

    class _Creds:
        @staticmethod
        def from_service_account_file(path, scopes=None):
            assert os.path.exists(path), "SA path deve existir"
            return object()
    sa.Credentials = _Creds
    sys.modules.update({"google": google, "google.oauth2": oauth2,
                        "google.oauth2.service_account": sa})

    # googleapiclient.discovery.build → serviço gravador
    class _Exec:
        def __init__(self, kind, kwargs):
            self.kind, self.kwargs = kind, kwargs

        def execute(self):
            CALLS[self.kind] = self.kwargs
            if self.kind == "insert":
                return {"htmlLink": "https://www.google.com/calendar/event?eid=FAKE123",
                        "id": "evt_fake"}
            if self.kind == "freebusy":
                cal = self.kwargs["body"]["items"][0]["id"]
                return {"calendars": {cal: {"busy": []}}}
            if self.kind == "list":
                return {"items": []}
            return {}

    class _Events:
        def insert(self, **kw):
            return _Exec("insert", kw)

        def list(self, **kw):
            return _Exec("list", kw)

    class _FreeBusy:
        def query(self, **kw):
            return _Exec("freebusy", kw)

    class _Svc:
        def events(self):
            return _Events()

        def freebusy(self):
            return _FreeBusy()

    gac = types.ModuleType("googleapiclient")
    disc = types.ModuleType("googleapiclient.discovery")
    disc.build = lambda *a, **k: _Svc()
    sys.modules.update({"googleapiclient": gac, "googleapiclient.discovery": disc})

    # mcp.server.fastmcp.FastMCP — decorator no-op (devolve a função pura)
    class _FastMCP:
        def __init__(self, name):
            self.name = name

        def tool(self):
            def deco(fn):
                return fn
            return deco

        def run(self, *a, **k):
            pass

    mcp = types.ModuleType("mcp")
    mcp_server = types.ModuleType("mcp.server")
    fastmcp = types.ModuleType("mcp.server.fastmcp")
    fastmcp.FastMCP = _FastMCP
    sys.modules.update({"mcp": mcp, "mcp.server": mcp_server, "mcp.server.fastmcp": fastmcp})


def main():
    _install_fakes()
    saf = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    json.dump({"type": "service_account", "client_email": "x@y.iam.gserviceaccount.com",
               "private_key": "k"}, open(saf.name, "w"))
    os.environ["GOOGLE_APPLICATION_CREDENTIALS"] = saf.name
    os.environ["GOOGLE_CALENDAR_ID"] = "negocio@example.com"

    here = os.path.dirname(os.path.abspath(__file__))
    script = os.path.join(here, "..", "modelos", "gcal_mcp.py")
    spec = importlib.util.spec_from_file_location("gcal_mcp", script)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)

    ok = 0

    def check(cond, msg):
        nonlocal ok
        print(("  \033[32m✔\033[0m " if cond else "  \033[31m✘\033[0m ") + msg)
        ok += 0 if cond else 1

    # 1) criar_evento → events().insert com body correto + retorna o link
    out = mod.criar_evento("Visita - João", "2026-06-20T15:00:00-03:00",
                           "2026-06-20T15:45:00-03:00", "Apto 2q Jardim X")
    ins = CALLS.get("insert", {})
    check("FAKE123" in out, "criar_evento retorna o link do evento criado")
    check(ins.get("calendarId") == "negocio@example.com", "insert usa o GOOGLE_CALENDAR_ID")
    b = ins.get("body", {})
    check(b.get("summary") == "Visita - João", "insert envia o título")
    check(b.get("start", {}).get("dateTime") == "2026-06-20T15:00:00-03:00", "insert envia o início")
    check(b.get("end", {}).get("dateTime") == "2026-06-20T15:45:00-03:00", "insert envia o fim")
    check(b.get("start", {}).get("timeZone") == "America/Sao_Paulo", "insert envia o fuso")

    # 2) calendario explícito sobrepõe o padrão
    CALLS.clear()
    mod.criar_evento("X", "2026-06-20T10:00:00-03:00", "2026-06-20T10:30:00-03:00",
                     calendario="outra@example.com")
    check(CALLS["insert"]["calendarId"] == "outra@example.com", "parâmetro 'calendario' sobrepõe o padrão")

    # 3) consultar_disponibilidade → freebusy().query
    CALLS.clear()
    res = mod.consultar_disponibilidade("2026-06-20T09:00:00-03:00", "2026-06-20T18:00:00-03:00")
    check("freebusy" in CALLS, "consultar_disponibilidade chama freebusy().query")
    check("LIVRE" in res, "consultar_disponibilidade reporta LIVRE quando não há ocupação")

    # 4) listar_eventos → events().list
    CALLS.clear()
    mod.listar_eventos("2026-06-20T00:00:00-03:00", "2026-06-21T00:00:00-03:00")
    check(CALLS.get("list", {}).get("singleEvents") is True, "listar_eventos usa events().list (singleEvents)")

    print()
    if ok == 0:
        print("\033[32m✔ Lógica do gcal_mcp.py OK — chamadas à API do Google estão corretas.\033[0m")
        return 0
    print(f"\033[31m✘ {ok} verificação(ões) falharam.\033[0m")
    return 1


if __name__ == "__main__":
    sys.exit(main())
