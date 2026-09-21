-- Bloco DUELOS2T: cenarios com exatamente 2 candidatos (simulacoes de 2o turno), com
-- quem ficou na frente (hi) e atras (lo). Inclui duelos hipoteticos; o painel marca e
-- filtra esses na tela.
with duelo as (
    select
        date_format(dt_fim_campo, 'yyyy-MM-dd') as dt_fim_campo,
        inst_ok as nm_instituto,
        max(pc_margem_erro) as pc_margem_erro,
        max(struct(cast(pc_intencao_voto as double) as v, nm_candidato as nm)) as hi,
        min(struct(cast(pc_intencao_voto as double) as v, nm_candidato as nm)) as lo
    from {{ ref('painel_votos') }}
    where qt_candidatos_cenario = 2 and tp_resposta = 'Candidato' and dt_fim_campo is not null
    group by id_cenario, 1, 2
),
l as (
    select
        dt_fim_campo, nm_instituto,
        hi.nm as nm_candidato_frente, hi.v as pc_frente,
        lo.nm as nm_candidato_atras,  lo.v as pc_atras,
        pc_margem_erro,
        concat_ws(';', dt_fim_campo, nm_instituto, hi.nm, cast(hi.v as string), lo.nm,
                  cast(lo.v as string), cast(pc_margem_erro as string)) as linha
    from duelo
)
select *, row_number() over (order by dt_fim_campo, nm_instituto, nm_candidato_frente, linha) as nr_ordem
from l
