# Exportação para iOS

Requisitos, sem exceção:

- **Mac** com macOS 12 ou mais novo.
- **Xcode** (versão aceita pela App Store no momento do build) com as Command
  Line Tools instaladas.
- **Conta Apple Developer** (a gratuita serve para instalar no seu próprio
  iPhone por 7 dias; a paga, US$ 99/ano, é necessária para distribuir).
- **Godot 4.4.x com templates de exportação iOS** instalados
  (Editor → Gerenciar Modelos de Exportação).
- iPhone 12 com iOS atualizado, confiando no computador.

Não é possível gerar um `.ipa` assinado a partir deste dispositivo (iPhone) nem
de um runner Linux. O CI deste repositório só roda os testes headless.

## Passo a passo

1. Abra o projeto no Godot (no Mac) e deixe importar.
2. Editor → Gerenciar Modelos de Exportação → baixar o modelo **iOS**.
3. Projeto → Exportar → preset **iOS**:
   - `application/app_store_team_id`: seu Team ID (Apple Developer).
   - `application/bundle_identifier`: `com.krr18.carioca` (ou o seu).
   - `application/min_ios_version`: 13.0 (padrão do preset).
   - Marcar `user_data/accessible_from_files_app` se quiser tirar os CSV de
     desempenho pelo app Arquivos.
4. Exportar para `build/ios/` — o Godot gera um projeto Xcode.
5. Abrir o `.xcodeproj` no Xcode, escolher o seu iPhone como destino e rodar.
   Na primeira vez, ajuste *Signing & Capabilities* com o seu time.
6. Para instalar em outro aparelho ou distribuir: arquivar (`Product → Archive`)
   e seguir pela App Store Connect.

## O que ainda falta neste projeto para a Fase 9

- Ícone em todos os tamanhos (hoje há um `icon.svg` de 128 px; o exportador usa
  padrões).
- Tela de lançamento.
- Build de *release* medido no aparelho (Fase 8).
- Capabilities declaradas: nenhuma permissão de privacidade está sendo usada
  hoje; se entrar localização, adicionar a descrição de uso no plist.

## Limitações conhecidas do preset atual

- `export_presets.cfg` foi escrito à mão; a Godot pode renomear chaves ao
  regravar o arquivo. Confira o painel de exportação antes do primeiro build.
- `export_filter` está em `all_resources` com exclusão de `tools/`, `docs/`,
  `tests/` e `data/osm/` — ajuste se os dados passarem a ser carregados do
  projeto em vez de baixados.
