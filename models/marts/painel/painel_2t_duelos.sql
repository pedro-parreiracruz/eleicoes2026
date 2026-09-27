-- Bloco DUELOS2T: cenarios com exatamente 2 candidatos (simulacoes de 2o turno), com quem
-- ficou na frente (hi) e atras (lo), no 8o campo da linha o percentual de indecisos,
-- brancos e nulos do mesmo cenario e, do 9o ao 12o, o registro da pesquisa no TSE, o nivel de
-- confianca, a contratacao (P = propria, C = contratada) e a empresa registrada; no 13o, a amostra. Inclui duelos hipoteticos; o painel marca e filtra
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
        max(nr_protocolo_registro) as nr_protocolo_registro,
        max(pc_nivel_confianca) as pc_nivel_confianca,
        max(qt_amostra) as qt_amostra,
        case when max(tp_contratacao) = 'Própria' then 'P' else 'C' end as tp_contratacao,
        replace(max(nm_empresa_registro), ';', ',') as nm_empresa_registro,
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
        d.nr_protocolo_registro, d.pc_nivel_confianca, d.tp_contratacao, d.nm_empresa_registro, d.qt_amostra,
        concat_ws(';', d.dt_fim_campo, d.nm_instituto, d.hi.nm, cast(d.hi.v as string), d.lo.nm,
                  cast(d.lo.v as string), coalesce(cast(d.pc_margem_erro as string), ''),
                  coalesce(cast(round(n.pc_indecisos, 2) as string), ''), d.nr_protocolo_registro,
                  coalesce(cast(d.pc_nivel_confianca as string), ''), d.tp_contratacao, d.nm_empresa_registro,
                  coalesce(cast(d.qt_amostra as string), '')) as linha
    from duelo d
    left join nao_resposta n using (id_cenario)
)
select *, row_number() over (order by dt_fim_campo, nm_instituto, nm_candidato_frente, linha) as nr_ordem
from l
