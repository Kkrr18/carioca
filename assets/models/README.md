# assets/models

Modelos 3D externos. Um arquivo por modelo, `nome-descritivo.glb`, sem ZIP
(o .zip nao pode ser descompactado no iPhone — B-21).

Regra de licenca: **so CC0 ou CC-BY**, com a origem e a licenca anotadas em
[data/ATTRIBUTION.md](../../data/ATTRIBUTION.md). Nada de conteudo com
copyright de jogo comercial.

## O que existe hoje (piloto, Fase 1.5)

| Arquivo | Origem | Licenca | Tamanho | Uso |
|---|---|---|---|---|
| vehicle-truck-red.glb | [Kenney — Starter Kit Racing](https://github.com/KenneyNL/Starter-Kit-Racing) (`models/vehicle-truck-red.glb`) | CC0 1.0 (assets; o codigo do kit e MIT) | 90 KB | piloto de asset: caminhao estacionado na areia, carregado por `scripts/world/model_prop.gd` |

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
