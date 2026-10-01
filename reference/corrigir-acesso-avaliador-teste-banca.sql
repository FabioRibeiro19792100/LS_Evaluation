-- Learning Sectors 2026 · sincroniza o avaliador de teste com a Banca
-- Execute no SQL Editor do Supabase. Pode ser executado novamente.

do $$
declare
  v_avaliador_id uuid;
begin
  select id into v_avaliador_id
  from avaliadores
  where lower(trim(nome))='avaliador teste · banca'
  order by criado_em,id
  limit 1;

  if v_avaliador_id is null then
    raise exception 'Avaliador Teste · Banca não encontrado. Execute primeiro cadastrar-avaliador-teste-banca.sql.';
  end if;

  update avaliadores
  set ativo=true, contabiliza=false
  where id=v_avaliador_id;

  insert into rodada_pareceristas(rodada_id,avaliador_id,ativo)
  values(3,v_avaliador_id,true)
  on conflict(rodada_id,avaliador_id) do update set ativo=true;

  insert into rodada_atribuicoes(rodada_id,inscricao_id,avaliador_id,ativa)
  select 3,re.inscricao_id,v_avaliador_id,true
  from rodada_equipes re
  where re.rodada_id=3
  on conflict(rodada_id,inscricao_id,avaliador_id) do update set ativa=true;
end
$$;

-- Redistribuir os pareceristas oficiais não pode mais apagar os acessos de teste.
create or replace function distribuir_rodada(p_token text,p_rodada_id smallint,p_modo text,p_quantidade smallint default null)
returns integer language plpgsql security definer set search_path=public as $$
declare v_total integer; v_avaliadores integer;
begin
  if not exists(select 1 from avaliadores where token=p_token and ativo and papel='admin') then raise exception 'acesso negado'; end if;
  if p_modo not in ('todos','aleatoria') then raise exception 'modo de distribuição inválido'; end if;

  select count(*) into v_avaliadores
  from rodada_pareceristas rp
  join avaliadores a on a.id=rp.avaliador_id
  where rp.rodada_id=p_rodada_id and rp.ativo and a.ativo and a.contabiliza;

  if v_avaliadores<1 then raise exception 'selecione pelo menos um parecerista para esta etapa'; end if;
  if p_modo='aleatoria' and (p_quantidade is null or p_quantidade<1 or p_quantidade>v_avaliadores) then
    raise exception 'informe uma quantidade entre 1 e %',v_avaliadores;
  end if;

  update rodadas
  set modo_atribuicao=p_modo,
      avaliacoes_por_equipe=case when p_modo='aleatoria' then p_quantidade else null end
  where id=p_rodada_id;

  -- Remove e refaz somente as atribuições oficiais.
  delete from rodada_atribuicoes ra
  using avaliadores av
  where ra.rodada_id=p_rodada_id
    and av.id=ra.avaliador_id
    and av.contabiliza;

  insert into rodada_atribuicoes(rodada_id,inscricao_id,avaliador_id)
  select p_rodada_id,e.inscricao_id,a.id
  from rodada_equipes e
  cross join lateral (
    select rp.avaliador_id id
    from rodada_pareceristas rp
    join avaliadores av on av.id=rp.avaliador_id
    where rp.rodada_id=p_rodada_id and rp.ativo and av.ativo and av.contabiliza
    order by case when p_modo='aleatoria' then random() else 0 end,av.nome
    limit case when p_modo='aleatoria' then p_quantidade else 2147483647 end
  ) a
  where e.rodada_id=p_rodada_id;
  get diagnostics v_total=row_count;

  -- Mantém cada perfil não contabilizado ligado a todas as equipes da sua etapa.
  insert into rodada_atribuicoes(rodada_id,inscricao_id,avaliador_id,ativa)
  select p_rodada_id,e.inscricao_id,rp.avaliador_id,true
  from rodada_equipes e
  join rodada_pareceristas rp on rp.rodada_id=e.rodada_id and rp.ativo
  join avaliadores av on av.id=rp.avaliador_id and av.ativo and not av.contabiliza
  where e.rodada_id=p_rodada_id
  on conflict(rodada_id,inscricao_id,avaliador_id) do update set ativa=true;

  return v_total;
end
$$;

revoke execute on function distribuir_rodada(text,smallint,text,smallint) from public,authenticated;
grant execute on function distribuir_rodada(text,smallint,text,smallint) to anon;

select
  a.nome,
  count(ra.inscricao_id) filter(where ra.ativa) as equipes_liberadas,
  'https://learning-sectors-avaliacao.vercel.app/avaliador?token='||a.token||'&rodada=3' as link_individual
from avaliadores a
left join rodada_atribuicoes ra
  on ra.avaliador_id=a.id and ra.rodada_id=3
where lower(trim(a.nome))='avaliador teste · banca'
group by a.id,a.nome,a.token;
