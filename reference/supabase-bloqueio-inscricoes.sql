-- Execute no SQL Editor do Supabase para reforçar no banco o bloqueio que já
-- existe na interface. Impede gravações por telas antigas ou chamadas diretas.

create or replace function salvar_avaliacao(
  p_token text, p_inscricao_id text,
  p_edi int, p_originalidade int, p_qualidade int, p_viabilidade int, p_impacto int,
  p_comentario text default null)
returns avaliacoes language plpgsql security definer set search_path = public as $$
declare v_id uuid; r avaliacoes;
begin
  select id into v_id from avaliadores
  where token = p_token and ativo and papel = 'parecerista';
  if v_id is null then raise exception 'token inválido'; end if;

  if p_inscricao_id = any(array[
    '63lswf3o8fr62voawekjue63lswf3jex', 'rqv39hekverfaqv9rqv39he0mri42wal',
    '4meflmc02tfnt10dc4mefl7voyhx839k', 'xx1wrvtcjb17f1o6ytkwxexx1wrv9ov1',
    'anm2vi5i4iwf5v4p5panm66xm6wn983x', '2ur9sr3djtwyxpg3av2ur9srl94xktcg',
    '100a8vobf7c6lpnxd100a8ve05sv0vu5'
  ]) then
    raise exception 'inscrição não disponível para avaliação';
  end if;

  insert into avaliacoes
    (avaliador_id, inscricao_id, edi, originalidade, qualidade, viabilidade, impacto, comentario)
  values
    (v_id, p_inscricao_id, p_edi, p_originalidade, p_qualidade, p_viabilidade,
     p_impacto, nullif(trim(p_comentario), ''))
  returning * into r;
  return r;
end $$;

revoke execute on function salvar_avaliacao(text,text,int,int,int,int,int,text)
from public, authenticated;
grant execute on function salvar_avaliacao(text,text,int,int,int,int,int,text)
to anon;
