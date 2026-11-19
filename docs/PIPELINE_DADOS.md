# Pipeline de dados (OSM + DEM) — plano da Fase 2

Objetivo: transformar o Rio real em dado do jogo, sem serviço pago.

## Fonte dos dados

| Dado | Fonte | Licença | Volume estimado |
|---|---|---|---|
| Linha de costa, ruas, quadras, áreas verdes, hidrografia | OpenStreetMap (Overpass API) | ODbL | dezenas de MB por recorte |
| Pegada dos prédios | OpenStreetMap | ODbL | grande; usar só onde houver cobertura |
| Relevo | Copernicus DEM GLO-30 (ESA) | Copernicus (aberto) | ~2 tiles de 30 m para a área |
| Altimetria alternativa | SRTM 1arcsec (NASA/USGS) | domínio público | 1 tile |

Atribuição obrigatória: ver `data/ATTRIBUTION.md`.

## Passos

1. **Recorte** — `world_polygon.json` (anel de 31 vértices) define a área.
   Ferramenta: `tools/geo/polygon_area.py` (mede e exporta GeoJSON).
2. **Download OSM** — Overpass via HTTP POST, uma consulta por tipo de feição
   para não estourar timeout: `highway`, `building`, `natural=coastline`,
   `natural=water`, `landuse`, `leisure=park`. Cache local em `data/osm/`
   (fora do repositório).
3. **Simplificação** — Douglas-Peucker com tolerância de 1-3 m para ruas e
   0,5 m para prédios; descartar `building=roof` e `building=garage` abaixo de
   20 m².
4. **Projeção** — mesma projeção do jogo (equiretangular local, origem em
   Copacabana). Gera coordenadas em metros; nada de latitude no runtime.
5. **Tiles por setor** — cada setor de 512 m vira um arquivo binário
   `data/tiles/<sx>_<sz>.bin`:
   ```
   cabecalho: u32 magic 'CRT1', u32 versao, u32 n_verts, u32 n_tris
   vertices:  f32 x, y, z (12 bytes por vértice)
   cores:     u8 r, g, b, a por vértice
   colisao:   u32 n_rects, cada Rect2 (4 x f32)
   ```
   Alvo: ≤ 300 KB por setor, ≤ 25 MB para o mundo todo comprimido.
   O jogo carrega no lugar de gerar (o gerador GDScript continua como
   "procedural" para áreas sem dado).
6. **Relevo** — amostrar o DEM em grade de 32 m (mesma do `cfg.CELL_SIZE`),
   gravar altura por célula no tile; `cfg.height_at` passa a ler o tile em vez
   da função analítica.
7. **Validação** — comparar contra o mapa: distância Copacabana→Ipanema,
   comprimento do eixo da ponte (13,29 km) e área do polígono (83 km² ±5%).

## Ferramentas a escrever (Fase 2)

- `tools/pipeline/fetch_osm.py` — Overpass + cache + relatório de cobertura.
- `tools/pipeline/dem_sample.py` — GeoTIFF do GLO-30 para grade de altura.
- `tools/pipeline/build_tiles.py` — gera os `.bin` e um índice.
- `tools/pipeline/test_tiles.py` — confere tamanho, contagem e ausência de
  buracos entre setores.

Todas em Python 3.12, só biblioteca padrão + `rasterio`/`shapely` (opcionais,
open source, gratuitas). Nada é pago.

## Estado

- Escrito: `tools/geo/polygon_area.py`.
- Pendente: todo o resto.
