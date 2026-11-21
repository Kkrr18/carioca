# CARIOCA

Jogo 3D de mundo aberto inspirado no Rio de Janeiro e em Niterói.
Godot 4.4 · GDScript · alvo iPhone 12 · custo zero (OpenStreetMap, DEM público,
Python e Blender).

Estado: **Fase 1 (Fundação)** — em andamento. Fundação jogável validada no
Safari de um iPhone (jogo carrega, anda, pula e salva), via build Web no
GitHub Pages, e agora com a **camada de GTA** (procurado, polícia, missões,
combate, roubo de carro, radar e HUD — ver [docs/GTA.md](docs/GTA.md)).
Meta de 30 FPS e app nativo iOS ainda NÃO medidos/gerados: a camada nova
também não foi medida no aparelho. Leia [docs/STATUS.md](docs/STATUS.md) antes
de acreditar em qualquer coisa aqui.

## O que já existe

### O jogo (a camada de GTA)

- **Nível de procurado**: calor contínuo de 0 a 5 estrelas
  (`scripts/game/wanted.gd`, puro e testado). Cada crime soma calor (agressão,
  carro tomado, tiro, policial ferido/morto); a cidade esfria quando a polícia
  perde você de vista — mais devagar quanto mais estrelas.
- **Polícia**: viaturas nascem em volta, perseguem sobre o chão analítico,
  encostam (machucando você ou o seu carro), atiram a partir de duas estrelas e
  **prendem** (BUSTED) se ficarem 2,5 s perto de você a pé. A viatura é uma
  malha assada com as luzes piscando: 3 desenhos por viatura, até 5 viaturas.
- **WASTED/BUSTED**: vida em zero ou prisão custam dinheiro e devolvem o
  jogador no hospital ou na delegacia, com a cidade esquecendo o crime.
- **Missões em Ipanema**: quatro serviços encadeados (ORLA 04, A ENCOMENDA,
  FUGA NA LAGOA, O CARGA) com marcador amarelo no chão, objetivo no HUD, falas
  em legenda, polícia roteirizada e recompensa em dinheiro. O roteiro
  (`scripts/game/missions.gd`) é puro; a cena só executa.
- **Combate**: punho e pistola (12 balas), mira pela câmera, clarão do cano,
  dano em viatura e crime registrado. Vida e colete em barras.
- **Roubo de carro**: `ENTRAR` ao lado de um carro de rua toma o carro — modelo,
  ficha (massa/motor/pneus do SUV, do esportivo ou do táxi) e posição. O carro
  tomado some da rua e volta a circular longe, 30 s depois.
- **Radar circular** estilo GTA: gira com a câmera, desenha mar, areia, ruas da
  mesma grade do `city_gen`, marcador de missão (preso na borda quando longe),
  viaturas piscando e o jogador. Tudo em `_draw()`, sem textura.
- **HUD do jogo**: dinheiro, vida/colete, cinco estrelas, arma e munição,
  missão e objetivo, legenda de fala, nome do bairro e da rua (Ipanema), piscada
  vermelha de dano. A telemetria de desenvolvimento começa escondida e volta no
  botão `DEV`, no rodapé.

### A fundação (o que já existia)

- Projeto Godot 4.4 configurado (renderer *Compatibility*, sem dependências
  externas).
- Geração procedural determinística de cidade por setor de 512 m: terreno,
  avenida da orla, ruas, calçadas, quadras, prédios com telhado, praças,
  palmeiras, quiosques.
- Streaming de setores em `WorkerThreadPool`: só arrays na thread, a malha é
  criada na thread principal, 2 setores por frame.
- Protagonista de modelo: o mesmo corpo CC0 da Quaternius que roda nos
  pedestres, pintado por vértice (homem branco, de cabelo preto, 1,80 m,
  camiseta laranja e jeans), com as animações de parado/andar/correr/pular que
  vêm dentro do arquivo. O corpo tem a cabeça lisa, então o **rosto é uma cabeça
  3D de verdade** (escaneada por Lee Perry-Smith, CC-BY 3.0 — crédito em
  [data/ATTRIBUTION.md](data/ATTRIBUTION.md)), escalada pela altura do
  personagem, com uma calota de **cabelo preto** por cima do crânio (a cabeça
  escaneada é careca). Se o modelo não carregar, volta para o boneco de caixas —
  o jogo nunca fica sem personagem.
- Personagem em terceira pessoa com câmera orbital, colisão por retângulos e
  chão analítico (sem corpos físicos estáticos).
- Controles de toque: joystick na esquerda, arrasto para olhar na direita,
  botões PULAR e CORRER.
- Céu e luz do Rio: o sol percorre um arco de azimute carioca (nasce no mar,
  se põe sobre o continente) e o céu passa pelos quatro momentos da cidade —
  meio-dia tropical, hora dourada com o zênite ainda azul, hora azul e noite
  com brilho de cidade no horizonte. Nevoeiro copia a cor do horizonte e
  engrossa de madrugada.
- Fase 1.5 visual: mar com ondas (mapa de normais gerado em código, animado),
  glow + tonemap ACES, sombra de contato, fachadas que acendem à noite, postes,
  bancos, lixeiras e carros estacionados (plano completo em
  docs/DETALHES_VISUAIS.md).
- **Modelos do mundo com geometria de verdade** (B-80/B-81): os props deixaram
  de ser cubos de `MultiMesh` e passaram a ter malha própria, gerada por código
  em `scripts/world/prop_mesh.gd`. O B-81 é a segunda passada, no pedido
  "melhore os gráficos e use modelos melhores para o mundo":
  - **palmeira** com tronco de cinco trechos (anel de resto de folha, colar no
    topo) e coroa de **nove folhas em três trechos** que sobem, abrem e caem na
    ponta, mais o cacho de cocos;
  - **árvore** com copa de **três camadas** (a de baixo escura, a do sol clara);
  - **banco** de ripas com encosto inclinado e estrutura de ferro, **lixeira**
    de oito lados com aro e tampa, **quiosque** com piso, balcão, quatro
    montantes, vitrine de vidro, toldo e placa, **guarda-sol** com duas abas
    (a de fora maior) e varas por baixo;
  - **carro parado** com soleira, capô, porta-malas, cabine de vidro, teto,
    para-brisa e vidro traseiro inclinados, grade, faróis, lanternas e rodas
    de oito lados com calota;
  - **cinco tipos novos**: canteiro de calçada, pedra da arrebentação, placa de
    nome de rua, hidrante e cadeira de praia;
  - **oclusão ambiente assada na cor do vértice** (`PropMesh.ao_shade`): a base
    de todo prop escurece perto do chão, sem textura e sem custo de pixel.

  Tudo é gerado **dentro da worker thread** junto com o setor (a malha de cada
  tipo é construída uma vez e instanciada por transformação), então continua
  sendo 1 chamada de desenho por setor.
- **Fachada de Ipanema** (B-81): o prédio ganhou **varandas** (laje + guarda-
  corpo na face que olha para a rua, a cada dois andares) e **embasamento de
  pedra** no pé, ambos no buffer de cor por vértice — nenhum desenho novo, e
  nada disso existe no LOD distante.
- **Calçada e praia habitadas** (B-81): canteiro, hidrante e placa de rua nas
  quadras, palmeiras de alturas diferentes, pedras na arrebentação e cadeiras
  de praia na sombra dos guarda-sóis.
- **Piso com relevo** (B-81): um mapa de normais de grão gerado em código no
  `sector_streamer.gd` dá relevo a asfalto, calçada, areia e calçadão (sem
  normal map fotografado e sem `ShaderMaterial` — a regra do B-25 continua), e
  o material dos props ganhou um *rim light* sutil para a silhueta se ler
  contra o céu. O mar ganhou uma **faixa de espuma** animada na arrebentação e
  o ambiente, um ajuste de contraste e saturação.
- **Rua de verdade** (B-80): platibanda coroando a laje de cada prédio, porta de
  entrada com moldura e vidro na fachada da rua, ar-condicionado de split preso
  na parede, toldo de loja em lona inclinada (não mais um caixote), árvore em
  cada calçada e uma faixa de **areia molhada** com brilho próprio entre a praia
  e o mar.
- Carro dirigível (primeiro incremento da Fase 4): nasce perto do ponto de
  nascimento com um marcador flutuante; entre pelo botão ENTRAR (ou tecla E) e
  dirija com o volante no joystick e os pedais ACEL/FREIO; rodas que giram e
  estercam, carroceria que acompanha o relevo e câmera própria.
- Física automotiva do carro: massa de 1450 kg, curva de torque, câmbio
  automático de 5 marchas, freio com ABS e controle de tração, peso que passa de
  eixo para eixo (o carro mergulha ao frear, levanta ao acelerar e rola para fora
  na curva), arrasto aerodinâmico e aderência por piso — asfalto, areia da praia
  e pedra do calçadão. Em curva rápida o carro **subesterça** em vez de girar no
  próprio eixo, como um carro de verdade. Tem ESP (corta acelerador quando o
  pneu chega no limite lateral) e a batida em parede é **por ângulo**: de frente
  o carro para, raspando ele desliza. O HUD mostra marcha, rotação e
  aderência; o som do motor acompanha o giro. Nada de `RigidBody3D`: a física
  roda sobre o chão analítico, sem nenhuma malha de colisão — é o que cabe no
  iPhone.
- Física do mundo (props e dano): caixas, cadeiras, lixeiras e cones espalhados
  pela rua com massa, impulso, atrito por piso, quique e sono automático. Você
  empurra andando e o carro atropela — o que passa da resistência do material
  (vidro, plástico, madeira, metal) quebra em destroços, com teto de fragmentos.
  O carro acumula avaria: batida tira potência do motor e, acima de 35%, ele puxa
  o volante; o HUD mostra `avaria N%`. Onze superfícies (asfalto, concreto, pedra,
  areia, terra, grama, lama, madeira, metal, vidro, água) com atrito próprio para
  pneu e para objeto. Tudo sobre o chão analítico, com LOD de 35/100 m, sono e
  3 desenhos no total ([docs/FISICA.md](docs/FISICA.md)).
- Tráfego: 12 carros de passeio (4 modelos CC0) pela grade de ruas, um desenho
  por modelo. Cada modelo tem **ficha própria**: o SUV freia antes e faz a
  esquina mais devagar, o esportivo anda mais — a velocidade não é mais
  instantânea, o carro acelera e freia pela ficha dele. Eles colidem com o seu
  carro, mantêm distância entre si e
  acompanham você pela cidade. O carro que você dirige é o sedã CC0, com rodas
  que giram e esterçam. As ruas têm sinalização pintada: eixo amarelo, faixa de
  pedestres e linha de retenção.
- Pedestres com rotina: pessoas andando na calçada em volta das quadras e na
  praia, com modelo de verdade — corpos adultos da Quaternius (CC0), homens e
  mulheres (7 corpos: casual, casual 2, worker, beach, suit, mulher casual e
  mulher formal), e as
  animações de andar/parar/correr. Um corpo só entra na rua se o CI provar que a
  animação mexe o esqueleto dele (mede o giro dos ossos, não só "o clipe toca"),
  e o corpo que traz as animações no próprio arquivo entra sempre, então não
  existe mais pedestre em T-pose deslizando. Cada um tem destino,
  pressa e tom próprios, para no canto, espera o sinal abrir para atravessar (a
  mesma fase dos semáforos dos carros), desiste e segue se demorar, sai da sua
  frente quando você chega perto e corre se um carro aparece em cima dele na
  travessia. À noite a rua esvazia. Sem os modelos, o jogo volta sozinho para
  bonecos de caixa (3 desenhos para todos).
- Semáforos: quatro postes por cruzamento com ciclo verde/amarelo/vermelho
  defasado; os carros param na linha de retenção e atravessam no verde. A
  cidade inteira de semáforos custa 2 desenhos por quadro.
- Lojas com interior: prédios baixos virados para a calçada ganham uma loja no
  térreo — o vão entra até 4,5 m para dentro do prédio, com piso, forro, paredes,
  balcão, prateleira, produtos e uma placa colorida (padaria, farmácia, bar,
  loja, mercado). Os colisores deixam o vão aberto, então **você entra andando**
  e não atravessa parede. Dentro de uma loja há **balconista** (NPC parado atrás
  do balcão, olhando para a rua) e, ao entrar, o HUD diz o **nome do comércio**.
  Custo: geometria no mesmo desenho do setor (nenhuma chamada nova), e a loja só
  existe no LOD detalhado — de longe o prédio fica fechado.
- Calçada com meio-fio: o miolo da quadra fica 15 cm acima da rua, e o chão de
  quem anda acompanha (personagem e carro sobem no meio-fio).
- Texturas no chão: asfalto, calçada, areia e o calçadão de pedra portuguesa
  (CC0), em escala de mundo (repetem por metro).
- Fachada de prédio: textura fotografada de janelas (Keith333, CC-BY 3.0,
  8 janelas × 4 andares num módulo de 22,9 × 12 m), tingida pela paleta de cada
  prédio e com a própria foto como mapa de emissão à noite.
- Som: motor sintetizado em código que sobe de tom com o giro, ruído de cidade
  ao fundo e impacto CC0 nas batidas (o Safari só libera áudio depois do
  primeiro toque na tela).
- Botão MEDIR no HUD: 15 s sem o limite de 30 FPS, com média, p95 e pior frame
  na telemetria — é assim que o FPS real é medido no aparelho.
- Piloto de asset externo: um modelo .glb CC0 (Kenney) carregado e normalizado
  por código (escala, eixo e apoio no chão), com o import verificado no CI.
- Caderno de estilo visual ([docs/ESTILO.md](docs/ESTILO.md)): premissa de
  realismo máximo dentro do orçamento do iPhone (geografia e sinalização reais,
  forma low-poly), paleta do Rio, regras de render.
- HUD com telemetria e gravador de desempenho em CSV.
- Salvamento versionado (`schema`, sha256, gzip, escrita atômica, recusa de
  versão futura e de arquivo corrompido).
- Polígono do mundo em GeoJSON e ferramenta Python que mede a área
  (`--strict` só quando o polígono real entrar, na Fase 2: hoje é rascunho).
- Build Web publica no GitHub Pages com um painel de console verde embutido
  (temporário): é por ele que se lê, no próprio iPhone, qualquer erro de
  script que o Safari esconde.

## Como testar

Guia completo, com os três caminhos (editor no computador, build Web no Safari do
iPhone via GitHub Pages, e só os testes automáticos): **[docs/TESTAR.md](docs/TESTAR.md)**.

Resumo:

- **Melhor:** instalar o Godot 4.4.x, abrir esta pasta e apertar F5.
- **Sem computador:** publicar no GitHub e deixar o workflow `web.yml` gerar o
  build Web no GitHub Pages (joga no Safari do iPhone).
- **Só o código:** `godot --headless --path . -s tests/runner.gd` ou a aba
  Actions do repositório.

O `index.html` da raiz é apenas uma página de apresentação (o Godot não gera
site): o jogo no navegador é o build publicado pelo GitHub Pages.

Medir a área do polígono:

```
python3 tools/geo/polygon_area.py
```

O conjunto de testes roda no GitHub Actions em cada push
(`.github/workflows/tests.yml`).

## Exportar para iPhone (Fase 9)

Requer **Mac com Xcode**. Não é possível gerar um `.ipa` assinado a partir do
iPhone nem do Linux. O preset `iOS` já está em `export_presets.cfg`
(bundle `com.krr18.carioca`, iOS 13, `team_id` em branco — preencha com o seu).
Passo a passo completo em [docs/EXPORTACAO_IOS.md](docs/EXPORTACAO_IOS.md).

## Documentos

- [docs/STATUS.md](docs/STATUS.md) — sistemas, bugs conhecidos, próximas tarefas.
- [docs/GTA.md](docs/GTA.md) — a camada de jogo: procurado, polícia, missões,
  combate, roubo de carro, radar e HUD (com a tabela de números para ajustar).
- [docs/TESTAR.md](docs/TESTAR.md) — como rodar e testar, com e sem computador.
- [docs/AUDITORIA.md](docs/AUDITORIA.md) — diagnóstico do que foi encontrado.
- [docs/ARQUITETURA.md](docs/ARQUITETURA.md) — decisões técnicas e por quê.
- [docs/FISICA.md](docs/FISICA.md) — auditoria da física, o que foi implementado,
  limites e o que falta (ragdoll, capotamento, dano estrutural).
- [docs/ESTILO.md](docs/ESTILO.md) — caderno de estilo visual (paleta, render, animação).
- [docs/ROADMAP.md](docs/ROADMAP.md) — as 9 fases com critério de saída.
- [docs/DETALHES_VISUAIS.md](docs/DETALHES_VISUAIS.md) — pesquisa e plano de
  detalhes visuais (modelos, texturas e técnicas CC0).
- [docs/OTIMIZACAO_IPHONE12.md](docs/OTIMIZACAO_IPHONE12.md) — medidas e metas.
- [docs/PIPELINE_DADOS.md](docs/PIPELINE_DADOS.md) — como o Rio real vira dado.
- [data/ATTRIBUTION.md](data/ATTRIBUTION.md) — licenças de dados.

## Licença

A definir pelo autor (ver `LICENSE`). Dados de mapa: © colaboradores do
OpenStreetMap, ODbL.
