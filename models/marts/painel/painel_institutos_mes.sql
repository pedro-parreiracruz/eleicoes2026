-- Bloco INSTITUTOSMES: pesquisas registradas no TSE por mes e instituto.
-- Uma linha por instituto (sem agrupar em "Outros"): o painel soma os meses para o
-- total do mercado e, com um instituto escolhido no filtro, usa so as linhas dele.
-- Ate 21/09/2026 so os 12 maiores vinham pelo nome e o resto virava "Outros", e o
-- filtro por um instituto pequeno mostrava o grafico vazio.
with base as (
    select
        date_format(dt_registro, 'yyyy-MM') as ano_mes,
        nm_instituto,
        count(*) as qt_pesquisas,
        round(sum(vr_pesquisa), 2) as vr_total
    from {{ ref('fct_pesquisas_registradas') }}
    group by 1, 2
),
l as (
    select *,
           concat_ws(';', ano_mes, nm_instituto, cast(qt_pesquisas as string), cast(vr_total as string)) as linha
    from base
)
select *, row_number() over (order by linha) as nr_ordem
from l
