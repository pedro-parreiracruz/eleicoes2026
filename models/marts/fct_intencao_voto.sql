-- Fato de intencao de voto 2026 (substitui 'f2026_IntencaoVoto' do Power BI).
-- Grao: 1 linha por id_cenario x nm_candidato.

select
    id_pesquisa,
    id_cenario,
    nm_instituto,
    nm_instituto_origem,
    dt_inicio_campo,
    dt_fim_campo,
    periodo_texto,
    qt_amostra,
    pc_margem_erro,
    tp_resposta,
    nm_candidato,
    nm_candidato_origem,
    sg_partido,
    fl_candidato_revisar,
    pc_valor                      as pc_intencao_voto,
    _ingerido_em
from {{ ref('int_intencao_voto__padronizada') }}
