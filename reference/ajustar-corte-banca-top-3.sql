-- Learning Sectors 2026 · a linha de corte da banca final marca o top 3.
update public.rodadas
set corte = 3
where id = 3;

select id, nome, corte
from public.rodadas
where id = 3;
