-- Seleção confirmada a partir da planilha de Planos de Ação recebida em 26/09/2026.
-- Pode ser executado novamente: o resultado permanece o mesmo.

begin;

update rodadas set corte = 19, status = 'fechada' where id = 1;
update rodadas set status = 'aberta' where id = 2;

update rodada_equipes
set selecionada = false, selecionada_em = null
where rodada_id = 1;

with selecionadas(inscricao_id) as (
  select unnest(array[
    'wy8q9g6m7d1tmx7ut1cwy8q9y9yobe9t', -- Entende Aí · LS-10
    'm0ly60dyt8ir3m0ly60d5zd758un4oa0', -- PitStop Limpo · LS-09
    'lhp7radabnk41x9h6lhmv7l1f8cehwu5', -- Construindo Pertencimento · LS-37
    'ofoqqtvmusw8zm59dgofoqcoofq9jq32', -- 4YouMoney / CONFI · LS-38
    'lk1deq6qbbpdeeqftbxkaklk1deq6mei', -- NutriTech · LS-30
    'txghw7sjs1fihyz7gytgtxgbovibhdbl', -- SENSA · LS-25
    'xj9dwatoym7zdbn0rvbasxevxj9dwatb', -- Inclui+ · LS-40
    'hys1dr605ula8ccp94hy33qpc90h68pu', -- Ilusionistas · LS-19
    '9hxkoo16q8aghgztc1b9hx5x9w4qh9f3', -- INCLUSÃO ETEC / VOTO_AMS · LS-07
    'zs65wcmfcg8ynbens4xzs65lhka6ixs3', -- Conecta Escola · LS-35
    'y1hnu9zzaoa31wak8y1hnu9jzm12g9wp', -- Friends · LS-02
    'pm3dz6yv6ef12rhqtdpm3dzjx3trkpbx', -- Inclusios Turing · LS-11
    'lw714f0xfdtl8er2yz3lw71vck2thbs5', -- Ponto-a-Ponto · LS-22
    'x0a37ucx91wdykgaopyfx0a37fuvyj0k', -- STEMinist · LS-17
    '1fy7mvqi164nnzpaao1fy7mnrio5njp5', -- Velozes e Curiosos · LS-24
    'vrrw50kn6rn3e47p0eq7grvrrw50kenl', -- LITERA · LS-15
    't3w9bdhw87sm8ypiyt3w9bmjiqzam4lj', -- SENSIMOB · LS-05
    'm880lk96v7xm4bvuwom880d6tlkdj7kf', -- ACESSAETECAP · LS-21
    'necsvu94teumoobhg3d7bvvnecsvuvzz'  -- Vozz · LS-31
  ]::text[])
)
update rodada_equipes re
set selecionada = true, selecionada_em = now()
from selecionadas s
where re.rodada_id = 1 and re.inscricao_id = s.inscricao_id;

delete from rodada_atribuicoes where rodada_id = 2;
delete from rodada_equipes where rodada_id = 2;

insert into rodada_equipes (rodada_id, inscricao_id, origem_rodada_id)
select 2, inscricao_id, 1
from rodada_equipes
where rodada_id = 1 and selecionada;

insert into rodada_atribuicoes (rodada_id, inscricao_id, avaliador_id)
select 2, re.inscricao_id, a.id
from rodada_equipes re
cross join avaliadores a
where re.rodada_id = 2
  and a.papel = 'parecerista'
  and a.ativo
  and a.contabiliza;

commit;

select count(*) as equipes_em_planos_de_acao
from rodada_equipes
where rodada_id = 2;
