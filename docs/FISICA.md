# CARIOCA - fisica do mundo (auditoria e o que foi implementado)

Este documento responde a especificacao "Realistic World Physics 2.0" aplicada a
ESTE projeto. Ele diz o que ja existia, o que entrou agora (B-69), o que foi
adaptado e por que, e o que falta. A regra do projeto continua valendo: nada aqui
foi medido no iPhone ainda, e o CI nunca prova "sensacao" — so medida e numero.

## 1. Auditoria (o que o projeto ja tinha)

- **Godot 4.4**, renderer `gl_compatibility`, alvo iPhone 12 via Web
  (GitHub Pages). Sem dependencia externa, sem plugin.
- **Mundo sem corpos de fisica**, de proposito (docs/ARQUITETURA.md): o chao e
  ANALITICO (`Cfg.height_at`, `Cfg.curb_at`, `Cfg.surface_at`) e predio e uma
  lista de retangulos por setor, resolvida por `SectorStreamer.push_out`. Nao
  existe malha de colisao em nenhum setor carregado.
- **Veiculo do jogador**: `scripts/vehicles/car.gd` + `vehicle_physics.gd`
  (B-67/B-68). Massa, curva de torque, cambio automatico de 5 marchas, ABS/TCS
  pelo circulo de aderencia, transferencia de peso, arrasto, rolamento, declive,
  aderencia por piso, subesterco no limite lateral, carroceria que mergulha/rola.
- **Transito**: `traffic.gd`, 12 carros CINEMATICOS (intencional).
- **Personagens**: `player.gd` (CharacterBody3D-like por codigo, chao analitico)
  e `pedestrians.gd` (MultiMesh + clipes do walker CC0, queda procedural por
  atropelamento, balconistas, panico na travessia).
- **Cidade**: `city_gen.gd` gera tudo em buffers de vertice (cor por vertice) por
  setor, dois LODs; `sector_streamer.gd` faz streaming em thread.
- **Sem conflito de scripts**: nenhum sistema disputava o mesmo no. O unico
  numero DUPLICADO era a aderencia por piso (estava dentro de
  `vehicle_physics.gd`) — foi unificada nesta rodada.

Consequencia direta para a especificacao: `RigidBody3D`, `StaticBody3D`,
`CharacterBody3D`, `Area3D`, `CollisionShape3D`, `Joint3D` e
`PhysicalBoneSimulator3D` so funcionam sobre geometria de colisao. Dar colisao
aos 9 setores de 512 m (ou a um heightfield de 6 x 3 km) custa memoria e CPU que
o iPhone 12 nao tem e quebraria a premissa "realismo maximo DENTRO do
orcamento". Entao a fisica foi implementada como MODULOS PUROS sobre o chao
analitico, com as mesmas grandezas (massa, impulso, atrito, restituicao,
resistencia de material). Isso mantem UMA representacao do mundo (nao duas que
podem divergir) e e testavel no CI.

## 2. O que foi implementado agora (B-69)

### `scripts/core/surface_db.gd` — banco de superficies
11 superficies: asfalto, concreto, pedra (calcadao), areia, terra, grama, lama,
madeira, metal, vidro, agua. Cada uma com duas colunas de atrito — `mu` (pneu) e
`slide` (objeto deslizando) —, restituicao (`bounce`), resistencia (`hardness`),
cor de poeira (`dust`) e etiqueta de som (`sound`). `kind_at(x, z)` usa a MESMA
divisao do `city_gen` (mar, praia, calcadao 111..127 m, rua vs calcada pelo
`Cfg.curb_at`). O carro passou a ler daqui: `VehiclePhysics.surface_mu` agora e
uma linha delegando. **Uma fonte so, sem numero duplicado.**

### `scripts/physics/prop_body.gd` — objeto movel (puro)
Estado em dicionario (posicao, velocidade, giro, massa, material, vida, sono) e
`step()` com gravidade 9,81, contato com o chao analitico, quique, atrito do
piso, arrasto do ar, giro ao ser jogado, SONO automatico e `impulse()` (N.s
dividido pela massa = variacao de velocidade). Tipos: caixa (14 kg, madeira),
cadeira (6 kg), lixeira (22 kg, metal), cone (3 kg, plastico) e destroco.

### `scripts/physics/damage.gd` — dano em 3 estados (puro)
INTACTO -> DANIFICADO -> DESTRUIDO pela fracao de vida que sobrou, com
resistencia por material (vidro 400 N.s, plastico 900, madeira 2200, metal 9000,
pedra 22000, concreto 45000), contagem de fragmentos por material, e a avaria do
carro (`power_scale`, `state_from_damage`, `dent`).

### `scripts/physics/prop_field.gd` — o sistema no mundo (Node3D)
- 20 objetos em volta do jogador, reciclados quando ficam a mais de 150 m.
- **Atropelamento**: o carro empurra com ~1,15x a velocidade dele, causa dano
  pelo impulso (massa 1450) e o objeto que passa da resistencia vira destrocos.
  O carro tambem leva arranhao (massa do objeto x 0,0015).
- **Empurrao a pe**: a velocidade do personagem vem da variacao de posicao do
  foco (nao depende do interno do player); empurra caixa e derruba cone, nao
  arremessa lixeira.
- **Parede**: `push_out` do streamer, o mesmo do carro e do personagem.
- **Destrocos**: no maximo 30, com vida de 8..13 s; o objeto destruido sai da
  lista e a rua repoe outro perto do jogador.
- **LOD em 3 faixas**: < 35 m fisica a 60 Hz; 35..100 m a 20 Hz com o tempo real
  acumulado (mesma trajetoria, menos chamadas); > 100 m nao integra, mas o
  dicionario guarda posicao, velocidade e giro — ao voltar, continua de onde
  parou (nada e "congelado no meio do voo" perdendo estado).
- **Custo de desenho**: 3 MultiMesh (cubo, cilindro, cone) com cor por instancia
  (tipo + avaria). Nenhuma chamada por objeto.
- **Som**: sinal `bumped(strength, surface)` ligado ao `impact.wav` CC0 que o jogo
  ja usava, com espera de 0,12 s para nao virar metralhadora.

### Carro (`car.gd`) e HUD
`damage` (0..1) + `damage_state` + `add_damage()`; entra dano por batida no
transito, em predio e em objeto; a avaria tira potencia do motor (passa pelo
`power` do `step()`) e, acima de 35%, o volante puxa para a direita. O HUD ganhou
a linha `avaria N% (intacto/danificado/destruido)`.

### `scripts/main.gd`
Monta o `PropField` depois dos pedestres, alimenta com `delta`/`focus` (jogador
ou carro) e liga o som. A telemetria mostra `props N (N acordados) + N destrocos
LOD 35/100 m`.

## 3. Mapa da especificacao

| Secao | Situacao |
|---|---|
| 1 Auditoria | Feita (este documento). |
| 2 Fisica global (9,81, 60 Hz) | Gravidade 9,81 nos modulos; `physics_ticks_per_second=60` ja no project.godot. Sem RigidBody3D: nao ha corpo para gravidade global, e nada recebe gravidade duas vezes. |
| 3 Colisoes universais | Adaptado: carro/predio/objetos pelo chao analitico + `push_out`. Nao ha carros, motos, caminhoes ou caixas como corpos fisicos — sao desenho e estado. Layers/masks nao se aplicam enquanto nao houver PhysicsServer em uso (tabela proposta na secao 5). |
| 4 Fisica veicular | Feito nas B-67/B-68/B-70: massa, transferencia de peso, mu por piso, FWD/RWD/AWD (presets), ABS, TCS, **ESP** (corta acelerador no limite lateral), cambio, curva de torque, arrasto, frenagem, e **impacto em parede por angulo** (de frente para, raspando desliza). O transito ganhou FICHA por modelo (B-70): SUV freia antes, faz a esquina mais devagar e o esportivo anda mais. **Falta**: capotamento (precisa de corpo com 3 eixos), dano visual por peca, moto e caminhao. |
| 5 Personagens/pedestres | Parcial: colisao com o mundo, empurrao de objetos e queda por atropelamento (B-64) existem. **Ragdoll fisico nao**: exige `PhysicalBoneSimulator3D` com ossos fisicos autorados no `.glb`; o walker CC0 nao tem. Ver limites. |
| 6 Destruicao | 3 estados e destrocos com teto para objetos moveis e para o carro. Vidro/para-choque/porta/retrovisor como pecas separadas precisam de malhas separadas (nao existem). Predio NAO e destrutivel: precisa de dano estrutural por seccao. |
| 7 Ambiente interativo | Caixas, cadeiras, lixeiras e cones: empurrar, tombar, rolar, cair, quebrar. Portas/janelas com `Joint3D` e mesas ainda nao (precisam de modelo e nao ha geometria de colisao para a dobradica). |
| 8 Animacoes fisicas | Rodas girando/estercando, carroceria mergulhando e rolando por aceleracao, queda dos pedestres: feitos por codigo sobre o modelo, sem mexer no corpo da simulacao. |
| 9 Superficies | Feito (11 superficies, 2 atritos, quique, resistencia, cor de poeira, etiqueta de som). |
| 10 Otimizacao iPhone | LOD 35/100 m, sono automatico, pooling/reciclagem, teto de 30 destrocos, 3 desenhos no total, sem PhysicsServer. |
| 11 Organizacao | `scripts/core/surface_db.gd`, `scripts/physics/{prop_body,damage,prop_field}.gd` (a pasta sugerida `res://physics/` virou `scripts/physics/` para seguir a convencao do projeto, e `surface_db` ficou em `scripts/core` porque e tabela pura de dados do mundo). |
| 12 Regras | Tipagem onde importa, comentarios nas partes de fisica, nada de API inventada, nada duplicado, nenhum asset removido. |
| 13 Testes | Ver secao 6. |
| 14 Entrega | Ver secao 7. |

## 4. Animacao, ragdoll e o que exatamente falta

- **Ragdoll**: precisa de um `.glb` com ossos fisicos (`PhysicalBone3D`). O corpo
  atual (`ped-walk.glb`, CC0) tem esqueleto e animacao, nao ossos fisicos. O
  caminho e: importar um corpo com bones fisicos ou autorar os bones no Blender,
  e so entao trocar o controlador por `PhysicalBoneSimulator3D`. Enquanto isso a
  queda e procedural (tomba 90 graus em 0,25 s e levanta), o que ja esta no ar.
- **Vidro, porta, retrovisor, para-choque**: precisam existir como MALHAS
  separadas no modelo do carro. O sedan CC0 e uma malha so. A infraestrutura de
  dano (3 estados + resistencia por material) ja aceita a peca quando ela existir.
- **Capotamento**: sem corpo com 3 eixos, o carro nao tomba; ele inclina (pitch e
  roll) ate o limite do que o chao permite. Fazer capotar de verdade exige um
  corpo rígido com suspensao — decisao de arquitetura que teria de vir junto com
  a malha de colisao do mundo.
- **Portas com dobradica**: `Joint3D` exige dois corpos fisicos. Quando houver
  geometria de colisao local (uma loja, por exemplo), da para fazer porta com
  `HingeJoint3D` so ali, em Area isolada.

## 5. Layers e masks (proposta para quando houver PhysicsServer)

Sem corpo fisico, layer/mask nao filtram nada. Quando entrarem (portas de loja,
props com colisao local), a tabela e: 1 mundo, 2 veiculos, 3 personagens, 4
props, 5 destrocos, 6 areas de gatilho (lojas, som). Carro colide com 1/2/4/5;
personagem com 1/2/4; destroco so com 1/4/5; area nao colide com nada (so emite).

## 6. Testes que o CI roda hoje

`godot --headless --path . -s tests/runner.gd`, entre outros:

- superficies: mar/praia/calcadao/rua/calcada certos, pneu e objeto com atritos
  diferentes, carro lendo do `SurfaceDB`;
- objeto movel: cai e POUSA no chao analitico, DORME parado, impulso acorda e
  vira velocidade, a mesma forca move mais a caixa leve que a lixeira pesada,
  areia para a caixa antes do asfalto;
- dano: 3 estados por vida, carro a 36 km/h quebra madeira, a 7 km/h nao quebra
  metal, pedestre nao quebra vidro, vidro faz mais destrocos que pedra, caixa
  atropelada a 54 km/h vira destroco, avaria total tira mais da metade do motor
  e o carro destruido acelera menos (passa pelo `step()` de verdade).

## 7. Arquivos desta rodada

Criados: `scripts/core/surface_db.gd`, `scripts/physics/damage.gd`,
`scripts/physics/prop_body.gd`, `scripts/physics/prop_field.gd`,
`docs/FISICA.md`.
Modificados: `scripts/vehicles/vehicle_physics.gd` (superficies + `power`),
`scripts/vehicles/car.gd` (avaria), `scripts/ui/hud.gd` (linha de avaria),
`scripts/main.gd` (montagem e quadro), `tests/runner.gd` (testes e lista de
compilacao), `docs/STATUS.md`, `README.md`.

## 8. Como testar no iPhone

1. Recarregue o jogo no Safari (o Pages publica sozinho no push).
2. Ande ate uma caixa ou lixeira e esbarre: ela sai do lugar e tomba.
3. Entre no carro e passe por cima dos cones/caixas: voam, quebram em destrocos e
   o HUD muda para `avaria N%`.
4. Bata de proposito em outro carro ou num predio: a avaria sobe, o motor perde
   forca e, acima de 35%, o carro puxa para a direita.
5. Telemetria: `props N (N acordados) + N destrocos` — se "acordados" ficar alto
   com tudo parado, o sono nao esta pegando.

## 9. Pendencias priorizadas (ordem sugerida)

1. Porta de loja e portas de interior (precisa de malha da porta; a dobradica
   seria por codigo ou `HingeJoint3D` numa Area isolada).
2. Pecas de carro separadas (vidro, retrovisor, para-choque) para dano visual.
3. Ragdoll, quando houver corpo com ossos fisicos.
4. Dano estrutural de predio por seccao (troca de LOD, sem fragmentos).
5. Moto e caminhao no transito com ficha propria (a estrutura de `apply_spec` ja
   aceita qualquer preset; falta o modelo CC0 e a estabilidade de 2 rodas, que
   no modelo bicycle e um caso a parte).

## 10. B-70: ESP, impacto em parede por angulo e ficha no transito

- **ESP** (`VehiclePhysics.esp_throttle`, `esp_active`): quando o pneu esta no
  limite lateral (slip acima de 0,35), o controle corta acelerador para devolver
  aderencia a curva — o pneu dividido entre tracao e curva perde das duas. Freando
  ele nao age. O HUD mostra `ESP` na linha de marcha/aderencia.
- **Parede por angulo** (`VehiclePhysics.wall_hit`): antes, QUALQUER encostao em
  predio zerava a velocidade. Agora o `push_out` devolve a normal da parede e a
  batida e decomposta: de frente o carro quase para e o dano e maior; raspando de
  lado ele desliza, perde so a componente perpendicular e arranha menos. O dano
  acompanha o quanto a batida foi de frente, nao a velocidade crua.
- **Transito com ficha** (`Traffic.apply_spec`, `spec_for_model`, `corner_speed`,
  `brake_of`, `accel_of`, `cruise_speed`): cada modelo da rua (sedan, SUV,
  esportivo, taxi) carrega massa, freio, centro de gravidade e ritmo proprios. O
  SUV freia antes (4,1 m/s2 contra 5,3 do sedan), faz a esquina a 6,3 m/s contra
  8,3 e o esportivo cruza a 10,3 m/s. A velocidade deixa de ser instantanea: o
  carro acelera e freia pela ficha (`v`), entao ele nao "salta" para o cruzeiro
  quando o carro da frente libera. Freia tambem no semaforo fechado (antes ele
  so travava a posicao e seguia em velocidade de cruzeiro, o que dava um arranque
  irreal no verde). Dicionarios sem `v` continuam com o modelo
  antigo, o que mantem os testes de transito existentes intactos.
- **Esportivo** (`VehiclePhysics.sport()`): preset novo (1250 kg, RWD, 260 Nm,
  centro de gravidade 0,45 m), disponivel para o jogador tambem.


