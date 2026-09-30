-- Learning Sectors 2026 · correção da criação de pareceristas
-- Execute este arquivo uma única vez no SQL Editor do Supabase.

create or replace function criar_parecerista(
  p_token text,
  p_nome text,
  p_email text default null
)
returns table(
  id uuid,
  nome text,
  email text,
  papel text,
  token text,
  ativo boolean,
  contabiliza boolean
)
language plpgsql
security definer
set search_path=public
as $$
begin
  if not exists (
    select 1 from avaliadores
    where avaliadores.token=p_token
      and avaliadores.ativo
      and avaliadores.papel='admin'
  ) then
    raise exception 'acesso negado';
  end if;

  if length(trim(coalesce(p_nome,'')))<3 then
    raise exception 'informe o nome completo do parecerista';
  end if;

  if exists (
    select 1 from avaliadores a
    where a.papel='parecerista'
      and a.ativo
      and lower(trim(a.nome))=lower(trim(p_nome))
  ) then
    raise exception 'este parecerista já está cadastrado';
  end if;

  return query
  insert into avaliadores(nome,email,papel,token,ativo,contabiliza)
  values(
    trim(p_nome),
    nullif(trim(coalesce(p_email,'')),''),
    'parecerista',
    'parecerista-'||replace(gen_random_uuid()::text,'-',''),
    true,
    true
  )
  returning
    avaliadores.id,
    avaliadores.nome,
    avaliadores.email,
    avaliadores.papel,
    avaliadores.token,
    avaliadores.ativo,
    avaliadores.contabiliza;
end
$$;

revoke execute on function criar_parecerista(text,text,text) from public,authenticated;
grant execute on function criar_parecerista(text,text,text) to anon;
