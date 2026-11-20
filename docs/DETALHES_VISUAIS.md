# Detalhes visuais dos primeiros ~18,9 km²

Pesquisa e plano (Fase 1.5) para deixar o mundo atual bonito e realista,
mantendo: custo zero, licenças livres, renderer Compatibility e alvo
iPhone 12 (Safari / WebGL2). Nada aqui foi implementado ainda — este
documento é o insumo da implementação.

## Restrições duras (doc oficial do Godot 4.4, renderer Compatibility)

O que NÃO existe e por isso não pode entrar no plano:

- SSAO, SSIL, SDFGI, VoxelGI, Screen-Space Reflections
- Volumetric fog (existe Fog Depth/Height, que é barato)
- Decals (sombras de contato serão quads escuros, não decals)
- Reflexos em tempo real ( ReflectionProbe existe, limite de 2 por mesh)

O que existe e será o corpo do trabalho visual:

- Glow, Tonemapping, Fog Depth/Height, MSAA 3D
- LightmapGI só renderiza (nãoassa no iPhone); assar no desktop é possível
- Export Web single-threaded (já tratado no jogo, `use_threads = false`)

Fonte: docs.godotengine.org/en/4.4/tutorials/rendering/renderers.html e
.../exporting_for_web.html (que também avisa: Safari tem peculiaridades
com WebGL 2 — testar sempre no aparelho, nunca confiar só no desktop).

## Modelos (todos CC0, verificáveis na página do asset)

| Pack | Uso no jogo | Licença |
|---|---|---|
| Kenney City Kit (Commercial/Suburban/Roads/Industrial) | módulos de fachada, telhado, toldo, placa | CC0 (kenney.nl/assets/city-kit-*) |
| Kenney Nature Kit (330 arquivos) | palmeiras, árvores, pedras para encosta | CC0 |
| KayKit City Builder Bits (32+ modelos, atlas única 1024²) | postes, bancos, lixeiras, semáforos | CC0 |
| Quaternius Ultimate Textured Buildings (76 modelos) | prédios residenciais com fachada de janela | ficha diz CC0; a licença geral do site mudou para "QAL v1.0" — usar só os packs antigos ou confirmar caso a caso |
| Poly Haven models | props de alta qualidade pontuais (Fase 8) | CC0 |

Regra de estilo: continuar low-poly. A cidade procedural já nasce low-poly;
misturar modelos realistas deixa o jogo com cara inconsistente.

## Texturas PBR (CC0, tileáveis)

- Poly Haven (polyhaven.com/textures) — CC0, 1K/2K/4K/8K, JPG/PNG, mapas
  Diffuse, Normal GL, Rough, AO e ARM.
- ambientCG (ambientcg.com) — CC0 1.0 universal, ZIPs 1K–8K em JPG/PNG.
- 3DTextures.me — CC0, grátis 1024² (4K é Patreon), download um a um.

Para iPhone: baixar em 1K–2K JPG (albedo + normal GL + rough/ARM),
comprimir para VRAM no import. Usar em trim sheets/atlas por FAMÍLIA de
fachada (residencial padrão, comercial, calçada, asfalto, areia, pedra de
morro) para manter o número de materiais baixo.

## HDRI (céu/iluminação)

Poly Haven HDRIs são CC0; categorias úteis: Pure Skies, Coast & Water.
ATENÇÃO: HDRI é estático e o jogo tem ciclo dia/noite. Duas opções:
1. Manter o céu procedural e investir só em materiais/névoa (mais barato).
2. Lerp entre 2 HDRIs (dia/noite) com `Sky` panorâmico — mais bonito e
   mais caro em memória e código. Decidir só depois da opção 1 validada.

## Técnicas (ordem de custo/benefício)

1. **Materiais antes de geometria.** Fog Depth/Height + Glow + Tonemapping
   ACES já dão o "haze" carioca sem nenhum asset. Custo: só Environment.
2. **Vertex color com AO assada no Blender** nos protótipos de prédio:
   profundidade sem textura, funciona em qualquer renderer, zero fetch.
3. **Prédios modulares em vez de caixa lisa:** módulo de base + corpo com
   janelas (atlas) + laje/telhado + detalhe de topo (caixa d'água, toldo).
   O city_gen passa a compor por hash determinístico — mantém o streaming.
   Em parte FEITO no B-50, sem asset: planta sorteada, topo recuado ou
   embasamento com torre, esquina chanfrada e cobertura como prop (casa de
   máquinas, caixa d'água, antena). Falta o atlas por módulo e o AO assada.
4. **MultiMesh por TIPO de prop** (postes, bancos, lixeiras, palmeiras,
   carros estacionados): 1 draw call por tipo por setor. A doc adverte que
   não há culling por instância — limitar por setor e variar
   `visible_instance_count`.
5. **Impostores à distância:** palmeiras/árvores viram Sprite3D billboard
   além de ~180 m, com `Visibility Range Begin/End` e transição por
   dithering (mais barato que alpha).
6. **Água com vida:** shader barato de scroll de UV em normal map + fresnel
   no StandardMaterial do mar. Sem reflexo em tela cheia.
7. **Sombra de contato:** quad escuro sob o personagem e props próximos
   (não há Decals no Compatibility).
8. **LODs de material:** no LOD distante, desligar normal map (caro em
   mobile), rim, specular alto. A doc recomenda exatamente isso.
9. **Compressão VRAM** ligada no import e no preset Web (ETC2/ASTC já
   habilitado no project.godot).

## Ordem de implementação proposta

- Passo A (sem assets): ambiente (1), água (6), sombra de contato (7),
  tonemapping. Medir FPS antes/depois no iPhone — cada passo entra com
  número, não com promessa.
- Passo B: baixar Kenney City Kit + Nature Kit e KayKit, importar como
  cenas/protótipos, plugar no prop_factory e no city_gen (3, 4).
- Passo C: texturas PBR (Poly Haven/ambientCG 1K) em trim sheets para
  asfalto, calçada, areia e fachada residencial (2, 8, 9).
- Passo D: impostores + visibility ranges (5) e HDRI (decisão tardia).

## Pendências de verificação

- Confirmar dentro dos ZIPs que os formatos incluem glTF (confirmado só
  para o City Kit Roads até agora).
- Quaternius: confirmar caso a caso se o pack é CC0 ou QAL.
- Nenhum FPS foi medido com estas técnicas — os passos incluem medição.
