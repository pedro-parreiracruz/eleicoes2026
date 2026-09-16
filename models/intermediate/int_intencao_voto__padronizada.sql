-- Padroniza instituto e candidato (DE-PARA), separa nome x partido e cria chaves estaveis.
-- Problema resolvido: no Power BI o 'Cenario' era "Cenario N" pela posicao da tabela na
-- pagina — qualquer edicao na Wikipedia renumerava tudo. Aqui:
--   id_pesquisa = instituto padronizado + datas de campo + amostra
--   id_cenario  = id_pesquisa + lista ordenada de candidatos da tabela

with base as (

    select * from {{ ref('stg_wikipedia__intencao_voto_2026') }}

),

de_para_instituto as (

    select * from {{ ref('de_para_instituto') }}

),

de_para_candidato as (

    select * from {{ ref('de_para_candidato') }} where fonte = 'wikipedia'

),

separado as (

    select
        b.*,
        coalesce(di.nm_instituto_padronizado, b.nm_instituto_origem)        as nm_instituto,
        case
            when b.tp_resposta <> 'Candidato' then null
            when b.coluna_candidato rlike '(?i) sem partido$'
                then regexp_replace(b.coluna_candidato, '(?i) sem partido$', '')
            when b.coluna_candidato like '% %'
                then regexp_replace(b.coluna_candidato, ' [^ ]+$', '')
            else b.coluna_candidato
        end                                                                 as nm_candidato_origem,
        case
            when b.tp_resposta <> 'Candidato' then null
            when b.coluna_candidato rlike '(?i) sem partido$' then 'Sem partido'
            when b.coluna_candidato like '% %'
                then regexp_extract(b.coluna_candidato, ' ([^ ]+)$', 1)
        end                                                                 as sg_partido
    from base b
    left join de_para_instituto di
        on di.nm_instituto_origem = b.nm_instituto_origem

),

padronizado as (

    select
        s.*,
        case
            when s.tp_resposta = 'Candidato'
                then coalesce(dc.nm_candidato_padronizado, s.nm_candidato_origem)
            else s.coluna_candidato
        end                                                                 as nm_candidato,
        coalesce(dc.revisar, s.tp_resposta = 'Candidato')                   as fl_candidato_revisar,
        sha2(concat_ws('|', s.nm_instituto, cast(s.dt_inicio_campo as string), cast(s.dt_fim_campo as string), cast(coalesce(s.qt_amostra, 0) as string)), 256) as id_pesquisa
    from separado s
    left join de_para_candidato dc
        on  dc.nm_candidato_origem = s.nm_candidato_origem
        and dc.sg_partido_origem   = s.sg_partido

),

com_cenario as (

    select
        *,
        sha2(concat_ws('|',
            id_pesquisa,
            array_join(array_sort(collect_set(nm_candidato) over (partition by tabela_idx, id_pesquisa)), ',')
        ), 256)                                                             as id_cenario
    from padronizado

)

select * from com_cenario
-- a mesma pesquisa/cenario pode aparecer em mais de uma tabela (ex. secao "ultimas" + secao mensal)
qualify row_number() over (
    partition by id_cenario, nm_candidato
    order by tabela_idx
) = 1
