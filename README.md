# CARIOCA

Jogo 3D de mundo aberto inspirado no Rio de Janeiro e em Niterói.
Godot 4.4 · GDScript · alvo iPhone 12 · custo zero (OpenStreetMap, DEM público,
Python e Blender).

Estado: **Fase 1 (Fundação)** — em andamento. Fundação jogável validada no
Safari de um iPhone (jogo carrega, anda, pula e salva), via build Web no
GitHub Pages. Meta de 30 FPS e app nativo iOS ainda NÃO medidos/gerados.
Leia [docs/STATUS.md](docs/STATUS.md) antes de acreditar em qualquer coisa aqui.

## O que já existe

- Projeto Godot 4.4 configurado (renderer *Compatibility*, sem dependências
  externas).
- Geração procedural determinística de cidade por setor de 512 m: terreno,
  avenida da orla, ruas, calçadas, quadras, prédios com telhado, praças,
  palmeiras, quiosques.
- Streaming de setores em `WorkerThreadPool`: só arrays na thread, a malha é
  criada na thread principal, 2 setores por frame.
- Personagem em terceira pessoa com câmera orbital, colisão por retângulos e
  chão analítico (sem corpos físicos estáticos).
- Controles de toque: joystick na esquerda, arrasto para olhar na direita,
  botões PULAR e CORRER.
- Céu e luz do Rio: o sol percorre um arco de azimute carioca (nasce no mar,
  se põe sobre o continente) e o céu passa pelos quatro momentos da cidade —
  meio-dia tropical, hora dourada com o zênite ainda azul, hora azul e noite
  com brilho de cidade no horizonte. Nevoeiro copia a cor do horizonte e
  engrossa de madrugada.
- Fase 1.5 visual: água com ondas/fresnel, glow + tonemap ACES, sombra de
  contato, fachadas de vidro que acendem à noite, postes, bancos, lixeiras
  e carros estacionados (plano completo em docs/DETALHES_VISUAIS.md).
- Carro dirigível (primeiro incremento da Fase 4): nasce perto do ponto de
  nascimento com um marcador flutuante; entre pelo botão ENTRAR (ou tecla E) e
  dirija com o volante no joystick e os pedais ACEL/FREIO; direção cinemática
  estável, rodas que giram e estercam, carroceria que acompanha o relevo e
  câmera própria.
- Tráfego: 12 carros de passeio (4 modelos CC0) pela grade de ruas, um desenho
  por modelo. Eles colidem com o seu carro, mantêm distância entre si e
  acompanham você pela cidade. O carro que você dirige é o sedã CC0, com rodas
  que giram e esterçam. As ruas têm sinalização pintada: eixo amarelo, faixa de
  pedestres e linha de retenção.
- Pedestres com rotina: 28 pessoas andando na calçada em volta das quadras e na
  praia. Cada uma tem destino, pressa e roupa próprios, para no canto, espera o
  sinal abrir para atravessar (a mesma fase dos semáforos dos carros), desiste e
  segue se demorar, sai da sua frente quando você chega perto e corre se um carro
  aparece em cima dela na travessia. À noite a rua esvazia. Custo: 3 desenhos
  por quadro para a cidade inteira (3 MultiMesh), com as pernas balançando de
  verdade porque cada perna é uma instância girada no quadril.
- Semáforos: quatro postes por cruzamento com ciclo verde/amarelo/vermelho
  defasado; os carros param na linha de retenção e atravessam no verde. A
  cidade inteira de semáforos custa 2 desenhos por quadro.
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
- [docs/TESTAR.md](docs/TESTAR.md) — como rodar e testar, com e sem computador.
- [docs/AUDITORIA.md](docs/AUDITORIA.md) — diagnóstico do que foi encontrado.
- [docs/ARQUITETURA.md](docs/ARQUITETURA.md) — decisões técnicas e por quê.
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
