extends RefCounted
## PropMesh: as malhas LOW-POLY de verdade dos props do mundo (B-80/B-81).
##
## B-80 tirou os props dos cubos do MultiMesh. B-81 e a segunda passada, no
## pedido "melhore os graficos e use modelos melhores para o mundo":
##   - palmeira: tronco em 5 trechos com colar no topo, coroa de 9 folhas em
##     TRES trechos (a folha abre, desce e afina na ponta) e o cacho de cocos;
##   - arvore: copa em tres camadas de cor (a de baixo escura, a do sol clara);
##   - banco: ripas de madeira no assento e no encosto inclinado + estrutura;
##   - lixeira de 8 lados com aro e tampa;
##   - quiosque com piso, balcao, quatro montantes, vidro, toldo e placa;
##   - guarda-sol com DUAS abas (a de fora maior) e varas por baixo;
##   - carro parado: capo, porta-malas, cabine de vidro, teto, para-brisa
##     inclinado, farois, lanternas e rodas com calota;
##   - CINCO tipos novos: canteiro (planta), pedra, placa de rua, hidrante e
##     cadeira de praia.
##
## Regras que valem para tudo aqui:
##   - a BASE do prop fica em y = 0: o chamador so translada e gira;
##   - a frente de uma face e -(b-a)x(d-a) (a convencao do city_gen), por isso
##     tri3()/face4() DEDUZEM a normal do winding e corrigem pela direcao
##     desejada: nao existe face invisivel por winding invertido;
##   - oclusao ambiente assada na COR DO VERTICE (ao_shade): o que esta perto
##     do chao fica mais escuro. E o "AO por vertice" que docs/ESTILO.md pede,
##     sem textura, sem shader e sem custo de pixel;
##   - orcamento: cada prop e visto a dezenas de metros, entao 4 a 8 lados
##     bastam. O setor inteiro fica abaixo do teto de
##     tests/runner.gd (_test_prop_sector_budget, 130k vertices).
##
## Quem chama: CityGen.generate() monta os defs (Dictionary) e depois
## _props_geometry() transforma cada def numa copia da malha do seu tipo. O
## SectorStreamer so recebe arrays prontos.

const PropFactory = preload("res://scripts/world/prop_factory.gd")

const TIRE := Color(0.078, 0.078, 0.088)
const HUB := Color(0.58, 0.59, 0.61)
const GLASS := Color(0.10, 0.14, 0.17)
const GLASS_LIGHT := Color(0.34, 0.44, 0.50)
const METAL := Color(0.55, 0.56, 0.58)
const METAL_DARK := Color(0.26, 0.27, 0.29)
const CONCRETE := Color(0.62, 0.61, 0.58)
const IRON := Color(0.24, 0.25, 0.27)
const HEADLIGHT := Color(0.96, 0.94, 0.82)
const TAILLIGHT := Color(0.70, 0.10, 0.10)

## Onde a luminaria encaixa no braco do poste (o poste e a luminaria sao duas
## instancias separadas, com a MESMA altura h): se este numero mudar, o disco de
## luz sai do lugar.
const ARM_X := 1.10


## Acumulador de malha: vertices, normais e cores. Equivalente ao GBuf do
## city_gen, mas com Transform3D, porque a MESMA malha de prop vira N instancias
## no setor.
class MBuf:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()

	func tri(a: Vector3, b: Vector3, d: Vector3, col: Color, nrm: Vector3) -> void:
		v.append(a)
		v.append(b)
		v.append(d)
		n.append(nrm)
		n.append(nrm)
		n.append(nrm)
		c.append(col)
		c.append(col)
		c.append(col)

	## Copia `src` transformada por `xf` (translacao + rotacao; a escala ja e
	## aplicada na construcao da malha, entao a base e ortonormal e a normal
	## pode ser girada direto, sem inversa-transposta).
	func add(src: MBuf, xf: Transform3D) -> void:
		var basis := xf.basis
		var origin := xf.origin
		for p in src.v:
			v.append(basis * p + origin)
		for q in src.n:
			n.append((basis * q).normalized())
		for col in src.c:
			c.append(col)

	func is_empty() -> bool:
		return v.is_empty()

	func top_y() -> float:
		var top := 0.0
		for p in v:
			top = maxf(top, p.y)
		return top


# --- Primitivas (todas com normal corrigida pelo winding) --------------------

## Triangulo. A normal sai do proprio winding e e invertida se apontar contra
## `want`: o chamador diz PARA ONDE a face deve olhar, nunca "como" ordenar.
static func tri3(buf: MBuf, a: Vector3, b: Vector3, d: Vector3, col: Color,
		want: Vector3) -> void:
	var nrm := -(b - a).cross(d - a)
	if nrm.length_squared() < 1e-12:
		return
	if want != Vector3.ZERO and nrm.dot(want) < 0.0:
		var tmp := b
		b = d
		d = tmp
		nrm = -nrm
	buf.tri(a, b, d, col, nrm.normalized())


## Quad a-b-c-d em ordem CICLICA (qualquer dos dois sentidos serve).
static func face4(buf: MBuf, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		col: Color, want: Vector3) -> void:
	tri3(buf, a, b, c, col, want)
	tri3(buf, a, c, d, col, want)


## Quad visivel dos DOIS lados (folha de palmeira, copa de guarda-sol): sem
## isto a folha some quando o jogador olha a palmeira de baixo para cima.
static func face4_double(buf: MBuf, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		col: Color, want: Vector3) -> void:
	face4(buf, a, b, c, d, col, want)
	face4(buf, a, d, c, b, col, -want)


static func _axis_of(b: Basis, i: int) -> Vector3:
	if i == 0:
		return b.x
	if i == 1:
		return b.y
	return b.z


## Caixa alinhada a `basis` (padrao: eixos do mundo), com centro e tamanho.
static func box(buf: MBuf, center: Vector3, size: Vector3, col: Color,
		basis: Basis = Basis()) -> void:
	var h := size * 0.5
	# [eixo da normal, eixo da tangente 1, eixo da tangente 2, sinal]
	var faces := [
		[0, 1, 2, 1.0], [0, 1, 2, -1.0],
		[1, 2, 0, 1.0], [1, 2, 0, -1.0],
		[2, 0, 1, 1.0], [2, 0, 1, -1.0],
	]
	for f in faces:
		var ax: int = f[0]
		var t1: int = f[1]
		var t2: int = f[2]
		var sgn: float = f[3]
		var nrm := _axis_of(basis, ax) * sgn
		var half_n: float = h[ax]
		var half_1: float = h[t1]
		var half_2: float = h[t2]
		var c0 := center + nrm * half_n
		var u := _axis_of(basis, t1) * half_1
		var w := _axis_of(basis, t2) * half_2
		face4(buf, c0 - u - w, c0 + u - w, c0 + u + w, c0 - u + w, col, nrm)


## Prisma (ou tronco de cone) de `sides` lados entre dois pontos, com eixo
## livre no espaco — e o que faz tronco, poste, roda, caixa d'agua e guarda-sol.
static func prism_dir(buf: MBuf, base: Vector3, top: Vector3, r0: float, r1: float,
		sides: int, col: Color, cap_top: bool = false, cap_bottom: bool = false,
		double_side: bool = false) -> void:
	var span := top - base
	if span.length() < 0.001 or sides < 3:
		return
	var axis := span.normalized()
	var u := axis.cross(Vector3.UP)
	if u.length() < 0.01:
		u = axis.cross(Vector3.RIGHT)
	u = u.normalized()
	var w := axis.cross(u).normalized()
	for i in sides:
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		var d0 := u * cos(a0) + w * sin(a0)
		var d1 := u * cos(a1) + w * sin(a1)
		var p0b := base + d0 * r0
		var p1b := base + d1 * r0
		var p0t := top + d0 * r1
		var p1t := top + d1 * r1
		var q0 := base + d0
		var q1 := base + d1
		var want := ((q0 + q1) * 0.5 - base)
		if want.length() < 0.0001:
			want = d0
		want = want.normalized()
		if double_side:
			face4_double(buf, p0b, p1b, p1t, p0t, col, want)
		else:
			face4(buf, p0b, p1b, p1t, p0t, col, want)
		if cap_bottom and r0 > 0.01:
			tri3(buf, base, p0b, p1b, col, -axis)
		if cap_top and r1 > 0.01:
			tri3(buf, top, p0t, p1t, col, axis)


## Esfera achatada de baixa resolucao (copa de arvore, arbusto, coco).
static func blob(buf: MBuf, center: Vector3, radii: Vector3, col: Color,
		segs: int = 5, rings: int = 2) -> void:
	for r in rings:
		var p0 := PI * float(r) / float(rings)
		var p1 := PI * float(r + 1) / float(rings)
		for s in segs:
			var t0 := TAU * float(s) / float(segs)
			var t1 := TAU * float(s + 1) / float(segs)
			var a := center + _sphere(p0, t0) * radii
			var b := center + _sphere(p0, t1) * radii
			var c := center + _sphere(p1, t1) * radii
			var d := center + _sphere(p1, t0) * radii
			face4(buf, a, b, c, d, col, (a + b + c + d) * 0.25 - center)


static func _sphere(phi: float, theta: float) -> Vector3:
	return Vector3(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta))


## Fita dupla-face entre pontos consecutivos, com largura que afina: a folha da
## palmeira. `pts` e `widths` tem o mesmo tamanho (>= 2) e `side` e a direcao
## transversal da fita (perpendicular ao eixo da folha).
static func ribbon(buf: MBuf, pts: Array, widths: Array, side: Vector3,
		c0: Color, c1: Color, want: Vector3) -> void:
	var n := pts.size()
	if n < 2 or widths.size() != n:
		return
	for i in n - 1:
		var p0: Vector3 = pts[i]
		var p1: Vector3 = pts[i + 1]
		var w0: float = widths[i]
		var w1: float = widths[i + 1]
		var t := float(i) / float(maxi(1, n - 1))
		var col := c0.lerp(c1, t)
		face4_double(buf, p0 - side * w0, p0 + side * w0, p1 + side * w1,
				p1 - side * w1, col, want)


## Oclusao ambiente "assada" na cor do vertice: multiplica a cor por um fator
## que vai de `floor_col` no chao a 1.0 em `top_y`. Sem textura, sem shader e
## sem custo de pixel — e o que da peso ao prop no chao (docs/ESTILO.md, AO por
## vertice).
static func ao_shade(buf: MBuf, top_y: float = 0.0, floor_col: float = 0.70) -> void:
	if buf.c.is_empty():
		return
	var top := top_y
	if top <= 0.05:
		top = buf.top_y()
	if top <= 0.05:
		return
	for i in buf.v.size():
		var y := buf.v[i].y
		var t := clampf(y / top, 0.0, 1.0)
		var f := lerpf(floor_col, 1.0, pow(t, 0.70))
		var col := buf.c[i]
		buf.c[i] = Color(col.r * f, col.g * f, col.b * f, col.a)


# --- Receita por tipo --------------------------------------------------------

## Malha do prop `kind` em escala real, com a base em y = 0.
## Devolve {"solid": MBuf, "glow": MBuf} — `glow` e o que ACENDE a noite.
## Tipo desconhecido devolve {} (o setor simplesmente nao desenha nada).
static func build(kind: String, h: float, hue: float) -> Dictionary:
	var solid := MBuf.new()
	var glow := MBuf.new()
	# O tom e um 0..1: o city_gen as vezes passa hue + 0.25 para variar o vizinho
	# e, sem o clamp, uma cor extrapolada (acima de 1) sairia estourada na tela.
	hue = clampf(hue, 0.0, 1.0)
	match kind:
		"palm":
			_palm(solid, h, hue)
		"palm_crown":
			_palm_crown(solid, h, hue)
		"tree":
			_trunk(solid, h, hue)
		"tree_crown":
			_tree_crown(solid, h, hue)
		"bush":
			_bush(solid, h, hue)
		"poste":
			_poste(solid, h)
		"lampadaria":
			_lamp(solid, glow, h)
		"banco":
			_banco(solid, hue)
		"lixeira":
			_lixeira(solid, hue)
		"kiosk":
			_kiosk(solid, hue)
		"umbrella":
			_umbrella(solid, hue)
		"caixa_dagua":
			_caixa_dagua(solid, hue)
		"casa_maquinas":
			_casa_maquinas(solid, hue)
		"antena":
			_antena(solid)
		"carro":
			_carro(solid, hue)
		"ar_condicionado":
			_ar_condicionado(solid, hue)
		"planta":
			_planta(solid, hue)
		"pedra":
			_pedra(solid, h, hue)
		"placa":
			_placa(solid, h, hue)
		"hidrante":
			_hidrante(solid, hue)
		"cadeira":
			_cadeira(solid, hue)
		_:
			return {}
	if not solid.is_empty():
		ao_shade(solid, 0.0, 0.70)
	return {"solid": solid, "glow": glow}


## Deslocamento lateral do tronco da palmeira na altura t (0 a 1). Depende SO
## de h, entao o tronco ("palm") e a copa ("palm_crown") — duas instancias
## separadas no city_gen — caem exatamente no mesmo ponto.
static func palm_offset(t: float, h: float) -> Vector3:
	return Vector3(0.11 * h * pow(clampf(t, 0.0, 1.0), 1.7), 0.0, 0.0)


## Ponto onde a copa da palmeira encaixa (topo do tronco).
static func palm_top(h: float) -> Vector3:
	return palm_offset(1.0, h) + Vector3(0.0, h, 0.0)


static func _palm(buf: MBuf, h: float, hue: float) -> void:
	var bark: Color = PropFactory.color_for("palm", hue)
	var segs := 5
	for i in segs:
		var t0 := float(i) / float(segs)
		var t1 := float(i + 1) / float(segs)
		var p0 := palm_offset(t0, h) + Vector3(0.0, h * t0, 0.0)
		var p1 := palm_offset(t1, h) + Vector3(0.0, h * t1, 0.0)
		# Anel de resto de folha: a cor alterna a cada trecho e o topo de cada
		# um e um tico mais grosso — e essa marcacao que le como palmeira.
		var r0 := lerpf(0.34, 0.17, t0)
		var r1 := lerpf(0.34, 0.17, t1)
		var col := bark if i % 2 == 0 else bark.darkened(0.13)
		prism_dir(buf, p0, p1, r0, r1 * 1.06, 5, col, false, false)
	# Colar no topo: esconde a emenda do tronco com a copa.
	var top := palm_top(h)
	prism_dir(buf, top - Vector3(0.0, 0.26, 0.0), top + Vector3(0.0, 0.04, 0.0),
			0.22, 0.15, 6, bark.darkened(0.20), false, false)


static func _palm_crown(buf: MBuf, h: float, hue: float) -> void:
	var top := palm_top(h)
	var green: Color = PropFactory.color_for("palm_crown", hue)
	var fronds := 9
	for k in fronds:
		var ang := TAU * hue + TAU * float(k) / float(fronds)
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		var side := Vector3(-sin(ang), 0.0, cos(ang))
		# Cada folha sobe, abre e cai: a "onda" que faz a silhueta da palmeira.
		var lift := 0.55 + 0.45 * sin(float(k) * 2.3999 + hue * TAU)
		var pts: Array = [
			top + dir * 0.20 + Vector3(0.0, 0.18, 0.0),
			top + dir * 1.10 + Vector3(0.0, 0.34 * lift, 0.0),
			top + dir * 2.15 + Vector3(0.0, 0.06 * lift, 0.0),
			top + dir * 3.05 + Vector3(0.0, -0.70 - 0.25 * lift, 0.0),
		]
		var widths := [0.09, 0.30, 0.25, 0.02]
		ribbon(buf, pts, widths, side, green, green.darkened(0.18), Vector3.UP)
	# Miolo (o "olho" da palmeira) e o cacho de cocos.
	blob(buf, top + Vector3(0.0, 0.02, 0.0), Vector3(0.38, 0.30, 0.38),
			green.darkened(0.30), 6, 2)
	blob(buf, top + Vector3(0.26, -0.12, 0.10), Vector3(0.13, 0.15, 0.13),
			Color(0.42, 0.36, 0.20), 5, 2)


static func _trunk(buf: MBuf, h: float, hue: float) -> void:
	prism_dir(buf, Vector3.ZERO, Vector3(0.0, h * 0.78, 0.0), 0.34, 0.17, 6,
			PropFactory.color_for("tree", hue), false, false)


static func _tree_crown(buf: MBuf, h: float, hue: float) -> void:
	var col: Color = PropFactory.color_for("tree_crown", hue)
	var r := clampf(h * 0.38, 1.4, 4.0)
	# Tres camadas: a de baixo escura (sombra da propria copa), a do meio na cor
	# e a de cima pega o sol. Antes eram dois blobs e a copa lia como pedra.
	blob(buf, Vector3(0.0, h * 0.86, 0.0), Vector3(r, r * 0.74, r),
			col.darkened(0.10), 5, 2)
	blob(buf, Vector3(r * 0.50, h * 0.96, -r * 0.34), Vector3(r * 0.56, r * 0.50, r * 0.56),
			col.lightened(0.08), 5, 2)
	blob(buf, Vector3(-r * 0.40, h * 1.00, r * 0.36), Vector3(r * 0.52, r * 0.46, r * 0.52),
			col.lightened(0.16), 5, 2)


static func _bush(buf: MBuf, h: float, hue: float) -> void:
	var col: Color = PropFactory.color_for("bush", hue)
	blob(buf, Vector3(0.0, h * 0.50, 0.0), Vector3(h * 0.50, h * 0.45, h * 0.50),
			col, 5, 2)
	blob(buf, Vector3(h * 0.30, h * 0.38, -h * 0.20), Vector3(h * 0.34, h * 0.30, h * 0.34),
			col.lightened(0.10), 5, 2)


## Poste de rua: base de concreto, coluna de 4 lados que afina e braco curvo em
## dois trechos. A luminaria vem no def seguinte ("lampadaria"), que usa a MESMA
## altura h e a mesma ponta (ARM_X). 4 lados porque um poste de 11 cm e visto a
## dezenas de metros: 5 lados custavam 30% mais vertices por nada.
static func _poste(buf: MBuf, h: float) -> void:
	var col: Color = PropFactory.color_for("poste", 0.0)
	prism_dir(buf, Vector3.ZERO, Vector3(0.0, 0.26, 0.0), 0.18, 0.15, 4, CONCRETE,
			false, false)
	prism_dir(buf, Vector3(0.0, 0.22, 0.0), Vector3(0.0, h, 0.0), 0.115, 0.075, 4,
			col, false, false)
	# Braco curvo: sai reto, dobra e chega na luminaria.
	var b0 := Vector3(0.0, h - 0.95, 0.0)
	var b1 := Vector3(ARM_X * 0.42, h - 0.22, 0.0)
	var b2 := Vector3(ARM_X, h - 0.02, 0.0)
	prism_dir(buf, b0, b1, 0.075, 0.062, 4, col.darkened(0.10), false, false)
	prism_dir(buf, b1, b2, 0.062, 0.050, 4, col.darkened(0.16), false, false)


static func _lamp(solid: MBuf, glow: MBuf, h: float) -> void:
	var head := Vector3(ARM_X, h - 0.02, 0.0)
	# Corpo da luminaria: um tronco de cone achatado com tampa.
	prism_dir(solid, head + Vector3(0.0, 0.02, 0.0), head + Vector3(0.0, 0.34, 0.0),
			0.30, 0.16, 6, Color(0.26, 0.27, 0.29), true, false)
	var lit: Color = PropFactory.color_for("lampadaria", 0.0)
	var cy := head.y + 0.03
	var prev := Vector3(0.27, 0.0, 0.0)
	for i in 6:
		var ang := TAU * float(i + 1) / 6.0
		var cur := Vector3(cos(ang) * 0.27, 0.0, sin(ang) * 0.27)
		tri3(glow, Vector3(head.x, cy, head.z),
				Vector3(head.x + prev.x, cy, head.z + prev.z),
				Vector3(head.x + cur.x, cy, head.z + cur.z), lit, Vector3.DOWN)
		prev = cur
	# Pequena cupula emissiva: o ponto de luz que o glow pega a noite.
	blob(glow, Vector3(head.x, cy - 0.02, head.z), Vector3(0.10, 0.06, 0.10), lit, 5, 1)


static func _banco(buf: MBuf, hue: float) -> void:
	var wood: Color = PropFactory.color_for("banco", hue)
	# Assento de ripas: 2 no assento, 2 no encosto inclinado.
	for i in 2:
		var z := -0.10 + float(i) * 0.20
		var tone := 0.05 if i % 2 == 0 else 0.0
		box(buf, Vector3(0.0, 0.44, z), Vector3(1.86, 0.05, 0.16),
				wood.lightened(tone))
	var tilt := Basis(Vector3.RIGHT, deg_to_rad(15.0))
	for i in 2:
		box(buf, Vector3(0.0, 0.64 + float(i) * 0.16, -0.26 - float(i) * 0.05),
				Vector3(1.86, 0.05, 0.11), wood, tilt)
	# Estrutura: perna de tras, perna da frente e travessa em cada lado.
	for sx in [-1.0, 1.0]:
		var x := float(sx) * 0.84
		box(buf, Vector3(x, 0.22, 0.12), Vector3(0.07, 0.44, 0.07), IRON)
		box(buf, Vector3(x, 0.48, -0.04), Vector3(0.07, 0.07, 0.52), IRON)


static func _lixeira(buf: MBuf, hue: float) -> void:
	var col: Color = PropFactory.color_for("lixeira", hue)
	prism_dir(buf, Vector3.ZERO, Vector3(0.0, 0.86, 0.0), 0.24, 0.27, 8, col,
			false, false)
	prism_dir(buf, Vector3(0.0, 0.86, 0.0), Vector3(0.0, 0.97, 0.0), 0.30, 0.30, 8,
			col.darkened(0.22), true, false)
	prism_dir(buf, Vector3(0.0, 0.97, 0.0), Vector3(0.0, 1.03, 0.0), 0.30, 0.22, 8,
			col.darkened(0.32), true, false)


static func _kiosk(buf: MBuf, hue: float) -> void:
	var body: Color = PropFactory.color_for("kiosk", hue)
	var white := Color(0.90, 0.89, 0.85)
	# Piso, balcao e tampo do balcao.
	box(buf, Vector3(0.0, 0.06, 0.0), Vector3(3.30, 0.12, 2.30),
			Color(0.55, 0.54, 0.50))
	box(buf, Vector3(0.0, 0.58, 1.05), Vector3(3.10, 0.90, 0.30), body.darkened(0.14))
	box(buf, Vector3(0.0, 1.06, 1.02), Vector3(3.24, 0.08, 0.54), white)
	# Quatro montantes e as paredes de fundo/laterais.
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			box(buf, Vector3(float(sx) * 1.55, 1.45, float(sz) * 1.05),
					Vector3(0.12, 2.58, 0.12), body.darkened(0.20))
	box(buf, Vector3(0.0, 1.32, -1.05), Vector3(3.10, 2.20, 0.10), body)
	box(buf, Vector3(-1.55, 1.32, 0.0), Vector3(0.10, 2.20, 2.10), body.darkened(0.06))
	box(buf, Vector3(1.55, 1.32, 0.0), Vector3(0.10, 2.20, 2.10), body)
	# Vitrine da frente (vidro escuro entre o balcao e o toldo).
	box(buf, Vector3(0.0, 1.98, 1.02), Vector3(2.86, 0.72, 0.06), GLASS)
	# Toldo maior que o corpo, caido para a frente, e a placa.
	box(buf, Vector3(0.0, 2.74, 0.10), Vector3(3.92, 0.14, 2.92),
			Color(0.86, 0.28, 0.22), Basis(Vector3.RIGHT, deg_to_rad(-7.0)))
	box(buf, Vector3(0.0, 2.44, 1.18), Vector3(2.30, 0.44, 0.08), white)


static func _umbrella(buf: MBuf, hue: float) -> void:
	var col: Color = PropFactory.color_for("umbrella", hue)
	var pole := Color(0.90, 0.90, 0.88)
	prism_dir(buf, Vector3.ZERO, Vector3(0.0, 2.30, 0.0), 0.045, 0.035, 4, pole,
			false, false)
	prism_dir(buf, Vector3.ZERO, Vector3(0.0, 0.10, 0.0), 0.34, 0.30, 6,
			Color(0.42, 0.42, 0.40), true, false)
	# Duas abas: a de fora (maior) e a do meio para a ponta. Dupla-face porque
	# quem esta sentado embaixo ve a sombra do guarda-sol, nao um buraco no ceu.
	prism_dir(buf, Vector3(0.0, 1.72, 0.0), Vector3(0.0, 2.04, 0.0), 1.58, 0.84, 8,
			col, false, false, true)
	prism_dir(buf, Vector3(0.0, 2.04, 0.0), Vector3(0.0, 2.20, 0.0), 0.84, 0.04, 8,
			col.lightened(0.06), false, false, true)
	prism_dir(buf, Vector3(0.0, 2.20, 0.0), Vector3(0.0, 2.32, 0.0), 0.05, 0.02, 4,
			pole, false, false)
	# Varas por baixo: os raios que seguram a lona.
	for i in 6:
		var a := TAU * float(i) / 6.0
		var tip := Vector3(cos(a) * 1.52, 1.74, sin(a) * 1.52)
		prism_dir(buf, Vector3(0.0, 1.82, 0.0), tip, 0.022, 0.018, 3, pole, false, false)


static func _caixa_dagua(buf: MBuf, hue: float) -> void:
	var col: Color = PropFactory.color_for("caixa_dagua", hue)
	# 6 lados: a de fibra de 1500 L e vista de longe, no alto do predio.
	prism_dir(buf, Vector3.ZERO, Vector3(0.0, 1.30, 0.0), 0.78, 0.78, 6, col,
			false, false)
	prism_dir(buf, Vector3(0.0, 1.30, 0.0), Vector3(0.0, 1.46, 0.0), 0.82, 0.30, 6,
			col.lightened(0.08), true, false)


static func _casa_maquinas(buf: MBuf, hue: float) -> void:
	var col: Color = PropFactory.color_for("casa_maquinas", hue)
	box(buf, Vector3(0.0, 1.25, 0.0), Vector3(3.20, 2.50, 2.60), col)
	box(buf, Vector3(0.0, 2.58, 0.0), Vector3(3.40, 0.16, 2.80), col.darkened(0.12))


static func _antena(buf: MBuf) -> void:
	prism_dir(buf, Vector3.ZERO, Vector3(0.0, 4.80, 0.0), 0.06, 0.04, 4, METAL,
			false, false)
	box(buf, Vector3(0.0, 3.40, 0.0), Vector3(1.30, 0.06, 0.06), METAL)
	box(buf, Vector3(0.0, 4.10, 0.0), Vector3(0.90, 0.05, 0.05), METAL)


## Carro parado de rua (o que o jogador ve na Avenida Atlantica). Comprimento no
## eixo X, como o def do city_gen ja era.
##
## B-81: o carro deixou de ser "duas caixas e quatro cilindros". Agora tem
## carroceria com soleira, capo, porta-malas, cabine de vidro, teto, para-brisa
## e vidro traseiro inclinados, grade, farois, lanternas e rodas com calota — e
## a silhueta de carro que se le a 30 m.
static func _carro(buf: MBuf, hue: float) -> void:
	var paint: Color = PropFactory.color_for("carro", hue)
	var glass := GLASS.lerp(GLASS_LIGHT, 0.22)
	var wheel_x := 1.36
	var wheel_z := 0.80
	var r := 0.33
	# Rodas (eixo em Z: o pneu e um cilindro vertical), com calota do lado de fora.
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var c := Vector3(float(sx) * wheel_x, 0.30, float(sz) * wheel_z)
			var zf := float(sz)
			prism_dir(buf, c - Vector3(0.0, 0.0, zf * 0.11),
					c + Vector3(0.0, 0.0, zf * 0.11), r, r, 6, TIRE, true, true)
			prism_dir(buf, c + Vector3(0.0, 0.0, zf * 0.11),
					c + Vector3(0.0, 0.0, zf * 0.125), 0.17, 0.15, 6, HUB, false, false)
	# Carroceria: soleira escura, corpo, capo e porta-malas.
	box(buf, Vector3(0.0, 0.38, 0.0), Vector3(4.28, 0.16, 1.78), paint.darkened(0.42))
	box(buf, Vector3(0.0, 0.58, 0.0), Vector3(4.18, 0.42, 1.74), paint)
	box(buf, Vector3(1.44, 0.82, 0.0), Vector3(1.28, 0.14, 1.66), paint.lightened(0.03))
	box(buf, Vector3(-1.62, 0.82, 0.0), Vector3(0.94, 0.14, 1.66), paint.lightened(0.03))
	# Cabine: vidro, teto e as duas janelas inclinadas.
	box(buf, Vector3(-0.10, 1.04, 0.0), Vector3(1.92, 0.40, 1.58), glass)
	box(buf, Vector3(-0.12, 1.26, 0.0), Vector3(1.86, 0.08, 1.52), paint)
	face4(buf, Vector3(0.88, 0.86, -0.78), Vector3(0.88, 0.86, 0.78),
			Vector3(0.80, 1.24, 0.74), Vector3(0.80, 1.24, -0.74), glass,
			Vector3(1.0, 0.35, 0.0))
	face4(buf, Vector3(-1.02, 0.86, -0.78), Vector3(-1.02, 0.86, 0.78),
			Vector3(-0.98, 1.24, 0.74), Vector3(-0.98, 1.24, -0.74), glass,
			Vector3(-1.0, 0.35, 0.0))
	# Frente e traseira: grade, farois e lanternas.
	box(buf, Vector3(2.10, 0.66, 0.0), Vector3(0.05, 0.18, 0.68), METAL_DARK)
	for sz in [-1.0, 1.0]:
		box(buf, Vector3(2.10, 0.82, float(sz) * 0.58), Vector3(0.05, 0.16, 0.30),
				HEADLIGHT)
		box(buf, Vector3(-2.10, 0.84, float(sz) * 0.60), Vector3(0.05, 0.18, 0.28),
				TAILLIGHT)


## Aparelho de split preso na fachada. Sai da parede no +X: a rotacao da
## instancia aponta o +X para fora (a rua).
static func _ar_condicionado(buf: MBuf, hue: float) -> void:
	var col := Color(0.88, 0.88, 0.85).lerp(Color(0.72, 0.74, 0.72), hue)
	box(buf, Vector3(0.18, 0.31, 0.0), Vector3(0.34, 0.62, 0.86), col)
	box(buf, Vector3(0.355, 0.31, 0.0), Vector3(0.02, 0.48, 0.74), col.darkened(0.45))


# --- Props novos (B-81) ------------------------------------------------------

## Canteiro de calcada com moita: o vaso de concreto e a planta que aparece
## entre a porta da loja e o meio-fio em toda rua de Ipanema.
static func _planta(buf: MBuf, hue: float) -> void:
	var pot: Color = PropFactory.color_for("planta", hue)
	box(buf, Vector3(0.0, 0.30, 0.0), Vector3(0.86, 0.60, 0.86), pot)
	var leaf: Color = PropFactory.color_for("tree_crown", hue)
	blob(buf, Vector3(0.0, 0.92, 0.0), Vector3(0.52, 0.46, 0.52), leaf, 5, 2)


## Pedra da arrebentacao: dois blobs achatados, um em cima do outro. Sem elas a
## faixa de areia molhada termina numa linha reta.
static func _pedra(buf: MBuf, h: float, hue: float) -> void:
	var col := Color(0.44, 0.43, 0.40).lerp(Color(0.58, 0.56, 0.52), hue)
	var r := clampf(h, 0.35, 2.2) * 0.5
	blob(buf, Vector3(0.0, r * 0.75, 0.0), Vector3(r * 1.30, r * 0.75, r), col, 6, 2)
	if h > 0.9:
		blob(buf, Vector3(r * 0.62, r * 0.40, r * 0.28),
				Vector3(r * 0.55, r * 0.34, r * 0.60), col.darkened(0.10), 5, 2)


## Placa de nome de rua na esquina: mastro de metal e as duas placas cruzadas.
static func _placa(buf: MBuf, h: float, hue: float) -> void:
	var plate := Color(0.14, 0.32, 0.26).lerp(Color(0.16, 0.24, 0.46), hue)
	prism_dir(buf, Vector3.ZERO, Vector3(0.0, h, 0.0), 0.055, 0.045, 5, METAL,
			false, false)
	box(buf, Vector3(0.0, h - 0.20, 0.0), Vector3(1.10, 0.28, 0.03), plate)
	box(buf, Vector3(0.0, h - 0.52, 0.0), Vector3(0.03, 0.26, 0.95),
			plate.lightened(0.10))


## Hidrante de calcada: corpo vermelho, base escura e duas saidas laterais.
static func _hidrante(buf: MBuf, hue: float) -> void:
	var col := Color(0.78, 0.20, 0.14).lerp(Color(0.86, 0.72, 0.18), hue)
	prism_dir(buf, Vector3.ZERO, Vector3(0.0, 0.08, 0.0), 0.19, 0.17, 6, METAL_DARK,
			true, false)
	prism_dir(buf, Vector3(0.0, 0.08, 0.0), Vector3(0.0, 0.62, 0.0), 0.13, 0.12, 6,
			col, false, false)
	prism_dir(buf, Vector3(0.0, 0.62, 0.0), Vector3(0.0, 0.70, 0.0), 0.10, 0.06, 6,
			col.darkened(0.15), true, false)
	for s in [-1.0, 1.0]:
		prism_dir(buf, Vector3(0.0, 0.44, 0.0), Vector3(float(s) * 0.21, 0.42, 0.0),
				0.055, 0.045, 5, col.darkened(0.12), false, false)


## Cadeira de praia: armacao de metal e a lona do assento e do encosto.
static func _cadeira(buf: MBuf, hue: float) -> void:
	var frame := Color(0.88, 0.88, 0.84)
	var cloth: Color = PropFactory.color_for("umbrella", hue)
	for s in [-1.0, 1.0]:
		var x := float(s) * 0.30
		prism_dir(buf, Vector3(x, 0.0, 0.42), Vector3(x, 0.30, -0.04), 0.030, 0.030, 3,
				frame, false, false)
		prism_dir(buf, Vector3(x, 0.30, -0.04), Vector3(x, 0.72, -0.40), 0.030, 0.030, 3,
				frame, false, false)
		prism_dir(buf, Vector3(x, 0.0, 0.42), Vector3(x, 0.28, 0.42), 0.030, 0.030, 3,
				frame, false, false)
	face4_double(buf, Vector3(-0.32, 0.31, -0.02), Vector3(0.32, 0.31, -0.02),
			Vector3(0.32, 0.25, 0.40), Vector3(-0.32, 0.25, 0.40), cloth, Vector3.UP)
	face4_double(buf, Vector3(-0.32, 0.31, -0.02), Vector3(0.32, 0.31, -0.02),
			Vector3(0.32, 0.70, -0.38), Vector3(-0.32, 0.70, -0.38),
			cloth.lightened(0.06), Vector3(0.0, 0.3, -1.0))
