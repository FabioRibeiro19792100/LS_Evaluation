-- Learning Sectors 2026 · pareceristas independentes por etapa
-- Execute este arquivo inteiro no SQL Editor do Supabase.

create extension if not exists pgcrypto;
alter table rodadas add column if not exists modo_atribuicao text not null default 'todos';
alter table rodadas add column if not exists avaliacoes_por_equipe smallint;

create or replace function criar_parecerista(p_token text,p_nome text,p_email text default null)
returns table(id uuid,nome text,email text,papel text,token text,ativo boolean,contabiliza boolean)
language plpgsql security definer set search_path=public as $$
begin
  if not exists(select 1 from avaliadores a where a.token=p_token and a.ativo and a.papel='admin') then
    raise exception 'acesso negado';
  end if;
  if length(trim(coalesce(p_nome,'')))<3 then
    raise exception 'informe o nome completo do parecerista';
  end if;
  if exists(select 1 from avaliadores a where a.papel='parecerista' and a.ativo and lower(trim(a.nome))=lower(trim(p_nome))) then
    raise exception 'este parecerista já está cadastrado';
  end if;
  return query
    insert into avaliadores(nome,email,papel,token,ativo,contabiliza)
    values(trim(p_nome),nullif(trim(coalesce(p_email,'')),''),'parecerista',
           'parecerista-'||encode(gen_random_bytes(12),'hex'),true,true)
    returning avaliadores.id,avaliadores.nome,avaliadores.email,avaliadores.papel,
              avaliadores.token,avaliadores.ativo,avaliadores.contabiliza;
end $$;

create or replace function avancar_equipes(p_token text,p_origem smallint,p_destino smallint,p_inscricoes text[])
returns integer language plpgsql security definer set search_path=public as $$
declare v_corte integer; v_total integer;
begin
  if not exists(select 1 from avaliadores where token=p_token and ativo and papel='admin') then raise exception 'acesso negado'; end if;
  select corte into v_corte from rodadas where id=p_origem;
  v_total:=coalesce(array_length(p_inscricoes,1),0);
  if v_total<>v_corte then raise exception 'selecione exatamente % equipes',v_corte; end if;
  delete from rodada_equipes where rodada_id=p_destino;
  insert into rodada_equipes(rodada_id,inscricao_id,origem_rodada_id)
  select p_destino,unnest(p_inscricoes),p_origem;
  delete from rodada_atribuicoes where rodada_id=p_destino;
  insert into rodada_atribuicoes(rodada_id,inscricao_id,avaliador_id)
  select p_destino,e.inscricao_id,a.id from rodada_equipes e
  cross join lateral (
    select d.id from (select distinct on (lower(trim(v.nome))) v.id,v.nome
      from avaliadores v where v.papel='parecerista' and v.ativo and v.contabiliza
      order by lower(trim(v.nome)),v.criado_em,v.id) d
    order by case when (select modo_atribuicao from rodadas where id=p_destino)='aleatoria' then random() else 0 end,d.nome
    limit case when (select modo_atribuicao from rodadas where id=p_destino)='aleatoria'
      then (select avaliacoes_por_equipe from rodadas where id=p_destino) else 2147483647 end
  ) a where e.rodada_id=p_destino;
  update rodada_equipes set selecionada=inscricao_id=any(p_inscricoes),
    selecionada_em=case when inscricao_id=any(p_inscricoes) then now() else null end
    where rodada_id=p_origem;
  update rodadas set status='fechada' where id=p_origem;
  update rodadas set status='aberta' where id=p_destino;
  return v_total;
end $$;

create or replace function distribuir_rodada(p_token text,p_rodada_id smallint,p_modo text,p_quantidade smallint default null)
returns integer language plpgsql security definer set search_path=public as $$
declare v_total integer; v_avaliadores integer;
begin
  if not exists(select 1 from avaliadores where token=p_token and ativo and papel='admin') then raise exception 'acesso negado'; end if;
  if p_modo not in ('todos','aleatoria') then raise exception 'modo de distribuição inválido'; end if;
  select count(distinct lower(trim(nome))) into v_avaliadores from avaliadores where papel='parecerista' and ativo and contabiliza;
  if p_modo='aleatoria' and (p_quantidade is null or p_quantidade<1 or p_quantidade>v_avaliadores) then raise exception 'informe uma quantidade entre 1 e %',v_avaliadores; end if;
  update rodadas set modo_atribuicao=p_modo,avaliacoes_por_equipe=case when p_modo='aleatoria' then p_quantidade else null end where id=p_rodada_id;
  delete from rodada_atribuicoes where rodada_id=p_rodada_id;
  insert into rodada_atribuicoes(rodada_id,inscricao_id,avaliador_id)
  select p_rodada_id,e.inscricao_id,a.id from rodada_equipes e
  cross join lateral (
    select d.id from (select distinct on (lower(trim(v.nome))) v.id,v.nome
      from avaliadores v where v.papel='parecerista' and v.ativo and v.contabiliza
      order by lower(trim(v.nome)),v.criado_em,v.id) d
    order by case when p_modo='aleatoria' then random() else 0 end,d.nome
    limit case when p_modo='aleatoria' then p_quantidade else 2147483647 end
  ) a where e.rodada_id=p_rodada_id;
  get diagnostics v_total=row_count; return v_total;
end $$;

update rodadas set
  orientacao='Avalie o plano de ação apresentado no formato Business Model Canvas, aplicando os mesmos critérios e pesos da seleção das inscrições.',
  criterios='[{"k":"edi","nome":"EDI (Equidade, Diversidade e Inclusão)","curto":"EDI","peso":30},{"k":"originalidade","nome":"Originalidade e Criatividade","curto":"Originalidade","peso":20},{"k":"qualidade","nome":"Qualidade da Proposta","curto":"Qualidade","peso":20},{"k":"viabilidade","nome":"Viabilidade","curto":"Viabilidade","peso":15},{"k":"impacto","nome":"Impacto Social","curto":"Impacto","peso":15}]'::jsonb
where id=2;

update rodadas set
  orientacao='Avalie o pitch de até 3 minutos e a arguição de até 5 minutos realizada pela banca.',
  criterios='[{"k":"viabilidade","nome":"Viabilidade","curto":"Viabilidade","peso":25},{"k":"inovacao","nome":"Inovação","curto":"Inovação","peso":25},{"k":"arguicao","nome":"Arguição","curto":"Arguição","peso":25},{"k":"impacto","nome":"Impacto","curto":"Impacto","peso":25}]'::jsonb
where id=3;

-- O regulamento não fixa quantidade de pareceres por projeto; o padrão é todos avaliarem todos.
update rodadas set modo_atribuicao='todos',avaliacoes_por_equipe=null where id in (1,2,3);
delete from rodada_atribuicoes where rodada_id in (2,3);
insert into rodada_atribuicoes(rodada_id,inscricao_id,avaliador_id)
select re.rodada_id,re.inscricao_id,a.id from rodada_equipes re cross join (
  select distinct on (lower(trim(nome))) id,nome from avaliadores
  where papel='parecerista' and ativo and contabiliza
  order by lower(trim(nome)),criado_em,id
) a where re.rodada_id in (2,3);

revoke execute on function criar_parecerista(text,text,text) from public,authenticated;
grant execute on function criar_parecerista(text,text,text) to anon;
revoke execute on function distribuir_rodada(text,smallint,text,smallint) from public,authenticated;
grant execute on function distribuir_rodada(text,smallint,text,smallint) to anon;
