-- Learning Sectors 2026 · recuperação após exclusão indevida na tela da banca
-- Este script NÃO altera rodada_equipes, selecionada ou selecionada_em.

do $$
declare
  v_avaliador_id uuid;
begin
  for v_avaliador_id in
    select distinct ar.avaliador_id
    from avaliacoes_rodada ar
    join avaliadores a on a.id = ar.avaliador_id
    where ar.rodada_id in (1,2)
      and a.papel = 'parecerista'
      and a.contabiliza
  loop
    update avaliadores set ativo = true where id = v_avaliador_id;

    insert into rodada_pareceristas (rodada_id, avaliador_id, ativo)
    select distinct ar.rodada_id, ar.avaliador_id, true
    from avaliacoes_rodada ar
    where ar.avaliador_id = v_avaliador_id and ar.rodada_id in (1,2)
    on conflict (rodada_id, avaliador_id) do update set ativo = true;

    insert into rodada_atribuicoes (rodada_id, inscricao_id, avaliador_id, ativa)
    select distinct ar.rodada_id, ar.inscricao_id, ar.avaliador_id, true
    from avaliacoes_rodada ar
    where ar.avaliador_id = v_avaliador_id and ar.rodada_id in (1,2)
    on conflict (rodada_id, inscricao_id, avaliador_id) do update set ativa = true;

    if not exists (
      select 1 from avaliadores a
      where a.id = v_avaliador_id
        and lower(trim(a.nome)) in (
          'vera oliveira', 'barbara cagliari', 'tiago jesus de souza',
          'avaliador teste · banca'
        )
    ) then
      update rodada_pareceristas set ativo = false
      where rodada_id = 3 and avaliador_id = v_avaliador_id;
      update rodada_atribuicoes set ativa = false
      where rodada_id = 3 and avaliador_id = v_avaliador_id;
    end if;
  end loop;
end
$$;

create or replace function excluir_parecerista(p_token text,p_avaliador_id uuid)
returns boolean language plpgsql security definer set search_path=public as $$
begin
  if not exists(select 1 from avaliadores where token=p_token and ativo and papel='admin') then
    raise exception 'acesso negado';
  end if;
  if not exists(select 1 from avaliadores where id=p_avaliador_id and papel='parecerista' and ativo) then
    raise exception 'parecerista não encontrado';
  end if;
  if exists(select 1 from avaliacoes_rodada where avaliador_id=p_avaliador_id)
     or exists(select 1 from avaliacoes where avaliador_id=p_avaliador_id) then
    raise exception 'Este parecerista possui avaliações históricas. Use Remover da etapa para preservar as notas anteriores.';
  end if;
  update avaliadores set ativo=false where id=p_avaliador_id;
  update rodada_pareceristas set ativo=false where avaliador_id=p_avaliador_id;
  update rodada_atribuicoes set ativa=false where avaliador_id=p_avaliador_id;
  return true;
end
$$;

revoke execute on function excluir_parecerista(text,uuid) from public,authenticated;
grant execute on function excluir_parecerista(text,uuid) to anon;

select a.nome, a.ativo,
  string_agg(distinct rp.rodada_id::text, ', ' order by rp.rodada_id::text)
    filter (where rp.ativo) as etapas_ativas
from avaliadores a
left join rodada_pareceristas rp on rp.avaliador_id = a.id
where a.papel = 'parecerista'
group by a.id, a.nome, a.ativo
order by a.nome;
