-- Bloco INSTITUTOS: mercado de pesquisas registradas no TSE, por instituto.
with base as (
    select
        nm_instituto,
        count(*) as qt_pesquisas,
        round(sum(vr_pesquisa), 2) as vr_total,
        sum(qt_entrevistados) as qt_entrevistados,
        count(case when ds_cargo = 'Presidente' then 1 end) as qt_presidente,
        count(case when tp_contratacao = 'Própria' then 1 end) as qt_propria,
        count(case when fl_dq_possui_alerta then 1 end) as qt_alerta,
        date_format(min(dt_registro), 'yyyy-MM-dd') as dt_primeiro_registro,
        date_format(max(dt_registro), 'yyyy-MM-dd') as dt_ultimo_registro
    from {{ ref('fct_pesquisas_registradas') }}
    group by nm_instituto
)
select *,
       concat_ws(';', nm_instituto, cast(qt_pesquisas as string), cast(vr_total as string),
                 cast(qt_entrevistados as string), cast(qt_presidente as string),
                 cast(qt_propria as string), cast(qt_alerta as string),
                 dt_primeiro_registro, dt_ultimo_registro) as linha,
       row_number() over (order by qt_pesquisas desc, nm_instituto) as nr_ordem
from base
