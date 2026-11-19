# ESTILO — o caderno de estilo visual do CARIOCA

Este documento e a lei visual do jogo. Toda melhoria grafica nova (prop,
veiculo, bairro, efeito, interface) precisa caber aqui; se nao couber, discute-se
o documento antes — nao se cria excecao depois.

## Direcao geral

- **Low-poly estilizado com iluminacao moderna.** Formas simples e legiveis
  (caixas, cilindros, silhuetas claras), mas com luz e atmosfera
  contemporaneas: tonemap ACES, glow suave, nevoia litoranea, sombras de
  contato. O Rio e reconhecivel pela SILHUETA (morro, calçadão, ondas,
  postes), nao por textura fotografica.
- **Legibilidade antes de detalhe.** Em tela de iPhone a 30 FPS, um objeto
  precisa ser reconhecivel a 40 m. Cor e silhueta valem mais que densidade de
  poligono.
- **Procedural primeiro.** Todo visual nasce em codigo (malhas por codigo, cor
  por vertice, MultiMesh) e so depois, se valer a pena, vira asset externo.
  Motivo pratico: o projeto nao tem terminal neste dispositivo; tudo precisa
  compilar no CI e rodar no Safari do iPhone.
- **Assets externos: CC0 ou CC-BY, sempre com creditos** (Kenney, Poly Pizza,
  Poly Haven, ambientCG, OpenGameArt, freesound). Nunca conteudo com
  copyright, mesmo "so para testar". Atribuicao vai em `data/ATTRIBUTION.md`.

## A paleta do Rio

Cores de referencia em codigo (`scripts/world/city_gen.gd`,
`scripts/world/prop_factory.gd`, `scripts/main.gd`). Novos elementos usam
esta paleta ou uma interpolacao entre duas cores dela — nada de sorteio livre
fora do espectre definido:

- **Mar**: azul-petroleo `Color(0.10, 0.26, 0.38)` com brilho de sol (roughness 0.12).
- **Areia**: seca `Color(0.86, 0.79, 0.64)`, molhada `Color(0.70, 0.65, 0.55)`.
- **Asfalto**: `Color(0.21, 0.22, 0.24)`; calcada `Color(0.63, 0.62, 0.59)`.
- **Predios**: paleta de pastel claro com tom de pedra (constante `PALETTE`) —
  branco, creme, areia, verde-agua; telhado cinza `Color(0.36, 0.34, 0.32)`;
  fachada de vidro `Color(0.55, 0.68, 0.78)` que acende a noite (emissao).
- **Vegetacao**: verde-mato `Color(0.22, 0.42, 0.24)` a `Color(0.33, 0.45, 0.27)`;
  tronco `Color(0.34, 0.27, 0.18)`.
- **Carros**: vermelho, azul e branco (constantes de "carro" no PropFactory);
  pneu quase preto, vidro claro.
- **Ceu**: azul profundo no topo `Color(0.20, 0.40, 0.72)`, horizon claro
  `Color(0.68, 0.79, 0.88)` — o "haze" de cidade litoranea.
- **Noite**: janelas e luminarias quentes `Color(1.0, 0.85, 0.55)`; luz da lua
  fria `Color(0.62, 0.72, 1.0)`, fraca.

## Regras tecnicas de render

- Renderer **Compatibility** (OpenGL ES 3.0). Nao trocar sem medir (ver
  `docs/ARQUITETURA.md` e `docs/OTIMIZACAO_IPHONE12.md`).
- 1 unidade = 1 metro. Cor por vertice, 1 material por setor, MultiMesh para props.
- **Sem ShaderMaterial custom no caminho critico**: o shader do mar congelou o
  WebGL no Safari (B-25). Efeitos novos usam StandardMaterial3D (emissao,
  roughness, UV offset) ate um shader ser reavaliado com cuidado.
- Pos-processamento permitido: tonemap ACES (exposure ~1.05), glow com
  threshold ~1.1, nevoia. Fora: SSAO, SSR, bloom pesado, screen-space de tela
  cheia que o Compatibility nao sustenta.
- Orcamentos atuais: setor full < 40k vertices; props somem a 700 m; malha de
  setor some a 1500 m (full) / 2400 m (LOD far). O fade suave (dither) so
  existe no Forward+, nao no Compatibility: no alvo o corte e seco (B-29).
- Sombra direcional em 2 splits, max 110 m. Sombras de contato = disco escuro
  unshaded (nao existe Decal no Compatibility).

## Animacao

- Enquanto nao houver esqueleto (Fase 3), animacao procedural por codigo:
  perna/braco por senoide (player), rodas girando e estercando + carroceria
  inclinando com o relevo (carro), ondas de mar por material.
- **Todo elemento novo precisa de pelo menos um movimento proprio** (girar,
  acender, balancar, piscar) — cidade morta nao e o Rio.
- Animacao nao pode custar draw calls novos: reutilizar malha e material,
  animar transform e emissao.

## Interface

- Toda UI por codigo (sem .tscn editado a mao), sem imagens nesta fase.
- Botoes de acao com o dedo: minimo ~46 px de raio de toque, nos cantos,
  fora da faixa superior reservada (TOP_UI no touch_controls.gd).
- Textos curtos em portugues do Brasil, SEM giri incorreto: o jogo e carioca,
  mas a interface precisa ser entendida por qualquer brasileiro.

## O que recusar

- Texturas fotograficas de alta resolucao (pesam no download do build Web e
  destoam do estilo).
- Modelos realistas ou de terceiros com copyright.
- Efeitos que so o PC roda: nada entra no jogo sem passar pelo teste do
  iPhone (export Web + Safari), a cada melhoria.
