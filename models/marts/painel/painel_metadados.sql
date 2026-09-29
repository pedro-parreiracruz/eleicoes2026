-- Cabecalho do painel: hora da carga, pesquisa mais recente, inicio de campo dela e cadencia
-- tipica de pesquisas (mediana de dias entre inicios de campo nos ultimos 120 dias).
-- As datas saem dos MESMOS blocos que o painel mostra (painel_1t_pesquisas e
-- painel_2t_duelos), nao de painel_votos: em 29/09/2026 um cenario da Genial/Quaest
-- (25-29/09, Lula x Marcal x Tarcisio) estava em painel_votos sem entrar em bloco nenhum, e o
-- chip "Pesquisa mais recente" mostrou uma data sem pesquisa na tela.
-- View, para que current_date() seja o da hora da leitura.
{{ config(materialized='view') }}

with pesquisas as (
    select dt_fim_campo, dt_inicio_campo from {{ ref('painel_1t_pesquisas') }}
    union
    select dt_fim_campo, dt_inicio_campo from {{ ref('painel_2t_duelos') }}
),

recente as (
    select max(dt_fim_campo) as dt_fim_campo from pesquisas
),

cad as (
    select datediff(d, lag(d) over (order by d)) as dias
    from (
        select distinct to_date(dt_inicio_campo) as d
        from pesquisas
        where to_date(dt_inicio_campo) >= date_sub(current_date(), 120)
    )
)

select
    date_format((select max(_ingerido_em) from {{ ref('painel_votos') }}), "yyyy-MM-dd'T'HH:mm:ss'Z'") as carga_utc,
    (select dt_fim_campo from recente) as campo_recente,
    -- inicio de campo das pesquisas que terminaram no dia mais recente
    coalesce((select max(p.dt_inicio_campo) from pesquisas p join recente r using (dt_fim_campo)),
             (select dt_fim_campo from recente)) as campo_inicio,
    cast(greatest(1, coalesce((select percentile_approx(dias, 0.5) from cad where dias > 0), 7)) as string) as cadencia
