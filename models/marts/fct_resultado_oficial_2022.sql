-- Resultado oficial Presidente 2022 (substitui 'f2022_ResultadoOficial' do Power BI).
-- Grao: 1 linha por ts_totalizacao x nr_turno x nm_candidato.
--
-- Correcao importante: no Power BI a coluna 'Data Totalizacao' tinha data E hora e era
-- relacionada com dCalendario[Date] (meia-noite). So as linhas de 00:00:00 casavam.
-- Aqui separamos dt_totalizacao (date, para relacionar) de ts_totalizacao (timestamp).
-- fl_resultado_final marca a ultima totalizacao de cada turno (resultado oficial).

with base as (

    select * from {{ ref('stg_tse__totalizacao_presidente_2022') }}

),

de_para as (

    select * from {{ ref('de_para_candidato') }} where fonte = 'tse_2022'

)

select
    b.ts_totalizacao,
    b.dt_totalizacao,
    b.nr_turno,
    coalesce(d.nm_candidato_padronizado, b.nm_candidato_origem)    as nm_candidato,
    b.nm_candidato_origem,
    b.pc_votos_validos_acumulado,
    b.ts_totalizacao = max(b.ts_totalizacao) over (partition by b.nr_turno) as fl_resultado_final,
    b._ingerido_em
from base b
left join de_para d
    on lower(d.nm_candidato_origem) = lower(b.nm_candidato_origem)
