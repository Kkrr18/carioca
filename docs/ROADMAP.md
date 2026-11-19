# Roadmap — 9 fases

Cada fase só fecha quando tiver: código, instruções de execução, teste e
documentação. "Não medido" não é "concluído".

## Fase 1 — Fundação (em andamento)

**Entrega:** projeto Godot que abre, gera cidade e deixa um personagem andar na
orla; poligonodo mundo; medidor de área; testes headless; CI.
**Critério de saída:** testes verdes no CI, jogo abre no desktop sem erro, área
do polígono medida e registrada em `docs/STATUS.md`.

## Fase 2 — Primeiro cenário (Copacabana real)

**Entrega:** trecho de Copacabana/Ipanema com geometria vinda do OpenStreetMap
(ruas, quadras, áreas verdes) e relevo do DEM; shader de água simples; ponte com
eixo real (ainda sem tráfego).
**Critério de saída:** caminhar da praia até a Lagoa sem buraco de streaming;
área e distâncias conferidas contra o mapa.
**Custo do pipeline:** Overpass tem limite de requisições; usar cache local.

## Fase 3 — Personagem

**Entrega:** modelo e animações (parado, andar, correr, pular) feitos no Blender,
exportados em glTF; troca de roupa simples; colisão contra relevo real.
**Critério de saída:** 4 animações em 60 fps de animação, sem "patinar" o pé.

## Fase 4 — Veículos

**Entrega:** carro dirigível, carro de passeio e moto; entrada/saída; câmera de
veículo; trânsito com faixas e semáforos simplificados.
**Critério de saída:** 20 veículos em um cruzamento sem colisão em cadeia.

## Fase 5 — Vida urbana

**Entrega:** NPCs em calçadas, feira, vendedor, cães; áudio brasileiro original
(praia, trânsito, rádio); multidão com LOD.
**Critério de saída:** 60 NPCs animados sem tirar o FPS da meta.

## Fase 6 — Mundo aberto

**Entrega:** polígono completo, streaming por setores vindo de dados em disco,
ponte de 13,3 km atravessável, teleférico/pontos de interesse.
**Critério de saída:** travessia completa da ponte sem travamento; mapa de
navegação.

## Fase 7 — Gameplay

**Entrega:** sistema de crime e polícia, missões com escolhas, economia, save
com estado do mundo (schema 2).
**Critério de saída:** uma missão completa com pelo menos duas escolhas e
consequências salvas.

## Fase 8 — Polimento

**Entrega:** otimização medida no iPhone 12, LODs, oclusão, áudio final, ajuste
de controles, acessibilidade.
**Critério de saída:** 30 FPS estáveis com p95 dentro do orçamento por 15 min
(ver `docs/OTIMIZACAO_IPHONE12.md`).

## Fase 9 — Aplicativo

**Entrega:** export iOS assinado, ícone e tela de lançamento, build de teste.
**Critério de saída:** `.ipa` abre no iPhone 12 real, instala, joga.

---

## Fora de escopo (decidido)

- Conteúdo de outros jogos: nenhum modelo, som, texto ou mapa de terceiros.
- Multiplayer.
- Android (depois do iOS, se fizer sentido).
