"""Normaliza nomes de exibição sem alterar a planilha de origem."""
import json
import re
from pathlib import Path

ARQUIVO = Path(__file__).with_name("inscricoes.json")

ESCOLAS = {
    "CENTRO PAULA SOUZA": "Etec São Sebastião",
    "Centro Paula Souza": "Etec São Sebastião",
    "Escola Tecnica Estadual de Taboão da Serra": "Escola Técnica Estadual de Taboão da Serra",
    "Etec Professor Alfredo de Barros Santos": "Escola Técnica Estadual Professor Alfredo de Barros Santos",
    "ETEC JORGE STREET": "Etec Jorge Street",
    "Etec Professora Maria Cristina  Medeiros": "Etec Professora Maria Cristina Medeiros",
    'Escola Técnica Estadual (ETEC) "Pedro Ferreira Alves"': "Etec Pedro Ferreira Alves",
    "ETEC Antônio Furlan": "Etec Antônio Furlan",
    "ETEC da Zona Leste": "Etec da Zona Leste",
    "ETEC Doutor Celso Giglio": "Etec Doutor Celso Giglio",
    "ETEC Irmã Agostina - Centro Paula Souza": "Etec Irmã Agostina",
    "ETEC PROFESSOR MASSUYUKI KAWANO": "Etec Professor Massuyuki Kawano",
    "ETEC Rosa Perrone Scavone": "Etec Rosa Perrone Scavone",
    "Etec Prefeito Alberto Feres Centro Paula Souza": "Etec Prefeito Alberto Feres",
    "ETEC Prefeito Alberto Feres": "Etec Prefeito Alberto Feres",
    "Etec Dr. Emílio Hernandez Aguilar": "Escola Técnica Dr. Emílio Hernandez Aguilar",
    "Etec Dr. emílio Hernandez Aguilar": "Escola Técnica Dr. Emílio Hernandez Aguilar",
    "Ceeteps - Etec Professor Alfredo de Barros Santos": "Escola Técnica Estadual Professor Alfredo de Barros Santos",
    "ETEC PROFESSOR ELIAS MIGUEL JÚNIOR": "Etec Professor Elias Miguel Júnior",
    "Colégio Estadual em Período Integral Ovaldo da Costa Meireles": "Colégio Estadual em Período Integral Osvaldo da Costa Meireles",
    "Colégio Estadual em Período integral Osvaldo da Costa Meireles": "Colégio Estadual em Período Integral Osvaldo da Costa Meireles",
    "colégio estadual em período integral osvaldo da costa meireles": "Colégio Estadual em Período Integral Osvaldo da Costa Meireles",
    "Escola Técnica Estadual de São Sebastião": "Etec São Sebastião",
    "ETEC de São Sebastião": "Etec São Sebastião",
    "ESCOLA TECNICA ESTADUAL DE SÃO SEBASTIÃO": "Etec São Sebastião",
    "ETEC Irmã Agostina": "Etec Irmã Agostina",
}

CIDADES_POR_ESCOLA = {
    "Conselheiro Antônio Prado": "Campinas",
    "Irmã Agostina": "São Paulo",
    "Prefeito Alberto Feres": "Araras",
}

CIDADES = {
    "São CAETANO DO SUL": "São Caetano do Sul",
    "SP Araras": "Araras",
}

PARTICULAS = {"da", "das", "de", "do", "dos", "e"}

EQUIPES_GOIAS = {"Cloves", "PawSave"}
EQUIPES_NAO_SELECIONADAS = {"Capeem", "Carpe Diem", "Frugalis", "QuickSilvers", "The Lookers"}

def espacos(valor):
    return re.sub(r"\s+", " ", (valor or "")).strip()

def nome_pessoa(valor):
    partes = espacos(valor).title().split()
    return " ".join(p.lower() if i and p.lower() in PARTICULAS else p for i, p in enumerate(partes))

def escola(valor):
    valor = espacos(valor)
    valor = ESCOLAS.get(valor, valor)
    # No produto todas as unidades são tratadas como Etecs; exibe apenas o
    # nome próprio para evitar repetir o tipo da instituição em cada linha.
    valor = re.sub(r"^Colégio Estadual em Período Integral\s+", "", valor, flags=re.I)
    valor = re.sub(r"^Escola Técnica Estadual\s+(?:de\s+)?", "", valor, flags=re.I)
    valor = re.sub(r"^Escola Técnica\s+", "", valor, flags=re.I)
    valor = re.sub(r"^Etec\s+(?:de\s+|da\s+)?", "", valor, flags=re.I)
    return espacos(valor)

dados = json.loads(ARQUIVO.read_text(encoding="utf-8"))
for item in dados:
    item["professor"] = nome_pessoa(item.get("professor"))
    item["escola"] = escola(item.get("escola"))
    item["municipio"] = CIDADES_POR_ESCOLA.get(item["escola"], CIDADES.get(espacos(item.get("municipio")), espacos(item.get("municipio"))))
    for estudante in item.get("estudantes", []):
        estudante["escola"] = escola(estudante.get("escola"))
    if item.get("equipe") in EQUIPES_GOIAS:
        item["elegibilidade"] = {
            "status": "fora_categoria",
            "motivo": "Não elegível: unidade localizada em Goiás, fora da categoria CPS.",
        }
    elif item.get("equipe") in EQUIPES_NAO_SELECIONADAS:
        item["elegibilidade"] = {
            "status": "nao_selecionada",
            "motivo": "Não selecionada: múltiplas inscrições submetidas pela mesma professora.",
        }

ARQUIVO.write_text(json.dumps(dados, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
print(f"{len(dados)} inscrições normalizadas")
