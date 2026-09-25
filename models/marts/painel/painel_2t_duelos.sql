-- Bloco DUELOS2T: cenarios com exatamente 2 candidatos (simulacoes de 2o turno), com quem
-- ficou na frente (hi) e atras (lo) e, no 8o campo da linha, o percentual de indecisos,
-- brancos e nulos do mesmo cenario. Inclui duelos hipoteticos; o painel marca e filtra
-- esses na tela.
with nao_resposta as (
    select id_cenario, sum(cast(pc_intencao_voto as double)) as pc_indecisos
    from {{ ref('painel_votos') }}
    where qt_candidatos_cenario = 2 and tp_resposta <> 'Candidato'
    group by 1
),
duelo as (
    select
        id_cenario,
        date_format(dt_fim_campo, 'yyyy-MM-dd') as dt_fim_campo,
        inst_ok as nm_instituto,
        max(pc_margem_erro) as pc_margem_erro,
        max(struct(cast(pc_intencao_voto as double) as v, nm_candidato as nm)) as hi,
        min(struct(cast(pc_intencao_voto as double) as v, nm_candidato as nm)) as lo
    from {{ ref('painel_votos') }}
    where qt_candidatos_cenario = 2 and tp_resposta = 'Candidato' and dt_fim_campo is not null
    group by 1, 2, 3
),
l as (
    select
        d.dt_fim_campo, d.nm_instituto,
        d.hi.nm as nm_candidato_frente, d.hi.v as pc_frente,
        d.lo.nm as nm_candidato_atras,  d.lo.v as pc_atras,
        d.pc_margem_erro,
        round(n.pc_indecisos, 2) as pc_indecisos,
        concat_ws(';', d.dt_fim_campo, d.nm_instituto, d.hi.nm, cast(d.hi.v as string), d.lo.nm,
                  cast(d.lo.v as string), cast(d.pc_margem_erro as string),
                  cast(round(n.pc_indecisos, 2) as string)) as linha
    from duelo d
    left join nao_resposta n using (id_cenario)
)
select *, row_number() over (order by dt_fim_campo, nm_instituto, nm_candidato_frente, linha) as nr_ordem
from l
