-- Learning Sectors 2026 · Seleção das inscrições
-- Rode este arquivo inteiro no SQL Editor do Supabase (uma vez).
--
-- Modelo: as tabelas ficam fechadas para a chave anon (RLS ligado, sem policies).
-- Todo acesso passa por funções que exigem o token do avaliador.
-- Avaliações são append-only: revisar uma nota cria uma nova linha,
-- a anterior permanece para auditoria.

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------- tabelas
create table if not exists avaliadores (
  id         uuid primary key default gen_random_uuid(),
  nome       text not null,
  email      text,
  papel      text not null default 'parecerista' check (papel in ('parecerista','admin')),
  token      text not null unique default encode(gen_random_bytes(12), 'hex'),
  ativo      boolean not null default true,
  contabiliza boolean not null default true,
  criado_em  timestamptz not null default now()
);
alter table avaliadores add column if not exists contabiliza boolean not null default true;

create table if not exists avaliacoes (
  id            uuid primary key default gen_random_uuid(),
  avaliador_id  uuid not null references avaliadores(id),
  inscricao_id  text not null,
  edi           smallint not null check (edi between 1 and 5),
  originalidade smallint not null check (originalidade between 1 and 5),
  qualidade     smallint not null check (qualidade between 1 and 5),
  viabilidade   smallint not null check (viabilidade between 1 and 5),
  impacto       smallint not null check (impacto between 1 and 5),
  comentario    text,
  criado_em     timestamptz not null default now()
);
create index if not exists avaliacoes_lookup on avaliacoes (avaliador_id, inscricao_id, criado_em desc);

alter table avaliadores enable row level security;
alter table avaliacoes  enable row level security;
revoke all on avaliadores, avaliacoes from anon, authenticated;

-- ---------------------------------------------------------------- funções
-- Quem é o dono deste token?
create or replace function validar_token(p_token text)
returns json language sql security definer set search_path = public as $$
  select json_build_object('id', id, 'nome', nome, 'papel', papel)
  from avaliadores where token = p_token and ativo;
$$;

-- Última versão de cada avaliação deste parecerista
create or replace function minhas_avaliacoes(p_token text)
returns setof avaliacoes language sql security definer set search_path = public as $$
  select distinct on (a.inscricao_id) a.*
  from avaliacoes a
  join avaliadores v on v.id = a.avaliador_id
  where v.token = p_token and v.ativo
  order by a.inscricao_id, a.criado_em desc;
$$;

-- Grava uma nova versão (nunca sobrescreve)
create or replace function salvar_avaliacao(
  p_token text, p_inscricao_id text,
  p_edi int, p_originalidade int, p_qualidade int, p_viabilidade int, p_impacto int,
  p_comentario text default null)
returns avaliacoes language plpgsql security definer set search_path = public as $$
declare v_id uuid; r avaliacoes;
begin
  select id into v_id from avaliadores where token = p_token and ativo and papel = 'parecerista';
  if v_id is null then raise exception 'token inválido'; end if;
  if p_inscricao_id = any(array[
    '63lswf3o8fr62voawekjue63lswf3jex', 'rqv39hekverfaqv9rqv39he0mri42wal',
    '4meflmc02tfnt10dc4mefl7voyhx839k', 'xx1wrvtcjb17f1o6ytkwxexx1wrv9ov1',
    'anm2vi5i4iwf5v4p5panm66xm6wn983x', '2ur9sr3djtwyxpg3av2ur9srl94xktcg',
    '100a8vobf7c6lpnxd100a8ve05sv0vu5', 'f94a0vnpde0ttlt1sxf94a0vz50f5z76'
  ]) then raise exception 'inscrição não disponível para avaliação'; end if;
  insert into avaliacoes (avaliador_id, inscricao_id, edi, originalidade, qualidade, viabilidade, impacto, comentario)
  values (v_id, p_inscricao_id, p_edi, p_originalidade, p_qualidade, p_viabilidade, p_impacto, nullif(trim(p_comentario), ''))
  returning * into r;
  return r;
end $$;

-- Dashboard: todas as versões de todas as avaliações, com nome do parecerista
create or replace function todas_avaliacoes(p_token text)
returns table (
  id uuid, avaliador_id uuid, avaliador text, inscricao_id text,
  edi smallint, originalidade smallint, qualidade smallint, viabilidade smallint, impacto smallint,
  comentario text, criado_em timestamptz, versao bigint, atual boolean)
language sql security definer set search_path = public as $$
  select a.id, a.avaliador_id, v.nome, a.inscricao_id,
         a.edi, a.originalidade, a.qualidade, a.viabilidade, a.impacto,
         a.comentario, a.criado_em,
         row_number() over (partition by a.avaliador_id, a.inscricao_id order by a.criado_em) as versao,
         (row_number() over (partition by a.avaliador_id, a.inscricao_id order by a.criado_em desc) = 1) as atual
  from avaliacoes a
  join avaliadores v on v.id = a.avaliador_id
  where exists (select 1 from avaliadores x where x.token = p_token and x.ativo and x.papel = 'admin')
  order by a.inscricao_id, v.nome, a.criado_em;
$$;

-- Dashboard: lista de pareceristas e seus links
drop function if exists listar_avaliadores(text);
create or replace function listar_avaliadores(p_token text)
returns table (id uuid, nome text, email text, papel text, token text, ativo boolean, contabiliza boolean)
language sql security definer set search_path = public as $$
  select id, nome, email, papel, token, ativo, contabiliza from avaliadores
  where exists (select 1 from avaliadores x where x.token = p_token and x.ativo and x.papel = 'admin')
  order by papel, nome;
$$;

-- As funções SECURITY DEFINER não ficam acessíveis por padrão a outros papéis.
-- A aplicação pública recebe somente as cinco operações explicitamente liberadas abaixo.
revoke execute on function validar_token(text) from public, authenticated;
revoke execute on function minhas_avaliacoes(text) from public, authenticated;
revoke execute on function salvar_avaliacao(text,text,int,int,int,int,int,text) from public, authenticated;
revoke execute on function todas_avaliacoes(text) from public, authenticated;
revoke execute on function listar_avaliadores(text) from public, authenticated;

grant execute on function validar_token(text) to anon;
grant execute on function minhas_avaliacoes(text) to anon;
grant execute on function salvar_avaliacao(text,text,int,int,int,int,int,text) to anon;
grant execute on function todas_avaliacoes(text) to anon;
grant execute on function listar_avaliadores(text) to anon;

-- ---------------------------------------------------------------- cadastro
-- Crie você (admin) e os pareceristas. O token é gerado automaticamente;
-- depois rode o select para copiar os links.
--
-- insert into avaliadores (nome, email, papel) values ('Fabio', 'fabio@...', 'admin');
-- insert into avaliadores (nome, email, contabiliza) values
--   ('Erica Orosco', 'erica@...', true),
--   ('Juliana Gelbaum', 'juliana@...', true),
--   ('Thayna Bonsaver', 'thayna@...', true),
--   ('Fabio Ribeiro', 'fabio@...', false);
--
-- select nome, papel, token from avaliadores order by papel, nome;
--
-- Link do parecerista: https://SEU-DOMINIO/avaliador.html?token=TOKEN
-- Link do dashboard:   https://SEU-DOMINIO/dashboard.html?token=TOKEN_ADMIN
-- Para revogar um acesso: update avaliadores set ativo = false where token = '...';
