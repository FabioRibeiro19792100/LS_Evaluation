#!/usr/bin/env python3
"""Servidor local do sistema de triagem, sem dependências de terceiros."""
from __future__ import annotations

import argparse
import json
import secrets
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
RPCS = {"validar_token", "minhas_avaliacoes", "salvar_avaliacao", "todas_avaliacoes", "listar_avaliadores",
        "listar_rodadas", "fila_rodada", "minhas_avaliacoes_rodada", "salvar_avaliacao_rodada",
        "todas_avaliacoes_rodada", "avancar_equipes", "listar_atribuicoes", "salvar_atribuicoes",
        "criar_parecerista", "excluir_parecerista", "listar_pareceristas_rodada",
        "definir_parecerista_rodada", "distribuir_rodada"}


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
          contabiliza INTEGER NOT NULL DEFAULT 1,
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
        CREATE TABLE IF NOT EXISTS rodadas (
          id INTEGER PRIMARY KEY, slug TEXT NOT NULL UNIQUE, nome TEXT NOT NULL,
          titulo TEXT NOT NULL, entrega TEXT NOT NULL, orientacao TEXT NOT NULL,
          corte INTEGER NOT NULL, criterios TEXT NOT NULL, ordem INTEGER NOT NULL UNIQUE,
          status TEXT NOT NULL DEFAULT 'configuracao', oficial INTEGER NOT NULL DEFAULT 1,
          modo_atribuicao TEXT NOT NULL DEFAULT 'todos', avaliacoes_por_equipe INTEGER
        );
        CREATE TABLE IF NOT EXISTS rodada_equipes (
          rodada_id INTEGER NOT NULL REFERENCES rodadas(id), inscricao_id TEXT NOT NULL,
          origem_rodada_id INTEGER, selecionada INTEGER NOT NULL DEFAULT 0,
          selecionada_em TEXT, PRIMARY KEY(rodada_id,inscricao_id)
        );
        CREATE TABLE IF NOT EXISTS rodada_atribuicoes (
          rodada_id INTEGER NOT NULL REFERENCES rodadas(id), inscricao_id TEXT NOT NULL,
          avaliador_id TEXT NOT NULL REFERENCES avaliadores(id), ativa INTEGER NOT NULL DEFAULT 1,
          criado_em TEXT NOT NULL, PRIMARY KEY(rodada_id,inscricao_id,avaliador_id)
        );
        CREATE TABLE IF NOT EXISTS rodada_pareceristas (
          rodada_id INTEGER NOT NULL REFERENCES rodadas(id),
          avaliador_id TEXT NOT NULL REFERENCES avaliadores(id),
          ativo INTEGER NOT NULL DEFAULT 1,
          criado_em TEXT NOT NULL,
          PRIMARY KEY(rodada_id,avaliador_id)
        );
        CREATE TABLE IF NOT EXISTS avaliacoes_rodada (
          id TEXT PRIMARY KEY, rodada_id INTEGER NOT NULL REFERENCES rodadas(id),
          avaliador_id TEXT NOT NULL REFERENCES avaliadores(id), inscricao_id TEXT NOT NULL,
          notas TEXT NOT NULL, comentario TEXT, criado_em TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS avaliacoes_rodada_lookup
          ON avaliacoes_rodada(rodada_id,avaliador_id,inscricao_id,criado_em DESC);
        """)
        if "contabiliza" not in {r[1] for r in con.execute("PRAGMA table_info(avaliadores)")}:
            con.execute("ALTER TABLE avaliadores ADD COLUMN contabiliza INTEGER NOT NULL DEFAULT 1")
        colunas_rodadas={r[1] for r in con.execute("PRAGMA table_info(rodadas)")}
        if "modo_atribuicao" not in colunas_rodadas:
            con.execute("ALTER TABLE rodadas ADD COLUMN modo_atribuicao TEXT NOT NULL DEFAULT 'todos'")
        if "avaliacoes_por_equipe" not in colunas_rodadas:
            con.execute("ALTER TABLE rodadas ADD COLUMN avaliacoes_por_equipe INTEGER")
        if con.execute("SELECT COUNT(*) FROM avaliadores").fetchone()[0] == 0:
            contas = [
                ("Administração", "admin@local", "admin", "admin-demo", 1),
                ("Erica Orosco", "erica@local", "parecerista", "parecerista-1", 1),
                ("Juliana Gelbaum", "juliana@local", "parecerista", "parecerista-2", 1),
                ("Thayna Bonsaver", "thayna@local", "parecerista", "parecerista-3", 1),
                ("Fabio Ribeiro", "fabio@local", "parecerista", "fabio-ribeiro", 0),
            ]
            con.executemany(
                "INSERT INTO avaliadores(id,nome,email,papel,token,ativo,contabiliza,criado_em) VALUES(?,?,?,?,?,1,?,?)",
                [(str(uuid.uuid4()), *c, agora()) for c in contas],
            )
        else:
            con.execute("UPDATE avaliadores SET nome='Erica Orosco', contabiliza=1 WHERE token='parecerista-1'")
            con.execute("UPDATE avaliadores SET nome='Juliana Gelbaum', contabiliza=1 WHERE token='parecerista-2'")
            con.execute("UPDATE avaliadores SET nome='Thayna Bonsaver', contabiliza=1 WHERE token='parecerista-3'")
            con.execute("INSERT INTO avaliadores(id,nome,email,papel,token,ativo,contabiliza,criado_em) SELECT ?,?,?,?,?,1,0,? WHERE NOT EXISTS (SELECT 1 FROM avaliadores WHERE token='fabio-ribeiro')", (str(uuid.uuid4()), "Fabio Ribeiro", "fabio@local", "parecerista", "fabio-ribeiro", agora()))
        criterios_1 = json.dumps([
            {"k":"edi","nome":"EDI (Equidade, Diversidade e Inclusão)","curto":"EDI","peso":30},
            {"k":"originalidade","nome":"Originalidade e Criatividade","curto":"Originalidade","peso":20},
            {"k":"qualidade","nome":"Qualidade da Proposta","curto":"Qualidade","peso":20},
            {"k":"viabilidade","nome":"Viabilidade","curto":"Viabilidade","peso":15},
            {"k":"impacto","nome":"Impacto Social","curto":"Impacto","peso":15}], ensure_ascii=False)
        criterios_3 = json.dumps([
            {"k":"viabilidade","nome":"Viabilidade","curto":"Viabilidade","peso":25},
            {"k":"inovacao","nome":"Inovação","curto":"Inovação","peso":25},
            {"k":"arguicao","nome":"Arguição","curto":"Arguição","peso":25},
            {"k":"impacto","nome":"Impacto","curto":"Impacto","peso":25}], ensure_ascii=False)
        rodadas = [
            (1,"inscricoes","Inscrições","Seleção das inscrições","Narrativa de ideação","Avalie a narrativa de ideação enviada pela equipe.",19,criterios_1,1,"aberta",0),
            (2,"planos","Planos de ação","Seleção dos planos de ação","Business Model Canvas","Avalie o plano de ação apresentado no formato Business Model Canvas, aplicando os mesmos critérios e pesos da seleção das inscrições.",10,criterios_1,2,"configuracao",1),
            (3,"banca","Banca","Avaliação da banca final","Pitch e arguição","Avalie o pitch de até 3 minutos e a arguição de até 5 minutos realizada pela banca.",1,criterios_3,3,"configuracao",1)]
        con.executemany("""INSERT INTO rodadas(id,slug,nome,titulo,entrega,orientacao,corte,criterios,ordem,status,oficial)
          VALUES(?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET nome=excluded.nome,titulo=excluded.titulo,
          entrega=excluded.entrega,orientacao=excluded.orientacao,corte=excluded.corte,criterios=excluded.criterios,
          ordem=excluded.ordem,oficial=excluded.oficial""", rodadas)
        inscricoes = json.loads((ROOT / "inscricoes.json").read_text())
        elegiveis = [x["id"] for x in inscricoes if x.get("elegibilidade", {}).get("status") == "elegivel"]
        con.executemany("INSERT OR IGNORE INTO rodada_equipes(rodada_id,inscricao_id) VALUES(1,?)", [(x,) for x in elegiveis])
        oficiais = con.execute("SELECT id FROM (SELECT id,row_number() OVER(PARTITION BY lower(trim(nome)) ORDER BY criado_em,id) rn FROM avaliadores WHERE papel='parecerista' AND ativo=1 AND contabiliza=1) WHERE rn=1").fetchall()
        con.executemany("INSERT OR IGNORE INTO rodada_atribuicoes(rodada_id,inscricao_id,avaliador_id,criado_em) VALUES(1,?,?,?)",
                        [(x, a["id"], agora()) for x in elegiveis for a in oficiais])
        con.execute("""INSERT OR IGNORE INTO rodada_pareceristas(rodada_id,avaliador_id,criado_em)
          SELECT DISTINCT rodada_id,avaliador_id,? FROM rodada_atribuicoes WHERE ativa=1""", (agora(),))
        con.execute("""INSERT OR IGNORE INTO avaliacoes_rodada(id,rodada_id,avaliador_id,inscricao_id,notas,comentario,criado_em)
          SELECT id,1,avaliador_id,inscricao_id,json_object('edi',edi,'originalidade',originalidade,'qualidade',qualidade,'viabilidade',viabilidade,'impacto',impacto),comentario,criado_em FROM avaliacoes""")


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

        if nome == "listar_rodadas":
            if not usuario(con, token):
                return []
            return [{**dicionario(r), "criterios": json.loads(r["criterios"]), "oficial": bool(r["oficial"])}
                    for r in con.execute("SELECT * FROM rodadas ORDER BY ordem").fetchall()]

        if nome == "fila_rodada":
            u = usuario(con, token)
            if not u:
                return []
            rodada = int(p.get("p_rodada_id") or 1)
            if u["papel"] == "admin":
                rows = con.execute("SELECT inscricao_id, selecionada FROM rodada_equipes WHERE rodada_id=? ORDER BY inscricao_id", (rodada,)).fetchall()
            else:
                rows = con.execute("""SELECT re.inscricao_id, re.selecionada FROM rodada_equipes re
                  JOIN rodada_atribuicoes ra ON ra.rodada_id=re.rodada_id AND ra.inscricao_id=re.inscricao_id
                  WHERE re.rodada_id=? AND ra.avaliador_id=? AND ra.ativa=1 ORDER BY re.inscricao_id""", (rodada,u["id"])).fetchall()
            return [dicionario(r) for r in rows]

        if nome == "minhas_avaliacoes_rodada":
            u = usuario(con, token)
            if not u:
                return []
            rodada = int(p.get("p_rodada_id") or 1)
            rows = con.execute("""SELECT ar.* FROM avaliacoes_rodada ar WHERE ar.rodada_id=? AND ar.avaliador_id=?
              AND ar.criado_em=(SELECT MAX(b.criado_em) FROM avaliacoes_rodada b WHERE b.rodada_id=ar.rodada_id AND b.avaliador_id=ar.avaliador_id AND b.inscricao_id=ar.inscricao_id)
              ORDER BY ar.inscricao_id""", (rodada,u["id"])).fetchall()
            return [{**dicionario(r), "notas": json.loads(r["notas"])} for r in rows]

        if nome == "salvar_avaliacao_rodada":
            u = usuario(con, token, "parecerista")
            if not u:
                raise ValueError("token inválido")
            rodada = int(p.get("p_rodada_id") or 1); inscricao_id = str(p.get("p_inscricao_id") or "")
            atribuida = con.execute("SELECT 1 FROM rodada_atribuicoes WHERE rodada_id=? AND inscricao_id=? AND avaliador_id=? AND ativa=1", (rodada,inscricao_id,u["id"])).fetchone()
            if not atribuida:
                raise ValueError("equipe não atribuída a este parecerista")
            config = con.execute("SELECT criterios FROM rodadas WHERE id=?", (rodada,)).fetchone()
            notas = p.get("p_notas") or {}; criterios = json.loads(config["criterios"] if config else "[]")
            if any(not isinstance(notas.get(c["k"]),(int,float)) or not 1 <= notas[c["k"]] <= 5 for c in criterios):
                raise ValueError("notas inválidas ou incompletas")
            rid = str(uuid.uuid4()); criado = agora()
            con.execute("INSERT INTO avaliacoes_rodada(id,rodada_id,avaliador_id,inscricao_id,notas,comentario,criado_em) VALUES(?,?,?,?,?,?,?)",
                        (rid,rodada,u["id"],inscricao_id,json.dumps(notas,ensure_ascii=False),str(p.get("p_comentario") or "").strip() or None,criado))
            r = dicionario(con.execute("SELECT * FROM avaliacoes_rodada WHERE id=?",(rid,)).fetchone()); r["notas"] = notas
            return r

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
            inscricoes = json.loads((ROOT / "inscricoes.json").read_text())
            ids = {x["id"] for x in inscricoes}
            elegiveis = {x["id"] for x in inscricoes if x.get("elegibilidade", {}).get("status") == "elegivel"}
            if inscricao_id not in ids:
                raise ValueError("inscrição inválida")
            if inscricao_id not in elegiveis:
                raise ValueError("inscrição não disponível para avaliação")
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
            rows = con.execute("SELECT id,nome,email,papel,token,ativo,contabiliza FROM avaliadores ORDER BY papel,nome").fetchall()
            return [{**dicionario(r), "ativo": bool(r["ativo"]), "contabiliza": bool(r["contabiliza"])} for r in rows]

        if nome == "criar_parecerista":
            nome_parecerista = str(p.get("p_nome") or "").strip()
            email = str(p.get("p_email") or "").strip() or None
            if len(nome_parecerista) < 3:
                raise ValueError("informe o nome completo do parecerista")
            if con.execute("SELECT 1 FROM avaliadores WHERE papel='parecerista' AND lower(trim(nome))=lower(trim(?)) AND ativo=1",(nome_parecerista,)).fetchone():
                raise ValueError("este parecerista já está cadastrado")
            token_novo = "parecerista-" + secrets.token_urlsafe(12)
            identificador = str(uuid.uuid4())
            con.execute("""INSERT INTO avaliadores(id,nome,email,papel,token,ativo,contabiliza,criado_em)
              VALUES(?,?,?,'parecerista',?,1,1,?)""", (identificador,nome_parecerista,email,token_novo,agora()))
            return dicionario(con.execute("SELECT id,nome,email,papel,token,ativo,contabiliza FROM avaliadores WHERE id=?",(identificador,)).fetchone())

        if nome == "excluir_parecerista":
            avaliador_id = str(p.get("p_avaliador_id") or "")
            alvo = con.execute("SELECT id FROM avaliadores WHERE id=? AND papel='parecerista' AND ativo=1", (avaliador_id,)).fetchone()
            if not alvo:
                raise ValueError("parecerista não encontrado")
            con.execute("UPDATE avaliadores SET ativo=0 WHERE id=?", (avaliador_id,))
            con.execute("UPDATE rodada_atribuicoes SET ativa=0 WHERE avaliador_id=?", (avaliador_id,))
            return True

        if nome == "listar_atribuicoes":
            rodada=int(p.get("p_rodada_id") or 1)
            return [dicionario(r) for r in con.execute("SELECT rodada_id,inscricao_id,avaliador_id,ativa FROM rodada_atribuicoes WHERE rodada_id=?",(rodada,)).fetchall()]

        if nome == "listar_pareceristas_rodada":
            rodada=int(p.get("p_rodada_id") or 1)
            return [dicionario(r) for r in con.execute("SELECT rodada_id,avaliador_id,ativo FROM rodada_pareceristas WHERE rodada_id=?",(rodada,)).fetchall()]

        if nome == "definir_parecerista_rodada":
            rodada=int(p.get("p_rodada_id") or 1); avaliador_id=str(p.get("p_avaliador_id") or ""); ativo=bool(p.get("p_ativo"))
            if not con.execute("SELECT 1 FROM avaliadores WHERE id=? AND papel='parecerista' AND ativo=1 AND contabiliza=1",(avaliador_id,)).fetchone():
                raise ValueError("parecerista inválido")
            con.execute("""INSERT INTO rodada_pareceristas(rodada_id,avaliador_id,ativo,criado_em) VALUES(?,?,?,?)
              ON CONFLICT(rodada_id,avaliador_id) DO UPDATE SET ativo=excluded.ativo""",(rodada,avaliador_id,int(ativo),agora()))
            if not ativo:
                con.execute("UPDATE rodada_atribuicoes SET ativa=0 WHERE rodada_id=? AND avaliador_id=?",(rodada,avaliador_id))
            return True

        if nome == "salvar_atribuicoes":
            rodada=int(p.get("p_rodada_id") or 1); inscricao=str(p.get("p_inscricao_id") or ""); ids=list(dict.fromkeys(p.get("p_avaliador_ids") or []))
            if not con.execute("SELECT 1 FROM rodada_equipes WHERE rodada_id=? AND inscricao_id=?",(rodada,inscricao)).fetchone():
                raise ValueError("equipe não pertence a esta rodada")
            con.execute("DELETE FROM rodada_atribuicoes WHERE rodada_id=? AND inscricao_id=?",(rodada,inscricao))
            validos=con.execute("SELECT id FROM (SELECT id,row_number() OVER(PARTITION BY lower(trim(nome)) ORDER BY criado_em,id) rn FROM avaliadores WHERE papel='parecerista' AND ativo=1 AND contabiliza=1) WHERE rn=1").fetchall(); validos={x["id"] for x in validos}
            if any(x not in validos for x in ids): raise ValueError("parecerista inválido")
            con.executemany("INSERT INTO rodada_atribuicoes(rodada_id,inscricao_id,avaliador_id,criado_em) VALUES(?,?,?,?)",[(rodada,inscricao,x,agora()) for x in ids])
            return len(ids)

        if nome == "distribuir_rodada":
            rodada=int(p.get("p_rodada_id") or 1); modo=str(p.get("p_modo") or "todos")
            quantidade=int(p.get("p_quantidade") or 0) if modo=="aleatoria" else None
            if modo not in ("todos","aleatoria"): raise ValueError("modo de distribuição inválido")
            avaliadores=[x["id"] for x in con.execute("""SELECT a.id FROM rodada_pareceristas rp JOIN avaliadores a ON a.id=rp.avaliador_id
              WHERE rp.rodada_id=? AND rp.ativo=1 AND a.ativo=1 AND a.contabiliza=1 ORDER BY a.nome""",(rodada,)).fetchall()]
            if not avaliadores: raise ValueError("selecione pelo menos um parecerista para esta etapa")
            if modo=="aleatoria" and (quantidade<1 or quantidade>len(avaliadores)):
                raise ValueError(f"informe uma quantidade entre 1 e {len(avaliadores)}")
            equipes=[x["inscricao_id"] for x in con.execute("SELECT inscricao_id FROM rodada_equipes WHERE rodada_id=?",(rodada,)).fetchall()]
            con.execute("UPDATE rodadas SET modo_atribuicao=?,avaliacoes_por_equipe=? WHERE id=?",(modo,quantidade,rodada))
            con.execute("DELETE FROM rodada_atribuicoes WHERE rodada_id=?",(rodada,))
            pares=[]
            for equipe in equipes:
                escolhidos=avaliadores if modo=="todos" else [x["id"] for x in con.execute("""SELECT a.id FROM rodada_pareceristas rp JOIN avaliadores a ON a.id=rp.avaliador_id
                  WHERE rp.rodada_id=? AND rp.ativo=1 AND a.ativo=1 AND a.contabiliza=1 ORDER BY random() LIMIT ?""",(rodada,quantidade)).fetchall()]
                pares.extend((rodada,equipe,a,agora()) for a in escolhidos)
            con.executemany("INSERT INTO rodada_atribuicoes(rodada_id,inscricao_id,avaliador_id,criado_em) VALUES(?,?,?,?)",pares)
            return len(pares)

        if nome == "todas_avaliacoes_rodada":
            rodada = int(p.get("p_rodada_id") or 1)
            rows = con.execute("""SELECT ar.*,v.nome AS avaliador,
              ROW_NUMBER() OVER(PARTITION BY ar.rodada_id,ar.avaliador_id,ar.inscricao_id ORDER BY ar.criado_em) AS versao,
              CASE WHEN ROW_NUMBER() OVER(PARTITION BY ar.rodada_id,ar.avaliador_id,ar.inscricao_id ORDER BY ar.criado_em DESC)=1 THEN 1 ELSE 0 END AS atual
              FROM avaliacoes_rodada ar JOIN avaliadores v ON v.id=ar.avaliador_id
              WHERE ar.rodada_id=? ORDER BY ar.inscricao_id,v.nome,ar.criado_em""", (rodada,)).fetchall()
            return [{**dicionario(r), "notas":json.loads(r["notas"]), "atual":bool(r["atual"])} for r in rows]

        if nome == "avancar_equipes":
            origem=int(p.get("p_origem") or 1); destino=int(p.get("p_destino") or origem+1); ids=list(dict.fromkeys(p.get("p_inscricoes") or []))
            corte=con.execute("SELECT corte FROM rodadas WHERE id=?",(origem,)).fetchone()
            if not corte or len(ids)!=corte["corte"]:
                raise ValueError(f"selecione exatamente {corte['corte'] if corte else 0} equipes")
            con.execute("DELETE FROM rodada_equipes WHERE rodada_id=?",(destino,)); con.execute("DELETE FROM rodada_atribuicoes WHERE rodada_id=?",(destino,))
            con.executemany("INSERT INTO rodada_equipes(rodada_id,inscricao_id,origem_rodada_id) VALUES(?,?,?)",[(destino,x,origem) for x in ids])
            config=con.execute("SELECT modo_atribuicao,avaliacoes_por_equipe FROM rodadas WHERE id=?",(destino,)).fetchone()
            avaliadores=[x["id"] for x in con.execute("SELECT id FROM (SELECT id,row_number() OVER(PARTITION BY lower(trim(nome)) ORDER BY criado_em,id) rn FROM avaliadores WHERE papel='parecerista' AND ativo=1 AND contabiliza=1) WHERE rn=1").fetchall()]
            pares=[]
            for equipe in ids:
                escolhidos=avaliadores if config["modo_atribuicao"]=="todos" else [x["id"] for x in con.execute("SELECT id FROM (SELECT id,row_number() OVER(PARTITION BY lower(trim(nome)) ORDER BY criado_em,id) rn FROM avaliadores WHERE papel='parecerista' AND ativo=1 AND contabiliza=1) WHERE rn=1 ORDER BY random() LIMIT ?",(config["avaliacoes_por_equipe"] or len(avaliadores),)).fetchall()]
                pares.extend((destino,equipe,a,agora()) for a in escolhidos)
            con.executemany("INSERT INTO rodada_atribuicoes(rodada_id,inscricao_id,avaliador_id,criado_em) VALUES(?,?,?,?)",pares)
            con.execute("UPDATE rodada_equipes SET selecionada=0,selecionada_em=NULL WHERE rodada_id=?",(origem,))
            con.executemany("UPDATE rodada_equipes SET selecionada=1,selecionada_em=? WHERE rodada_id=? AND inscricao_id=?",[(agora(),origem,x) for x in ids])
            con.execute("UPDATE rodadas SET status='fechada' WHERE id=?",(origem,)); con.execute("UPDATE rodadas SET status='aberta' WHERE id=?",(destino,))
            return len(ids)

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
