-- Execute uma vez no SQL Editor do Supabase.
-- Remove apenas as avaliações de teste e garante os cinco acessos do sistema.

begin;

delete from avaliacoes;

alter table avaliadores
  add column if not exists contabiliza boolean not null default true;

-- Remove cadastros antigos dos mesmos nomes que receberam tokens aleatórios.
delete from avaliadores
where (lower(nome) = 'erica orosco' and token <> 'parecerista-1')
   or (lower(nome) = 'juliana gelbaum' and token <> 'parecerista-2')
   or (lower(nome) = 'thayna bonsaver' and token <> 'parecerista-3')
   or (lower(nome) = 'fabio ribeiro' and token <> 'fabio-ribeiro');

insert into avaliadores (nome, email, papel, token, ativo, contabiliza)
values
  ('Administração', 'admin@local', 'admin', 'admin-demo', true, true),
  ('Erica Orosco', 'erica@local', 'parecerista', 'parecerista-1', true, true),
  ('Juliana Gelbaum', 'juliana@local', 'parecerista', 'parecerista-2', true, true),
  ('Thayna Bonsaver', 'thayna@local', 'parecerista', 'parecerista-3', true, true),
  ('Fabio Ribeiro', 'fabio@local', 'parecerista', 'fabio-ribeiro', true, false)
on conflict (token) do update set
  nome = excluded.nome,
  email = excluded.email,
  papel = excluded.papel,
  ativo = excluded.ativo,
  contabiliza = excluded.contabiliza;

drop function if exists listar_avaliadores(text);
create function listar_avaliadores(p_token text)
returns table (id uuid, nome text, email text, papel text, token text, ativo boolean, contabiliza boolean)
language sql security definer set search_path = public as $$
  select id, nome, email, papel, token, ativo, contabiliza
  from avaliadores
  where exists (
    select 1 from avaliadores x
    where x.token = p_token and x.ativo and x.papel = 'admin'
  )
  order by papel, nome;
$$;

revoke execute on function listar_avaliadores(text) from public, authenticated;
grant execute on function listar_avaliadores(text) to anon;

commit;

select nome, papel, contabiliza, token
from avaliadores
order by papel, contabiliza desc, nome;
