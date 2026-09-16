-- Execute uma vez no SQL Editor do Supabase.
-- Três pareceristas oficiais entram no cálculo; Fabio Ribeiro fica apenas em apoio/auditoria.

alter table avaliadores
  add column if not exists contabiliza boolean not null default true;

update avaliadores set nome = 'Erica Orosco', contabiliza = true
where token = 'parecerista-1' or lower(nome) = 'parecerista 1';

update avaliadores set nome = 'Juliana Gelbaum', contabiliza = true
where token = 'parecerista-2' or lower(nome) = 'parecerista 2';

update avaliadores set nome = 'Thayna Bonsaver', contabiliza = true
where token = 'parecerista-3' or lower(nome) = 'parecerista 3';

insert into avaliadores (nome, papel, contabiliza)
select 'Erica Orosco', 'parecerista', true
where not exists (select 1 from avaliadores where lower(nome) = 'erica orosco');

insert into avaliadores (nome, papel, contabiliza)
select 'Juliana Gelbaum', 'parecerista', true
where not exists (select 1 from avaliadores where lower(nome) = 'juliana gelbaum');

insert into avaliadores (nome, papel, contabiliza)
select 'Thayna Bonsaver', 'parecerista', true
where not exists (select 1 from avaliadores where lower(nome) = 'thayna bonsaver');

insert into avaliadores (nome, papel, contabiliza)
select 'Fabio Ribeiro', 'parecerista', false
where not exists (select 1 from avaliadores where lower(nome) = 'fabio ribeiro' and papel = 'parecerista');

update avaliadores set contabiliza = true
where lower(nome) in ('erica orosco','juliana gelbaum','thayna bonsaver') and papel = 'parecerista';

update avaliadores set contabiliza = false
where lower(nome) = 'fabio ribeiro' and papel = 'parecerista';

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

select nome, papel, contabiliza, token
from avaliadores
order by papel, contabiliza desc, nome;
