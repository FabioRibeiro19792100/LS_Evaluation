import base64
import json
import os
from pathlib import Path

from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC
from cryptography.hazmat.primitives import hashes

raiz = Path(__file__).resolve().parent
inscricoes = json.load(open(raiz / "inscricoes.json"))
senha = os.environ.get("LS_DATA_PASSWORD")
if not senha:
    raise SystemExit("Defina LS_DATA_PASSWORD para gerar as páginas protegidas.")

salt = os.urandom(16)
iv = os.urandom(12)
chave = PBKDF2HMAC(algorithm=hashes.SHA256(), length=32, salt=salt, iterations=250_000).derive(senha.encode())
texto = json.dumps(inscricoes, ensure_ascii=False, separators=(",", ":")).encode()
cifrado = AESGCM(chave).encrypt(iv, texto, None)
protegido = json.dumps(base64.b64encode(salt + iv + cifrado).decode())
publicos = json.dumps([{"codigo": x["codigo"], "equipe": x["equipe"]} for x in inscricoes], ensure_ascii=False)
for t in ("avaliador","dashboard"):
    html = open(raiz / f"{t}.template.html", encoding="utf-8").read()
    html = html.replace("__DADOS_PUBLICOS__", publicos).replace("__DADOS_CRIPTOGRAFADOS__", protegido)
    open(raiz / f"{t}.html", "w", encoding="utf-8").write(html)
print("ok")
