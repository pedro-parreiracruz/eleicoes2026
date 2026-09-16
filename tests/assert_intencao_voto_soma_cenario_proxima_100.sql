{{ config(severity='warn') }}

-- Em cada cenario, candidatos + nao-resposta deveriam somar ~100%.
-- Somas muito fora indicam coluna faltando/sobrando na extracao da Wikipedia
-- (ex. "Vantagem" entrando como voto, ou tabela com cabecalho de 2 linhas).

select
    id_cenario,
    nm_instituto,
    dt_fim_campo,
    sum(pc_intencao_voto) as pc_soma
from {{ ref('fct_intencao_voto') }}
group by all
having sum(pc_intencao_voto) not between 90 and 110
