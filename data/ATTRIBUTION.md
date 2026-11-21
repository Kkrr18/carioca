# Atribuicao de dados e conteudo

## Dados geograficos (Fase 1 e seguintes)

- Coordenadas de referencia (pontos de praia, pontes, bairros) obtidas do
  **OpenStreetMap** via Nominatim / Overpass. Dados do OpenStreetMap sao
  distribuidos sob a **Open Database License (ODbL) 1.0**.
  - Texto: https://opendatacommons.org/licenses/odbl/1-0/
  - Uso no jogo: qualquer tela ou arquivo que apresente dados derivados do OSM
    deve exibir "Mapa: (c) colaboradores do OpenStreetMap, ODbL".
  - O que usamos: geometria de costa, eixos de rua, pegada de predios, areas
    verdes e hidos. Recortes gerados ficam em data/geo/ e devem manter o
    mesmo aviso no cabecalho do arquivo.

## Elevacao

- **Copernicus DEM GLO-30** (ESA), licenca de uso aberto Copernicus; alternativa
  **SRTM 1arcsec** (dominio publico, NASA/USGS).
- Os arquivos brutos baixados nao entram no repositorio (ver .gitignore).

## Codigo e ferramentas

- Godot Engine: licenca MIT (https://godotengine.org/license).
- Este projeto: a definir pelo autor (ver LICENSE).

## Modelos 3D externos

- `assets/models/head.glb` — cabeça humana escaneada por **Lee Perry-Smith**
  (Infinite-Realities / IR-LTD), distribuída com o exemplo "LeePerrySmith" do
  **three.js** (https://github.com/mrdoob/three.js/tree/dev/examples/models/gltf/LeePerrySmith).
  Licença **Creative Commons Attribution 3.0 Unported (CC BY 3.0)**
  (https://creativecommons.org/licenses/by/3.0/): a atribuição é OBRIGATÓRIA e
  está registrada aqui. Uso no jogo: cabeça 3D do protagonista (B-77),
  carregada por `scripts/player/player.gd`. O `.glb` traz só a geometria — as
  texturas do autor (difusa/normal/specular) ficaram de fora, então o jogo usa
  um material chapado de pele.
- `assets/models/vehicle-truck-red.glb` + `assets/models/Textures/colormap.png`
  — caminhao low-poly e o atlas de cores do
  **Starter Kit: Racing** de **Kenney** (https://kenney.nl,
  https://github.com/KenneyNL/Starter-Kit-Racing). Os assets 3D do pacote sao
  **CC0 1.0** (https://creativecommons.org/publicdomain/zero/1.0/); o codigo
  do kit e MIT. Usado como piloto de asset externo (B-21): um unico modelo,
  carregado por `scripts/world/model_prop.gd`. O `.glb` referencia o PNG por
  caminho relativo, entao os dois arquivos andam juntos (B-37).
- `assets/models/quaternius-car.glb`, `quaternius-suv.glb`,
  `quaternius-sports-car.glb`, `quaternius-taxi.glb` — carros low-poly do pack
  **"Cars"** de **Quaternius** (https://quaternius.com, tambem em
  https://poly.pizza). Licenca **CC0 1.0**; nenhuma atribuicao e exigida, mas
  fica registrada por respeito ao autor. Obtidos de um espelho no GitHub
  (little-zack-wong/vehicle-museum, commit `c46c517`) porque o download do
  poly.pizza e por JavaScript, sem URL direta de arquivo.
- Regra do projeto: so CC0 ou CC-BY, com origem e licenca anotadas aqui e em
  [assets/models/README.md](../assets/models/README.md). Nada de conteudo com
  copyright de jogo comercial.
- `assets/models/ped-casual.glb`, `ped-casual2.glb`, `ped-worker.glb`,
  `ped-beach.glb`, `ped-suit.glb`, `ped-f-casual.glb`,
  `ped-f-formal.glb` — corpos de pessoa **vestidos** (adultos, com
  esqueleto — homens e mulheres) do pack **"Ultimate Modular Characters"**
  de **Quaternius** (https://quaternius.com). Licenca **CC0 1.0**
  (nenhuma atribuicao exigida; fica registrada por respeito ao autor).
  Obtidos do espelho no GitHub **trebeljahr/quaternius-showcase**
  (https://github.com/trebeljahr/quaternius-showcase, pastas
  `public/glb/modular_men/` e `public/glb/modular_women/`), porque o
  download do site oficial e .zip e o iPhone nao descompacta. Os
  arquivos NAO trazem animacao nenhuma. (B-57/B-79)
- `assets/models/ped-walk.glb` — animacoes (**idle, walk, run**) do pack
  **"Animated Human Low Poly"** de **Quaternius**
  (https://opengameart.org/content/animated-human-low-poly, 2017), licenca
  **CC0 1.0**. Copia em .glb do espelho **pengqianhan/campus-world-model**
  (https://github.com/pengqianhan/campus-world-model, `public/models/walker.glb`).
  Serve de duas formas: como CORPO de pedestre (as animacoes vem no proprio
  arquivo, sem retarget) e como fonte dos clipes idle/walk/run que
  `scripts/world/pedestrians.gd` retargeta para os corpos modulares — e so
  quando a maioria das trilhas acha osso no esqueleto do corpo.

## Texturas

- `assets/textures/facade.jpg` — "Buildings - Batch of 21 Seamless Textures
  with normalmaps" (`ApartmentWindows_S.jpg`) de **Keith333** em
  https://opengameart.org/content/buildings-batch-of-21-seamless-textures-with-normalmaps.
  Licenca **CC-BY 3.0**: atribuicao obrigatoria —
  "Buildings - Batch of 21 Seamless Textures" por Keith333, CC-BY 3.0.
  Cobre 22,9 m de largura (8 janelas) por 12 m de altura (4 andares).
- `assets/textures/calcada.jpg` — "Seamless calcada (Portuguese pavement)" de
  **Demetrius** em https://opengameart.org/content/seamless-calcada-portuguese-pavement.
  Licenca **CC0** (credito opcional). Usada no calcadao da orla.
- `assets/textures/asphalt.jpg` (asphalt_02), `pavement.jpg` (dirty_concrete) e
  `sand.jpg` (aerial_beach_01) — texturas do **Poly Haven**
  (https://polyhaven.com/textures), 1024x1024, licenca **CC0 1.0** (sem
  atribuicao obrigatoria). Autor: Rob Tuytel. Baixadas dos mapas difusos 1K do
  CDN oficial (dl.polyhaven.org). Regra do projeto: 1K–2K tileavel entra, 4K/8K
  nao (ver docs/ESTILO.md).

## Sons

- `assets/sounds/impact.wav` — "Metal Impact Sounds" (`thud2.wav`), de
  **Brian MacIntosh (BMacZero)** em
  https://opengameart.org/content/metal-impact-sounds. Licenca **CC0 1.0**
  (o credito e opcional; fica registrado por respeito ao autor).
- O motor e o ruido da cidade **nao vem de arquivo**: sao sintetizados em
  `scripts/audio/vehicle_audio.gd`. Motivo: nao existe loop de motor CC0 em
  .wav/.mp3 com URL direta, e o Safari do iPhone nao decodifica .ogg.

## Terceiros

- Nao ha conteudo de jogos comerciais. Nomes de bairros, ruas e praias sao
  fatos geograficos; personagens, missoes e roteiro sao originais.
