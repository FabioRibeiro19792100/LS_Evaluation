-- Learning Sectors 2026 · persistência imediata da seleção entre etapas
-- Execute uma única vez no SQL Editor do projeto sxegrslhumunntjwzcoi.

create or replace function marcar_selecao_rodada(
  p_token text,
  p_rodada_id smallint,
  p_inscricao_id text,
  p_selecionada boolean
)
returns integer
language plpgsql
security definer
set search_path=public
as $$
declare
  v_corte integer;
  v_total integer;
  v_atual boolean;
begin
  if not exists (
    select 1 from avaliadores
    where token=p_token and ativo and papel='admin'
  ) then
    raise exception 'acesso negado';
  end if;

  -- Serializa marcações simultâneas da mesma rodada para o limite não ser excedido.
  perform pg_advisory_xact_lock(p_rodada_id::bigint);

  select re.selecionada into v_atual
  from rodada_equipes re
  where re.rodada_id=p_rodada_id and re.inscricao_id=p_inscricao_id
  for update;

  if not found then
    raise exception 'equipe não pertence a esta etapa';
  end if;

  select corte into v_corte from rodadas where id=p_rodada_id;

  if p_selecionada and not v_atual then
    select count(*) into v_total
    from rodada_equipes
    where rodada_id=p_rodada_id and selecionada;

    if v_total>=v_corte then
      raise exception 'limite de % equipes atingido',v_corte;
    end if;
  end if;

  update rodada_equipes
  set selecionada=p_selecionada,
      selecionada_em=case when p_selecionada then coalesce(selecionada_em,now()) else null end
  where rodada_id=p_rodada_id and inscricao_id=p_inscricao_id;

  select count(*) into v_total
  from rodada_equipes
  where rodada_id=p_rodada_id and selecionada;

  return v_total;
end
$$;

revoke execute on function marcar_selecao_rodada(text,smallint,text,boolean) from public,authenticated;
grant execute on function marcar_selecao_rodada(text,smallint,text,boolean) to anon;
