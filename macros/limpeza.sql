{#
  Macros de limpeza reutilizadas pelos modelos de staging.
  Substituem as colunas calculadas DAX e os passos Power Query do arquivo
  "pesquisas eleitorais.pbix".
#}

{# Texto TSE: trim + sentinelas de nulo do TSE (#NULO#, #NE#, vazio) viram NULL #}
{% macro tse_texto(col) -%}
    case
        when trim({{ col }}) in ('', '#NULO#', '#NULO', '#NE#', '#NE') then null
        else regexp_replace(trim({{ col }}), ' +', ' ')
    end
{%- endmacro %}

{# Numero no formato brasileiro ("96.380,00") -> decimal. Codigos TSE negativos (-1, -3) viram NULL #}
{% macro br_decimal(col, tipo='decimal(18,2)') -%}
    case
        when try_cast(replace(replace({{ tse_texto(col) }}, '.', ''), ',', '.') as {{ tipo }}) < 0 then null
        else try_cast(replace(replace({{ tse_texto(col) }}, '.', ''), ',', '.') as {{ tipo }})
    end
{%- endmacro %}

{# Data/hora TSE: aceita "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd", "dd/MM/yyyy HH:mm:ss" e "dd/MM/yyyy" #}
{% macro tse_timestamp(col) -%}
    coalesce(
        try_to_timestamp({{ tse_texto(col) }}, 'yyyy-MM-dd HH:mm:ss'),
        try_to_timestamp({{ tse_texto(col) }}, 'yyyy-MM-dd'),
        try_to_timestamp({{ tse_texto(col) }}, 'dd/MM/yyyy HH:mm:ss'),
        try_to_timestamp({{ tse_texto(col) }}, 'dd/MM/yyyy')
    )
{%- endmacro %}

{# Texto livre com numero ("45,2%", "± 2,0 p.p.") -> decimal #}
{% macro texto_para_decimal(col, tipo='decimal(9,2)') -%}
    try_cast(
        nullif(regexp_replace(replace(cast({{ col }} as string), ',', '.'), '[^0-9.]', ''), '')
        as {{ tipo }}
    )
{%- endmacro %}

{# Abreviacao de mes (pt ou en, 3 primeiras letras) -> numero do mes #}
{% macro mes_para_numero(expr) -%}
    case lower(substr({{ expr }}, 1, 3))
        when 'jan' then 1
        when 'fev' then 2  when 'feb' then 2
        when 'mar' then 3
        when 'abr' then 4  when 'apr' then 4
        when 'mai' then 5  when 'may' then 5
        when 'jun' then 6
        when 'jul' then 7
        when 'ago' then 8  when 'aug' then 8
        when 'set' then 9  when 'sep' then 9
        when 'out' then 10 when 'oct' then 10
        when 'nov' then 11
        when 'dez' then 12 when 'dec' then 12
    end
{%- endmacro %}
