# ESTILO — o caderno de estilo visual do CARIOCA

Este documento e a lei visual do jogo. Toda melhoria grafica nova (prop,
veiculo, bairro, efeito, interface) precisa caber aqui; se nao couber, discute-se
o documento antes — nao se cria excecao depois.

## Premissa: realismo maximo dentro do que o iPhone aguenta

Decisao do autor (2026-11): o jogo persegue **realismo maximo**. Como o alvo e um
iPhone 12 a 30 FPS no renderer Compatibility, isso quer dizer realismo de
GEOGRAFIA, SINALIZACAO e COMPORTAMENTO — nao textura fotografica:

- **Realismo que entra:** mapa real (OSM + DEM, Fase 2), ruas com eixo amarelo,
  faixa de pedestres e linha de retencao, semaforos com ciclo, mao direita,
  calcada e meio-fio, trafego com distancia e cruzamento, relevo real, sol na
  posicao da hora, mar e nevoa.
- **Realismo que NAO cabe:** textura fotografica em tudo, PBR pesado, reflexo em
  tempo real, SSAO/SSR, modelos de 20k+ triangulos em quantidade. Cada um custa
  quadro, e o alvo e um telefone.
- **Forma:** continua low-poly — e o que roda. O que muda e a referencia:
  proporcao, escala e cor de coisa real, no lugar certo do mapa.
- **Silhueta de cidade, nao de caixa:** predio nao pode ser o mesmo cubo em
  todo lote (B-50). Cada lote sorteia planta (largura e profundidade
  independentes), posicao dentro do lote, e um volume entre caixa reta, topo
  recuado e embasamento com torre recuada — porque e a silhueta que o jogador
  ve de longe. Cobertura tem detalhe (casa de maquinas, caixa d'agua, antena).

## Direcao geral

- **Low-poly por orcamento, realismo por referencia.** Formas simples e
  legiveis (caixas, cilindros, silhuetas claras), mas com luz e atmosfera
  contemporaneas: tonemap ACES, glow suave, nevoia litoranea, sombras de
  contato. O Rio e reconhecivel pela SILHUETA (morro, calçadão, ondas, postes)
  e pela GEOMETRIA CERTA: rua onde a rua existe, ponte onde a ponte existe.
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
  branco, creme, areia, verde-agua; laje/telhado cinza `Color(0.50, 0.49, 0.45)`;
  embasamento 32% mais escuro que o corpo (pedra/concreto da loja); toldo em
  lona colorida (`AWNINGS`), nunca cinza; fachada com a foto de janela (emissao
  a noite).
- **Vegetacao**: verde-mato `Color(0.22, 0.42, 0.24)` a `Color(0.33, 0.45, 0.27)`;
  tronco `Color(0.34, 0.27, 0.18)`.
- **Carros**: vermelho, azul e branco (constantes de "carro" no PropFactory);
  pneu quase preto, vidro claro.
- **Ceu**: zenite e horizonte com paletas SEPARADAS (um gradiente unico de
  azul para branco e o que faz o ceu parecer plastico). Os quatro momentos
  estao em `scripts/world/day_night.gd` e valem como lei:
  - **Meio-dia tropical**: zenite `Color(0.09, 0.31, 0.74)`, horizonte
    `Color(0.74, 0.85, 0.93)` (nevoa marinha umida) e sol branco-quente
    `Color(1.00, 0.96, 0.89)` a 72 graus de altura.
  - **Hora dourada**: sol ambar `Color(1.00, 0.64, 0.32)`, horizonte coral
    `Color(0.99, 0.60, 0.36)` e o zenite AINDA azul `Color(0.15, 0.33, 0.66)`.
    Essa separacao de cor e o por do sol carioca; sombra comprida, gradiente
    longo (`sky_curve` baixo).
  - **Hora azul** (logo depois do por do sol): zenite indigo
    `Color(0.09, 0.15, 0.42)`, horizonte rosa-ambar `Color(0.84, 0.44, 0.42)`.
  - **Noite**: zenite `Color(0.020, 0.031, 0.074)`, mas o horizonte tem brilho
    de cidade `Color(0.125, 0.104, 0.104)` — o ceu do Rio nao fica preto, e a
    exposicao sobe para o que esta na rua continuar legivel.
  - A nevoa copia a cor do horizonte (senao a emenda aparece) e engrossa de
    madrugada, quando a umidade do mar fecha o tempo.
- **Caminho do sol**: o sol NASCE NO MAR (azimute 112 graus, sobre z negativo) e
  SE POE SOBRE O CONTINENTE (292 graus). Nada de sol subindo e descendo sempre
  no mesmo lugar do ceu: sem arco de azimute nao existe por do sol.
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

- Texturas fotograficas de alta resolucao: 1K–2K tileavel (asfalto, calcada,
  fachada) entra; 4K/8K nao.
- Modelos realistas ou de terceiros com copyright.
- Efeitos que so o PC roda: nada entra no jogo sem passar pelo teste do
  iPhone (export Web + Safari), a cada melhoria.
