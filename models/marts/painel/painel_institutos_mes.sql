-- Bloco INSTITUTOSMES: pesquisas registradas por mes; os 12 institutos com mais
-- registros aparecem pelo nome, o resto vira "Outros".
with topi as (
    select nm_instituto
    from {{ ref('fct_pesquisas_registradas') }}
    group by 1
    order by count(*) desc, nm_instituto
    limit 12
),
base as (
    select
        date_format(p.dt_registro, 'yyyy-MM') as ano_mes,
        case when t.nm_instituto is null then 'Outros' else p.nm_instituto end as nm_instituto,
        count(*) as qt_pesquisas,
        round(sum(p.vr_pesquisa), 2) as vr_total
    from {{ ref('fct_pesquisas_registradas') }} p
    left join topi t using (nm_instituto)
    group by 1, 2
),
l as (
    select *,
           concat_ws(';', ano_mes, nm_instituto, cast(qt_pesquisas as string), cast(vr_total as string)) as linha
    from base
)
select *, row_number() over (order by linha) as nr_ordem
from l
