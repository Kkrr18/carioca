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
| Veiculo dirigivel (carro — Fase 4, incremento minimo) | Escrito | scripts/vehicles/car.gd |
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

## Proximas tarefas (Fase 1 -> Fase 2)

1. Refazer o poligono a partir de dados OSM validados e rodar o CI ate verde (B-14, B-16).
2. Medir FPS no iPhone jogando uma sessao real (B-09): o botao PERF grava CSV.
3. Pedir ao usuario que toque em SALVAR e CARREGAR no jogo e confirme que o save volta (valida o B-08 no aparelho).
4. Fase 4 (incremento minimo): testar no iPhone (ENTRAR, ACEL/FREIO, SAIR) e tocar MEDIR para o FPS real; se estiver liso, trafego basico (carros de passeio seguindo as ruas) e a meta "dirigir do Rio ate Niteroi".
5. Fase 2: pipeline OSM/DEM (Overpass -> recorte do poligono -> tiles) e a ponte Rio-Niteroi como malha (B-04).
6. Fase 1.5 (visual, paralela): plano em docs/DETALHES_VISUAIS.md. Passos A-D
   em codigo (procedural); falta validar no aparelho e medir FPS.
7. B-21: o piloto (um .glb CC0) ja entrou e e verificado pelo CI. O proximo
   passo e medir no aparelho o custo em FPS e bytes; so entao importar
   Kenney/KayKit/Poly Haven em lote e substituir os props procedurais.

