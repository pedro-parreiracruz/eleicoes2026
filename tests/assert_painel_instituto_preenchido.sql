-- O painel nao pode ter linha de 1o turno sem nome de instituto: todas as medias
-- cairiam num "instituto" vazio. Foi o que um regex mal escapado causou em 21/09/2026.
{{ config(severity='warn') }}
select 'painel_1t_pesquisas' as bloco, linha from {{ ref('painel_1t_pesquisas') }}
where trim(coalesce(nm_instituto, '')) = '' or nm_instituto rlike '<|\\[|ref name='
union all
select 'painel_1t_valores', linha from {{ ref('painel_1t_valores') }}
where trim(coalesce(nm_instituto, '')) = '' or nm_instituto rlike '<|\\[|ref name='
