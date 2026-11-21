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
| Luz do Rio (4 momentos de ceu) e clima (claro/nublado/chuva) | Escrito, nao validado | scripts/world/day_night.gd |
| Veiculo dirigivel (fisica automotiva B-67) | Escrito | scripts/vehicles/car.gd, scripts/vehicles/vehicle_physics.gd |
| Fisica ambiental: superficies, objetos moveis, dano e destrocos (B-69) | Escrito | scripts/core/surface_db.gd, scripts/physics/ |
| Piloto de asset externo (.glb CC0 normalizado pelo AABB) | Escrito | scripts/world/model_prop.gd, assets/models/ |
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

- Fase 1: encerramento — fundacao jogavel validada no iPhone (web). Falta
  apenas o poligono valido (B-14/B-16) para o CI ficar 100% verde.
- Fase 1.5 (detalhes visuais): Passo A (tonemap/glow, agua com ondas e
  fresnel, sombra de contato) e Passo B/C/D procedural (fachadas de vidro
  com janelas que acendem a noite, postes com luminaria, bancos, lixeiras,
  carros estacionados na avenida, distancias de visibilidade com fade).
  Pendente: validacao no aparelho (jogar + FPS) e assets externos (B-21).
- Fase 4 (incremento minimo): carro dirigivel — cinematica "bicycle" por
  codigo (sem VehicleBody3D, mesma filosofia de colisao do player), rodas que
  giram e estercam, carroceria que inclina com o relevo, camera propria,
  farois/lanternas emissivos. Nesta rodada, para o usuario conseguir ENTRAR e
  ANDAR no iPhone (B-36/B-38): o carro nasce a ~5,7 m do spawn com marcador
  flutuante, o raio do botao subiu de 3,5 m para 12 m, o botao ENTRAR/SAIR e
  desenhado e tratado pelo TouchControls (nao e mais Button do HUD) e,
  dirigindo, PULAR/CORRER viram ACEL/FREIO. A
  telemetria mostra "carro dirigindo/livre, dist, km/h, acel %, volante %".
  Pendente: validacao no aparelho.
- Medicao de FPS (B-09): o HUD ganhou o botao MEDIR — 15 s sem o limite de 30
  FPS e o resultado (media, p95 e pior frame) fica na telemetria. Pendente:
  ler o numero no iPhone.
- Piloto de asset externo (B-21): UM .glb CC0 (Kenney, caminhao) carregado por
  scripts/world/model_prop.gd, com escala, eixo e apoio no chao normalizados
  pelo AABB e fallback silencioso. O CI importa o .glb e TESTA que ele vira
  PackedScene com volume e triangulos. Isolado de proposito: nao substitui o
  carro dirigivel nem os props procedurais ate vermos o custo no aparelho.
- Premissa de realismo (decisao do autor, 2026-11): registrada em
  docs/ESTILO.md. Realismo maximo, no alvo iPhone 12, significa geografia,
  sinalizacao e comportamento reais; a forma continua low-poly por orcamento.
  Primeiro passo entregue: sinalizacao pintada nas ruas (eixo amarelo
  tracejado, faixa de pedestres e linha de retencao, so no LOD full) em
  city_gen.gd, mais o asfalto das duas ruas em niveis diferentes — as esquinas
  piscavam por z-fighting desde a Fase 1.
- Transito (Fase 4, rodada 2): o carro do jogador COLIDE com os carros de
  transito (hit_test por circulos no plano XZ, empurrao para fora, perda do
  embalo e signal `crashed`), os carros mantem distancia entre si
  (_apply_spacing: quem vem atras alivia e para) e o transito ACOMPANHA o
  jogador (place_near: quem ficou a mais de 260 m volta para 150-260 m, fora do
  campo de visao). Pendente: validar no aparelho.
- Som (Fase 4): motor sintetizado em AudioStreamGenerator (tom sobe com o giro,
  amplitude com o acelerador) + ruido filtrado de cidade + impacto CC0
  (thud2.wav). Nao existe loop de motor CC0 em .wav/.mp3 com URL direta, e o
  Safari do iPhone nao toca .ogg — por isso a sintese. O Safari so libera audio
  depois do primeiro toque, o que ja acontece no joystick. Pendente: ouvir no
  aparelho e ajustar volume/timbre.
- Frota externa (Fase 4): quatro carros CC0 da Quaternius (sedan, SUV,
  esportivo e taxi) em assets/models/, 161-177 KB e ~3k triangulos cada, SEM
  textura (so cor de material) e com rodas em nos separados — o que permite
  girar e estercar depois. O CI valida o import, os triangulos, as dimensoes e
  a existencia dos nos de roda (_test_car_models). Agora o sedan e o carro do
  jogador (rodas que giram e esterçam; a caixa de codigo e a reserva) e os
  quatro modelos abastecem o transito basico (scripts/world/traffic.gd): 12
  carros na grade de ruas perto do nascimento, um desenho por modelo, cada
  modelo assado numa malha unica com cor de vertice. NAO validado no aparelho:
  falta ver o FPS com o transito em cena e se as rodas giram no sentido certo.
  Limitacoes conhecidas: sem semaforo, e na curva a faixa desliza em linha
  reta (sem arco). Colisao com o jogador, distancia entre carros e o transito
  que acompanha o jogador entraram na rodada seguinte (duas entradas acima).
  Descartados na pesquisa: Khronos ToyCar (CC0, mas 5,4 MB, ~89k triangulos e
  materiais que o renderer Compatibility nao aplica) e o Range Rover da
  IvOfficial (o mais bonito, 23k triangulos e texturizado — pesado demais para
  trafego, fica como opcao para um carro unico no futuro).

## Testados

- CI (job "Godot headless"): geracao de setor deterministica, limites de
  malha, LOD, colisores, props, mar/praia/interior, save/load versionado,
  setor_of e compilacao de TODOS os scripts do jogo (agora incluindo main.gd
  e os autoloads). As checagens de DADO do poligono (area, auto-intersecao,
  pontos de referencia) aparecem como DESVIO enquanto o poligono for rascunho
  (B-14): CI verde quer dizer "o codigo compila e as checagens de codigo
  passam", NAO "o mapa esta validado".
- CI (job "Godot headless"), teste de CENA do carro (B-38): monta personagem +
  carro numa cena minima, chama o mesmo caminho do botao ENTRAR, acelera pelo
  pedal ACEL por 1 s a 30 Hz e sai. Resultado: carro ocupado, personagem
  desligado e invisivel, camera do carro assume, throttle 1.00, 7,5 m/s,
  3,9 m andados em 1 s, e ao sair o personagem e a camera voltam. 76 checagens
  verdes, 0 falhas. Isto prova a LOGICA de entrar/andar/sair; nao prova que o
  toque chega ao jogo — isso so o aparelho diz.
- CI (job "Exportar Web"): o projeto exporta para Web sem erro.
- Build Web de 19/11/2026 (commit 1f0632f): o jogo RENDERIZA no navegador.
  Inspecao do Pages em viewport de telefone: ceu com gradiente, mar, areia,
  personagem de costas, HUD completo (titulo, telemetria, SALVAR/CARREGAR/
  PERF/+1h/LIMITAR 30, PULAR/CORRER, joystick) e o toast de boas-vindas. O
  painel de console mostra SO as duas linhas de boot do Godot ("Godot Engine
  v4.4.1" e "OpenGL ES 3.0 (WebGL 2.0) - Compatibility"): nenhum SCRIPT
  ERROR, nenhum Parse Error. O streaming gerou 2 setores. NAO verificado
  ainda: FPS, movimento e o carro — a inspecao roda em segundo plano, com o
  laco de render congelado; isso precisa de uma sessao real no aparelho.
- Deploy no GitHub Pages: ativo, https://kkrr18.github.io/carioca/ responde.
- JOGAVEL CONFIRMADO NO IPHONE (Safari, iOS 18): o usuario jogou — cidade
  carrega, personagem anda/pula, controles de toque respondem. NAO medido
  ainda: FPS real no aparelho (B-09), aquecimento, bateria.

## Bugs conhecidos

- B-01: RESOLVIDO. Compilacao validada no CI (job "Godot headless") e no
  aparelho: em 2026-02 o usuario confirmou o jogo jogavel no Safari do iPhone
  apos a correcao do B-20. O Godot continua sem rodar neste dispositivo; a
  validacao de compilacao continua sendo do CI.
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
- B-10: RESOLVIDO. O workflow web.yml roda, o export Web passa e o Pages
  publica em https://kkrr18.github.io/carioca/. Validado pelo usuario no
  Safari de um iPhone: o jogo carrega e da para jogar.
- B-20: RESOLVIDO. player.gd tinha duas declaracoes coladas na mesma linha
  (preload de TouchControls + const WALK_SPEED) e quatro chamadas a
  Input.is_key_down(), metodo que NAO existe no Godot 4 (o certo e
  Input.is_key_pressed). Os testes headless nao pegavam porque nao carregam
  player.gd. O erro derrubava a compilacao de main.gd (que o pre-carrega) e
  deixava o jogo sem cena nenhuma (tela azul no Safari). Corrigido em
  824c7a9 e confirmado jogando no iPhone.
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
- B-19: GitHub Pages NAO funciona em repositorio privado no plano Free. A tela
  do GitHub oferece "Upgrade or make this repository public to enable Pages".
  Opcoes gratuitas: repositorio publico (Pages e Actions gratis) ou hospedar o
  build em Cloudflare Pages/Netlify. Opcao paga: GitHub Pro/Team. Isso foi dito
  errado antes ("Pages e gratis") e esta corrigido aqui e em docs/TESTAR.md.
- B-18: O erro de deploy do Pages aparece se Pages nao estiver ligado.
- B-21: Os assets externos do plano visual (Kenney City Kit/Nature Kit,
  KayKit, texturas Poly Haven/ambientCG) NAO foram incorporados: nao existe
  forma de descompactar ZIPs neste dispositivo (sem terminal). O que entrou
  foi o equivalente PROCEDURAL (fachadas, mobiliario, carros). Para os assets
  reais: baixar em um PC, importar no Godot e commitar as cenas .glb/.tscn.
- B-22: O shader da agua e a iluminacao de janelas nao sao exercidos pelos
  testes headless (exigem GPU). Validar no Safari do iPhone apos o proximo
  deploy do Pages.
- B-23: MEIO CORRIGIDO — ver B-29. A constante usada era
  GeometryInstance3D.VISIBILITY_RANGE_FADE_DITHER, que nao existe no Godot 4.
  O "conserto" para VISIBILITY_RANGE_FADE_SELF_DITHER TAMBEM estava errado,
  entao o setor continuou sem compilar por mais dois commits.
- B-24: Os testes headless nao carregavam main.gd, player.gd, hud.gd,
  touch_controls.gd nem sector_streamer.gd, entao erros de compilacao
  neles passavam despercebidos no CI (aconteceu em B-20 e B-23). RESOLVIDO:
  o runner agora compila 10 scripts do jogo via GDScript.reload() e recusa
  qualquer falha (autoloads World/SaveManager continuam fora desse teste
  porque o modo -s nao os registra).
- B-25: O shader customizado do mar (ondas + fresnel do Passo A) congelou
  o render no Safari/WebGL: depois do load, NENHUM frame chegava a ser
  desenhado (nem o rótulo BOOT nem o HUD apareciam), o que aponta o
  primeiro draw do plano do mar — unico codigo meu que so roda em GPU e
  nunca exercido em GPU pelos testes. REVERTIDO ao StandardMaterial3D
  (roughness 0.12 + specular, brilho pelo sol do dia/noite). Agua animada
  fica para reavaliar com NoiseTexture2D como normal map (sem shader
  custom). Validar no proximo deploy.
- B-26: No build abc6dd8 o teste de compilacao acusou falha em
  sector_streamer.gd e hud.gd; no commit seguinte (mesmo codigo de jogo,
  so log melhorado) os dois compilaram. Provavel idiossincrasia de
  GDScript.reload() com recurso em cache no CI. Se voltar, o proprio Godot
  imprime o "Parse Error" com arquivo e linha no log (ver B-30).
- B-27: Depois da reversao do shader do mar (B-25), o jogo continua sem
  desenhar nada no Safari (canvas so limpa a cor de fundo). O console do
  Godot, onde o erro real aparece, nao e visivel no iPhone. MITIGACAO: o
  workflow web.yml agora injeta no build Web um painel verde que mostra no
  proprio jogo tudo o que o Godot imprime no console. Proxima leitura desse
  painel deve apontar o erro exato (script, shader ou runtime). O painel e
  temporario e sera removido quando a Fase 1.5 estiver validada. CUMPRIU O
  PAPEL: a leitura de 19/11/2026 apontou o B-28.
- B-28: RESOLVIDO. A tela azul do Safari NAO era o shader do mar (B-25/B-27):
  era `environment.tonemap_mode = Environment.TONEMAPPER_ACES` em main.gd. O
  enum do Godot 4 e ToneMapper com prefixo TONE_MAPPER_ (TONE_MAPPER_ACES). O
  script nao compilava, a cena nao montava e o canvas ficava so na cor de
  limpeza. Lido no painel do B-27: "Parse Error: Cannot find member
  TONEMAPPER_ACES in base Environment ... res://scripts/main.gd". Corrigido.
- B-29: RESOLVIDO. `GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF_DITHER`
  (o "conserto" do B-23) tambem nao existe: o enum VisibilityRangeFadeMode
  tem DISABLED, _SELF e _DEPENDENCIES. Pior: a doc do 4.4 diz que o fade so
  vale no Forward+ — no Compatibility ele faz o mesmo que DISABLED. Entao
  sector_streamer.gd agora usa DISABLED (corte seco, comentario honesto) e o
  "dithering" saiu do codigo e do ESTILO.md.
- B-30: RESOLVIDO. O teste de compilacao do runner era um alarme que nao
  tocava: chamava `GDScript.get_errors()`, que NAO existe no Godot 4, dentro
  do ramo de erro. A excecao abortava a funcao antes do `check()` — quando um
  script falhava, a checagem inteira desaparecia do log e o CI podia ficar
  verde. Foi assim que B-28/B-29 chegaram ao aparelho. Junto: _test_save_rejects
  fazia `str(bytes)` (PackedByteArray nao vira o texto do cabecalho) e
  estourava no indice 3, pulando 3 checagens em silencio (o log mostrou
  "Out of bounds get index '3'"). Agora a falha e sempre reportada com os
  arquivos, o cabecalho e lido com get_string_from_utf8(), e main.gd e os
  dois autoloads entram na lista — o arquivo que monta a cena era o unico
  que o CI nunca compilava.
- B-31: RESOLVIDO. O teste de ida e volta lon/lat <-> metros acusava erro de
  0,057 m: Vector2 e float32 no Godot e 1234,5 m perde precisao na conversao.
  Nao e bug do jogo (a conversao e a mesma do Python); tolerancia do teste
  virou 0,2 m.
- B-32: RESOLVIDO. hud.gd chamava `Performance.RENDER_TOTAL_TRIANGLES`, que
  nao existe no enum Monitor do Godot 4 (so PRIMITIVES e DRAW_CALLS). Como o
  main monta o HUD antes do player, esse erro pararia o jogo inteiro. Agora
  usa RENDER_TOTAL_PRIMITIVES_IN_FRAME como proxy e o rotulo diz "prim".
- B-33: Fase 4 — corrigido antes de validar: enquanto o jogador dirigia, o
  streaming e o mar continuavam no ponto onde ele saiu do carro, entao a
  cidade nao carregava na frente do veiculo. Agora o foco do mundo e o carro
  quando esta ocupado (main.gd), e o arrasto de olhar e descartado ao dirigir
  (a camera do personagem nao da mais um salto ao sair).
- B-34: RESOLVIDO. hud.gd chamava `get_viewport_rect()` — metodo de CanvasItem
  — dentro de um CanvasLayer, e o HUD inteiro nao compilava. Introduzido no
  incremento do carro, ao posicionar o botao CARRO. Achado pelo teste de
  compilacao na primeira execucao em que ele realmente compilou main.gd
  (B-30): "Parse Error: Function get_viewport_rect() not found in base self",
  em hud.gd:137. O tamanho visivel agora vem de
  get_viewport().get_visible_rect().size.
- B-35: RESOLVIDO ESCRITO (falta validar no aparelho). A interface era
  pequena demais no iPhone: o jogo desenha num viewport logico de 1280x720
  esticado para a tela, e em retrato a altura logica chega a ~2770 px, entao
  um texto de 12 px aparecia com ~6 px reais e o botao ENTRAR do carro com
  ~16 px. hud.gd e touch_controls.gd agora multiplicam fontes, botoes e
  deslocamentos por _ui, derivado da altura logica do viewport; a barra do
  topo e o botao do carro passaram a usar ancoras e retangulos explicitos em
  vez de posicoes fixas em _process.
- B-36: RESOLVIDO ESCRITO (falta validar no aparelho). O usuario jogou e nao
  conseguiu entrar/andar no carro. Causas provaveis, todas tratadas: o carro
  ficava a 14 m do spawn e o botao so aparecia a 3,5 m (agora nasce a ~5,7 m e
  o raio e 12 m, entao o botao aparece no nascimento); o acelerador era o eixo Y do joystick que
  tambem vira o volante (agora ha pedais ACEL/FREIO dedicados); e o carro nao
  tinha marcador (agora tem um poste com esfera). A telemetria passou a
  mostrar carro/velocidade/acelerador/volante, para diagnosticar no aparelho
  sem o console do Safari.
- B-37: RESOLVIDO. O `.glb` da Kenney NAO e auto-contido: ele referencia
  `Textures/colormap.png` por caminho relativo. O `--import` do CI acusou
  "Can't open file from path 'res://assets/models/Textures/colormap.png'" e
  importou o modelo SEM textura (o teste teria passado, o jogador veria um
  caminhao cinza). Corrigido baixando o PNG (10 KB) e mantendo a pasta
  `Textures/` ao lado do `.glb`. Licao: ao trazer um `.glb`, trazer tambem as
  texturas que ele referencia; o log do import no CI mostra o caminho exato.
- B-38: RESOLVIDO ESCRITO (falta validar no aparelho). O usuario tocou em
  "ENTRAR NO CARRO" e nada aconteceu. A inspecao do build publicado deu o fato
  decisivo: a telemetria dizia "carro livre dist 6 m acel 0% volante 0%" e o
  botao aparecia grande na tela. Ou seja: o jogo sabia do carro e mostrava o
  botao — o que nao chegava era o TOQUE. Os botoes do HUD sao `Button` do Godot
  (entrada da GUI); os botoes do jogo (PULAR/CORRER) sao desenhados e tratados
  pelo `TouchControls` via InputEventScreenTouch, e esses sempre funcionaram no
  iPhone. Entao o ENTRAR/SAIR virou um botao do `TouchControls` (circulo ambar
  acima dos pedais, lido por `take_car_press()`), o `Button` do HUD foi
  removido e o main chama a acao direto, sem passar pelo signal.
  Na mesma rodada, a barra do topo virou duas fileiras de 3: com 6 botoes numa
  linha ela ficava mais larga que a tela em retrato e "CARREGAR" saia cortado
  na borda esquerda (visto na inspecao), e a telemetria passou a comecar
  abaixo da barra. A inspecao tambem confirmou, no build publicado, que o
  caminhao da Kenney aparece na areia e que a telemetria informa
  "modelo vehicle-truck-red.glb: 6 malhas, 946 tris, 5.4 m".
- B-39: RESOLVIDO ESCRITO (falta validar no aparelho). O usuario viu "as rodas
  bugadas" no carro CC0. Duas causas de geometria, nao de codigo de direcao:
  (1) eu girava o NO da roda do .glb, mas nesse arquivo (export obj2gltf) o no
  da roda tem a origem no CENTRO DO MODELO, entao a roda nao girava — ela
  ORBITAVA o carro; (2) o eixo de giro era adivinhado pela menor dimensao do
  AABB, e o no "BackWheels" carrega as DUAS rodas de tras: o AABB dele e largo
  em X, a menor dimensao caia em Y, e as rodas de tras giravam como um prato.
  Correcao: cada roda ganha um pivo proprio no centro dela (calculado pelo AABB
  no espaco do carro), o no e reparentado para esse pivo — conferido por teste,
  o pivo * roda = a transformacao original — e o giro passa a ser no eixo
  LATERAL do carro (X local), com sinal que leva o topo da roda para -Z. O raio
  sai do proprio modelo para a velocidade angular bater. Testes novos no CI
  cobrem o pivo e a direcao de rolagem. Licao: em .glb de terceiro, nem a
  origem do no nem o "eixo" da peca sao o que o nome sugere.
- B-40: RESOLVIDO ESCRITO. A deteccao de "para onde o carro aponta" lia a
  ORIGEM do no da roda no .glb. Nesses modelos (export obj2gltf) a origem do no
  da roda fica no centro do modelo e a geometria vive nos vertices, entao a
  leitura dava ZERO para todas as rodas: a frente nunca era detectada e a meia
  volta nunca era aplicada. O CI pegou isso nos quatro modelos de transito
  ("rodas da frente ficam em -Z" falhou nos quatro, com 128 checagens verdes).
  Correcao: o centro de cada roda vem do AABB da MALHA
  (ModelProp.wheel_centers), usado tanto pela deteccao de frente quanto pelo
  teste, mais uma checagem de que os eixos dianteiro e traseiro estao
  separados por mais de 1 m — que teria pego o caso dos zeros.
- B-42: RESOLVIDO ESCRITO. O som nao ligava e o painel de console do build
  mostrava, a cada sessao: "WARNING: /root/Main/VehicleAudio/Engine is trying
  to play a sample from a stream that cannot be sampled" (achado na inspecao do
  Pages). Causa: o AudioStreamGenerator era tocado no _ready, antes de o Safari
  liberar o AudioContext (que exige um gesto), entao o play() falhava e o motor
  ficava mudo para sempre. Agora o stream so e iniciado no primeiro toque/tecla
  (_input), com ate 8 tentativas espacadas e sem insistir a cada quadro; a
  telemetria ganhou a linha "som: ..." para dizer no aparelho se o audio ligou.
  Na mesma rodada: o som de batida tinha cooldown zero e metralhava enquanto o
  carro ficava encostado — agora ha 0,35 s entre batidas.

- B-43: Fase 4 — CALCADA COM MEIO-FIO. O miolo da quadra passou a ser desenhado
  `Cfg.CURB_HEIGHT` (0,15 m) acima do terreno, com face vertical fechando a
  diferenca no encontro com a rua. O chao de quem anda acompanha
  (`Cfg.surface_at` = terreno + meio-fio): sem isso o personagem e o carro
  afundariam 15 cm ao subir na calcada — o chao analitico e a malha tem que
  concordar. Postes de luz, toldos, arvores e o transito passaram a usar
  surface_at. As faces do meio-fio existem so no LOD full. NAO validado no
  aparelho.
- B-44: Fase 4 — SEMAFOROS. Quatro postes por cruzamento dentro de 190 m do
  jogador, desenhados em DOIS MultiMesh (poste+carcaca e lentes, a cor da lente
  vindo da cor de instancia), entao todos os semaforos em cena custam 2
  chamadas de desenho. Ciclo de 26 s (verde 10 / amarelo 2 / tudo vermelho 1,
  depois o mesmo para a via cruzada), com fase defasada por cruzamento para o
  transito nao parar todo junto. O carro para na linha de retencao (5 m antes
  do centro) no vermelho e atravessa no verde; quem ja entrou termina de
  passar. NAO validado no aparelho: falta ver a lente de dia, se a fase casa
  com o carro parando e quanto custou em FPS.
- B-45: A premissa de realismo maximo ficou registrada no ESTILO.md como
  "geografia, sinalizacao e comportamento reais dentro do orcamento do
  iPhone", com a forma ainda low-poly. Texturas fotograficas em tudo, PBR
  pesado e reflexo em tempo real continuam fora: o renderer Compatibility do
  iPhone 12 nao sustenta.

- B-46: Fase 4 — TEXTURAS NO CHAO. Asfalto, calcada e areia ganharam textura
  CC0 1K do Poly Haven (asphalt_02, dirty_concrete, aerial_beach_01), cada uma
  numa surface propria com UV em escala de mundo (repete a cada 3 m; a areia a
  cada 10 m). O city_gen passou a devolver 17 arrays (as 3 superficies
  texturadas no fim) e o streamer monta 3 materiais — custo: +3 desenhos por
  setor. O mar continua com cor por vertice (SEABED), nao com textura de areia.
  Se o arquivo faltar, a superficie cai na cor de reserva e o jogo segue.
  Calçada portuguesa com o padrao de ondas do Rio NAO existe em CC0 com URL
  direta (pesquisa): o que existe e pedra de Lisboa (OpenGameArt, CC0) ou foto
  com marca d'agua. O proximo passo e gerar o padrao de ondas em codigo
  (ImageTexture) no calcadao. NAO validado no aparelho: falta ver o custo em
  FPS das 3 texturas e se o tiling ficou na escala certa.
- B-47: Fase 4 — CALCADAO. Primeira tentativa: padrao de ondas gerado em codigo
  (faixas senoidais). O autor jogou e disse que ficou ruim — e dava para prever:
  a textura era 128 px sobre 6 m (21 px/m), sem detalhe nenhum de perto, e
  listras regulares parecem carpete. CORRIGIDO: o calcadao passou a usar uma
  textura CC0 de pedra portuguesa de verdade (Demetrius, OpenGameArt, 1K,
  916 KB, `_0` no fim do nome do arquivo — sem ele da 404). Licao: textura
  gerada em codigo sem poder ver o resultado e aposta; quando existe textura
  real CC0, ela ganha.
- B-48: Fase 4 — FACHADA DOS PREDIOS. Os predios eram caixas de cor chapada com
  uma "casca de vidro" por fora que acendia a noite. Agora o corpo do predio e
  uma caixa com UV de fachada (uma janela por andar de 3 m, `FACADE_TILE`), numa
  surface propria com DUAS texturas geradas em codigo: albedo cinza (tingido
  pela cor da paleta, por vertice) e mapa de emissao que acende SO as janelas a
  noite. A casca de vidro saiu, entao o numero de desenhos por setor continua o
  mesmo (a surface de vidro virou a de fachada). Topo e base usam o canto liso
  da textura para o telhado nao ganhar janela. NAO validado no aparelho.
- B-49: Fase 4 — FACHADA FOTOGRAFADA. A fachada gerada em codigo (um retangulo
  de janela por modulo) foi trocada por uma textura fotografada de verdade:
  "Buildings - Batch of 21 Seamless Textures" de Keith333 (OpenGameArt,
  CC-BY 3.0, arquivo por arquivo, sem zip). Modulo escolhido:
  `ApartmentWindows_S.jpg`, 8 janelas x 4 andares cobrindo 22,9 x 12 m. O UV do
  predio passou a usar DUAS medidas (`FACADE_W`/`FACADE_H`) em vez de um tile
  unico, senao a janela esticava. A foto tambem serve de mapa de emissao a
  noite, com energia baixa (a fachada pega luz de cidade em vez de ficar preta).
  O padrao gerado continua como reserva. Poly Haven NAO tem categoria de
  fachada; ambientCG tem (CC0) mas so em .zip. NAO validado no aparelho: falta
  ver a escala da janela na tela e a noite.
- B-50: Fase 4 — VOLUME DOS PREDIOS. O autor jogou e disse o que o codigo ja
  mostrava: "os predios estao quadrados e meio feios". Diagnostico: a planta
  era `lote - 1..3 m` nos DOIS eixos (todo lote saia ~19 x 20 m), o volume era
  sempre a MESMA caixa e o topo era um caixote de 42% da area — cubo, cubo,
  cubo. CORRIGIDO: (1) largura e profundidade agora sao independentes (metade a
  inteira do lote) e o predio se desloca dentro do lote; (2) tres volumes —
  caixa reta, topo recuado (setback) e embasamento de 4,2/6,3 m com torre
  recuada, esta ultima as vezes com a esquina CHANFRADA; (3) a geometria passou
  a ser um PRISMA de planta arbitraria (`_plan_rect` + `_add_prism_tx`, com
  leque no teto e sem face de baixo), entao o chanfro custa o mesmo que a
  caixa; (4) o caixote do telhado saiu da malha e virou prop no MultiMesh
  (casa de maquinas, caixa d'agua, antena) — corte de ~8k vertices no buffer de
  cor por setor, que paga a geometria nova com folga; (5) toldo virou lona
  colorida e fica na face voltada para a calcada. Colisor continua sendo o
  retangulo da planta cheia: recuo e chanfro so acontecem acima da rua, entao
  nao existe parede invisivel na esquina. Numeros do CI (setor 3,0): buffer de
  cor por setor 17112 -> 10704 vertices (a laje de cada predio saiu da malha),
  fachada 6120 -> 10485 vertices; no total o setor ficou com MENOS triangulos
  que antes, com dois volumes por predio. NAO validado no aparelho: falta ver
  se a cidade deixou de parecer um formigueiro de cubos e o FPS (MEDIR).
- B-51: Fase 4 — CEU E LUZ DO RIO. O autor pediu "ceu mais bonito e uma
  iluminacao propria do rio". O ciclo antigo tinha um sol que subia e descia
  SEMPRE no mesmo lugar do ceu (so a altura mudava) e um gradiente unico de
  azul para branco — por isso nao havia por do sol e o ceu parecia plastico.
  Agora `scripts/world/day_night.gd` tem um modelo de luz puro e testavel
  (`sun_direction`, `look`, `aim_basis`): (1) o sol percorre um ARCO de
  azimute do Rio, nascendo no mar (112 graus) e se pondo sobre o continente
  (292), com 72 graus de altura maxima; (2) quatro momentos com paleta propria
  — meio-dia tropical, hora dourada (horizonte coral com zenite ainda azul),
  hora azul e noite com brilho de cidade no horizonte (o ceu do Rio nao e
  preto); (3) a nevoa copia a cor do horizonte e engrossa de madrugada
  (umidade do mar); (4) exposicao, glow e bloom sobem a noite; (5) o ceu so e
  reescrito a cada 1/50 de hora, porque cada escrita no material do ceu manda
  o Godot refazer o mapa de radiancia (economia para o iPhone). Teste novo de
  20 checagens no CI, sem GPU. NAO validado no aparelho: falta ver o por do sol
  na praia e se a noite ficou legivel (e o custo em FPS).
- B-52: Fase 4 — GRANULADO E "COISAS FEIAS". O autor viu "muito granulado" e
  coisas "meio bugadas e feinhas". Sete causas, todas medidas no codigo:
  (1) `msaa_3d=0` — o jogo rodava SEM anti-aliasing nenhum, e toda diagonal da
  cidade piscava em movimento (agora MSAA 2x); (2) brilho do sol no mar com
  roughness 0,12 em 60 km de plano virava faisca pixel a pixel (0,30);
  (3) glow com threshold 1,1 e bloom 0,20: halo em tudo que era claro e, como o
  buffer de glow e de meia resolucao, granulado grosso (agora threshold 1,35,
  intensidade <=0,38, bloom ~0); (4) disco do sol com 13-20 graus de raio, um
  bolo branco no ceu — e de noite, com o no do sol escondido, quem virava a luz
  do ceu era a LUA, com o mesmo disco gigante (agora 4,5-7 graus, e o sol nunca
  e escondido: energia 0 a noite); (5) as duas ruas de cada esquina ficavam no
  mesmo plano com 5 mm de diferenca e o cruzamento piscava de longe (a vertical
  agora sai em dois pedacos que encostam pela BORDA, sem area em comum; a
  pintura subiu para 6 cm acima do asfalto); (6) a fachada usava a FOTO inteira
  como emissao a 1,4 de energia, entao a PAREDE acendia junto com a janela
  (0,55); (7) palmeira e arvore eram uma coluna VERDE de 7 a 11 m, a coisa mais
  feia da cidade — agora sao tronco (marrom) + copa (verde) girada, duas
  instancias do MESMO MultiMesh, sem nenhum desenho novo. NAO validado no
  aparelho: o autor precisa dizer se o granulado sumiu, se a cidade ficou menos
  feia e quanto o MSAA 2x custou no MEDIR.
- B-53: Fase 4 — PEDESTRES COM VIDA. O autor pediu "NPCs agora tendo uma vida e
  sendo realista". Novo `scripts/world/pedestrians.gd` (28 pessoas):
  (1) ROTINA, nao enfeite deslizando: anda pela calcada em volta da quadra,
  canto a canto, no sentido que sorteou; em cada canto decide entre seguir a
  volta (65%), atravessar a rua (35%) ou PARAR (12%) para olhar o celular;
  (2) SINAL: para atravessar ele espera a via que vai cruzar ficar vermelha para
  os carros — usa a MESMA fase dos semaforos do transito (`Traffic.light_states`,
  semaforo da esquina do canto); se demorar 18 s, desiste e segue;
  (3) VIDA DE RUA: na praia caminha pela areia e pelo calcadao indo e voltando,
  as vezes parado olhando o mar; sai da frente do jogador quando ele chega a 1,5
  m e CORRE (2,3x) se um carro aparece a menos de 9 m durante a travessia;
  de madrugada sobra 1/3 das pessoas, de dia a calcada enche (`life_fraction`);
  (4) GENTE DIFERENTE: altura 0,93 a 1,07, seis tons de pele, oito cores de
  camisa e cinco de calca, tudo por semente propria — mesma pessoa, mesma roupa;
  12% correm na orla;
  (5) CUSTO: 3 MultiMesh para todos (corpo, cabeca+bracos e pernas), ou seja 3
  desenhos por quadro na cidade inteira; cada perna e uma instancia girada no
  quadril, entao as pernas balancam de verdade sem esqueleto. Corpo e cabeca
  compartilham a transformacao (mesma origem, pe no chao).
  A logica (cantos, travessia de 13 m, sinal, vida por hora, semente) e pura e
  testada no CI. NAO validado no aparelho: falta ver se eles andam no lugar
  certo da calcada, se param no sinal e quanto custou em FPS.
- B-54: Fase 4 — MODELO NOS PEDESTRES. O autor pediu "pega um modelo e aplica
  nesses npcs, um modelo bonito". Entrou o **CesiumMan** (Khronos glTF Sample
  Assets, `Models/CesiumMan`, CC-BY 4.0, (c) 2017 Cesium): personagem COM
  ESQUELETO e ciclo de caminhada embutido, 1,5 mil triangulos, 428 KB, com
  atribuicao em `data/ATTRIBUTION.md`. Escolha do arquivo: nao existe CC0 com
  humano animado e URL direta (Kenney, Quaternius e KayKit sao .zip; poly.pizza
  baixa por JavaScript), e o repositorio de amostras da Khronos e o unico com
  .glb direto, estavel e de licenca clara. Como o modelo e animado, cada pessoa
  virou um no proprio (esqueleto + AnimationPlayer), e nao MultiMesh: por isso a
  turma caiu de 28 para 18 e cada pessoa so e desenhada ate 110 m. Escala e
  apoio no chao saem do AABB do modelo; a tinta de 35% da cor da camisa
  diferencia as pessoas sem tingir a pele; o passo CONGELA quando a pessoa para
  (senao ela marcha no lugar esperando o sinal) e a velocidade da animacao
  segue a pressa. Sem o arquivo (ou se o import quebrar), o sistema volta
  sozinho para os bonecos de caixa de 3 MultiMesh — o jogo nunca fica sem
  gente. NAO validado no aparelho: falta ver se ele anda PARA A FRENTE (o glTF
  olha para +Z; se estiver de costas, trocar `MODEL_YAW` de PI para 0) e quanto
  o esqueleto custou em FPS.
- B-55: Fase 4 — JOGO INSPECIONADO E PEDESTRE CONSERTADO. O autor disse "ta bem
  bugado os modelos, joga e ve". Pela PRIMEIRA vez o jogo foi olhado rodando (o
  inspetor de web abriu o build do Pages e leu a tela): os pedestres apareciam,
  andavam, ficavam no chao e no tamanho certo (o modelo tem 4.672 triangulos,
  AABB de 1,14 x 1,51 x 0,31 m), a animacao tocava e o console do Godot so
  mostrava as 2 linhas de boot — nenhum erro. O que estava feio era outra coisa,
  e so dava para ver olhando:
  (1) eu tinha DESLIGADO a sombra dos pedestres para economizar FPS e eles
  viravam adesivo colado na areia branca (o inspetor descreveu assim);
  (2) a tinta de 35% da cor da camisa tingia o CORPO INTEIRO (pele e calca) e
  cada pessoa virava um manequim verde/azul listrado;
  (3) a pose congelava com pause/play e o `play()` recomecava o ciclo, entao a
  pessoa dava um salto de pose ao voltar a andar;
  (4) o apoio no chao usava `mi.transform`, que num glTF importado e a transform
  LOCAL dentro do esqueleto — agora usa `ModelProp.rel_xf`;
  (5) eles nunca apareciam a menos de 32 m do jogador.
  CORRIGIDO: sombra do sol de volta (12 pessoas em vez de 14 para pagar),
  sombra de contato num MultiMesh (1 desenho para todas: ancora no chao mesmo
  com sol a pino), tinta caiu para 18% + variacao de brilho (a textura original
  volta a aparecer), congelamento por velocidade 0 (sem reiniciar o ciclo),
  rel_xf para escala/apoio e nascimento a partir de 12 m. Numeros medidos no
  aparelho: 30 FPS parado (p95 34-38 ms), 15-20 FPS durante o streaming de
  setor, 153-166 desenhos, ~101-114 mil primitivas. O proximo corte de custo
  (se precisar) e o anel distante: 8 setores x 3 superficies texturadas.
- B-57: Fase 4 — PERSONAGEM DE VERDADE. O autor: "pega modelos bons, os
  personagens estao parecendo bonecos coloridos de 1,10 de altura". O problema
  era o CesiumMan (B-54): um homem so, repetido em todo mundo, sem roupa de rua,
  e a altura saia menor que a pedida porque a escala era medida no BIND POSE
  (o AABB da malha parada), enquanto a pessoa e desenhada na pose da animacao.
  SOLUCAO: tres corpos **adultos e vestidos** da Quaternius ("Ultimate Modular
  Characters": `ped-casual`, `ped-worker`, `ped-beach`, CC0, 767/658/814 KB) e
  as animacoes (idle/walk/run) do "Animated Human" da Quaternius (CC0,
  `ped-walk.glb`, 543 KB), **retargetadas** em tempo de execucao: as trilhas do
  clipe sao recopiadas apontando para o esqueleto de cada corpo, os dois vem do
  mesmo rig. O CesiumMan saiu do projeto. Escala agora vem da ALTURA POSADA do
  esqueleto (pe a cabeca), nao do bind pose; cada pessoa recebe um dos tres
  corpos em rodizio (variedade de graca) e o clipe de parado toca quando ela
  para. Sem os arquivos, volta para as caixas. O CI prova o que importa: os tres
  corpos importam, tem esqueleto e o clipe de caminhada casa com os ossos deles
  (se nao casasse, o pedestre ficaria em T-pose e o teste falharia). Custo:
  4 arquivos, ~2,7 MB; cada pessoa continua 1 desenho. NAO validado no aparelho
  ainda.- B-58: Fase 4 — PEDESTRE EM T-POSE. O autor: "ta bem bugado os modelos. Joga e
  veja voce mesmo". Joguei o build do Pages pelo inspetor de navegador: console
  LIMPO (nenhum erro de script) e, nas capturas, os pedestres de bracos
  horizontais, PARADOS na pose, DESLIZANDO pela areia e sem sombra nenhuma.
  CAUSA: `can_retarget` aceitava UMA trilha casando com um osso. Os corpos
  modulares ("Ultimate Modular Characters") e o walker ("Animated Human") sao
  packs diferentes: poucos nomes de osso coincidem, o retarget descartava quase
  tudo e o clipe "tocava" (o AnimationPlayer dizia que sim) sem mover um osso. O
  teste do CI usava a MESMA funcao fraca, entao passava verde em cima do bug.
  CORRECAO: (1) `match_ratio` mede a fracao de trilhas que acham osso e exige
  `MATCH_MIN` (60%); (2) `probe_motion` posa o esqueleto no inicio e no meio do
  clipe e mede o GIRO REAL dos ossos — abaixo de 0,05 rad o corpo nao serve;
  (3) `choose_bodies` so entrega corpo que passa nas duas provas; (4) o corpo que
  traz as animacoes no PROPRIO arquivo (o walker) usa o AnimationPlayer dele, sem
  retarget nenhum, e entra SEMPRE — o jogo nunca mais fica sem gente que anda
  (sem modelo, cai para as caixas); (5) sombra de contato maior e mais escura
  (1,30 m, 40%). O CI agora imprime casamento e movimento por corpo e falha se o
  corpo escolhido nao mexer o esqueleto.
- B-59: Fase 1.5 — CEU LAVADO, CHAO ESTOURADO E FAIXA NA CALCADA. Nas capturas
  do build: ceu branco-acinzentado as 09h45 com o sol a 60 graus, areia sem
  textura (branco puro) e uma faixa reta e mais clara cortando o calcadao em
  diagonal. CAUSA: `fog_sky_affect` = 0,65 jogava a cor da nevoa em cima do ceu
  INTEIRO e o azul do zenite virava branco; sol 1,30 + ambiente 1,05 + exposicao
  1,02 estouravam areia e calcada (albedo ~0,9); a faixa diagonal era a emenda
  entre os splits da sombra direcional, que caiam a ~11 m da camera.
  CORRECAO: nevoa tinge o ceu em 0,15 de dia (0,30 de noite), horizonte mais
  saturado, sol 1,12, ambiente 0,86, exposicao 0,96 de dia; splits da sombra em
  45% e 75% dos 120 m (a emenda sai do primeiro plano e a resolucao perto do
  jogador continua alta). O CI ganhou 2 checagens: `sky_affect` <= 0,25 e
  meio-dia sem estourar. TAMBEM: o painel de console do build Web cobria o
  joystick no canto esquerdo; foi para o centro de baixo.

- B-60: Fase 4 — MANEQUIM BRANCO E SOMBRA QUADRADA. Joguei o build de novo pelo
  inspetor depois de B-58: os pedestres ANDAM (bracos embaixo, passada
  completa) — o T-pose morreu. Mas o corpo aprovado (o walker) vem SEM textura e
  aparecia um MANEQUIM BRANCO NU, igual em todo mundo, e a sombra de contato era
  um RETANGULO cinza duro do tamanho da pessoa, embaixo de cada um (e do
  jogador tambem).
  CORRECAO: (1) `paint_body` pinta o corpo pela ALTURA do vertice — calca
  embaixo, camisa no meio, pele em cima — por cor de vertice, com o material
  usando a cor de vertice como albedo. Nao precisa de textura nem de arquivo
  novo, e cada pessoa usa a propria paleta (a rua volta a ter camisa vermelha,
  azul, branca...); (2) sombra de contato virou mancha REDONDA com gradiente
  radial (`GradientTexture2D`), no pedestre e no jogador. O CI ganhou 3
  checagens: corpo pintado tem cor de vertice, sombra tem textura e continua
  transparente, e a animacao toca em todos. FALTA: o personagem do jogador
  ainda e de caixas (os "bracos" sao duas tabuas horizontais), e os 3 corpos
  modulares continuam fora da rua (rig diferente: 11% de casamento) — o
  caminho para usa-los e remapear os ossos por posicao na hierarquia.

- B-61: Fase 4 — MOTOR MUDO E AVISO NO PAINEL. Ao entrar no carro aparecia no
  painel "is trying to play a sample from a stream that cannot be sampled":
  `_start_stream` chamava `play()` e so enchia o buffer no `_process` seguinte,
  e o mixer pegava o gerador VAZIO. Agora `_push()` enche 80 ms na hora do play e
  o player nao e reiniciado se ja esta tocando (cada `play()` num gerador vazio
  repetia o aviso). Fecha o B-42 no build Web; falta confirmar ouvindo no iPhone.

- B-62: Fase 4 — PEDESTRE DE COSTAS (MOONWALK). O autor: "eles andam pra tras ja
  reparou? meio que fazendo moonwalk". CAUSA: `MODEL_YAW = PI` partia da
  suposicao de que o glTF da Quaternius olha para +Z. O walker olha para o -Z
  (a frente do Godot), entao o giro extra deixava o corpo 180 graus fora do
  sentido do passo: ele atravessava a rua olhando para tras. Pior: o PI era
  somado na hora de DESENHAR, longe do calculo que guarda o yaw, e nenhum teste
  olhava a DIRECAO — o clipe tocava, a perna mexia, e o corpo ia de re.
  CORRECAO: `MODEL_YAW = 0.0` e a conta virou uma funcao pura, `facing_yaw(dir)`,
  usada no calculo e na escrita da rotacao. O CI ganhou uma checagem: para cinco
  direcoes, o -Z do no depois do giro aponta na direcao do passo (erro < 0,01).
  Licao para os proximos modelos: a frente do glTF nao se adivinha, se mede —
  quando entrar o modelo do jogador, conferir isso antes de tudo.

- B-63: Fase 3/4 — PROTAGONISTA DE MODELO. O autor: "coloque um bom modelo para
  o protagonista, ele ainda esta em blocos. Um homem de 1,80, branco, cabelo
  preto". Ficou: o MESMO corpo CC0 da Quaternius que ja roda nos pedestres
  (`ped-walk.glb`, o unico com as animacoes dentro do arquivo — idle, walk, run
  e jump), entao o jogador nao depende de retarget nenhum. Pintura por altura do
  vertice (a mesma `paint_body`, agora com um parametro de CABELO): calca
  embaixo, camiseta no meio, pele no alto e cabelo na nuca e no topo do cranio —
  a frente da cabeca continua pele (senao o rosto vira uma mascara preta). Cores
  do pedido: pele branca (0,96/0,84/0,75), cabelo quase preto (0,09), camiseta
  laranja e jeans (identidade do boneco antigo). Altura 1,80 m medida no
  ESQUELETO POSADO (o AABB da malha mente — ver B-57), pe apoiado no chao.
  Animacao escolhida pela velocidade: parado, andando (<2,2 m/s), correndo
  (clipe de corrida com compasso = velocidade/4,6) e pulo no ar. O boneco de
  caixas fica como reserva se o arquivo nao carregar.
  O giro segue a licao da B-62: o avatar gira por atan2(dir) e o modelo leva PI
  num filho, entao a frente olha no sentido do passo — e o CI tem checagem propria
  para isso (4 direcoes) mais uma de que a pintura acerta calca/camisa/cabelo.
  NAO validado no aparelho: falta ver se ele anda de frente e se o passo casa com
  a velocidade (se patinar, ajustar os divisores 4,6 e 1,5).

- B-64: Fase 4 — ANIMACOES DOS NPCs. O autor pediu "animacoes mais trabalhadas".
  O CI imprimiu o inventario do `ped-walk.glb`: **so 3 clipes** (idle, walk,
  run) — o espelho do GitHub perdeu pulo/punch/work/death do pack da Quaternius.
  Entregue: papeis de clipe resolvidos por nome (idle/walk/run/gesto/queda, cada
  um so entra se existir), transicoes com blend (0,28 s no passo, 0,12 s no
  resto), clipe de CORRIDA para quem corre na orla com compasso casado com a
  velocidade (sem patinar), giro de espera de +-12 graus em quem esta parado e
  QUEDA por codigo quando o carro do jogador passa a mais de 3 m/s a menos de
  1,7 m (tomba 90 graus em 0,25 s, fica 4,5 s no chao com o passo congelado e
  levanta). `clip_for`, `clip_pace`, `car_hit` e `fall_pitch` sao puros e
  testados. FALTA: um arquivo com os 7 clipes do pack (so existe em .zip) e
  gestos reais de conversa.
- B-65: Fase 4 — LOJAS COM INTERIOR. Predio baixo (2 ou 3 andares) virado para a
  calcada ganha loja no terreo: o vao (ate 5,5 m de frente por 4,5 m de fundo,
  3 m de pe direito) entra para dentro do predio, a fachada da frente passa a ser
  desenhada em 3 pedacos (dois lados + verga, com UV de modulo continuo) e por
  dentro entram piso, forro, 3 paredes, balcao, prateleira, 2 produtos e a placa
  colorida do tipo (padaria/farmacia/bar/loja/mercado). Tudo no buffer de cor
  por vertice: NENHUM desenho novo por setor. Os colisores passam de 1 retangulo
  para 3 (corpo do predio + as duas laterais do vao), entao o jogador ENTRA
  andando e nao atravessa parede; no LOD far o vao fica fechado e o colisor
  volta a ser um retangulo so, para a colisao casar com o que se ve. O toldo sai
  quando ha loja (a placa ocupa o mesmo lugar, ~3,4 m). `street_side`,
  `shop_colliders` e a fachada com vao sao puros e testados no CI (vao livre,
  parede fechada, 3 pedacos, nada cobrindo a porta). NAO validado no aparelho:
  falta entrar numa loja e ver se o interior le bem a luz do dia.

- B-66: Fase 4 — LOJA COM GENTE E COM NOME. Sequencia do B-65: a loja agora
  PUBLICA dados. O `city_gen` passou a devolver uma 25a lista com as lojas do
  setor (`_shop_spot`: `stand` = ponto do balconista atras do balcao, `front` =
  boca do vao, `facing` = para onde ele olha, `name` = Padaria/Farmacia/Bar/
  Loja/Mercado). O streamer guarda isso em `meta["shops"]` e expoe
  `shops_near(pos, raio)`; o modulo dos pedestres recebe o streamer e os 3
  primeiros pedestres viram BALCONISTAS: ficam parados atras do balcao, olhando
  para a rua, com o gesto de tempos em tempos, e nunca andam nem atravessam. Sem
  loja por perto eles voltam a ser pedestre comum (nao ficam perdidos). O `main`
  pergunta `shops_near` a cada quadro e, ao ENTRAR no vao, mostra o nome do
  comercio no aviso do HUD (uma vez por loja, nao a cada quadro). No LOD far a
  lista vem vazia: a frente esta fechada e nao ha balconista la dentro. Custo: 3
  pedestres dos 12 viram balconistas (nenhum desenho novo). Testes: o spot tem
  os 4 campos, o nome vem da tabela, o balconista esta dentro do vao e olha para
  a rua, o setor publica as lojas e o LOD far nao. NAO validado no aparelho:
  falta ver o balconista dentro da loja e o aviso do nome ao entrar.

- B-67: Fase 4 — FISICA AUTOMOTIVA DE VERDADE. O autor colou uma especificacao de
  "Realistic Physics Engine — Godot 4" (RigidBody3D + 4 RayCast3D de suspensao,
  mola/amortecedor, circulo de aderencia, transferencia de peso, arrasto, FWD/
  RWD/AWD) e pediu para implementar otimizada para o iPhone 12. A ARQUITETURA
  nao pode ser copiada, e o motivo esta em docs/ARQUITETURA.md: este mundo NAO
  TEM corpos de fisica. O chao e analitico (`Cfg.height_at`/`surface_at`) e
  predio e uma lista de retangulos (`push_out`), entao nao existe malha para os
  raios do RigidBody3D encostarem — ele cairia para sempre. Dar colisao aos 9
  setores carregados (512 m cada) estoura memoria e CPU no iPhone, que e
  exatamente o que a premissa "realismo maximo DENTRO do orcamento" proibe.
  ENTREGUE: o MESMO conjunto de quantidades fisicas, integrado sobre o chao
  analitico, num modulo PURO — `scripts/vehicles/vehicle_physics.gd`
  (`extends RefCounted`, sem no, sem cena, sem aleatoriedade) — que recebe o
  estado e devolve o proximo. E literalmente o codigo que roda no jogo
  (`car.gd::_drive` chama `step()`), e o CI mede os numeros, nao a intencao.
  O que entrou: massa (1450 kg no sedan; presets compacto 1100 kg e SUV 2200 kg
  AWD prontos em `compact()`/`suv()`), curva de torque (pico em 4000 rpm,
  0,55x na lenta 0,72x no corte), forca na roda = torque x marcha x diferencial /
  raio, cambio AUTOMATICO de 5 marchas (sobe a 5900, desce a 1700, com espera de
  0,55/0,40 s para nao "cacar" marcha), freio com ABS e tracao com TCS — os dois
  saem de graca do CIRCULO DE ADERENCIA (`tire_force`: o pneu nunca transmite
  mais que mu x carga normal), transferencia de peso por eixo e por lado
  (`normal_loads`: frear carrega a frente, curva carrega o lado de fora),
  arrasto aerodinamico 1/2 rho Cd A v^2 (Cd 0,32 e A 2,2 m2 no sedan) e
  rolamento, gravidade no declive (o carro perde velocidade na subida e ganha na
  descida, medido em `Cfg.surface_at` a +-1,6 m na frente e atras), aderencia POR
  PISO (asfalto 1,0 na cidade, areia 0,55 na praia, pedra 0,85 no calcadao) e
  LIMITE LATERAL mu*g: pedir curva demais a 80 km/h agora faz o carro SUBESTERAR
  (o volante perde autoridade e o HUD mostra a aderencia em %), em vez de girar
  no proprio eixo como antes. A carroceria tambem mergulha ao frear e levanta ao
  acelerar (accel_long) e rola para fora na curva (accel_lat). O som do motor
  passou a usar o GIRO (nao a velocidade), entao a troca de marcha e audivel; o
  HUD ganhou a linha "marcha N  R rpm  aderencia X%" — e por ela que se ve no
  aparelho se o cambio esta subindo e se o carro morre na areia. O trafego
  continua CINEMATICO de proposito: 12 carros com fisica completa nao cabem no
  iPhone, e a fisica e do carro do jogador. Testes novos no CI: torque com pico
  no meio, 1a girando mais alto e puxando mais que a 4a, arrasto quadruplicando
  ao dobrar a velocidade, cargas somando m*g, freio carregando a frente, curva
  carregando o lado de fora, pneu cortado em mu*carga, 0-100 km/h entre 4 e 16 s
  com o cambio chegando a 5a, mais de 108 km/h em 40 s, areia freando mais longe
  que asfalto, freio parando EXATAMENTE em zero (sem engatar a re), re saturando
  em REVERSE_MAX e subida de 8% freando mais que o plano. NAO validado no
  aparelho: falta dirigir e dizer se o carro "pesa" como carro (se estiver mole,
  mexer em torque/massas do preset; se estiver duro demais, no `brake`).

- B-68: Fase 4 — VOLANTE COM MAIS CURSO. Pedido do autor: "deixa o volante
  virar um pouco mais, ta muito limitado o volante". O esterco maximo parado
  subiu de 0,55 rad (31 graus) para 0,75 rad (43 graus), a resposta do volante
  de 3,5 para 4,5 rad/s e a queda com a velocidade ficou menos agressiva (0,55
  para 0,40): a 18 km/h o carro agora fecha uma curva de 3,6 m de raio em vez de
  5,7 m. Isso NAO deixa o carro nervoso na avenida, porque acima de ~10 m/s quem
  limita a curva e a ADERENCIA (mu*g, B-67) e nao o curso do volante: o ganho
  aparece nas manobras — virar na quadra, sair da areia, encostar. A roda
  DESENHADA ganhou um teto proprio (`VISUAL_STEER` = 0,60 rad, 34 graus) para
  nao entrar no para-lama quando o volante esta todo virado. Testes novos: o
  volante vira 40+ graus parado e o raio a 18 km/h fica abaixo de 4 m.

- B-69: Fase 4 — FISICA AMBIENTAL (caixas, lixeiras, cones, cadeiras, dano e
  destrocos). O autor pediu o "Realistic World Physics 2.0" completo (RigidBody3D,
  StaticBody3D, CharacterBody3D, Area3D, CollisionShape3D, PhysicsServer3D,
  PhysicalBoneSimulator3D, Joint3D) e a auditoria esta em docs/FISICA.md, com o
  mapa item por item da especificacao. A conclusao curta: esses recursos precisam
  de GEOMETRIA de colisao, e este mundo nao tem nenhuma de proposito (chao
  analitico + retangulos por `push_out`); dar colisao aos 9 setores de 512 m nao
  cabe no iPhone 12 e criaria uma SEGUNDA representacao do mundo. Entao a fisica
  entrou como modulos puros sobre o chao analitico, com as mesmas grandezas
  (massa, impulso, atrito, restituicao, resistencia de material) — e o mesmo
  codigo roda no jogo e no CI. ENTREGUE: (1) `surface_db.gd`, UM banco com 11
  superficies (asfalto, concreto, pedra, areia, terra, grama, lama, madeira,
  metal, vidro, agua), cada uma com atrito de PNEU (mu), atrito de OBJETO
  deslizando (slide), quique, resistencia, cor de poeira e etiqueta de som — o
  carro passou a ler daqui, acabando com o numero duplicado que existia dentro
  de vehicle_physics.gd; (2) `prop_body.gd`, objeto movel puro: gravidade 9,81,
  contato com o chao, quique, atrito do piso, arrasto, giro, SONO automatico e
  impulso em N.s (a caixa de 14 kg voa, a lixeira de 22 kg so anda); (3)
  `damage.gd`, 3 estados (intacto/danificado/destruido) por resistencia de
  material e contagem de fragmentos; (4) `prop_field.gd`, o sistema vivo no
  mundo: 20 objetos em volta do jogador, atropelamento pelo carro (empurrao com
  1,15x a velocidade + dano pelo impulso de 1450 kg), empurrao a pe pela
  velocidade do personagem, colisao com predio pelo `push_out`, destrocos com
  teto de 30 e vida de 8..13 s, reciclagem a 150 m e LOD em 3 faixas (60 Hz ate
  35 m, 20 Hz com tempo acumulado ate 100 m, estado guardado acima disso — nada
  congela perdendo a trajetoria); custo de desenho: 3 MultiMesh no total (cubo,
  cilindro, cone) com cor por instancia. O CARRO ganhou avaria: batida em
  transito, predio e objeto somam dano; a potencia cai pelo `power` do `step()`
  e, acima de 35%, ele puxa o volante para a direita. O HUD mostra
  `avaria N% (intacto/danificado/destruido)` e a telemetria mostra `props N (N
  acordados) + N destrocos`. O som usa o `impact.wav` CC0 que ja existia, com
  espera de 0,12 s. Testes novos: piso certo em mar/praia/calcadao/rua/calcada,
  pneu e objeto com atritos diferentes, carro lendo do banco, caixa caindo e
  pousando, sono, impulso virando velocidade, caixa leve mais rapida que a
  lixeira, areia parando antes do asfalto, 3 estados de dano, carro a 36 km/h
  quebrando madeira e a 7 km/h nao quebrando metal, pedestre nao quebrando vidro,
  caixa atropelada virando destroco e carro destruido acelerando menos.
  NAO validado no aparelho. NAO ENTROU (e por que, em docs/FISICA.md): ragdoll
  fisico (falta corpo com PhysicalBone3D), capotamento (precisa de corpo rigido),
  vidro/retrovisor/para-choque como pecas (o sedan CC0 e uma malha so), portas
  com Joint3D, ESP no carro e dano estrutural de predio.

- B-70: Fase 4 — ESP, PAREDE POR ANGULO E FICHA NO TRANSITO. Continuacao do
  pedido de fisica realista (docs/FISICA.md). Tres coisas que o autor sente
  dirigindo: (1) ESP de verdade no carro do jogador — quando o pneu passa do
  limite lateral (slip acima de 0,35) o controle CORTA ACELERADOR para devolver
  aderencia a curva, que e o que ele faz na vida real (o pneu dividido entre
  tracao e curva perde das duas); freando ele nao age. O HUD mostra "ESP" na
  linha de marcha/aderencia. (2) IMPACTO EM PAREDE POR ANGULO: antes, qualquer
  encostao em predio zerava a velocidade, o que parecia bug (raspar de lado
  parava o carro). Agora o `push_out` devolve a normal da parede e a velocidade
  e decomposta: de frente o carro quase para e o dano e maior; raspando ele
  DESLIZA na parede, perde so a componente perpendicular e arranha menos. O dano
  acompanha o quanto a batida foi de frente, nao a velocidade crua.
  (3) TRANSITO COM FICHA: cada modelo da rua (sedan, SUV, esportivo, taxi)
  carrega massa, freio, centro de gravidade e ritmo proprios. O SUV (2200 kg, CG
  0,72 m) freia a 4,1 m/s2 contra 5,3 do sedan e faz a esquina a 6,3 m/s contra
  8,3; o esportivo (1250 kg, CG 0,45 m, RWD) cruza a 10,3 m/s. A velocidade
  deixou de ser instantanea: o carro tem `v` real que sobe e desce pela ficha,
  entao o SUV nao "salta" para o cruzeiro quando o carro da frente libera,
  reduz ANTES da esquina (16 m antes) e FREIA no sinal fechado (antes ele so
  travava a posicao e arrancava no verde em velocidade de cruzeiro).
  Dicionarios de carro sem `v` (montados em
  teste) continuam no modelo antigo, o que manteve os testes de transito
  existentes intactos. Novo preset `VehiclePhysics.sport()` (1250 kg, RWD,
  260 Nm) tambem disponivel para o jogador. Testes novos: ESP so age com
  acelerador e slip alto e nao mexe no freio; batida de frente mata o embalo,
  raspando o carro desliza (4x mais velocidade restante) e machuca menos;
  esportivo mais leve e mais forte que o sedan; SUV mais pesado, esquina mais
  devagar, freio mais fraco; esportivo anda mais que o SUV; carro com ficha nao
  salta para o cruzeiro num quadro e vai ganhando velocidade; carro sem ficha
  continua no modelo antigo. NAO validado no aparelho.

- B-71: Fase 4 — PRIMEIRO TESTE "JOGANDO" (inspetor de navegador) E 3 CORRECOES.
  Tentei jogar o build Web de verdade (kkrr18.github.io/carioca) com o inspetor
  de navegador desta sessao. LIMITE HONESTO DA FERRAMENTA: a aba fica em segundo
  plano, o loop do Godot congela (`FPS 1 / frame 1000 ms`, tudo travado no
  primeiro quadro: `pos 1600, 1, 100`, `relogio 09:30`, `carro livre 0 km/h`) e
  a ferramenta nao envia teclas nem segura botao — entao ENTRAR, ACEL e o
  joystick nao foram acionaveis. Ou seja: DIRIGIR continua nao testado por mim;
  a sensacao de volante/motor/freio so o dedo do autor resolve.
  O QUE DEU PARA VERIFICAR no quadro real: o jogo carrega sem tela preta (barra
  de progresso, WebGL 2.0/WebKit), o painel de console nao mostra erro de script
  (so um `[error] (end of list)` sem mensagem, que nao e do jogo — nao ha stack
  nem texto de engine), os 4 modelos do transito e o caminhao CC0 carregam, o
  avatar aparece de camiseta laranja/jeans com sombra de contato, os pedestres
  estao na cena (12 pessoas, 4 desenhos cada), o HUD lista `props 20`, e os
  objetos fisicos ESTAO na cena (caixote de madeira, lixeira verde, cone laranja)
  apoiados no chao — nenhum flutuando ou enterrado.
  TRES PROBLEMAS ACHADOS E CORRIGIDOS: (1) o AVISO central do HUD ficava em
  cima da telemetria e tapava justamente o valor de "aderencia" — o aviso agora
  fica a 32% da altura da tela, abaixo do bloco de telemetria e acima dos botoes
  de toque; (2) `draw calls 0  primitivas 0  objetos 0  mem 0 MB`: no build Web
  os monitores de rendering do Godot voltam todos 0, entao a linha era lixo —
  `_metric_ok()` agora exige draw calls > 0 e, quando indisponivel, a linha
  simplesmente nao aparece; (3) `props 20 (20 acordados)` num quadro PARADO: os
  objetos nasciam acordados e integravam sem motivo — `place_on_ground()` agora
  deixa o objeto DORMINDO, e o CI verifica que dormindo ele nao afunda nem
  treme. ANOTADO PARA O PROXIMO PASSO VISUAL (pre-existente, nao e bug de
  codigo): o guarda-sol/quiosque da praia e uma laje fina sobre um mastro — sem
  um modelo CC0 de guarda-sol ou de quiosque ele vai continuar "feinho"; e o
  HUD anuncia `som: toque na tela para ligar` porque o toque do inspetor nao e
  um gesto de verdade do Safari.

- B-71 (CORRECAO, depois de rodar em PRIMEIRO PLANO): dois dos tres problemas
  acima eram artefato do PRIMEIRO QUADRO CONGELADO, nao do build. Com o loop
  rodando, os monitores de rendering do Web funcionam (draw calls 145,
  primitivas 76.503, objetos 1.404 — so `mem` fica 0) e os objetos dormem
  sozinhos 0,45 s depois (`props 20 (0 acordados) + 0 destrocos` em todas as
  leituras). O aviso em cima da telemetria era real e ficou corrigido; o
  `_metric_ok()` novo continua valendo (com draw calls 0 os numeros sao lixo),
  mas o comentario "no Web os monitores voltam 0" estava ERRADO: voltam 0
  quando NADA foi desenhado ainda. O teste em primeiro plano NAO conseguiu
  provar: ENTRAR e MEDIR nao recebem o "toque" do inspetor (ele clica no
  canvas, o Safari nao trata como gesto), entao nao houve medicao de 15 s nem
  carro dirigindo. E a HUD apareceu com a primeira fileira de botoes cortada no
  topo e o console cortado embaixo no viewport de telefone do inspetor: isso
  precisa ser conferido no iPhone de verdade ANTES de mexer no layout.

- B-72: Fase 4 — O CUSTO QUE APARECEU JOGANDO: SOMBRA DO SOL E CEU POR QUADRO.
  Rodando o build Web em primeiro plano, com o jogador PARADO na praia, a
  telemetria mostrou ao longo de 7 minutos de relogio de jogo (09:47 -> 16:53):
  FPS 29 -> 9-15, draw calls 145 -> 263, primitivas 76.503 -> 175.909, objetos
  1.404 -> 1.528. O quadro ficava MAIS CARO conforme o sol baixava, sem nada se
  mexer: com o sol baixo a sombra fica comprida, o frustum da sombra cobre muito
  mais cidade e cada objeto entra no passe de sombra OUTRA vez (por isso draw
  calls e primitivas dobram). Pior: `day_night.apply()` re-apontava o sol TODO
  QUADRO, e no ceu procedural quem desenha o sol e o MATERIAL do ceu — cada
  mudanca de direcao manda o Godot refazer o mapa de radiancia do ambiente
  (`ambient_light_source = SKY`), caro no WebGL. CORRECOES: (1) sombra de 2048
  para 1024 px (project.godot); (2) distancia de sombra de 120 m para 80 m
  (`Cfg.SUN_SHADOW_DISTANCE`, usado pelo main); (3) sol e lua so sao
  re-apontados quando andam mais de 0,004 rad (~0,23 grau, ~1 vez por segundo)
  em vez de a cada quadro. O que o jogador ve de perto nao muda — a sombra
  continua na rua em volta dele; sai a sombra inutil de 100 m de distancia.
  Testes novos no CI travam o orcamento: sombra <= 1024 px, distancia <= 80 m e
  epsilon >= 0,002 rad. NAO medido ainda: o FPS depois destas tres mudancas — o
  proximo teste e repetir a MESMA cena parada no fim da tarde e comparar draw
  calls/primitivas/FPS com os numeros acima.

## Proximas tarefas (Fase 1 -> Fase 2)1. Refazer o poligono a partir de dados OSM validados e rodar o CI ate verde (B-14, B-16).
2. Medir FPS no iPhone jogando uma sessao real (B-09): o botao PERF grava CSV.
3. Pedir ao usuario que toque em SALVAR e CARREGAR no jogo e confirme que o save volta (valida o B-08 no aparelho).
4. Fase 4 (incremento minimo): testar no iPhone (ENTRAR, ACEL/FREIO, SAIR) e tocar MEDIR para o FPS real; se estiver liso, trafego basico (carros de passeio seguindo as ruas) e a meta "dirigir do Rio ate Niteroi".
5. Fase 2: pipeline OSM/DEM (Overpass -> recorte do poligono -> tiles) e a ponte Rio-Niteroi como malha (B-04).
6. Fase 1.5 (visual, paralela): plano em docs/DETALHES_VISUAIS.md. Passos A-D
   em codigo (procedural); falta validar no aparelho e medir FPS.
7. B-21: o piloto (um .glb CC0) ja entrou e e verificado pelo CI. O proximo
   passo e medir no aparelho o custo em FPS e bytes; so entao importar
   Kenney/KayKit/Poly Haven em lote e substituir os props procedurais.
8. B-50: andar de carro pela cidade no iPhone e dizer se o volume dos predios
   resolveu o "quadrado" e se o FPS aguentou (MEDIR). Se ainda faltar forma,
   o proximo passo barato e VARIAR A LARGURA do lote na quadra (hoje 2 x 2
   lotes identicos de 23 x 23 m) e dar recuos diferentes por quadra.
9. B-51: deixar o relogio correr ate umas 17h30 (uns 8 min de jogo, a partir
   das 9h30 do nascimento), ir para a areia e olhar o por do sol sobre o
   continente de frente para o mar; depois conferir a noite (janelas acesas,
   rua legivel). Se o sol baixo encandear na camera, abaixar `SUN_ENERGY`.
10. B-58: olhar de perto um pedestre andando e dizer se as pernas mexem de
   verdade e se ele anda DE FRENTE (se estiver de costas, trocar `MODEL_YAW` de
   `PI` para 0,0). O log do CI diz, por corpo, o "casamento" e o "movimento": se
   os corpos modulares passarem, a rua volta a ter tres tipos de gente; se nao,
   quem anda e o walker, e o proximo passo e procurar corpos com rig igual ao
   dele ou juntar as superficies do corpo numa so (B-57).
11. B-59: se a faixa diagonal no calcadao continuar existindo com a sombra
   ajustada, ela e geometria (dois quads de calcada com brilho diferente) e nao
   sombra: precisa de uma captura com a posicao do HUD (`pos x, y, z`) para eu
   achar o par de quads.


12. B-67: dirigir no iPhone e ler a linha "marcha / rpm / aderencia" do HUD.
   O que conferir: a marcha sobe sozinha (1a -> 2a por volta dos 55 km/h), o som
   do motor CAI de tom na troca, o carro freia forte e nao gira no proprio eixo
   em curva rapida, e na areia ele sai mais devagar que no asfalto. Se estiver
   "mole", aumentar torque/massas em `VehiclePhysics.sedan()`; se estiver duro,
   diminuir `brake`.

13. B-69: no iPhone, esbarrar numa caixa (ela tomba), passar de carro por cima de
   cones/caixas (voam, quebram em destrocos, o HUD muda para "avaria N%") e bater
   num predio ou carro para ver a avaria subir e o motor perder forca. Ler na
   telemetria "props N (N acordados) + N destrocos": com tudo parado, "acordados"
   tem de ficar baixo (senao o sono nao esta pegando no Web). Se os objetos
   afundarem no chao ou tremerem parados, o problema esta no `step()` de
   prop_body.gd (contato com o chao analitico), nao no desenho.
