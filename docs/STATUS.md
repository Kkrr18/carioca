# CARIOCA - estado do projeto

Versao: 0.1.0-dev. Fase atual: 1 (Fundacao), em andamento.

Regra de uso: um item so vai para "Testados" quando um teste automatico ou uma
medicao no aparelho confirma. "Concluido" significa escrito, sem validacao.
Nada aqui foi executado no Godot ainda: o motor nao roda neste dispositivo, e o
primeiro teste real acontece no GitHub Actions (.github/workflows/tests.yml).

## Sistemas

| Sistema | Estado | Arquivo |
|---|---|---|
| Configuracao do projeto, entrada, exportacao iOS | Escrito | project.godot, export_presets.cfg |
| Constantes e altura analitica do mundo | Escrito | scripts/core/cfg.gd |
| Geo (area, ponto em poligono, distancia) | Escrito | scripts/core/geo.gd |
| Poligono do mundo (rascunho) | Escrito, area nao medida | data/geo/world_polygon.json |
| Medidor de area (Python) | Escrito | tools/geo/polygon_area.py |
| Geracao de setor (predios, ruas, orla, props) | Escrito | scripts/world/city_gen.gd |
| Streaming por setores (threads) | Escrito | scripts/world/sector_streamer.gd |
| Props (MultiMesh) | Escrito | scripts/world/prop_factory.gd |
| Personagem em terceira pessoa + colisao simples | Escrito | scripts/player/player.gd |
| Controles por toque | Escrito | scripts/ui/touch_controls.gd |
| HUD e telemetria | Escrito | scripts/ui/hud.gd, scripts/core/perf_log.gd |
| Ciclo dia/noite e clima (2 estados de tempo) | Escrito | scripts/world/day_night.gd |
| Salvamento versionado (schema 1, sha256, gzip) | Escrito | scripts/autoload/save_manager.gd |
| Testes headless | Escrito | tests/runner.gd |
| Cena principal | Escrito | scenes/main.tscn, scripts/main.gd |
| Build Web (GitHub Pages) e preset de exportacao Web | Escrito, nunca executado | .github/workflows/web.yml, export_presets.cfg |
| Atribuicao de dados | Escrito | data/ATTRIBUTION.md |

## Planejados (ainda nao escritos)

- Pipeline de dados reais: OSM (Overpass), DEM Copernicus GLO-30, recorte e
  geracao de tiles. Fase 2.
- Ponte Rio-Niteroi transitavel com geometria real. Fase 2/6.
- Personagem com modelo e animacao feitos no Blender. Fase 3.
- Veiculos e trafego com IA. Fase 4.
- NPCs, vida urbana, audio brasileiro original. Fase 5.
- Mundo completo de ~83 km2 com streaming. Fase 6.
- Crime, policia, missoes, narrativa, economia. Fase 7.
- Polimento visual, otimizacao no iPhone 12. Fase 8.
- Build iOS real e distribuicao. Fase 9.

## Em desenvolvimento

- Fase 1: validar que o projeto abre no Godot 4.4 sem erros de compilacao.

## Testados

- Nada ainda. O primeiro resultado vem do CI (tests.yml) apos o primeiro push.

## Bugs conhecidos

- B-01: Nao compilado. Pode haver erros de sintaxe ou de tipo do GDScript que
  so o Godot revela. Prioridade maxima.
- B-02: A area do poligono nao foi medida. O valor do arquivo nao e confiavel.
- B-03: O poligono e um anel unico montado pela concatenacao de 3 grupos
  (rio-oeste, corredor da ponte, Niteroi). A ligacao entre eles nao foi
  validada; pode gerar auto-intersecao (o runner testa isso).
- B-04: A ponte e um eixo, nao uma malha. O personagem ainda nao sobe nela.
- B-05: O relevo e analitico (funcao seno/cosseno), nao o real. Nao ha morros
  do Rio de verdade.
- B-06: Colisao so de predios, em retangulos. Sem colisao de veiculo ou de
  poste.
- B-07: Sem audio.
- B-08: O save guarda posicao e relogio; nao guarda estado do mundo.
- B-09: Sem verificacao de desempenho em aparelho. A meta de 30 FPS no iPhone 12
  e uma hipotese ate medirmos (docs/OTIMIZACAO_IPHONE12.md).
- B-10: O build Web (.github/workflows/web.yml) nunca rodou. Pode falhar na
  instalacao do Godot, na exportacao ou na publicacao.
- B-11: O projeto nao tem remote Git configurado. Ate fazer push, nem o CI de
  testes nem o build Web rodam.
- B-12: No build Web o export padrao nao tem threads: a geracao de setor passa
  para a thread principal, com raio menor. Previsto no codigo, nao medido.
- B-13: `index.html` na raiz e uma pagina de apresentacao, NAO o jogo. O jogo
  publicado so existe depois que o workflow `web.yml` gera `build/web/`. Se um
  dia o build web for commitado na raiz, esse arquivo e substituido.

- B-14: O poligono de data/geo/world_polygon.json foi escrito a mao e NAO e
  valido. O CI (run 44447685635) mostrou: arestas 0 e 27 se cruzam (nao e
  simples), area 97,9 km2 (faixa 75-95), e os pontos de Botafogo e Caju caem
  fora. O rascunho deve ser refeito a partir do recorte OSM, nao ajustado no
  olho.
- B-15: O teste do grau de latitude usava 1105,4 m (aproximacao elipsoidal),
  mas o jogo e o haversine usam a esfera (111,19 km/grau). Corrigido o teste
  para 1111,9 m. A projecao do jogo (110540 m/grau) continua sendo a local.
- B-16: O CI de testes ainda acusa falhas (ver B-14). Nao e sinal de que o
  codigo do jogo esteja errado: e o poligono.
- B-17: Pages precisa ser ligado manualmente uma vez: Settings > Pages >
  Source = GitHub Actions. O token do workflow nao tem permissao para isso.
- B-18: O erro de deploy do Pages aparece se Pages nao estiver ligado.

## Proximas tarefas (Fase 1)

1. Refazer o poligono a partir de dados OSM validados e rodar o CI ate verde (B-14, B-16).
2. Ligar o Pages uma vez em Settings (B-17) e confirmar o build web no Safari (B-10).
3. Verificar a ligacao dos blocos do poligono (B-03).
4. Confirmar com o usuario a instalacao do Godot 4.4 e a exportacao iOS.

