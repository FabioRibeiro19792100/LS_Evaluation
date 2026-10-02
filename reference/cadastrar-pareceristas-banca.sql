-- Learning Sectors 2026 · cadastro dos pareceristas da Banca
-- Pode ser executado novamente sem duplicar os cadastros.

do $$
declare
  v_id uuid;
  v_nome text;
  v_email text;
begin
  for v_nome,v_email in
    select * from (values
      ('Vera Oliveira','Vera.Oliveira@BritishCouncil.Org'),
      ('Barbara Cagliari','barbara.cagliari@britishcouncil.org'),
      ('Tiago Jesus de Souza','tiago.souza@cps.sp.gov.br'),
      ('Pietra Tonin','ptonin@grandepremiof1.com.br')
    ) as convidados(nome,email)
  loop
    select a.id into v_id
    from avaliadores a
    where a.papel='parecerista'
      and (
        lower(trim(a.nome))=lower(trim(v_nome))
        or lower(trim(coalesce(a.email,'')))=lower(trim(v_email))
      )
    order by a.ativo desc,a.criado_em,a.id
    limit 1;

    if v_id is null then
      insert into avaliadores(nome,email,papel,token,ativo,contabiliza)
      values(
        v_nome,
        v_email,
        'parecerista',
        'parecerista-'||replace(gen_random_uuid()::text,'-',''),
        true,
        true
      )
      returning id into v_id;
    else
      update avaliadores
      set nome=v_nome,email=v_email,ativo=true,contabiliza=true
      where id=v_id;
    end if;

    insert into rodada_pareceristas(rodada_id,avaliador_id,ativo)
    values(3,v_id,true)
    on conflict(rodada_id,avaliador_id)
    do update set ativo=true;
  end loop;
end
$$;

select
  a.nome,
  a.email,
  'https://learning-sectors-avaliacao.vercel.app/avaliador?token='||a.token||'&rodada=3' as link_individual
from avaliadores a
join rodada_pareceristas rp
  on rp.avaliador_id=a.id
 and rp.rodada_id=3
 and rp.ativo
where lower(trim(a.nome)) in (
  'vera oliveira',
  'barbara cagliari',
  'tiago jesus de souza',
  'pietra tonin'
)
order by a.nome;
