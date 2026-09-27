#!/usr/bin/env python3
"""Importa os 19 planos de ação para a base local usada na geração das telas."""
import json
import re
import unicodedata
from pathlib import Path

import openpyxl

RAIZ = Path(__file__).resolve().parent
ARQUIVO = RAIZ.parent / "LSBR-26092026-planos-de-acao-submetidos.xlsx"


def chave(valor):
    texto = unicodedata.normalize("NFD", str(valor or ""))
    return re.sub(r"[^a-z0-9]+", "", "".join(c for c in texto if unicodedata.category(c) != "Mn").lower())


wb = openpyxl.load_workbook(ARQUIVO, read_only=True, data_only=True)
ws = wb.active
linhas = list(ws.iter_rows(values_only=True))
cabecalhos = [str(x or "").strip() for x in linhas[0]]


def coluna(prefixo):
    return next(i for i, nome in enumerate(cabecalhos) if nome.startswith(prefixo))


campos = {
    "projeto": coluna("Nome do projeto:"),
    "problema": coluna("Qual problema o projeto quer resolver?"),
    "beneficiarios": coluna("Quem será beneficiado(a) pelo projeto?"),
    "solucao": coluna("Qual é a solução que o projeto propõe?"),
    "originalidade": coluna("Originalidade e criatividade"),
    "diversidade_impacto": coluna("Como o projeto promove diversidade e impacto social?"),
    "proposta_valor": coluna("Proposta de Valor"),
    "segmentos": coluna("Segmentos de públicos"),
    "canais": coluna("Canais -"),
    "relacionamento": coluna("Relacionamento com Clientes/Usuários"),
    "sustentacao": coluna("Fontes de sustentação e perenidade"),
    "recursos": coluna("Recursos Principais"),
    "atividades": coluna("Atividades-Chave"),
    "parcerias": coluna("Parcerias-chave"),
    "custos": coluna("Estrutura de Custos"),
    "stem_aplicacao": coluna("Aplicação dos conhecimentos STEM"),
}
idx_equipe = coluna("Nome da equipe:")
idx_professor = coluna("Nome completo da(o) professor(a) líder:")
idx_stem = [coluna(x) for x in ("Ciência", "Tecnologia", "Engenharia", "Matemática")]

por_professor = {}
por_equipe = {}
for linha in linhas[1:]:
    plano = {nome: str(linha[ix] or "").strip() for nome, ix in campos.items()}
    plano["equipe_enviada"] = str(linha[idx_equipe] or "").strip()
    plano["stem"] = [cabecalhos[ix] for ix in idx_stem if str(linha[ix] or "").strip()]
    por_professor[chave(linha[idx_professor])] = plano
    por_equipe[chave(linha[idx_equipe])] = plano

aliases = {
    chave("Claudio Roberto Corredato"): chave("VOTO_AMS"),
    chave("Marcio dos Santos"): chave("CONFI (Controle Financeiro Inteligente)"),
    chave("Marcelo João da Silva"): chave("ACESSAETECAP"),
}

caminho = RAIZ / "inscricoes.json"
inscricoes = json.loads(caminho.read_text(encoding="utf-8"))
codigo_max_por_equipe = {}
for item in inscricoes:
    equipe = chave(item.get("equipe"))
    numero = int(re.sub(r"\D", "", item.get("codigo", "0")) or 0)
    codigo_max_por_equipe[equipe] = max(numero, codigo_max_por_equipe.get(equipe, 0))
total = 0
for inscricao in inscricoes:
    equipe = chave(inscricao.get("equipe"))
    professor = chave(inscricao.get("professor"))
    plano = por_equipe.get(equipe)
    numero = int(re.sub(r"\D", "", inscricao.get("codigo", "0")) or 0)
    if plano and numero != codigo_max_por_equipe[equipe]:
        plano = None
    if not plano and aliases.get(professor) == equipe:
        plano = por_professor.get(professor)
    if plano:
        inscricao["plano_acao"] = plano
        total += 1

if total != len(por_professor):
    raise SystemExit(f"Importação incompleta: {total} de {len(por_professor)} planos associados.")
caminho.write_text(json.dumps(inscricoes, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(f"{total} planos de ação associados às equipes.")
