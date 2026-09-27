-- Bloco PESQUISAS1T do painel: uma linha por (dia de fim de campo, instituto) nos
-- cenarios de 1o turno com a lista oficial (7+ candidatos, nenhum fora da urna).
-- linha = data;instituto;amostra;margem;registro(s) no TSE;nivel de confianca;
--         contratacao (P = propria, C = contratada);empresa registrada
-- nr_ordem = ordem em que entra.
with base as (
    select
        date_format(dt_fim_campo, 'yyyy-MM-dd') as dt_fim_campo,
        inst_ok as nm_instituto,
        max(qt_amostra) as qt_amostra,
        max(pc_margem_erro) as pc_margem_erro,
        array_join(array_sort(collect_set(nr_protocolo_registro)), ',') as nr_protocolo_registro,
        max(pc_nivel_confianca) as pc_nivel_confianca,
        case when max(tp_contratacao) = 'Própria' then 'P' else 'C' end as tp_contratacao,
        replace(max(nm_empresa_registro), ';', ',') as nm_empresa_registro
    from {{ ref('painel_votos') }}
    where qt_candidatos_cenario >= 7 and qt_fora_da_urna_cenario = 0 and dt_fim_campo is not null
    group by 1, 2
),
l as (
    select *,
           concat_ws(';', dt_fim_campo, nm_instituto, cast(qt_amostra as string), cast(pc_margem_erro as string),
                     nr_protocolo_registro, coalesce(cast(pc_nivel_confianca as string), ''),
                     tp_contratacao, nm_empresa_registro) as linha
    from base
)
select *, row_number() over (order by linha) as nr_ordem
from l
