-- Learning Sectors 2026 - migração para avaliação em rodadas
-- Execute este arquivo depois de schema.sql no SQL Editor do Supabase.
-- Mantém a tabela avaliacoes original intacta e copia seu histórico para a rodada 1.

create table if not exists rodadas (
  id smallint primary key,
  slug text not null unique,
  nome text not null,
  titulo text not null,
  entrega text not null,
  orientacao text not null,
  corte smallint not null check (corte > 0),
  criterios jsonb not null,
  ordem smallint not null unique,
  status text not null default 'configuracao' check (status in ('configuracao','aberta','fechada')),
  oficial boolean not null default true,
  criado_em timestamptz not null default now()
);

create table if not exists rodada_equipes (
  rodada_id smallint not null references rodadas(id),
  inscricao_id text not null,
  origem_rodada_id smallint references rodadas(id),
  selecionada boolean not null default false,
  selecionada_em timestamptz,
  primary key (rodada_id, inscricao_id)
);

create table if not exists rodada_atribuicoes (
  rodada_id smallint not null references rodadas(id),
  inscricao_id text not null,
  avaliador_id uuid not null references avaliadores(id),
  ativa boolean not null default true,
  criado_em timestamptz not null default now(),
  primary key (rodada_id, inscricao_id, avaliador_id)
);

create table if not exists avaliacoes_rodada (
  id uuid primary key default gen_random_uuid(),
  rodada_id smallint not null references rodadas(id),
  avaliador_id uuid not null references avaliadores(id),
  inscricao_id text not null,
  notas jsonb not null,
  comentario text,
  criado_em timestamptz not null default now(),
  check (jsonb_typeof(notas) = 'object')
);
create index if not exists avaliacoes_rodada_lookup
  on avaliacoes_rodada (rodada_id, avaliador_id, inscricao_id, criado_em desc);

alter table rodadas enable row level security;
alter table rodada_equipes enable row level security;
alter table rodada_atribuicoes enable row level security;
alter table avaliacoes_rodada enable row level security;
revoke all on rodadas, rodada_equipes, rodada_atribuicoes, avaliacoes_rodada from anon, authenticated;

insert into rodadas (id,slug,nome,titulo,entrega,orientacao,corte,criterios,ordem,status,oficial) values
(1,'inscricoes','Inscrições','Seleção das inscrições','Narrativa de ideação','Avalie a narrativa de ideação enviada pela equipe.',19,
 '[{"k":"edi","nome":"EDI (Equidade, Diversidade e Inclusão)","curto":"EDI","peso":30},{"k":"originalidade","nome":"Originalidade e Criatividade","curto":"Originalidade","peso":20},{"k":"qualidade","nome":"Qualidade da Proposta","curto":"Qualidade","peso":20},{"k":"viabilidade","nome":"Viabilidade","curto":"Viabilidade","peso":15},{"k":"impacto","nome":"Impacto Social","curto":"Impacto","peso":15}]',1,'aberta',false),
(2,'planos','Planos de ação','Seleção dos planos de ação','Business Model Canvas','Avalie o plano de ação no formato Business Model Canvas.',10,
 '[{"k":"edi","nome":"EDI (Equidade, Diversidade e Inclusão)","curto":"EDI","peso":30},{"k":"originalidade","nome":"Originalidade e Criatividade","curto":"Originalidade","peso":20},{"k":"qualidade","nome":"Qualidade da Proposta","curto":"Qualidade","peso":20},{"k":"viabilidade","nome":"Viabilidade","curto":"Viabilidade","peso":15},{"k":"impacto","nome":"Impacto Social","curto":"Impacto","peso":15}]',2,'configuracao',true),
(3,'banca','Banca','Avaliação da banca final','Pitch e arguição','Avalie a apresentação e as respostas da equipe à banca.',1,
 '[{"k":"viabilidade","nome":"Viabilidade","curto":"Viabilidade","peso":25},{"k":"inovacao","nome":"Inovação","curto":"Inovação","peso":25},{"k":"arguicao","nome":"Arguição","curto":"Arguição","peso":25},{"k":"impacto","nome":"Impacto","curto":"Impacto","peso":25}]',3,'configuracao',true)
on conflict (id) do update set
  nome=excluded.nome,titulo=excluded.titulo,entrega=excluded.entrega,
  orientacao=excluded.orientacao,corte=excluded.corte,criterios=excluded.criterios,
  ordem=excluded.ordem,oficial=excluded.oficial;

-- As avaliações existentes passam a constituir a Rodada 1.
insert into avaliacoes_rodada (id,rodada_id,avaliador_id,inscricao_id,notas,comentario,criado_em)
select a.id,1,a.avaliador_id,a.inscricao_id,
       jsonb_build_object('edi',a.edi,'originalidade',a.originalidade,'qualidade',a.qualidade,'viabilidade',a.viabilidade,'impacto',a.impacto),
       a.comentario,a.criado_em
from avaliacoes a
on conflict (id) do nothing;

create or replace function validar_notas_rodada(p_rodada_id smallint, p_notas jsonb)
returns boolean language sql stable security definer set search_path=public as $$
  select coalesce(bool_and(
    p_notas ? (c->>'k') and
    jsonb_typeof(p_notas->(c->>'k'))='number' and
    (p_notas->>(c->>'k'))::numeric between 1 and 5
  ),false)
  from rodadas r cross join lateral jsonb_array_elements(r.criterios) c
  where r.id=p_rodada_id
$$;

create or replace function listar_rodadas(p_token text)
returns setof rodadas language sql security definer set search_path=public as $$
  select r.* from rodadas r
  where exists(select 1 from avaliadores a where a.token=p_token and a.ativo)
  order by r.ordem
$$;

create or replace function fila_rodada(p_token text,p_rodada_id smallint)
returns table(inscricao_id text) language sql security definer set search_path=public as $$
  select re.inscricao_id from rodada_equipes re
  join avaliadores a on a.token=p_token and a.ativo
  where re.rodada_id=p_rodada_id
    and (a.papel='admin' or exists(
      select 1 from rodada_atribuicoes ra
      where ra.rodada_id=re.rodada_id and ra.inscricao_id=re.inscricao_id
        and ra.avaliador_id=a.id and ra.ativa))
  order by re.inscricao_id
$$;

create or replace function minhas_avaliacoes_rodada(p_token text,p_rodada_id smallint)
returns table(id uuid,rodada_id smallint,avaliador_id uuid,inscricao_id text,notas jsonb,comentario text,criado_em timestamptz)
language sql security definer set search_path=public as $$
  select distinct on (ar.inscricao_id) ar.id,ar.rodada_id,ar.avaliador_id,ar.inscricao_id,ar.notas,ar.comentario,ar.criado_em
  from avaliacoes_rodada ar join avaliadores a on a.id=ar.avaliador_id
  where a.token=p_token and a.ativo and ar.rodada_id=p_rodada_id
  order by ar.inscricao_id,ar.criado_em desc
$$;

create or replace function salvar_avaliacao_rodada(p_token text,p_rodada_id smallint,p_inscricao_id text,p_notas jsonb,p_comentario text default null)
returns avaliacoes_rodada language plpgsql security definer set search_path=public as $$
declare v_avaliador uuid; v_resultado avaliacoes_rodada;
begin
  select id into v_avaliador from avaliadores where token=p_token and ativo and papel='parecerista';
  if v_avaliador is null then raise exception 'token inválido'; end if;
  if not exists(select 1 from rodada_atribuicoes where rodada_id=p_rodada_id and inscricao_id=p_inscricao_id and avaliador_id=v_avaliador and ativa)
    then raise exception 'equipe não atribuída a este parecerista'; end if;
  if not validar_notas_rodada(p_rodada_id,p_notas) then raise exception 'notas inválidas ou incompletas'; end if;
  insert into avaliacoes_rodada(rodada_id,avaliador_id,inscricao_id,notas,comentario)
  values(p_rodada_id,v_avaliador,p_inscricao_id,p_notas,nullif(trim(p_comentario),'')) returning * into v_resultado;
  return v_resultado;
end $$;

create or replace function todas_avaliacoes_rodada(p_token text,p_rodada_id smallint)
returns table(id uuid,rodada_id smallint,avaliador_id uuid,avaliador text,inscricao_id text,notas jsonb,comentario text,criado_em timestamptz,versao bigint,atual boolean)
language sql security definer set search_path=public as $$
  select ar.id,ar.rodada_id,ar.avaliador_id,a.nome,ar.inscricao_id,ar.notas,ar.comentario,ar.criado_em,
    row_number() over(partition by ar.rodada_id,ar.avaliador_id,ar.inscricao_id order by ar.criado_em),
    row_number() over(partition by ar.rodada_id,ar.avaliador_id,ar.inscricao_id order by ar.criado_em desc)=1
  from avaliacoes_rodada ar join avaliadores a on a.id=ar.avaliador_id
  where ar.rodada_id=p_rodada_id and exists(select 1 from avaliadores x where x.token=p_token and x.ativo and x.papel='admin')
  order by ar.inscricao_id,a.nome,ar.criado_em
$$;

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
  select p_destino,i,a.id from unnest(p_inscricoes) i cross join avaliadores a
  where a.papel='parecerista' and a.ativo and a.contabiliza;
  update rodada_equipes set selecionada=inscricao_id=any(p_inscricoes),selecionada_em=case when inscricao_id=any(p_inscricoes) then now() else null end where rodada_id=p_origem;
  update rodadas set status='fechada' where id=p_origem;
  update rodadas set status='aberta' where id=p_destino;
  return v_total;
end $$;

create or replace function listar_atribuicoes(p_token text,p_rodada_id smallint)
returns table(rodada_id smallint,inscricao_id text,avaliador_id uuid,ativa boolean)
language sql security definer set search_path=public as $$
  select ra.rodada_id,ra.inscricao_id,ra.avaliador_id,ra.ativa from rodada_atribuicoes ra
  where ra.rodada_id=p_rodada_id and exists(select 1 from avaliadores a where a.token=p_token and a.ativo and a.papel='admin')
$$;

create or replace function salvar_atribuicoes(p_token text,p_rodada_id smallint,p_inscricao_id text,p_avaliador_ids uuid[])
returns integer language plpgsql security definer set search_path=public as $$
declare v_total integer;
begin
  if not exists(select 1 from avaliadores where token=p_token and ativo and papel='admin') then raise exception 'acesso negado'; end if;
  if not exists(select 1 from rodada_equipes where rodada_id=p_rodada_id and inscricao_id=p_inscricao_id) then raise exception 'equipe não pertence a esta rodada'; end if;
  delete from rodada_atribuicoes where rodada_id=p_rodada_id and inscricao_id=p_inscricao_id;
  insert into rodada_atribuicoes(rodada_id,inscricao_id,avaliador_id)
  select p_rodada_id,p_inscricao_id,a.id from avaliadores a where a.id=any(p_avaliador_ids) and a.papel='parecerista' and a.ativo and a.contabiliza;
  get diagnostics v_total=row_count; return v_total;
end $$;

revoke execute on function validar_notas_rodada(smallint,jsonb) from public,authenticated;
revoke execute on function listar_rodadas(text) from public,authenticated;
revoke execute on function fila_rodada(text,smallint) from public,authenticated;
revoke execute on function minhas_avaliacoes_rodada(text,smallint) from public,authenticated;
revoke execute on function salvar_avaliacao_rodada(text,smallint,text,jsonb,text) from public,authenticated;
revoke execute on function todas_avaliacoes_rodada(text,smallint) from public,authenticated;
revoke execute on function avancar_equipes(text,smallint,smallint,text[]) from public,authenticated;
revoke execute on function listar_atribuicoes(text,smallint) from public,authenticated;
revoke execute on function salvar_atribuicoes(text,smallint,text,uuid[]) from public,authenticated;
grant execute on function listar_rodadas(text),fila_rodada(text,smallint),minhas_avaliacoes_rodada(text,smallint),salvar_avaliacao_rodada(text,smallint,text,jsonb,text),todas_avaliacoes_rodada(text,smallint),avancar_equipes(text,smallint,smallint,text[]),listar_atribuicoes(text,smallint),salvar_atribuicoes(text,smallint,text,uuid[]) to anon;

-- A Rodada 1 precisa conter todas as inscrições elegíveis. A aplicação local
-- faz essa carga automaticamente. No Supabase, rode também o arquivo
-- seed-rodada-1.sql gerado junto desta migração.
