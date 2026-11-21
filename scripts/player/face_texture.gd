extends RefCounted
## FaceTexture: o ROSTO do protagonista (B-76).
##
## O corpo CC0 da Quaternius (ped-walk.glb) tem cabeca lisa: `paint_body` pinta
## pele, camiseta, calca e cabelo por ALTURA do vertice, entao o rosto fica sem
## olhos, boca ou sobrancelha — nos prints do iPhone o protagonista aparece com
## uma cara branca e vazia. Aqui o rosto e DESENHADO em codigo (Image RGBA) e
## aplicado num quad na frente da cabeca.
##
## Por que desenhar em vez de baixar uma textura de rosto:
##   * a regra do projeto e asset CC0/CC-BY com atribuicao, e textura de rosto
##     solta em .png quase sempre vem dentro de pacote (zip, que nao abrimos);
##   * 64x96 pixels desenhados em codigo custam ~24 KB de VRAM, ficam no estilo
##     low-poly do resto e nao dependem de download;
##   * o rosto acompanha o TAMANHO do personagem: tudo e fracao da altura
##     (AVATAR_HEIGHT = 1,80 m), entao mudar a altura muda o rosto junto.
##
## Tudo aqui e PURO (sem no, sem cena) e testado no CI: a imagem e as medidas.

## Fracao da altura do corpo -> medidas do rosto (em metros por metro de corpo).
## Cabeca humana: ~1/8 da altura; o rosto (olhos a queixo) ~0,105 e a largura
## ~0,075. O centro fica a 0,92 da altura (nivel dos olhos) e o quad paira 5 cm
## (x altura) na frente do cranio para nao brigar com a malha (z-fighting).
const FACE_W := 0.075
const FACE_H := 0.105
const FACE_CENTER_Y := 0.920
const FACE_FRONT := 0.050

## Cores do rosto (o resto e transparente: a pele do corpo aparece).
const EYE_COL := Color(0.14, 0.10, 0.08)
const GLINT_COL := Color(0.95, 0.95, 0.95)
const BROW_COL := Color(0.10, 0.08, 0.07)
const NOSE_COL := Color(0.72, 0.52, 0.44, 0.45)
const MOUTH_COL := Color(0.48, 0.22, 0.18)


## Medidas do rosto para um corpo de `body_height` metros: o quad (size) e o
## centro no espaco do personagem (Y para cima, +Z para a frente).
static func layout(body_height: float) -> Dictionary:
	var h := maxf(1.0, body_height)
	return {
		"size": Vector2(FACE_W, FACE_H) * h,
		"center": Vector3(0.0, FACE_CENTER_Y * h, FACE_FRONT * h),
	}


## Desenha o rosto: fundo transparente, olhos com brilho, sobrancelhas, sombra
## do nariz e boca. `w` x `h` em pixels (proporcao 2:3 para caber num rosto).
static func face_image(w: int = 64, h: int = 96) -> Image:
	var iw := maxi(8, w)
	var ih := maxi(12, h)
	var img := Image.create(iw, ih, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))

	# Sobrancelhas: barra fina acima de cada olho.
	var brow_y := int(round(float(ih) * 0.29))
	var brow_h := maxi(1, int(round(float(ih) * 0.035)))
	for side in [-1, 1]:
		var cx := _eye_center_x(iw, side)
		var bw := int(round(float(iw) * 0.22))
		img.fill_rect(Rect2i(cx - bw / 2, brow_y, bw, brow_h), BROW_COL)

	# Olhos: amendoa escura com um brilho no canto superior.
	var eye_y := int(round(float(ih) * 0.40))
	var eye_h := maxi(2, int(round(float(ih) * 0.11)))
	var eye_w := maxi(3, int(round(float(iw) * 0.17)))
	for side in [-1, 1]:
		var cx := _eye_center_x(iw, side)
		img.fill_rect(Rect2i(cx - eye_w / 2, eye_y, eye_w, eye_h), EYE_COL)
		var gx := cx - eye_w / 4
		var gy := eye_y + maxi(1, eye_h / 4)
		img.fill_rect(Rect2i(gx, gy, maxi(1, iw / 32), maxi(1, ih / 48)), GLINT_COL)

	# Sombra do nariz: risco vertical fraco no meio, entre os olhos e a boca.
	var nose_w := maxi(1, int(round(float(iw) * 0.05)))
	var nose_y := int(round(float(ih) * 0.55))
	var nose_h := int(round(float(ih) * 0.10))
	img.fill_rect(Rect2i(iw / 2 - nose_w / 2, nose_y, nose_w, nose_h), NOSE_COL)

	# Boca: risco horizontal, levemente levantado nas pontas (sorriso discreto).
	var mouth_h := maxi(1, int(round(float(ih) * 0.028)))
	var mouth_w := int(round(float(iw) * 0.30))
	var mouth_y := int(round(float(ih) * 0.76))
	img.fill_rect(Rect2i(iw / 2 - mouth_w / 2, mouth_y, mouth_w, mouth_h), MOUTH_COL)
	for side in [-1, 1]:
		# Tipo explicito de proposito: `side` vem de um Array (Variant) e o `:=`
		# nao consegue inferir (o CI pegou isso na B-76, igual ao B-65).
		var mx: int = iw / 2 + int(side) * (mouth_w / 2 - maxi(1, iw / 32))
		img.fill_rect(Rect2i(mx, mouth_y - mouth_h, maxi(1, iw / 32), mouth_h), MOUTH_COL)
	return img


## Centro horizontal do olho do lado `side` (-1 = esquerdo do rosto).
static func _eye_center_x(w: int, side: int) -> int:
	return w / 2 + side * int(round(float(w) * 0.20))


## Material do rosto: textura própria, recorte por alfa (barato e sem ordem de
## transparência no iPhone), sem sombra projetada e visivel dos dois lados (um
## erro de winding nunca esconde a cara).
static func material() -> StandardMaterial3D:
	var tex := ImageTexture.create_from_image(face_image())
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.albedo_color = Color(1, 1, 1, 1)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.5
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.roughness = 0.95
	mat.metallic_specular = 0.0
	return mat
