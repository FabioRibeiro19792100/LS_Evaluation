-- Learning Sectors 2026 · exclusão segura de pareceristas
-- Execute este arquivo inteiro no SQL Editor do Supabase.
-- O cadastro é desativado para preservar as avaliações e os registros históricos.

create or replace function excluir_parecerista(p_token text,p_avaliador_id uuid)
returns boolean language plpgsql security definer set search_path=public as $$
begin
  if not exists(
    select 1 from avaliadores a
    where a.token=p_token and a.ativo and a.papel='admin'
  ) then
    raise exception 'acesso negado';
  end if;

  if not exists(
    select 1 from avaliadores a
    where a.id=p_avaliador_id and a.papel='parecerista' and a.ativo
  ) then
    raise exception 'parecerista não encontrado';
  end if;

  update avaliadores set ativo=false where id=p_avaliador_id;
  update rodada_atribuicoes set ativa=false where avaliador_id=p_avaliador_id;
  return true;
end $$;

revoke execute on function excluir_parecerista(text,uuid) from public,authenticated;
grant execute on function excluir_parecerista(text,uuid) to anon;
