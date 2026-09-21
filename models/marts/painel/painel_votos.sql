-- Base do painel: cada resposta de fct_intencao_voto com o nome do instituto limpo
-- (inst_ok) e o perfil do cenario (n = candidatos listados, n_fora = quantos nao tem
-- candidatura registrada no TSE). Mesma logica dos CTEs inst / f / c da consulta
-- antiga do site/gerar.py (tag git painel-consulta-legada).
--
-- Atencao: o Databricks interpreta escapes dentro de literal de string, entao cada
-- barra invertida de regex vai DOBRADA ('\\[' vira '\[' no motor). Com barra simples,
-- 'Quaest[17]' vira ']' e o painel perde o nome dos institutos (aconteceu em 21/09/2026).

with nomes as (
    select
        nm_instituto,
        trim(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(
            nm_instituto, '(?i)<?ref[ \\t]+name[ \\t]*=.*$', ''), '(?i)<ref[^>]*>.*$', ''),
            '<[^>]*>', ''), '\\[[^\\]]*\\]', ''), ' +', ' ')) as limpo,
        count(*) as qt
    from {{ ref('fct_intencao_voto') }}
    group by 1, 2
),

-- mesma empresa escrita de jeitos diferentes: chave = palavras em ordem alfabetica;
-- vence a grafia mais frequente
inst as (
    select
        nm_instituto,
        first_value(limpo) over (partition by chave order by qt desc, limpo) as nm_canon
    from (
        select nm_instituto, limpo, qt,
               array_join(array_sort(filter(split(lower(regexp_replace(limpo, '[^A-Za-z0-9À-ÿ]', ' ')), ' +'), x -> x <> '')), '|') as chave
        from nomes
    )
),

f as (
    select v.*, i.nm_canon as inst_ok
    from {{ ref('fct_intencao_voto') }} v
    join inst i using (nm_instituto)
),

-- n_fora: nomes do cenario sem candidatura registrada (seed candidatos_registrados).
-- O 1o turno so usa cenarios com n_fora = 0; os duelos passam todos e o painel filtra
-- na tela, com o botao de cenarios hipoteticos.
c as (
    select
        f.id_cenario,
        count(case when f.tp_resposta = 'Candidato' then 1 end) as n,
        count(case when f.tp_resposta = 'Candidato' and f.nm_candidato is not null
                        and r.nm_candidato is null then 1 end) as n_fora
    from f
    left join {{ ref('candidatos_registrados') }} r on r.nm_candidato = f.nm_candidato
    group by 1
)

select f.*, c.n as qt_candidatos_cenario, c.n_fora as qt_fora_da_urna_cenario
from f
join c using (id_cenario)
