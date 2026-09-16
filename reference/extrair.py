"""Extrai da planilha do Typeform apenas os campos necessários à avaliação.
Nada de CPF, data de nascimento, cor/raça, gênero ou deficiência sai daqui."""
import json, sys
from openpyxl import load_workbook

SRC = sys.argv[1] if len(sys.argv) > 1 else "/mnt/user-data/uploads/LSBR-inscritos-14092026__1_.xlsx"
OUT = sys.argv[2] if len(sys.argv) > 2 else "/home/claude/inscricoes.json"

wb = load_workbook(SRC, read_only=True)
rows = list(wb.active.iter_rows(values_only=True))
hdr, rows = rows[0], rows[1:]

COMPONENTES = range(22, 51)           # colunas de componentes curriculares (checkbox)
ESTUDANTES = [(57, 60, 63), (67, 70, 73), (77, 80, 83), (87, 90, 93)]  # nome, escola, série

def s(v):
    return (v or "").strip() if isinstance(v, str) else ("" if v is None else str(v))

def serie_curta(v):
    v = s(v)
    if v.startswith("1"): return "1ª série EM"
    if v.startswith("2"): return "2ª série EM"
    return v

rows = sorted(rows, key=lambda r: s(r[169]))  # ordem de envio
out = []
for i, r in enumerate(rows, 1):
    comps = [s(r[c]) for c in COMPONENTES if s(r[c]) and c != 50]
    outro = s(r[51])
    if outro: comps.append(outro)
    estudantes = []
    for n, e, se in ESTUDANTES:
        if s(r[n]):
            estudantes.append({"escola": s(r[e]), "serie": serie_curta(r[se])})
    uf = s(r[16])
    eleg = {"status": "elegivel", "motivo": ""}
    if not uf.startswith("SP"):
        eleg = {"status": "fora_categoria",
                "motivo": f"Escola fora do Centro Paula Souza ({uf}). A categoria CPS é exclusiva das unidades do CPS (cláusula 2)."}
    out.append({
        "id": s(r[0]),
        "codigo": f"LS-{i:02d}",
        "equipe": s(r[55]),
        "categoria": "Centro Paula Souza",
        "escola": s(r[15]),
        "municipio": s(r[17]),
        "uf": uf,
        "professor": s(r[5]),
        "colider_nome": s(r[98]) if s(r[97]) == "1" else "",
        "componentes": comps,
        "conhecimento_ti": s(r[52]),
        "colider": s(r[97]) == "1",
        "estudantes": estudantes,
        "autodeclaracao": {
            "todos_perfis": s(r[152]),
            "genero": s(r[153]),
            "cor_raca": s(r[154]),
            "deficiencia": s(r[155]),
        },
        "narrativa": s(r[54]),
        "enviado_em": s(r[169]),
        "elegibilidade": eleg,
    })

json.dump(out, open(OUT, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
print(len(out), "inscrições;", sum(1 for x in out if x["elegibilidade"]["status"] != "elegivel"), "fora da categoria")
