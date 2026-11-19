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

## Como rodar (primeira vez)

1. Instale o **Godot 4.4.1** (ou 4.4.x) — godotengine.org.
2. Abra a pasta do projeto no Godot (ele importa o `icon.svg` sozinho).
3. Aperte **F5** (Play). No desktop, WASD move, mouse com botão esquerdo
   arrastado gira a câmera, espaço pula.

Linha de comando equivalente:

```
godot --path . 
```

## Como testar

Testes headless (não precisam de GPU):

```
godot --headless --path . -s tests/runner.gd
```

Medir a área do polígono:

```
python3 tools/geo/polygon_area.py
```

O mesmo conjunto roda no GitHub Actions em cada push (`.github/workflows/tests.yml`).

## Exportar para iPhone (Fase 9)

Requer **Mac com Xcode**. Não é possível gerar um `.ipa` assinado a partir do
iPhone nem do Linux. O preset `iOS` já está em `export_presets.cfg`
(bundle `com.krr18.carioca`, iOS 13, `team_id` em branco — preencha com o seu).
Passo a passo completo em [docs/EXPORTACAO_IOS.md](docs/EXPORTACAO_IOS.md).

## Documentos

- [docs/STATUS.md](docs/STATUS.md) — sistemas, bugs conhecidos, próximas tarefas.
- [docs/AUDITORIA.md](docs/AUDITORIA.md) — diagnóstico do que foi encontrado.
- [docs/ARQUITETURA.md](docs/ARQUITETURA.md) — decisões técnicas e por quê.
- [docs/ROADMAP.md](docs/ROADMAP.md) — as 9 fases com critério de saída.
- [docs/OTIMIZACAO_IPHONE12.md](docs/OTIMIZACAO_IPHONE12.md) — medidas e metas.
- [docs/PIPELINE_DADOS.md](docs/PIPELINE_DADOS.md) — como o Rio real vira dado.
- [data/ATTRIBUTION.md](data/ATTRIBUTION.md) — licenças de dados.

## Licença

A definir pelo autor (ver `LICENSE`). Dados de mapa: © colaboradores do
OpenStreetMap, ODbL.
