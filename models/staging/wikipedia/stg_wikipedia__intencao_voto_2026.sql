-- Uma linha por celula (pesquisa x cenario x coluna) da Wikipedia, ja tipada.
-- Substitui os passos Power Query de f2026_IntencaoVoto (remocao de linhas-evento,
-- conversao de percentual/amostra) e corrige problemas que o PQ deixava passar:
--   * colunas-artefato ("Header", "Column", "Vantagem"/"Diferenca") entravam como dado;
--     "Header" era classificado como Candidato e "Vantagem" como Nao-resposta.
--   * espacos duplos no nome ("Flavio  PL" vs "Flavio PL").
--   * periodo sem ano e sem data real -> agora vira dt_inicio_campo / dt_fim_campo.
--   * margem de erro ficava como texto.

with fonte as (

    select * from {{ source('wikipedia', 'intencao_voto_2026') }}

),

limpo as (

    select
        cast(tabela_idx as int)                                         as tabela_idx,
        regexp_replace(trim(instituto_texto), ' +', ' ')                as nm_instituto_origem,
        regexp_replace(trim(periodo_texto), ' +', ' ')                  as periodo_texto,
        -- remove notas de rodape tipo [12]
        regexp_replace(regexp_replace(trim(coluna_candidato), '\\[[^\\]]*\\]', ''), ' +', ' ') as coluna_candidato,
        try_cast(regexp_replace(amostra_texto, '[^0-9]', '') as int)    as qt_amostra,
        {{ texto_para_decimal('margem_texto', 'decimal(5,2)') }}         as pc_margem_erro,
        {{ texto_para_decimal('valor_texto', 'decimal(9,2)') }}          as pc_valor,
        _ingerido_em
    from fonte
    where nullif(trim(instituto_texto), '') is not null
      and nullif(trim(periodo_texto), '') is not null
      -- linha-evento: celula mesclada replica o mesmo texto em todas as colunas
      and trim(instituto_texto) <> trim(periodo_texto)

),

classificado as (

    select
        *,
        case
            when lower(coluna_candidato) rlike '^(header|column)[ 0-9]*$'
              or lower(coluna_candidato) rlike 'vantagem|diferen|lead|margem|amostra'
                then 'Artefato'
            when lower(coluna_candidato) rlike 'indecis|absten|absent|outros|branco|nulo|nenhum|nao sabe|não sabe'
                then 'Não-resposta'
            else 'Candidato'
        end as tp_resposta,

        -- periodo: "27 Mar - 29 Mar", "27-29 mar", "27 de marco a 2 de abril"
        regexp_extract_all(periodo_texto, '([0-9]{1,2})', 1)            as dias,
        filter(
            regexp_extract_all(lower(periodo_texto), '([a-zç]{3,})', 1),
            m -> {{ mes_para_numero('m') }} is not null
        )                                                               as meses
    from limpo

),

com_datas as (

    select
        *,
        try_to_date(format_string('%04d-%02d-%02d',
            year(_ingerido_em),
            {{ mes_para_numero('try_element_at(meses, 1)') }},
            cast(try_element_at(dias, 1) as int))) as dt_inicio_bruta,
        try_to_date(format_string('%04d-%02d-%02d',
            year(_ingerido_em),
            {{ mes_para_numero('try_element_at(meses, -1)') }},
            cast(try_element_at(dias, -1) as int))) as dt_fim_bruta
    from classificado
    where size(dias) > 0 and size(meses) > 0

)

select
    tabela_idx,
    nm_instituto_origem,
    periodo_texto,
    -- a Wikipedia nao informa o ano: usa o ano da carga e recua 1 ano se a data cair no futuro
    case when dt_inicio_bruta > to_date(_ingerido_em) then add_months(dt_inicio_bruta, -12) else dt_inicio_bruta end as dt_inicio_campo,
    case when dt_fim_bruta    > to_date(_ingerido_em) then add_months(dt_fim_bruta, -12)    else dt_fim_bruta    end as dt_fim_campo,
    qt_amostra,
    pc_margem_erro,
    coluna_candidato,
    tp_resposta,
    pc_valor,
    _ingerido_em
from com_datas
where tp_resposta <> 'Artefato'
  and pc_valor is not null
  and pc_valor between 0 and 100
