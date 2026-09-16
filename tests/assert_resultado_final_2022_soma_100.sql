{{ config(severity='warn') }}

-- ATENCAO: confirme se PE_VOTOS_TOT_ACUMULADO e % sobre votos validos ou sobre o total (com brancos/nulos).
-- No resultado final de cada turno, os percentuais de votos validos devem somar 100% (+-0,5 p.p.).

select
    nr_turno,
    sum(pc_votos_validos_acumulado) as pc_soma
from {{ ref('fct_resultado_oficial_2022') }}
where fl_resultado_final
group by nr_turno
having abs(sum(pc_votos_validos_acumulado) - 100) > 0.5
