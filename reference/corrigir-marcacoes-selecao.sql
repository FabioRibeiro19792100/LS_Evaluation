-- Faz o dashboard devolver a marcação das equipes selecionadas já gravada no banco.
-- Execute no SQL Editor depois de selecionar-planos-acao-19.sql.

drop function if exists fila_rodada(text,smallint);

create function fila_rodada(p_token text,p_rodada_id smallint)
returns table(inscricao_id text, selecionada boolean)
language sql
security definer
set search_path=public
as $$
  select re.inscricao_id, re.selecionada
  from rodada_equipes re
  join avaliadores a on a.token=p_token and a.ativo
  where re.rodada_id=p_rodada_id
    and (a.papel='admin' or exists(
      select 1
      from rodada_atribuicoes ra
      where ra.rodada_id=re.rodada_id
        and ra.inscricao_id=re.inscricao_id
        and ra.avaliador_id=a.id
        and ra.ativa))
  order by re.inscricao_id
$$;

revoke execute on function fila_rodada(text,smallint) from public,authenticated;
grant execute on function fila_rodada(text,smallint) to anon;
