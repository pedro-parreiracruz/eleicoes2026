-- Bloco PESQUISAS1T do painel: uma linha por (dia de fim de campo, instituto) nos
-- cenarios de 1o turno com a lista oficial (7+ candidatos, nenhum fora da urna).
-- linha = texto exato que vai para o HTML; nr_ordem = ordem em que entra.
with base as (
    select
        date_format(dt_fim_campo, 'yyyy-MM-dd') as dt_fim_campo,
        inst_ok as nm_instituto,
        max(qt_amostra) as qt_amostra,
        max(pc_margem_erro) as pc_margem_erro
    from {{ ref('painel_votos') }}
    where qt_candidatos_cenario >= 7 and qt_fora_da_urna_cenario = 0 and dt_fim_campo is not null
    group by 1, 2
)
select *,
       concat_ws(';', dt_fim_campo, nm_instituto, cast(qt_amostra as string), cast(pc_margem_erro as string)) as linha,
       row_number() over (order by concat_ws(';', dt_fim_campo, nm_instituto, cast(qt_amostra as string), cast(pc_margem_erro as string))) as nr_ordem
from base
