-- Learning Sectors 2026 · pareceristas independentes por etapa
-- Execute este arquivo inteiro no SQL Editor do Supabase.

create table if not exists rodada_pareceristas (
  rodada_id smallint not null references rodadas(id),
  avaliador_id uuid not null references avaliadores(id),
  ativo boolean not null default true,
  criado_em timestamptz not null default now(),
  primary key (rodada_id,avaliador_id)
);
alter table rodada_pareceristas enable row level security;
revoke all on rodada_pareceristas from anon,authenticated;

-- Mantém somente o cadastro canônico de cada nome, mesmo que existam registros
-- antigos duplicados na tabela de avaliadores.
delete from rodada_pareceristas rp
using avaliadores atual
where atual.id=rp.avaliador_id
  and exists (
    select 1 from avaliadores canon
    where canon.papel='parecerista' and canon.ativo and canon.contabiliza
      and lower(trim(canon.nome))=lower(trim(atual.nome))
      and (canon.criado_em,canon.id)<(atual.criado_em,atual.id)
  );

insert into rodada_pareceristas(rodada_id,avaliador_id)
select distinct ra.rodada_id,canon.id
from rodada_atribuicoes ra
join avaliadores usado on usado.id=ra.avaliador_id
join lateral (
  select a.id from avaliadores a
  where a.papel='parecerista' and a.ativo and a.contabiliza
    and lower(trim(a.nome))=lower(trim(usado.nome))
  order by a.criado_em,a.id limit 1
) canon on true
where ra.ativa
on conflict (rodada_id,avaliador_id) do update set ativo=true;

-- Remove atribuições duplicadas antigas e deixa a redistribuição recriá-las
-- apenas com os pareceristas canônicos de cada etapa.
delete from rodada_atribuicoes ra
using avaliadores atual
where atual.id=ra.avaliador_id
  and exists (
    select 1 from avaliadores canon
    where canon.papel='parecerista' and canon.ativo and canon.contabiliza
      and lower(trim(canon.nome))=lower(trim(atual.nome))
      and (canon.criado_em,canon.id)<(atual.criado_em,atual.id)
  );

create or replace function listar_pareceristas_rodada(p_token text,p_rodada_id smallint)
returns table(rodada_id smallint,avaliador_id uuid,ativo boolean)
language sql security definer set search_path=public as $$
  select rp.rodada_id,rp.avaliador_id,rp.ativo from rodada_pareceristas rp
  where rp.rodada_id=p_rodada_id
    and exists(select 1 from avaliadores a where a.token=p_token and a.ativo and a.papel='admin')
$$;

create or replace function definir_parecerista_rodada(p_token text,p_rodada_id smallint,p_avaliador_id uuid,p_ativo boolean)
returns boolean language plpgsql security definer set search_path=public as $$
begin
  if not exists(select 1 from avaliadores where token=p_token and ativo and papel='admin') then raise exception 'acesso negado'; end if;
  if not exists(select 1 from avaliadores where id=p_avaliador_id and ativo and papel='parecerista' and contabiliza) then raise exception 'parecerista inválido'; end if;
  insert into rodada_pareceristas(rodada_id,avaliador_id,ativo) values(p_rodada_id,p_avaliador_id,p_ativo)
    on conflict(rodada_id,avaliador_id) do update set ativo=excluded.ativo;
  if not p_ativo then update rodada_atribuicoes set ativa=false where rodada_id=p_rodada_id and avaliador_id=p_avaliador_id; end if;
  return true;
end $$;

create or replace function distribuir_rodada(p_token text,p_rodada_id smallint,p_modo text,p_quantidade smallint default null)
returns integer language plpgsql security definer set search_path=public as $$
declare v_total integer; v_avaliadores integer;
begin
  if not exists(select 1 from avaliadores where token=p_token and ativo and papel='admin') then raise exception 'acesso negado'; end if;
  if p_modo not in ('todos','aleatoria') then raise exception 'modo de distribuição inválido'; end if;
  select count(*) into v_avaliadores from rodada_pareceristas rp join avaliadores a on a.id=rp.avaliador_id
    where rp.rodada_id=p_rodada_id and rp.ativo and a.ativo and a.contabiliza;
  if v_avaliadores<1 then raise exception 'selecione pelo menos um parecerista para esta etapa'; end if;
  if p_modo='aleatoria' and (p_quantidade is null or p_quantidade<1 or p_quantidade>v_avaliadores) then raise exception 'informe uma quantidade entre 1 e %',v_avaliadores; end if;
  update rodadas set modo_atribuicao=p_modo,avaliacoes_por_equipe=case when p_modo='aleatoria' then p_quantidade else null end where id=p_rodada_id;
  delete from rodada_atribuicoes where rodada_id=p_rodada_id;
  insert into rodada_atribuicoes(rodada_id,inscricao_id,avaliador_id)
  select p_rodada_id,e.inscricao_id,a.id from rodada_equipes e
  cross join lateral (
    select rp.avaliador_id id from rodada_pareceristas rp join avaliadores av on av.id=rp.avaliador_id
    where rp.rodada_id=p_rodada_id and rp.ativo and av.ativo and av.contabiliza
    order by case when p_modo='aleatoria' then random() else 0 end,av.nome
    limit case when p_modo='aleatoria' then p_quantidade else 2147483647 end
  ) a where e.rodada_id=p_rodada_id;
  get diagnostics v_total=row_count; return v_total;
end $$;

revoke execute on function listar_pareceristas_rodada(text,smallint) from public,authenticated;
revoke execute on function definir_parecerista_rodada(text,smallint,uuid,boolean) from public,authenticated;
grant execute on function listar_pareceristas_rodada(text,smallint),definir_parecerista_rodada(text,smallint,uuid,boolean),distribuir_rodada(text,smallint,text,smallint) to anon;
