# Learning Sectors 2026 · Sistema de triagem das inscrições

## Executar a versão completa local

Esta versão já inclui backend e banco SQLite persistente, sem instalação de pacotes:

```bash
python3 server.py
```

Depois, abra:

- Parecerista: `http://127.0.0.1:8000/avaliador.html?token=parecerista-1`
- Administração: `http://127.0.0.1:8000/dashboard.html?token=admin-demo`

Contas iniciais: `parecerista-1`, `parecerista-2`, `parecerista-3` e `admin-demo`.
O arquivo `learning_sectors.db` é criado automaticamente no primeiro início. As
avaliações são append-only: cada alteração gera uma nova versão para auditoria.

Para produção, troque os tokens de demonstração antes de publicar e mantenha o
servidor atrás de HTTPS. O restante deste documento descreve também a opção
original de implantação no Supabase.

Dois ambientes, um banco mínimo no Supabase, sem dado sensível fora da planilha original.

## Arquivos

| Arquivo | O que é |
|---|---|
| `schema.sql` | Tabelas, funções e permissões. Rodar uma vez no SQL Editor do Supabase. |
| `avaliador.html` | Página do parecerista. Acessada por `avaliador.html?token=...` |
| `dashboard.html` | Consolidação, ranking, auditoria e exportação. Acessada por `dashboard.html?token=TOKEN_ADMIN` |
| `inscricoes.json` | As 42 inscrições com os campos usados na avaliação (já embutido nas duas páginas). |
| `extrair.py` | Gera o `inscricoes.json` a partir da planilha do Typeform. Só é preciso rodar de novo se a planilha mudar. |

## Passo a passo

1. **Supabase.** Crie um projeto, abra o SQL Editor, cole `schema.sql` inteiro e execute.
2. **Pareceristas.** No mesmo SQL Editor, cadastre você e a banca (os comandos estão comentados no fim do `schema.sql`). O token de cada pessoa é gerado sozinho.
3. **Chaves.** Em Project Settings > API, copie a *Project URL* e a chave *anon public*. Cole no topo de `avaliador.html` e de `dashboard.html`, nas constantes `SUPABASE_URL` e `SUPABASE_ANON_KEY`. A chave anon pode ficar exposta: as tabelas estão fechadas para ela, e todo acesso passa pelas funções que exigem token.
4. **Hospedagem.** Suba os dois HTML na mesma pasta em Vercel, Netlify, GitHub Pages ou qualquer hospedagem estática. Os arquivos são autocontidos (fonte via Google Fonts e SDK do Supabase via jsDelivr).
5. **Links.** Abra o dashboard com o seu token de admin: a última seção lista os pareceristas com o link pronto de cada um, já montado com o endereço da hospedagem.

## Como funciona

**Parecerista.** Recebe a fila das 40 inscrições elegíveis, uma por vez, com escola, professor(a)-líder, componentes, estudantes, autodeclaração sobre a equipe e a narrativa completa. Dá nota de 1 a 5 em cada um dos cinco critérios do regulamento (5.1.1), com o texto do critério e os pontos a observar logo ali. Comentário opcional. Pode voltar a qualquer inscrição e salvar uma nova versão até o prazo. Avaliação cega: uma pessoa nunca vê a nota das outras.

**Dashboard.** Progresso por parecerista, ranking com linha de corte nas 20 vagas, nota final e médias por critério, painel com as avaliações de cada inscrição (quem, quando, notas, comentário, histórico de versões) e duas exportações em CSV: o ranking consolidado e a auditoria completa, com todas as versões de todas as notas.

**Cálculo.** Para cada parecerista, média ponderada dos critérios na escala de 1 a 5 (EDI 30%, Originalidade 20%, Qualidade 20%, Viabilidade 15%, Impacto 15%). A nota final é a média dessas médias ponderadas entre pareceristas, também mantida na escala de 1 a 5. Desempate na ordem do regulamento 5.1.2: EDI, Originalidade, Qualidade, Viabilidade, Impacto. Se duas equipes empatarem também em todos os critérios, aparece a marca "empate": o regulamento não prevê critério além desse, então a decisão é da organização.

**Auditoria.** Nenhuma nota é sobrescrita ou apagada. Cada salvamento é uma linha nova com data e hora; o dashboard mostra a versão atual e o histórico. Para revogar o acesso de alguém: `update avaliadores set ativo = false where token = '...'`.

**Elegibilidade.** LS-28 (PawSave) e LS-29 (Cloves), ambas do Colégio Estadual em Período Integral Osvaldo da Costa Meireles, em Luziânia (GO), estão marcadas como fora da categoria e não entram na fila dos pareceristas. Aparecem no dashboard com o motivo. Para reverter ou marcar outra inscrição, edite o campo `elegibilidade` em `inscricoes.json` (ou em `extrair.py`) e gere as páginas de novo.

**Dados pessoais.** Foram deixados fora do sistema: CPF, datas de nascimento, e-mail, telefone, cor ou raça, identidade de gênero, deficiência, nomes dos estudantes e links de documentos. O cruzamento com a planilha original é pelo `id_typeform`, presente nos dois CSV exportados.

## Regenerar as páginas depois de editar dados

```
python3 extrair.py LSBR-inscritos.xlsx inscricoes.json
python3 build.py     # injeta o JSON em avaliador.html e dashboard.html
```
