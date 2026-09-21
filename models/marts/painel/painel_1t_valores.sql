-- Bloco VALORES1T: media de intencao de voto por (dia, instituto, candidato) nos mesmos
-- cenarios de 1o turno de painel_1t_pesquisas.
with base as (
    select
        date_format(dt_fim_campo, 'yyyy-MM-dd') as dt_fim_campo,
        inst_ok as nm_instituto,
        nm_candidato,
        coalesce(sg_partido, '?') as sg_partido,
        round(avg(cast(pc_intencao_voto as double)), 2) as pc_intencao_voto
    from {{ ref('painel_votos') }}
    where qt_candidatos_cenario >= 7 and qt_fora_da_urna_cenario = 0
      and tp_resposta = 'Candidato' and dt_fim_campo is not null
    group by 1, 2, 3, 4
),
l as (
    select *,
           concat_ws(';', dt_fim_campo, nm_instituto, concat(nm_candidato, '|', sg_partido),
                     cast(pc_intencao_voto as string)) as linha
    from base
)
select *, row_number() over (order by linha) as nr_ordem
from l
