-- Learning Sectors 2026 · restaura a exibição das notas da etapa inicial
-- Execute este arquivo inteiro no SQL Editor do Supabase.
-- Nenhuma nota é recalculada ou apagada; apenas o parecerista duplicado é
-- substituído pelo cadastro canônico já selecionado para a Rodada 1.

begin;

with canonicos as (
  select distinct on (lower(trim(a.nome)))
    lower(trim(a.nome)) chave,
    a.id
  from rodada_pareceristas rp
  join avaliadores a on a.id=rp.avaliador_id
  where rp.rodada_id=1 and rp.ativo and a.ativo and a.contabiliza
  order by lower(trim(a.nome)),a.criado_em,a.id
), mapa as (
  select antigo.id antigo_id,canonicos.id canonico_id
  from avaliadores antigo
  join canonicos on canonicos.chave=lower(trim(antigo.nome))
  where antigo.papel='parecerista' and antigo.contabiliza
    and antigo.id<>canonicos.id
)
update avaliacoes_rodada ar
set avaliador_id=mapa.canonico_id
from mapa
where ar.rodada_id=1 and ar.avaliador_id=mapa.antigo_id;

with canonicos as (
  select distinct on (lower(trim(a.nome)))
    lower(trim(a.nome)) chave,
    a.id
  from rodada_pareceristas rp
  join avaliadores a on a.id=rp.avaliador_id
  where rp.rodada_id=1 and rp.ativo and a.ativo and a.contabiliza
  order by lower(trim(a.nome)),a.criado_em,a.id
), mapa as (
  select antigo.id antigo_id,canonicos.id canonico_id
  from avaliadores antigo
  join canonicos on canonicos.chave=lower(trim(antigo.nome))
  where antigo.papel='parecerista' and antigo.contabiliza
    and antigo.id<>canonicos.id
)
update avaliacoes a
set avaliador_id=mapa.canonico_id
from mapa
where a.avaliador_id=mapa.antigo_id;

-- Desativa somente os cadastros repetidos que não são os utilizados pela etapa.
with canonicos as (
  select distinct on (lower(trim(a.nome)))
    lower(trim(a.nome)) chave,
    a.id
  from rodada_pareceristas rp
  join avaliadores a on a.id=rp.avaliador_id
  where rp.rodada_id=1 and rp.ativo and a.ativo and a.contabiliza
  order by lower(trim(a.nome)),a.criado_em,a.id
)
update avaliadores a
set ativo=false
from canonicos
where a.papel='parecerista' and a.contabiliza
  and lower(trim(a.nome))=canonicos.chave
  and a.id<>canonicos.id;

commit;

-- Conferência esperada: três pareceristas oficiais e as notas novamente visíveis.
select a.nome,count(*) total_registros
from avaliacoes_rodada ar
join avaliadores a on a.id=ar.avaliador_id
where ar.rodada_id=1 and a.ativo and a.contabiliza
group by a.nome order by a.nome;
