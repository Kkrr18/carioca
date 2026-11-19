# CARIOCA

Jogo 3D de mundo aberto inspirado no Rio de Janeiro e em Niterói.
Godot 4.4 · GDScript · alvo iPhone 12 · custo zero (OpenStreetMap, DEM público,
Python e Blender).

Estado: **Fase 1 (Fundação)** — em andamento, código nunca executado ainda.
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
- Ciclo dia/noite com céu procedural, nevoeiro e dois estados de tempo.
- HUD com telemetria e gravador de desempenho em CSV.
- Salvamento versionado (`schema`, sha256, gzip, escrita atômica, recusa de
  versão futura e de arquivo corrompido).
- Polígono do mundo em GeoJSON e ferramenta Python que mede a área.

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
- [docs/ROADMAP.md](docs/ROADMAP.md) — as 9 fases com critério de saída.
- [docs/OTIMIZACAO_IPHONE12.md](docs/OTIMIZACAO_IPHONE12.md) — medidas e metas.
- [docs/PIPELINE_DADOS.md](docs/PIPELINE_DADOS.md) — como o Rio real vira dado.
- [data/ATTRIBUTION.md](data/ATTRIBUTION.md) — licenças de dados.

## Licença

A definir pelo autor (ver `LICENSE`). Dados de mapa: © colaboradores do
OpenStreetMap, ODbL.
