-- Uma linha por (instante de totalizacao, turno, candidato).
-- Substitui o Power Query de f2022_ResultadoOficial: o despivot das colunas
-- <CANDIDATO>_PE_VOTOS_TOT_ACUMULADO e montado dinamicamente a partir do schema da tabela raw,
-- entao candidatos novos (ou colunas renomeadas pelo TSE) nao quebram o modelo.

{%- set relacao = source('tse', 'totalizacao_presidente_2022') -%}
{%- set sufixo = '_PE_VOTOS_TOT_ACUMULADO' -%}
{%- set excluidas = ['BRANCO' ~ sufixo, 'NULO' ~ sufixo] -%}
{%- set colunas_pct = [] -%}

{%- if execute -%}
    {%- for col in adapter.get_columns_in_relation(relacao) -%}
        {%- set nome = col.name | trim -%}
        {%- if nome.upper().endswith(sufixo) and nome.upper() not in excluidas -%}
            {%- do colunas_pct.append(nome) -%}
        {%- endif -%}
    {%- endfor -%}
{%- endif %}

with fonte as (

    select * from {{ relacao }}

),

despivotado as (

    {%- if colunas_pct | length == 0 %}
    -- nenhuma coluna de percentual encontrada (parse sem conexao ou tabela vazia)
    select
        cast(null as string) as dt_totalizacao_texto,
        cast(null as string) as turno_texto,
        cast(null as string) as coluna_origem,
        cast(null as string) as pct_texto,
        cast(null as timestamp) as _ingerido_em
    where 1 = 0
    {%- else %}
    {%- for c in colunas_pct %}
    select
        DT_TOTALIZACAO       as dt_totalizacao_texto,
        TURNO                as turno_texto,
        '{{ c | upper }}'    as coluna_origem,
        `{{ c }}`            as pct_texto,
        _ingerido_em
    from fonte
    {% if not loop.last %}union all{% endif %}
    {%- endfor %}
    {%- endif %}

)

select
    {{ tse_timestamp('dt_totalizacao_texto') }}                         as ts_totalizacao,
    to_date({{ tse_timestamp('dt_totalizacao_texto') }})                as dt_totalizacao,
    try_cast(regexp_replace(turno_texto, '[^0-9]', '') as int)          as nr_turno,
    coluna_origem,
    -- "CIRO_GOMES_PE_VOTOS_TOT_ACUMULADO" -> "Ciro Gomes" (nome bruto; padronizacao via seed)
    initcap(replace(regexp_replace(coluna_origem, '{{ sufixo }}$', ''), '_', ' ')) as nm_candidato_origem,
    {{ br_decimal('pct_texto', 'decimal(9,4)') }}                       as pc_votos_validos_acumulado,
    _ingerido_em
from despivotado
where {{ br_decimal('pct_texto', 'decimal(9,4)') }} is not null
