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

- `assets/models/vehicle-truck-red.glb` — caminhao low-poly do
  **Starter Kit: Racing** de **Kenney** (https://kenney.nl,
  https://github.com/KenneyNL/Starter-Kit-Racing). Os assets 3D do pacote sao
  **CC0 1.0** (https://creativecommons.org/publicdomain/zero/1.0/); o codigo
  do kit e MIT. Usado como piloto de asset externo (B-21): um unico arquivo,
  carregado por `scripts/world/model_prop.gd`.
- Regra do projeto: so CC0 ou CC-BY, com origem e licenca anotadas aqui e em
  [assets/models/README.md](../assets/models/README.md). Nada de conteudo com
  copyright de jogo comercial.

## Terceiros

- Nao ha conteudo de jogos comerciais. Nomes de bairros, ruas e praias sao
  fatos geograficos; personagens, missoes e roteiro sao originais.
