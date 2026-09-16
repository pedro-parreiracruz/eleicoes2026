-- Dimensao de institutos de pesquisa registrados no TSE. Chave: CNPJ.
-- No Power BI o instituto era um texto (nome fantasia ou razao social), o que
-- quebrava a contagem quando a mesma empresa registrava com grafias diferentes.

with pesquisas as (

    select * from {{ ref('int_pesquisas__classificadas') }}
    where nr_cnpj_empresa is not null

)

select
    nr_cnpj_empresa,
    -- nome mais usado nos registros da empresa
    max_by(nm_instituto, qtd)          as nm_instituto,
    max_by(nm_empresa, qtd)            as nm_empresa,
    sum(qtd)                           as qt_pesquisas_registradas,
    min(dt_registro_min)               as dt_primeiro_registro,
    max(dt_registro_max)               as dt_ultimo_registro
from (
    select
        nr_cnpj_empresa, nm_instituto, nm_empresa,
        count(*) as qtd, min(dt_registro) as dt_registro_min, max(dt_registro) as dt_registro_max
    from pesquisas
    group by all
)
group by nr_cnpj_empresa
