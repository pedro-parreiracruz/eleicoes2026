-- Fato de pesquisas registradas no PesqEle (substitui a tabela '2026_Pesquisas' do Power BI).
-- Grao: 1 linha por nr_protocolo_registro.
-- Todas as UEs sao mantidas; para reproduzir o painel atual filtre fl_abrangencia_nacional = true.

select
    nr_protocolo_registro,
    ano_eleicao,
    nm_eleicao,
    ds_cargo,
    sg_uf,
    sg_ue,
    nm_ue,
    fl_abrangencia_nacional,

    nr_cnpj_empresa,
    nm_instituto,
    nm_empresa,
    tp_contratacao,
    tp_metodo_coleta,
    nm_estatistico_resp,
    cd_conre,

    dt_registro,
    dt_inicio_campo,
    dt_fim_campo,
    dt_divulgacao,
    nr_dias_campo,
    nr_dias_campo_divulgacao,
    nr_dias_registro_divulgacao,

    qt_entrevistados,
    vr_pesquisa,
    vr_custo_por_entrevista,
    pc_margem_erro_teorica,

    fl_dq_amostra_invalida,
    fl_dq_valor_ausente,
    fl_dq_campo_invertido,
    fl_dq_divulgacao_antes_fim_campo,
    fl_dq_registro_fora_prazo_legal,
    fl_dq_sem_nome_fantasia,
    (
        fl_dq_amostra_invalida or fl_dq_valor_ausente or fl_dq_campo_invertido
        or fl_dq_divulgacao_antes_fim_campo or fl_dq_registro_fora_prazo_legal
    )                                               as fl_dq_possui_alerta,

    ds_metodologia_pesquisa,
    ds_plano_amostral,
    ts_geracao_arquivo_tse,
    _ingerido_em
from {{ ref('int_pesquisas__classificadas') }}
