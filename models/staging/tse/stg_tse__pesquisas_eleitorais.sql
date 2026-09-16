-- Uma linha por pesquisa registrada no PesqEle.
-- Substitui no Power BI: colunas 'Data Inicio Campo', 'Data Fim Campo', 'Data Divulgacao',
-- 'Data Registro', 'Qtd Entrevistados' e 'Valor Pesquisa' (todas eram DAX sobre texto).

with fonte as (

    select * from {{ source('tse', 'pesquisa_eleitoral_2026') }}

),

tipado as (

    select
        -- chave
        {{ tse_texto('NR_PROTOCOLO_REGISTRO') }}                    as nr_protocolo_registro,

        -- eleicao / abrangencia
        try_cast({{ tse_texto('AA_ELEICAO') }} as int)              as ano_eleicao,
        {{ tse_texto('CD_ELEICAO') }}                               as cd_eleicao,
        {{ tse_texto('NM_ELEICAO') }}                               as nm_eleicao,
        upper({{ tse_texto('SG_UF') }})                             as sg_uf,
        {{ tse_texto('SG_UE') }}                                    as sg_ue,
        upper({{ tse_texto('NM_UE') }})                             as nm_ue,
        {{ tse_texto('DS_CARGO') }}                                 as ds_cargo,

        -- empresa / responsavel
        regexp_replace({{ tse_texto('NR_CNPJ_EMPRESA') }}, '[^0-9]', '') as nr_cnpj_empresa,
        upper({{ tse_texto('NM_EMPRESA') }})                        as nm_empresa,
        {{ tse_texto('NM_EMPRESA_FANTASIA') }}                      as nm_empresa_fantasia,
        {{ tse_texto('CD_CONRE') }}                                 as cd_conre,
        {{ tse_texto('NM_ESTATISTICO_RESP') }}                      as nm_estatistico_resp,
        upper({{ tse_texto('ST_PESQUISA_PROPRIA') }})               as st_pesquisa_propria,

        -- datas (texto "yyyy-MM-dd HH:mm:ss" no CSV)
        {{ tse_timestamp('DT_REGISTRO') }}                          as ts_registro,
        to_date({{ tse_timestamp('DT_REGISTRO') }})                 as dt_registro,
        to_date({{ tse_timestamp('DT_INICIO_PESQUISA') }})          as dt_inicio_campo,
        to_date({{ tse_timestamp('DT_FIM_PESQUISA') }})             as dt_fim_campo,
        to_date({{ tse_timestamp('DT_DIVULGACAO') }})               as dt_divulgacao,

        -- metricas (texto pt-BR no CSV: "96380,00")
        case
            when {{ br_decimal('QT_ENTREVISTADO', 'int') }} > 0
            then {{ br_decimal('QT_ENTREVISTADO', 'int') }}
        end                                                         as qt_entrevistados,
        {{ br_decimal('VR_PESQUISA', 'decimal(18,2)') }}            as vr_pesquisa,

        -- textos descritivos
        {{ tse_texto('DS_METODOLOGIA_PESQUISA') }}                  as ds_metodologia_pesquisa,
        {{ tse_texto('DS_PLANO_AMOSTRAL') }}                        as ds_plano_amostral,
        {{ tse_texto('DS_SISTEMA_CONTROLE') }}                      as ds_sistema_controle,
        {{ tse_texto('DS_DADO_MUNICIPIO') }}                        as ds_dado_municipio,

        -- metadados do arquivo TSE e da carga
        {{ tse_timestamp("concat(DT_GERACAO, ' ', HH_GERACAO)") }}  as ts_geracao_arquivo_tse,
        _ingerido_em,
        _arquivo_origem

    from fonte

)

select * from tipado
-- o CSV do TSE pode repetir o protocolo entre arquivos por UF; fica a linha mais recente
qualify row_number() over (
    partition by nr_protocolo_registro
    order by ts_geracao_arquivo_tse desc nulls last, _ingerido_em desc
) = 1
