# Como testar o jogo

O CARIOCA é um projeto **Godot**, não um site. Ele não tem `index.html` para
publicar direto: o único jeito de rodar é o próprio motor, no computador, ou um
build exportado por ele.

Existem três caminhos. O A é o melhor; o B é o único que funciona sem computador.

---

## A) No computador, com o editor Godot (recomendado)

Precisa de: Mac (Intel ou Apple Silicon), Windows ou Linux. **Não existe editor
Godot para iPhone.**

1. Baixe o **Godot 4.4.x** em https://godotengine.org/download (é gratuito e não
   precisa instalar nada: é um `.zip`/`.dmg`).
2. Abra o Godot → **Import** → escolha a pasta do projeto (a que tem
   `project.godot`) → **Import & Edit**.
3. Na primeira abertura ele importa o `icon.svg`. Espere até a barra de baixo
   parar.
4. Aperte **F5** (ou o ▶ no canto superior direito).

Controles no desktop:

- **W A S D** — andar (segure **Shift** para correr)
- **Espaço** — pular (segurando, você "flutua": é provisório)
- **Mouse com botão direito arrastado** ou **setas do teclado** — girar a câmera

O que deve acontecer: o personagem aparece na areia, de frente para o mar, com a
cidade atrás; a HUD no canto mostra FPS, draw calls, setores carregados e o
relógio.

Linha de comando, se preferir:

```
godot --path . 
```

### Se der erro ao abrir

Erros de script aparecem no painel **Debugger → Errors**. Como o projeto nunca
foi executado, é esperado encontrar algum. Copie a mensagem e me passe; com o
texto exato eu corrijo.

---

## B) Sem computador: build Web publicado pelo GitHub Actions

Dá para jogar no **Safari do iPhone**, desde que o repositório esteja no GitHub.

1. O projeto precisa ir para o GitHub (hoje ele está só no dispositivo, sem
   remote). Peça o push e eu configuro o remote para `Kkrr18/carioca`.
2. No GitHub, abra **Settings → Pages** e em **Source** escolha
   **GitHub Actions**.
3. O workflow `.github/workflows/web.yml` roda sozinho a cada push na `main`:
   instala o Godot 4.4.1 e os modelos de exportação, exporta para Web e publica.
4. Quando o job **Publicar no Pages** ficar verde, o jogo abre em:
   `https://kkrr18.github.io/carioca/`
   (o endereço exato aparece no resumo do job)
5. No iPhone, abra esse endereço no **Safari**. O joystick fica na metade
   esquerda da tela, o arrasto na direita gira a câmera.

Limitações honestas desse caminho:

- **Nunca foi executado.** O workflow foi escrito agora e pode precisar de
  ajuste no primeiro run.
- No build Web o jogo roda **sem threads** (o export web padrão não tem
  `WorkerThreadPool`); o código detecta isso e gera os setores na thread
  principal, com raio menor. Isso foi previsto, mas não medido.
- Desempenho em Safari/WebGL é pior que no app nativo e não serve como medição
  da meta de 30 FPS. É para ver e jogar, não para avaliar performance.
- iPhone em Safari com 5 abas abertas descarta o jogo (o iOS recarrega a aba).

---

## C) Sem computador e sem querer jogar: só os testes automáticos

Isso valida o código (compila? gera sempre o mesmo mundo? o save corrompido é
recusado? a área do polígono está na faixa?) sem mostrar o jogo.

- **No GitHub:** cada push na `main` roda `.github/workflows/tests.yml`
  (aba **Actions** → job **Godot headless**). Verde = testes passaram.
- **No computador:**
  ```
  godot --headless --path . -s tests/runner.gd
  python3 tools/geo/polygon_area.py
  ```

Saída esperada do runner: uma linha por verificação (`ok` / `FALHA` / `DESVIO`)
e no fim `RESULTADO: N passaram, 0 falharam`. Ele sai com código 1 se algo
falhar.

---

## D) No iPhone como aplicativo (só na Fase 9)

Não é possível hoje: precisa de **Mac + Xcode + conta Apple Developer**. O
passo a passo está em `docs/EXPORTACAO_IOS.md`. Até lá, o teste no aparelho é o
caminho B.

---

## O que olhar em qualquer teste

1. O chão aparece sem buraco ao andar até a esquina? (streaming)
2. O personagem atravessa prédio? (colisão)
3. Dá para entrar no mar? (deve parar no raso)
4. Apertar **SALVAR** e depois **CARREGAR** volta para a mesma posição e hora?
5. **+1h** muda a luz; **PERF** esconde a telemetria.
6. FPS no HUD: é medição de mentira? Não: é só informativo no desktop/Web. A
   meta de 30 FPS só vale medida no iPhone 12 com build de release
   (`docs/OTIMIZACAO_IPHONE12.md`).

Ao encontrar um problema, me diga: o que fez, o que esperava e o que aconteceu
(inclusive a mensagem de erro). Cada um vira item em `docs/STATUS.md`.
