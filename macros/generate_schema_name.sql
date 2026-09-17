{#
  Produção: usa o schema configurado (staging, marts...) sem prefixo.
  Desenvolvimento: prefixa com o schema do usuário (ex.: dbt_pcruz_marts).

  É produção quando o target se chama 'prod' (dbt Core) OU quando o dbt Platform
  informa que o ambiente é de produção (DBT_CLOUD_ENVIRONMENT_TYPE = 'prod'),
  assim não depende do "Target name" configurado no ambiente.
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- set eh_prod = target.name == 'prod' or env_var('DBT_CLOUD_ENVIRONMENT_TYPE', '') | lower == 'prod' -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- elif eh_prod -%}
        {{ custom_schema_name | trim }}
    {%- else -%}
        {{ target.schema }}_{{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
