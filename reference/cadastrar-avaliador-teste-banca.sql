-- Learning Sectors 2026 · avaliador de teste exclusivo da banca
--
-- Execute no SQL Editor do projeto Supabase da aplicação.
-- Pode ser executado novamente: o cadastro e as atribuições não serão duplicados.
-- As avaliações deste perfil são salvas normalmente, mas `contabiliza=false`
-- impede que sejam usadas nas médias, ranking, progresso e auditoria oficiais.

do $$
declare
  v_avaliador_id uuid;
begin
  select a.id
    into v_avaliador_id
  from avaliadores a
  where a.papel = 'parecerista'
    and lower(trim(a.nome)) = 'avaliador teste · banca'
  order by a.ativo desc, a.criado_em, a.id
  limit 1;

  if v_avaliador_id is null then
    insert into avaliadores (nome, email, papel, token, ativo, contabiliza)
    values (
      'Avaliador Teste · Banca',
      'avaliador-teste@local',
      'parecerista',
      'teste-banca-' || replace(gen_random_uuid()::text, '-', ''),
      true,
      false
    )
    returning id into v_avaliador_id;
  else
    update avaliadores
       set email = 'avaliador-teste@local',
           ativo = true,
           contabiliza = false
     where id = v_avaliador_id;
  end if;

  -- O perfil existe apenas na etapa 3 (Banca).
  insert into rodada_pareceristas (rodada_id, avaliador_id, ativo)
  values (3, v_avaliador_id, true)
  on conflict (rodada_id, avaliador_id)
  do update set ativo = true;

  delete from rodada_pareceristas
  where avaliador_id = v_avaliador_id
    and rodada_id <> 3;

  delete from rodada_atribuicoes
  where avaliador_id = v_avaliador_id
    and rodada_id <> 3;

  -- Dá acesso a todas as equipes que pertencem atualmente à banca.
  insert into rodada_atribuicoes (rodada_id, inscricao_id, avaliador_id, ativa)
  select 3, re.inscricao_id, v_avaliador_id, true
  from rodada_equipes re
  where re.rodada_id = 3
  on conflict (rodada_id, inscricao_id, avaliador_id)
  do update set ativa = true;
end
$$;

-- Defesa no banco: avaliações de perfis não contabilizados não são devolvidas
-- ao dashboard, à auditoria nem às exportações oficiais.
create or replace function todas_avaliacoes_rodada(p_token text,p_rodada_id smallint)
returns table(id uuid,rodada_id smallint,avaliador_id uuid,avaliador text,inscricao_id text,notas jsonb,comentario text,criado_em timestamptz,versao bigint,atual boolean)
language sql security definer set search_path=public as $$
  select ar.id,ar.rodada_id,ar.avaliador_id,a.nome,ar.inscricao_id,ar.notas,ar.comentario,ar.criado_em,
    row_number() over(partition by ar.rodada_id,ar.avaliador_id,ar.inscricao_id order by ar.criado_em),
    row_number() over(partition by ar.rodada_id,ar.avaliador_id,ar.inscricao_id order by ar.criado_em desc)=1
  from avaliacoes_rodada ar
  join avaliadores a on a.id=ar.avaliador_id
  where ar.rodada_id=p_rodada_id
    and a.ativo
    and a.contabiliza
    and exists(select 1 from avaliadores x where x.token=p_token and x.ativo and x.papel='admin')
  order by ar.inscricao_id,a.nome,ar.criado_em
$$;

revoke execute on function todas_avaliacoes_rodada(text,smallint) from public,authenticated;
grant execute on function todas_avaliacoes_rodada(text,smallint) to anon;

-- O resultado desta consulta traz o link individual para copiar.
select
  a.nome,
  a.contabiliza,
  'https://learning-sectors-avaliacao.vercel.app/avaliador?token=' || a.token || '&rodada=3' as link_individual
from avaliadores a
where lower(trim(a.nome)) = 'avaliador teste · banca'
  and a.ativo;
