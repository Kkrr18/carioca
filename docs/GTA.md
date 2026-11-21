# CARIOCA — a camada de GTA

Este documento descreve o que transforma o mundo aberto do CARIOCA num jogo de
ação: **procurado (estrelas), perseguição policial, missões, combate, roubo de
carro, radar e HUD**. É a camada que o jogador chama de "GTA" — não é o mapa,
nem os modelos: é o ciclo de jogo em cima deles.

Estado: **implementado e sem medição no aparelho**. Os sistemas estão ligados no
`main.gd`, os testes puros rodam no CI, e nada aqui foi visto rodando num
iPhone. Ver "O que ainda não existe", no fim.

## O ciclo

1. O jogador entra no marcador amarelo do Posto 9 e a missão começa.
2. Uma missão é uma lista de passos: chegar (`goto`), ouvir (`say`), esperar
   (`wait`), aguentar (`survive`). Alguns passos **acendem a polícia**.
3. Com estrelas acesas, viaturas nascem em volta e perseguem. Quanto mais
   estrelas, mais viaturas e mais rápido.
4. A pé, perto de uma viatura por 2,5 s, você é **preso** (BUSTED). Com a vida
   em zero, é **WASTED**. Os dois custam dinheiro e voltam você para um ponto
   fixo: delegacia ou hospital.
5. Fora do campo de visão da polícia o calor esfria e as estrelas apagam.
6. Missão cumprida, o dinheiro cai na conta e o marcador pula para a próxima.

## Arquivos

- `scripts/game/wanted.gd` — **puro**. Calor (0 a 5), estrelas, tabela de
  crimes, esfriamento, número e velocidade das viaturas, multa de prisão.
- `scripts/world/police.gd` — viaturas: nascimento, perseguição, batida,
  tiro, prisão. Malha assada (1 desenho) + duas lentes piscando.
- `scripts/game/missions.gd` — **puro**. O roteiro: 4 missões encadeadas, com
  texto, pontos do bairro e recompensa.
- `scripts/game/mission_runner.gd` — executa o roteiro na cena: marcador,
  chegada, falas, recompensa.
- `scripts/game/ipanema.gd` — **puro**. Ruas e pontos do bairro pregados na
  grade de 64 m do `city_gen`; dá o texto de localização do HUD.
- `scripts/ui/radar.gd` — minimapa circular com mar, areia, ruas, blips.
- `scripts/ui/gta_hud.gd` — dinheiro, vida, colete, estrelas, arma, missão,
  legenda, nome da rua e a tela de WASTED/BUSTED.
- `scripts/player/player.gd` — vida, colete, dinheiro, armas, dano, mira.
- `scripts/world/traffic.gd` — `car_near()` / `take_car()`: roubo de carro.
- `scripts/vehicles/car.gd` — `set_vehicle()`: troca modelo e ficha ao tomar
  outro carro.

## Números (onde mexer)

| O quê | Onde | Valor |
|---|---|---|
| Calor de cada crime | `wanted.gd` `CRIMES` | 1,0 a 3,0 |
| Esfriamento por segundo | `wanted.gd` `DECAY_FAST/SLOW` | 0,085 a 0,030 |
| Viaturas por estrela | `wanted.gd` `cop_count` | até 5 |
| Velocidade da viatura | `wanted.gd` `cop_speed` | 19 a 31 m/s |
| Alcance do tiro da polícia | `police.gd` `SHOOT_RANGE` | 30 m |
| Tempo para ser preso | `wanted.gd` `arrest_seconds` | 2,5 s |
| Multa de prisão | `wanted.gd` `busted_fine` | 20% |
| Raio do radar | `radar.gd` `MAP_METERS` | 165 m |
| Ponto de partida das missões | `missions.gd` `LIST` | Posto 9, ... |

## Regras que valem a pena lembrar

- **Nada de física nova.** A viatura anda sobre o mesmo chão analítico
  (`Cfg.surface_at`) e desvia de prédio pelo `push_out` do streamer. Não existe
  corpo de física no mundo e não vai existir.
- **Custo de desenho**: a viatura é uma malha só (cor por vértice) + 2 lentes
  com material compartilhado. Cinco viaturas = 15 desenhos.
- **Carro tomado** some da rua sem mexer no `instance_count` do MultiMesh
  (escala zero); voltar a mexer nesse número entre quadros estoura índice.
- **A telemetria** (`hud.gd`) começa escondida. O botão `DEV`, no rodapé,
  mostra/esconde — é por ela que se mede FPS no iPhone.
- **Salvamento**: dinheiro, vida, colete, arma e munição entram no `player.state()`
  como campos opcionais (save antigo continua valendo; schema segue 1).

## O que ainda NÃO existe

- **Som de tiro, sirene e motosserra**: nenhum áudio novo. O motor e o impacto
  continuam sendo os únicos sons.
- **Pedestre reagindo a tiro**: os pedestres desviam e correm de carro, mas não
  existe "pânico de tiro" nem atropelamento contado como crime.
- **Combate contra pedestre**: o alvo do combate é a viatura. Mirar em pedestre
  não faz nada (os pedestres são MultiMesh, sem alvo por indivíduo).
- **Roubo de carro em movimento**: só com o carro de rua praticamente parado e o
  jogador a pé perto dele.
- **Medição no aparelho**: o custo das viaturas, do radar e das barras no iPhone
  ainda não foi medido. O radar desenha ~1 círculo, ~15 linhas e ~6 blips por
  quadro; o HUD, ~10 retângulos e 5 estrelas.
