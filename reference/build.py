import json
from pathlib import Path

raiz = Path(__file__).resolve().parent
dados = json.dumps(json.load(open(raiz / "inscricoes.json")), ensure_ascii=False)
for t in ("avaliador","dashboard"):
    html = open(raiz / f"{t}.template.html", encoding="utf-8").read().replace("__DADOS__", dados)
    open(raiz / f"{t}.html", "w", encoding="utf-8").write(html)
print("ok")
