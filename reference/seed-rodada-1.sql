-- Carga inicial das 34 inscrições elegíveis na Rodada 1.
-- Execute depois de schema-rodadas.sql.
insert into rodada_equipes(rodada_id,inscricao_id)
select 1,id from (values
('ao2vx47wls3jypovao2vx4mrg9kepweq'),('y1hnu9zzaoa31wak8y1hnu9jzm12g9wp'),
('25m6zr0qruonoyl25ms0oaz1rt8so8t8'),('1awoduk3l5wzs13fap21awomk3amd67s'),
('t3w9bdhw87sm8ypiyt3w9bmjiqzam4lj'),('w2zkddn509f6tp90vvw2zzg25vpbir5f'),
('9hxkoo16q8aghgztc1b9hx5x9w4qh9f3'),('crcvaq4v927bbvv5xk0nto1crcvs7yb1'),
('m0ly60dyt8ir3m0ly60d5zd758un4oa0'),('wy8q9g6m7d1tmx7ut1cwy8q9y9yobe9t'),
('pm3dz6yv6ef12rhqtdpm3dzjx3trkpbx'),('vrrw50kn6rn3e47p0eq7grvrrw50kenl'),
('512z3p5fxdlpkw2d512z3u9g0vly46gc'),('x0a37ucx91wdykgaopyfx0a37fuvyj0k'),
('pz04x0hylfh0wratjq3cqpz04x0hnyjf'),('hys1dr605ula8ccp94hy33qpc90h68pu'),
('849w2lar7zlq2cc38g3849w2l5ly72hs'),('m880lk96v7xm4bvuwom880d6tlkdj7kf'),
('lw714f0xfdtl8er2yz3lw71vck2thbs5'),('tp69vtjcfg5hv178etp69v0fpbz86p13'),
('1fy7mvqi164nnzpaao1fy7mnrio5njp5'),('txghw7sjs1fihyz7gytgtxgbovibhdbl'),
('k0e39rccfjxjdh42agk0e39p1c83btu6'),('nyntdne0elaec5bnyq96nynmqctce9b9'),
('lk1deq6qbbpdeeqftbxkaklk1deq6mei'),('necsvu94teumoobhg3d7bvvnecsvuvzz'),
('kmd06qnx57bfoeq72tmkmd06h67pmiul'),('27c7kyx8qxxp8buzw727c7kyldhhq2xm'),
('zs65wcmfcg8ynbens4xzs65lhka6ixs3'),('lhp7radabnk41x9h6lhmv7l1f8cehwu5'),
('ofoqqtvmusw8zm59dgofoqcoofq9jq32'),('xj9dwatoym7zdbn0rvbasxevxj9dwatb'),
('jl4cu8ei5h1imyzkjl4cu8ei6rhl97vf'),('tmb3qn0ji8jvl5611tmb3qn0jjvq0wsm')
) as elegiveis(id)
on conflict do nothing;

insert into rodada_atribuicoes(rodada_id,inscricao_id,avaliador_id)
select 1,re.inscricao_id,a.id
from rodada_equipes re cross join avaliadores a
where re.rodada_id=1 and a.papel='parecerista' and a.ativo and a.contabiliza
on conflict do nothing;
