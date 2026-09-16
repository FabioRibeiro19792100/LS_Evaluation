#!/usr/bin/env python3
"""Servidor local do sistema de triagem, sem dependências de terceiros."""
from __future__ import annotations

import argparse
import json
import sqlite3
import uuid
from datetime import datetime, timezone
from http import HTTPStatus
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote, urlparse

ROOT = Path(__file__).resolve().parent
DB_PATH = ROOT / "learning_sectors.db"
CRITERIOS = ("edi", "originalidade", "qualidade", "viabilidade", "impacto")
RPCS = {"validar_token", "minhas_avaliacoes", "salvar_avaliacao", "todas_avaliacoes", "listar_avaliadores"}


def agora() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def conectar() -> sqlite3.Connection:
    con = sqlite3.connect(DB_PATH)
    con.row_factory = sqlite3.Row
    con.execute("PRAGMA foreign_keys = ON")
    con.execute("PRAGMA journal_mode = WAL")
    return con


def inicializar() -> None:
    with conectar() as con:
        con.executescript("""
        CREATE TABLE IF NOT EXISTS avaliadores (
          id TEXT PRIMARY KEY, nome TEXT NOT NULL, email TEXT,
          papel TEXT NOT NULL CHECK (papel IN ('parecerista','admin')),
          token TEXT NOT NULL UNIQUE, ativo INTEGER NOT NULL DEFAULT 1,
          criado_em TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS avaliacoes (
          id TEXT PRIMARY KEY, avaliador_id TEXT NOT NULL REFERENCES avaliadores(id),
          inscricao_id TEXT NOT NULL,
          edi INTEGER NOT NULL CHECK (edi BETWEEN 1 AND 5),
          originalidade INTEGER NOT NULL CHECK (originalidade BETWEEN 1 AND 5),
          qualidade INTEGER NOT NULL CHECK (qualidade BETWEEN 1 AND 5),
          viabilidade INTEGER NOT NULL CHECK (viabilidade BETWEEN 1 AND 5),
          impacto INTEGER NOT NULL CHECK (impacto BETWEEN 1 AND 5),
          comentario TEXT, criado_em TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS avaliacoes_lookup
          ON avaliacoes (avaliador_id, inscricao_id, criado_em DESC);
        """)
        if con.execute("SELECT COUNT(*) FROM avaliadores").fetchone()[0] == 0:
            contas = [
                ("Administração", "admin@local", "admin", "admin-demo"),
                ("Parecerista 1", "p1@local", "parecerista", "parecerista-1"),
                ("Parecerista 2", "p2@local", "parecerista", "parecerista-2"),
                ("Parecerista 3", "p3@local", "parecerista", "parecerista-3"),
            ]
            con.executemany(
                "INSERT INTO avaliadores(id,nome,email,papel,token,ativo,criado_em) VALUES(?,?,?,?,?,1,?)",
                [(str(uuid.uuid4()), *c, agora()) for c in contas],
            )


def usuario(con: sqlite3.Connection, token: str, papel: str | None = None):
    sql = "SELECT * FROM avaliadores WHERE token=? AND ativo=1"
    args: list[object] = [token]
    if papel:
        sql += " AND papel=?"
        args.append(papel)
    return con.execute(sql, args).fetchone()


def dicionario(row) -> dict:
    return dict(row) if row else None


def executar_rpc(nome: str, p: dict):
    token = str(p.get("p_token") or "")
    with conectar() as con:
        if nome == "validar_token":
            u = usuario(con, token)
            return {"id": u["id"], "nome": u["nome"], "papel": u["papel"]} if u else None

        if nome == "minhas_avaliacoes":
            u = usuario(con, token)
            if not u:
                return []
            rows = con.execute("""
              SELECT a.* FROM avaliacoes a
              WHERE a.avaliador_id=? AND a.criado_em=(
                SELECT MAX(b.criado_em) FROM avaliacoes b
                WHERE b.avaliador_id=a.avaliador_id AND b.inscricao_id=a.inscricao_id)
              ORDER BY a.inscricao_id
            """, (u["id"],)).fetchall()
            return [dicionario(r) for r in rows]

        if nome == "salvar_avaliacao":
            u = usuario(con, token, "parecerista")
            if not u:
                raise ValueError("token inválido")
            inscricao_id = str(p.get("p_inscricao_id") or "")
            ids = {x["id"] for x in json.loads((ROOT / "inscricoes.json").read_text())}
            if inscricao_id not in ids:
                raise ValueError("inscrição inválida")
            notas = [int(p.get("p_" + c, 0)) for c in CRITERIOS]
            if any(n < 1 or n > 5 for n in notas):
                raise ValueError("as notas devem estar entre 1 e 5")
            registro = (str(uuid.uuid4()), u["id"], inscricao_id, *notas,
                        (str(p.get("p_comentario") or "").strip() or None), agora())
            con.execute("""INSERT INTO avaliacoes
              (id,avaliador_id,inscricao_id,edi,originalidade,qualidade,viabilidade,impacto,comentario,criado_em)
              VALUES(?,?,?,?,?,?,?,?,?,?)""", registro)
            return dicionario(con.execute("SELECT * FROM avaliacoes WHERE id=?", (registro[0],)).fetchone())

        admin = usuario(con, token, "admin")
        if not admin:
            raise ValueError("token de administrador inválido")

        if nome == "listar_avaliadores":
            rows = con.execute("SELECT id,nome,email,papel,token,ativo FROM avaliadores ORDER BY papel,nome").fetchall()
            return [{**dicionario(r), "ativo": bool(r["ativo"])} for r in rows]

        if nome == "todas_avaliacoes":
            rows = con.execute("""
              SELECT a.*, v.nome AS avaliador,
                ROW_NUMBER() OVER(PARTITION BY a.avaliador_id,a.inscricao_id ORDER BY a.criado_em) AS versao,
                CASE WHEN ROW_NUMBER() OVER(PARTITION BY a.avaliador_id,a.inscricao_id ORDER BY a.criado_em DESC)=1 THEN 1 ELSE 0 END AS atual
              FROM avaliacoes a JOIN avaliadores v ON v.id=a.avaliador_id
              ORDER BY a.inscricao_id,v.nome,a.criado_em
            """).fetchall()
            return [{**dicionario(r), "atual": bool(r["atual"])} for r in rows]
    raise ValueError("operação desconhecida")


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT), **kwargs)

    def do_POST(self):
        path = unquote(urlparse(self.path).path)
        if not path.startswith("/api/rpc/"):
            self.send_error(HTTPStatus.NOT_FOUND)
            return
        nome = path.rsplit("/", 1)[-1]
        if nome not in RPCS:
            self.json_response(HTTPStatus.NOT_FOUND, {"error": "operação desconhecida"})
            return
        try:
            tamanho = int(self.headers.get("Content-Length", "0"))
            if tamanho > 64_000:
                raise ValueError("requisição muito grande")
            params = json.loads(self.rfile.read(tamanho) or b"{}")
            self.json_response(HTTPStatus.OK, {"data": executar_rpc(nome, params)})
        except (ValueError, TypeError, json.JSONDecodeError) as exc:
            self.json_response(HTTPStatus.BAD_REQUEST, {"error": str(exc)})
        except Exception:
            self.json_response(HTTPStatus.INTERNAL_SERVER_ERROR, {"error": "erro interno"})

    def json_response(self, status: HTTPStatus, value: dict):
        body = json.dumps(value, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def end_headers(self):
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        super().end_headers()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8000)
    args = parser.parse_args()
    inicializar()
    print(f"Avaliador: http://{args.host}:{args.port}/avaliador.html?token=parecerista-1")
    print(f"Dashboard: http://{args.host}:{args.port}/dashboard.html?token=admin-demo")
    ThreadingHTTPServer((args.host, args.port), Handler).serve_forever()
