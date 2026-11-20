# assets/models

Modelos 3D externos. Um arquivo por modelo, `nome-descritivo.glb`, sem ZIP
(o .zip nao pode ser descompactado no iPhone — B-21).

Regra de licenca: **so CC0 ou CC-BY**, com a origem e a licenca anotadas em
[data/ATTRIBUTION.md](../../data/ATTRIBUTION.md). Nada de conteudo com
copyright de jogo comercial.

## O que existe hoje

| Arquivo | Origem | Licenca | Tamanho | Uso |
|---|---|---|---|---|
| vehicle-truck-red.glb | [Kenney — Starter Kit Racing](https://github.com/KenneyNL/Starter-Kit-Racing) (`models/vehicle-truck-red.glb`) | CC0 1.0 (assets; o codigo do kit e MIT) | 90 KB | piloto de asset: caminhao estacionado na areia, carregado por `scripts/world/model_prop.gd` |
| Textures/colormap.png | idem (`models/Textures/colormap.png`) | CC0 1.0 | 10 KB | atlas de cores que o `.glb` acima referencia por caminho relativo |
| quaternius-car.glb | Quaternius, pack "Cars" ([poly.pizza/m/unqqkULtRU](https://poly.pizza/m/unqqkULtRU)) | CC0 1.0 | 161 KB | sedã: carro do jogador (Fase 4) |
| quaternius-suv.glb | Quaternius ([poly.pizza/m/xsMtZhBkxL](https://poly.pizza/m/xsMtZhBkxL)) | CC0 1.0 | 177 KB | tráfego |
| quaternius-sports-car.glb | Quaternius (pack "Cars") | CC0 1.0 | 171 KB | tráfego (carro raro/mais rápido) |
| quaternius-taxi.glb | Quaternius (pack "Cars") | CC0 1.0 | 177 KB | tráfego (taxi carioca) |
| ped-casual.glb, ped-worker.glb, ped-beach.glb | Quaternius, "Ultimate Modular Characters" ([espelho no GitHub](https://github.com/trebeljahr/quaternius-showcase/tree/main/public/glb/modular_men)) | CC0 1.0 | 767 / 658 / 814 KB | pedestres (B-57): adultos vestidos com esqueleto, **sem animação** |
| ped-walk.glb | Quaternius, "Animated Human Low Poly" ([OpenGameArt](https://opengameart.org/content/animated-human-low-poly), [espelho](https://github.com/pengqianhan/campus-world-model)) | CC0 1.0 | 543 KB | só as animações (idle/walk/run), retargetadas para os corpos acima |

**Os carros da Quaternius nao tem textura**: as cores vem de material por peça
(carroceria, vidros, farois, lanternas, pneus). Isso e otimo aqui: como a cor e
plana, da para juntar as pecas numa malha unica com cor de vertice e desenhar
cada carro em 1 chamada de desenho — o que resolve o custo do trafego no iPhone.
As rodas vem em nos separados (`NormalCar1_FrontLeftWheel`, ...), entao girar e
estercar e possivel; o CI confere isso no teste `_test_car_models`.

O que os .glb trouxeram da Quaternius pelo [poly.pizza](https://poly.pizza) veio
por um espelho no GitHub ([little-zack-wong/vehicle-museum](https://github.com/little-zack-wong/vehicle-museum),
precisao de commit `c46c517`), porque o download do poly.pizza e por JavaScript
e nao tem URL direta. A autoria e a licenca sao as do autor original (CC0 1.0).

**O `.glb` da Kenney nao e auto-contido**: ele aponta para
`Textures/colormap.png` ao lado dele. Sem esse PNG o import funciona, mas o
modelo entra SEM textura (foi o que o CI mostrou na primeira importacao —
B-37). Ao trazer outro `.glb`, baixe tambem as texturas que ele referencia e
mantenha a mesma estrutura de pastas.

O `ModelProp` normaliza escala, eixo e pivo do modelo automaticamente
(AABB): escala para N metros no eixo Z, apoia no chao e centra. E por isso que
um modelo de outra escala nao quebra a cena.

## Como adicionar outro

1. Baixar o `.glb` individual (nao o pacote) do site do autor.
2. Salvar aqui com um nome descritivo.
3. Anotar origem, licenca e tamanho em `data/ATTRIBUTION.md` e nesta tabela.
4. Apontar `model_path` de um `ModelProp` para o arquivo (ver `scripts/main.gd`).

O Godot importa o `.glb` no `--import` (CI) e no export: nada de `.import`
precisa ser commitado (esta no .gitignore).
