-- Bloco VALORES1T: media por (dia, instituto, resposta) nos cenarios de 1o turno com a
-- lista oficial. Traz candidatos E nao-respostas (indecisos, brancos, nulos e "outros"):
-- o 5o campo da linha separa os dois (C = candidato, N = nao-resposta), e o painel usa as
-- nao-respostas num bloco proprio, fora da disputa entre candidatos.
with base as (
    select
        date_format(dt_fim_campo, 'yyyy-MM-dd') as dt_fim_campo,
        inst_ok as nm_instituto,
        nm_candidato,
        coalesce(sg_partido, '?') as sg_partido,
        tp_resposta,
        round(avg(cast(pc_intencao_voto as double)), 2) as pc_intencao_voto
    from {{ ref('painel_votos') }}
    where qt_candidatos_cenario >= 7 and qt_fora_da_urna_cenario = 0
      and dt_fim_campo is not null
    group by 1, 2, 3, 4, 5
),
l as (
    select *,
           case when tp_resposta = 'Candidato' then 'C' else 'N' end as tp_linha,
           concat_ws(';', dt_fim_campo, nm_instituto, concat(nm_candidato, '|', sg_partido),
                     cast(pc_intencao_voto as string),
                     case when tp_resposta = 'Candidato' then 'C' else 'N' end) as linha
    from base
)
select *, row_number() over (order by linha) as nr_ordem
from l
