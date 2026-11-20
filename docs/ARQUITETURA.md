# Arquitetura (Fase 1)

## Decisões

**Godot 4.4 + GDScript, zero dependências.** Nada de plugin, GDExtension ou
biblioteca paga. O que precisar de desempenho extra vira dado pré-processado em
Python (grátis, roda no CI) em vez de código nativo no jogo.

**Renderer Compatibility (OpenGL ES 3.0).** É o caminho com menos variáveis no
iPhone e o que funciona em aparelhos mais antigos. Forward+/Mobile (Metal) fica
para a Fase 8, com medição. Trocar é uma linha em `project.godot`, mas muda o
orçamento de desempenho — não trocar sem medir.

**1 unidade = 1 metro.** O mundo tem ~13 x 12 km no polígono; com `float32` a
precisão a 13 km é de ~1 mm, suficiente. Se a Fase 6 mostrar tremulação de
vértice, entra *floating origin*.

**Coordenadas locais + georreferência.** Origem na frente de Copacabana
(-22.9743, -43.1828). `cfg.local_to_lonlat()` e `lonlat_to_local()` convertem
linearmente (equiretangular: 110.540 m por grau de latitude, 102.450 m por grau
de longitude nessa latitude). Todas as ferramentas (Python, GDScript) usam a
mesma conta, por isso a área medida bate entre elas.

**eixo X = litoral, eixo Z = continente, Z<0 = mar.** O terreno é uma função
`height_at(x, z)` pura e determinística. Nenhuma malha de altura precisa ser
guardada: qualquer sistema pode perguntar a altura.

## Geração e streaming

- Setor = 512 m x 512 m. Cada setor gera uma malha única com cor por vértice
  (1 draw call por setor) mais um MultiMesh de props.
- **Determinismo**: PRNG xorshift32 próprio (`CityGen.Rng`) e hash de célula
  (`mix3`). O mesmo seed gera o mesmo mundo em qualquer versão do Godot e em
  qualquer máquina; é o que permite testar e reconstruir a partir de um save.
- **Threads**: a worker só calcula `PackedArray`s (sem nós, sem rendering). A
  malha é montada na thread principal, 2 por frame. `WorkerThreadPool` com
  prioridade baixa.
- **LOD**: anel interno (1) detalhado; anel externo (2) sem toldo, árvore,
  detalhe de cobertura (props) nem meio-fio. O sorteio do lote acontece igual
  nos dois LODs, então a silhueta (volume, recuo e altura do prédio) não muda
  ao se aproximar.
- **Fora do raio**: nada é carregado. O horizonte é o nevoeiro + o plano do mar.
- **Frontal de quadra**: as ruas ficam nas bordas de quadras de 64 m e a grade
  é alinhada a x=0 e z=128; como 512 é múltiplo de 64, nenhuma quadra cruza a
  fronteira de dois setores (sem costura nem buraco).

## Colisão

Sem física estática no mundo. O personagem:

1. pergunta a altura do terreno (`cfg.height_at`) e gruda no chão;
2. empurra-se para fora dos retângulos de prédio (`SectorStreamer.push_out`);
3. recusa posições em água mais funda que `MIN_WADE_DEPTH`.

Custo por frame: uma consulta de altura e poucas dezenas de retângulos. Não há
dependência de `move_and_slide` contra corpos estáticos — o resultado é o mesmo
a qualquer frame rate. Veículos (Fase 4) provavelmente vão para um sistema
próprio de cinemática, não para `VehicleBody3D`.

## Salvamento

`user://saves/slot0.carsave`:

```
CARIOCA-SAVE;<schema>;<versao>;<sha256 do blob>;<bytes>\n
<json do estado comprimido com gzip>
```

- Escrita em `.tmp` + rename: um fechamento no meio não apaga o save anterior.
- Schema futuro é recusado (não abre, não sobrescreve).
- Schema antigo passa por `_migrate()` (vazio hoje, schema 1 é o primeiro).
- Checksum e tamanho conferidos antes de desserializar.

## O que o save guarda hoje

Seed do mundo, posição/orientação do personagem, câmera, hora, clima, tempo de
jogo. Não guarda estado de missão (não existe ainda).

## Estrutura de pastas

```
project.godot, export_presets.cfg, icon.svg
scenes/main.tscn          cena única (a composição é feita por código)
scripts/main.gd           boot, save/load, ligação entre sistemas
scripts/core/             cfg, geo, perf_log  (puro, testável sem cena)
scripts/autoload/         world, save_manager
scripts/world/            city_gen, sector_streamer, prop_factory, day_night
scripts/player/           player (personagem + câmera)
scripts/ui/               touch_controls, hud
tests/runner.gd           testes headless
tools/geo/                medidor de área em Python
data/geo/                 polígono do mundo
docs/                     este documento e os demais
```

## Por que a composição é por código

A cena `main.tscn` só aponta para `scripts/main.gd`, que cria ambiente, sol,
mar, streamer, personagem, controles e HUD. Vantagens: o projeto tem poucos
arquivos para revisar à distância, nada de nós órfãos em `.tscn` editados à mão,
e o boot é legível de cima a baixo. Custo: o editor visual do Godot mostra uma
cena vazia — quando a Fase 3 trouxer modelos do Blender, as cenas desses
personagens voltam a ser `.tscn` de verdade.

## Decisões pendentes

- Renderer Mobile/Metal: medir na Fase 8.
- Tile de dados carregado de disco (Fase 2) x geração em GDScript (hoje).
- Malha de colisão real para o relevo montanhoso (hoje só altura analítica).
- Áudio: motor próprio com dados brasileiros originais (Fase 5).
