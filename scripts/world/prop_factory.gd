extends RefCounted
## PropFactory: aparencia dos props instanciados (palmeira, arvore, quiosque,
## guarda-sol). O streamer usa MultiMesh com o cubo unitario; aqui ficam as
## cores por instancia. Na Fase 5 estes props viram malhas proprias (Blender).
## Acessado via preload nos scripts; sem class_name de proposito.

const TRUNK := Color(0.34, 0.27, 0.18)
const LEAF := Color(0.22, 0.42, 0.24)
const BUSH := Color(0.28, 0.44, 0.22)
const KIOSK_A := Color(0.95, 0.86, 0.55)
const KIOSK_B := Color(0.55, 0.75, 0.85)
const UMBRELLA_A := Color(0.92, 0.35, 0.30)
const UMBRELLA_B := Color(0.30, 0.55, 0.85)


static func color_for(kind: String, hue: float) -> Color:
	match kind:
		"palm":
			return LEAF.darkened(0.05)
		"tree", "bush":
			return BUSH.lerp(LEAF, hue)
		"kiosk":
			return KIOSK_A.lerp(KIOSK_B, hue)
		"umbrella":
			return UMBRELLA_A.lerp(UMBRELLA_B, hue)
		"poste":
			return Color(0.55, 0.55, 0.58)
		"lampadaria":
			return Color(1.0, 0.93, 0.72)
		"banco":
			return Color(0.50, 0.36, 0.22)
		"lixeira":
			return Color(0.20, 0.30, 0.24)
		"carro":
			if hue < 0.33:
				return Color(0.75, 0.18, 0.15)
			elif hue < 0.66:
				return Color(0.16, 0.34, 0.60)
			return Color(0.88, 0.87, 0.85)
		"carro_top":
			return Color(0.75, 0.82, 0.88)
		# Cobertura dos predios (B-50): a caixa d'agua branca/bege de fibra, a
		# casa de maquinas de concreto e a antena escura.
		"caixa_dagua":
			return Color(0.88, 0.87, 0.82).darkened(hue * 0.22)
		"casa_maquinas":
			return Color(0.74, 0.73, 0.69)
		"antena":
			return Color(0.30, 0.31, 0.33)
		_:
			return LEAF


## Deslocamento vertical e escala do cubo unitario para cada tipo de prop.
## Retorna [offset_y, tamanho] para a instancia.
static func shape_for(kind: String, h: float) -> Array:
	match kind:
		"palm":
			return [h * 0.5, Vector3(0.5, h, 0.5)]
		"tree":
			return [h * 0.5, Vector3(h * 0.55, h, h * 0.55)]
		"bush":
			return [h * 0.5, Vector3(h, h, h)]
		"kiosk":
			return [1.6, Vector3(4.5, 3.2, 3.5)]
		"umbrella":
			return [2.2, Vector3(3.4, 0.2, 3.4)]
		"poste":
			return [h * 0.5, Vector3(0.22, h, 0.22)]
		"lampadaria":
			return [h + 0.2, Vector3(1.3, 0.3, 0.5)]
		"banco":
			return [0.3, Vector3(2.0, 0.4, 0.6)]
		"lixeira":
			return [0.55, Vector3(0.55, 1.0, 0.55)]
		"carro":
			return [0.35, Vector3(4.2, 1.3, 1.8)]
		"carro_top":
			return [1.15, Vector3(2.2, 0.65, 1.6)]
		# Cobertura: tamanhos em escala real (caixa d'agua ~1500 L, casa de
		# maquinas de elevador, antena de 4,8 m).
		"caixa_dagua":
			return [0.75, Vector3(1.9, 1.5, 1.9)]
		"casa_maquinas":
			return [1.25, Vector3(3.2, 2.5, 2.6)]
		"antena":
			return [2.4, Vector3(0.14, 4.8, 0.14)]
		_:
			return [h * 0.5, Vector3(1.0, h, 1.0)]
