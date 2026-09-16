-- Calendario 2022-2026 (substitui a tabela calculada dCalendario do Power BI).
-- Diferenca: 'Dias ate a Eleicao' agora considera o 1o turno do ciclo; o 2o turno
-- fica em coluna propria.

with datas as (

    select explode(sequence(date'2022-01-01', date'2026-12-31', interval 1 day)) as dt

)

select
    dt                                                        as dt_data,
    year(dt)                                                  as nr_ano,
    month(dt)                                                 as nr_mes,
    date_format(dt, 'MMM')                                    as ds_mes_abrev,
    date_format(dt, 'yyyy-MM')                                as ds_ano_mes,
    case when year(dt) <= 2022 then '2022' else '2026' end    as ds_ciclo_eleitoral,
    datediff(
        case when year(dt) <= 2022 then date'{{ var("data_1t_2022") }}' else date'{{ var("data_1t_2026") }}' end,
        dt
    )                                                         as nr_dias_ate_1t,
    datediff(
        case when year(dt) <= 2022 then date'{{ var("data_2t_2022") }}' else date'{{ var("data_2t_2026") }}' end,
        dt
    )                                                         as nr_dias_ate_2t
from datas
