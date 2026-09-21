-- Cabecalho do painel: hora da carga, janela de campo e cadencia tipica de pesquisas
-- (mediana de dias entre inicios de campo nos ultimos 120 dias). View, para que
-- current_date() seja o da hora da leitura, como na consulta antiga.
{{ config(materialized='view') }}

with cad as (
    select datediff(dt_inicio_campo, lag(dt_inicio_campo) over (order by dt_inicio_campo)) as dias
    from (
        select distinct dt_inicio_campo
        from {{ ref('fct_intencao_voto') }}
        where dt_inicio_campo >= date_sub(current_date(), 120)
    )
)
select
    date_format((select max(_ingerido_em) from {{ ref('fct_intencao_voto') }}), "yyyy-MM-dd'T'HH:mm:ss'Z'") as carga_utc,
    date_format((select max(dt_fim_campo) from {{ ref('fct_intencao_voto') }}), 'yyyy-MM-dd') as campo_recente,
    date_format((select max(dt_inicio_campo) from {{ ref('fct_intencao_voto') }}), 'yyyy-MM-dd') as campo_inicio,
    cast(greatest(1, coalesce((select percentile_approx(dias, 0.5) from cad where dias > 0), 7)) as string) as cadencia
