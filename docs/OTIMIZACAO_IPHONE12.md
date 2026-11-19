# Otimização para iPhone 12 — plano e orçamento

**Nada aqui foi medido.** Este documento é o plano de medição e o orçamento com
o qual o jogo vai ser julgado. Nenhum número abaixo é resultado de teste.

## Orçamento por frame (30 FPS = 33,3 ms)

| Recurso | Meta | Como medir |
|---|---|---|
| Frame total | p50 ≤ 26 ms, p95 ≤ 33 ms | CSV do `perf_log.gd` |
| CPU (lógica + cena) | ≤ 10 ms | `TIME_PROCESS` no HUD |
| GPU (desenho) | ≤ 22 ms | frame time menos CPU |
| Draw calls | ≤ 250 | `RENDER_TOTAL_DRAW_CALLS_IN_FRAME` |
| Triângulos visíveis | ≤ 300 mil | `RENDER_TOTAL_TRIANGLES` |
| Nós | ≤ 6.000 | `OBJECT_NODE_COUNT` |
| RAM estática | ≤ 1,2 GB | `MEMORY_STATIC` |
| Geração de setor (thread) | ≤ 120 ms | `stats()["gen_ms"]` |
| Pico de frame ao instalar setor | ≤ 8 ms | CSV (coluna `ms` com posição) |

## O que já está no código por causa desse orçamento

- 1 malha e 1 draw call por setor, cor por vértice (0 texturas, 0 materiais
  extras), mais 1 MultiMesh por setor para props.
- LOD por anel: o anel externo descarta telhado, toldo, árvore e props.
- Streaming limitado a 3 x 3 setores detalhados + 5 x 5 ao todo (2 setores por
  frame).
- Sem corpos físicos estáticos: colisão por consulta de altura + retângulos.
- Sem MSAA, sem SSAO, sem reflexo, sem volumétrico; nevoa no lugar de horizonte
  distante; plano do mar acompanha o jogador.
- Sombra direcional com 2 splits a 110 m, desligada à noite e com tempo nublado.
- Texturas: nenhuma nesta fase (as futuras entram em ASTC/ETC2).

## Protocolo de medição (a fazer no aparelho)

1. Exportar o build de *release* (o debug custa caro no GDScript).
2. No iPhone 12, iniciar na praia, esperar 10 s parado.
3. Rodar 3 rotas de 5 min: (a) parado olhando o mar, (b) correndo pela orla,
   (c) atravessando quadras até o limite do streaming.
4. Salvar o CSV (`user://perf/`) para o app Arquivos e anexar a
   `docs/MEDICOES/AAAA-MM-DD_iphone12.md` com p50, p95, p99 e o pior frame.
5. Repetir após 15 min contínuos (teste térmico): o iPhone reduz clock.
6. Só então decidir: manter, subir qualidade ou cortar.

## Escada de qualidade adaptativa (Fase 8)

Se o p95 passar de 33 ms por 3 s:

1. reduzir a escala de renderização (0,85 → 0,7 → 0,6);
2. cortar o anel externo (far_ring 2 → 1);
3. reduzir a sombra a 1 split e 60 m;
4. desligar sombra em trânsito.

## Ideias de ganho (não medidas, ordem de suspeita)

- Tirar a geração da thread GDScript: gerar tiles em Python/CI e carregar
  arquivos pronto. É a mudança com maior chance de resolver engasgos.
- Substituir o streamer GDScript por `MultiMesh` por tipo de prédio (poucos
  materiais, muitas instâncias).
- Congelar o ciclo dia/noite em horário fixo durante missões.
- Reduzir a resolução do céu procedural (hoje é grátis em Compatibility, mas
  confirmar).
