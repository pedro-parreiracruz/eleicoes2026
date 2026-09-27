-- Casa cada pesquisa da Wikipedia com o registro dela no TSE (PesqEle 2026; Lei 9.504/97,
-- art. 33: pesquisa eleitoral so pode ser divulgada se registrada). A Wikipedia nao traz o
-- numero de registro, entao o casamento e por:
--   instituto  seed instituto_registro_tse (palavra-chave no nome da empresa registrada);
--   periodo    ate 3 dias de diferenca no inicio e no fim do campo;
--   amostra    o TSE guarda a amostra PLANEJADA e a Wikipedia a realizada, entao amostra
--              diferente so pesa na escolha (distancia + 4), nao elimina.
-- Sem inicio batendo, ainda casa se o fim (1 dia) e a amostra (1%) baterem: e o caso de
-- inicio digitado errado na Wikipedia. Fica o registro de menor distancia.
-- Pesquisa sem registro localizado NAO entra no painel: painel_votos faz inner join aqui.
with pesquisas as (
    select id_pesquisa, inst_ok,
           min(dt_inicio_campo) as dt_inicio_campo,
           min(dt_fim_campo) as dt_fim_campo,
           max(qt_amostra) as qt_amostra
    from {{ ref('painel_votos_todos') }}
    where dt_fim_campo is not null
    group by 1, 2
),

chaves as (
    select p.*,
           coalesce(s.chave_tse,
                    regexp_replace(lower(translate(p.inst_ok, 'ÁÀÂÃÉÊÍÓÔÕÚÇáàâãéêíóôõúç',
                                                   'AAAAEEIOOOUCaaaaeeiooouc')), '[^a-z0-9]', '')) as chave_tse
    from pesquisas p
    left join {{ ref('instituto_registro_tse') }} s on s.inst_ok = p.inst_ok
),

registros as (
    select r.*,
           regexp_replace(lower(translate(concat_ws(' ', r.nm_empresa, r.nm_instituto),
                          'ÁÀÂÃÉÊÍÓÔÕÚÇáàâãéêíóôõúç', 'AAAAEEIOOOUCaaaaeeiooouc')), '[^a-z0-9]', '') as nome_busca,
           lower(concat_ws(' ', r.ds_plano_amostral, r.ds_metodologia_pesquisa)) as texto_plano
    from {{ ref('fct_pesquisas_registradas') }} r
    where r.sg_uf = 'BR' and r.ds_cargo like '%Presidente%'
      -- registro nacional que e espelho de pesquisa estadual (mesma empresa, datas e
      -- amostra registradas tambem numa UF) nao e a pesquisa nacional
      and not exists (
          select 1 from {{ ref('fct_pesquisas_registradas') }} e
          where e.sg_uf <> 'BR' and e.nr_cnpj_empresa = r.nr_cnpj_empresa
            and e.dt_inicio_campo = r.dt_inicio_campo and e.dt_fim_campo = r.dt_fim_campo
            and e.qt_entrevistados = r.qt_entrevistados
      )
),

candidatos as (
    select c.id_pesquisa, r.nr_protocolo_registro, r.nm_empresa, r.tp_contratacao,
           r.dt_registro, r.qt_entrevistados, r.texto_plano,
           abs(datediff(c.dt_inicio_campo, r.dt_inicio_campo)) + abs(datediff(c.dt_fim_campo, r.dt_fim_campo))
             + case when abs(c.qt_amostra - r.qt_entrevistados) <= greatest(50, 0.05 * r.qt_entrevistados)
                    then 0 else 4 end as nr_distancia
    from chaves c
    join registros r
      on r.nome_busca rlike c.chave_tse
     and (
          (abs(datediff(c.dt_fim_campo, r.dt_fim_campo)) <= 3
           and abs(datediff(coalesce(c.dt_inicio_campo, c.dt_fim_campo), r.dt_inicio_campo)) <= 3)
          or (abs(datediff(c.dt_fim_campo, r.dt_fim_campo)) <= 1
              and abs(c.qt_amostra - r.qt_entrevistados) <= greatest(20, 0.01 * r.qt_entrevistados))
     )
),

melhor as (
    select *, row_number() over (partition by id_pesquisa order by nr_distancia, nr_protocolo_registro) as rk
    from candidatos
)

select
    id_pesquisa,
    nr_protocolo_registro,
    nm_empresa as nm_empresa_registro,
    tp_contratacao,
    dt_registro,
    qt_entrevistados as qt_entrevistados_registro,
    nr_distancia,
    -- nivel de confianca declarado no plano amostral ("... nivel de confianca de 95%")
    cast(coalesce(
        nullif(regexp_extract(texto_plano, 'confian[cç]a[^0-9]{0,40}([0-9]{2})([,.][0-9]+)? ?%', 1), ''),
        nullif(regexp_extract(texto_plano, '([0-9]{2})([,.][0-9]+)? ?%[^.]{0,40}confian', 1), '')
    ) as int) as pc_nivel_confianca
from melhor
where rk = 1
