# Auditoria do projeto (início da Fase 1)

Data da auditoria: primeiro contato com o repositório.

## O que foi encontrado

- O repositório `Kkrr18/carioca` está **vazio**: sem código, sem assets, sem
  histórico. `git status` mostra "No commits yet" na branch `main`.
- Nada de dependências, build, testes ou CI preexistentes.
- Não há README, licença ou `.gitignore` (criados nesta entrega).

## Pasta "Carioca" antiga

- Existe na lista de projetos do dispositivo uma pasta `Carioca` (pasta comum,
  não repositório).
- **Ela não está acessível a esta conversa** (o acesso foi negado) e, conforme o
  pedido, **não foi usada como base**. Nada desta entrega deriva dela.
- Se o conteúdo dela deve entrar no projeto, é preciso liberar o acesso e
  decidir o que aproveitar; hoje ela não influencia nenhuma linha de código.

## Referências geográficas usadas

Não havia dados no repositório. Para não inventar coordenadas, foram levantados
pontos reais:

- Ponte Rio–Niterói: início no Caju (-22.88464, -43.21671), extremidade sobre a
  água junto à Ilha da Conceição (-22.87278, -43.13637), praça de pedágio
  (-22.87792, -43.11574). O eixo não é reto: sobe ~3 km para nordeste saindo do
  Caju, cruza a baía a leste e desce junto à Ilha da Conceição.
- Praias (meio da faixa): Ipanema (-22.98706, -43.20480), Leblon (-22.98789,
  -43.22137), Copacabana (-22.97569, -43.18100), Botafogo (-22.94540,
  -43.17992), Flamengo (-22.92800, -43.16965).
- Niterói: Icaraí (-22.90888, -43.11386), Itacoatiara (-22.97487, -43.03439),
  Camboinhas (-22.96308, -43.05813), Itaipu (-22.97070, -43.04657).
- Distâncias conferidas: Ipanema → margem de Niterói, ~10,7 km (Jurujuba) e
  ~12,8 km (Icaraí).

Fonte: dados do OpenStreetMap consultados via Nominatim/Overpass, com conferência
visual em mapa. Licença e atribuição em `data/ATTRIBUTION.md`.

## Consequências para o primeiro dia

1. Não havia nada a "consertar": toda a estrutura é nova (ver ARQUITETURA).
2. A única base confiável de geografia era a consulta acima, então o relevo da
   Fase 1 é analítico e o litoral é uma reta idealizada. O Rio real entra na
   Fase 2 pelo pipeline de dados.
3. Nenhuma promessa de desempenho é possível antes do primeiro build no
   aparelho. Ver `docs/OTIMIZACAO_IPHONE12.md`.

## Riscos identificados

- **Godot não roda neste dispositivo.** O código só é validado no CI ou no
  computador do usuário; o primeiro contato com o motor deve mesmo gerar
  correções.
- **iOS exige Mac + Xcode.** Sem isso, não há `.ipa`. É a Fase 9.
- **Streaming em GDScript** é a maior incerteza de desempenho no iPhone 12. Se a
  geração de setor passar do orçamento por frame, o próximo passo é gerar os
  setores em Python/Blender e só carregar arquivos no jogo.
