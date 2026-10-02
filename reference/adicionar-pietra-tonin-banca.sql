-- Learning Sectors 2026 · inclusão de Pietra Tonin na banca
-- Execute no SQL Editor do Supabase. Pode ser executado novamente.

do $$
declare
  v_avaliador_id uuid;
begin
  select a.id into v_avaliador_id
  from avaliadores a
  where a.papel='parecerista'
    and (
      lower(trim(a.nome))='pietra tonin'
      or lower(trim(coalesce(a.email,'')))='ptonin@grandepremiof1.com.br'
    )
  order by a.ativo desc,a.criado_em,a.id
  limit 1;

  if v_avaliador_id is null then
    insert into avaliadores(nome,email,papel,token,ativo,contabiliza)
    values(
      'Pietra Tonin',
      'ptonin@grandepremiof1.com.br',
      'parecerista',
      'parecerista-'||replace(gen_random_uuid()::text,'-',''),
      true,
      true
    )
    returning id into v_avaliador_id;
  else
    update avaliadores
    set nome='Pietra Tonin',
        email='ptonin@grandepremiof1.com.br',
        ativo=true,
        contabiliza=true
    where id=v_avaliador_id;
  end if;

  insert into rodada_pareceristas(rodada_id,avaliador_id,ativo)
  values(3,v_avaliador_id,true)
  on conflict(rodada_id,avaliador_id) do update set ativo=true;

  -- Como a banca usa todos os integrantes, libera as equipes atuais para Pietra.
  insert into rodada_atribuicoes(rodada_id,inscricao_id,avaliador_id,ativa)
  select 3,re.inscricao_id,v_avaliador_id,true
  from rodada_equipes re
  where re.rodada_id=3
  on conflict(rodada_id,inscricao_id,avaliador_id) do update set ativa=true;
end
$$;

select
  a.nome,
  a.email,
  count(ra.inscricao_id) filter(where ra.ativa) as equipes_liberadas,
  'https://learning-sectors-avaliacao.vercel.app/avaliador?token='||a.token||'&rodada=3' as link_individual
from avaliadores a
left join rodada_atribuicoes ra
  on ra.avaliador_id=a.id and ra.rodada_id=3
where lower(trim(a.nome))='pietra tonin'
group by a.id,a.nome,a.email,a.token;
