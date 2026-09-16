-- Regras de negocio e flags de qualidade sobre as pesquisas registradas.
-- Substitui no Power BI: 'Instituto', 'Tipo Contratacao', 'Metodo de Coleta',
-- 'Custo por Entrevista' (DAX) e passa a expor as regras usadas nas medidas de transparencia.

with pesquisas as (

    select * from {{ ref('stg_tse__pesquisas_eleitorais') }}

)

select
    p.*,

    -- Instituto: nome fantasia; se ausente, razao social
    coalesce(p.nm_empresa_fantasia, initcap(p.nm_empresa))                  as nm_instituto,

    case p.st_pesquisa_propria
        when 'S' then 'Própria'
        when 'N' then 'Contratada'
    end                                                                     as tp_contratacao,

    -- Mesma ordem de precedencia do SWITCH(TRUE()) do Power BI
    case
        when lower(p.ds_metodologia_pesquisa) rlike 'ura|automatizad|resposta aud'
            then 'Telefônica automatizada (URA)'
        when lower(p.ds_metodologia_pesquisa) rlike 'cati|telef'
            then 'Telefônica com entrevistador'
        when lower(p.ds_metodologia_pesquisa) rlike ' web|questionário estruturado web|painel|online|internet'
            then 'Web / painel online'
        when lower(p.ds_metodologia_pesquisa) rlike 'pessoa|domicili|face a face|presencia'
            then 'Presencial'
        else 'Não classificada'
    end                                                                     as tp_metodo_coleta,

    try_divide(p.vr_pesquisa, p.qt_entrevistados)                           as vr_custo_por_entrevista,

    -- margem de erro teorica (p = 0,5; 95%): 0,98 / sqrt(n)
    case when p.qt_entrevistados > 0 then 0.98 / sqrt(p.qt_entrevistados) end as pc_margem_erro_teorica,

    datediff(p.dt_divulgacao, p.dt_fim_campo)                               as nr_dias_campo_divulgacao,
    datediff(p.dt_divulgacao, p.dt_registro)                                as nr_dias_registro_divulgacao,
    datediff(p.dt_fim_campo, p.dt_inicio_campo) + 1                         as nr_dias_campo,

    -- flags de abrangencia
    (p.nm_ue = 'BRASIL')                                                    as fl_abrangencia_nacional,

    -- flags de qualidade (nao removem linhas: ficam visiveis no Power BI e nos testes)
    (p.qt_entrevistados is null)                                            as fl_dq_amostra_invalida,
    (p.vr_pesquisa is null or p.vr_pesquisa = 0)                            as fl_dq_valor_ausente,
    (p.dt_inicio_campo > p.dt_fim_campo)                                    as fl_dq_campo_invertido,
    (p.dt_divulgacao < p.dt_fim_campo)                                      as fl_dq_divulgacao_antes_fim_campo,
    (datediff(p.dt_divulgacao, p.dt_registro) < {{ var('prazo_minimo_registro_dias') }}) as fl_dq_registro_fora_prazo_legal,
    (p.nm_empresa_fantasia is null)                                         as fl_dq_sem_nome_fantasia

from pesquisas p
