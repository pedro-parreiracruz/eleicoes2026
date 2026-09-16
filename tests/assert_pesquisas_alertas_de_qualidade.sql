{{ config(severity='warn') }}

-- Lista pesquisas com qualquer alerta de qualidade (nao bloqueia o build).
-- Com store_failures, o resultado fica em <schema>_dq_falhas para auditoria.

select
    nr_protocolo_registro,
    nm_instituto,
    dt_registro,
    dt_inicio_campo,
    dt_fim_campo,
    dt_divulgacao,
    qt_entrevistados,
    vr_pesquisa,
    fl_dq_amostra_invalida,
    fl_dq_valor_ausente,
    fl_dq_campo_invertido,
    fl_dq_divulgacao_antes_fim_campo,
    fl_dq_registro_fora_prazo_legal
from {{ ref('fct_pesquisas_registradas') }}
where fl_dq_possui_alerta
