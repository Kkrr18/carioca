extends Node
## SaveManager (autoload): salvamento versionado em user://saves/.
##
## Formato do arquivo (.carsave):
##   linha 1 (texto): CARIOCA-SAVE;<schema>;<versao do app>;<sha256 do blob>;<bytes do blob>
##   resto: JSON do estado comprimido com gzip.
##
## Regras:
## - schema MAIOR que o suportado => recusa (nao corrompe o arquivo).
## - schema MENOR => migra em _migrate() (ainda nao existe schema anterior ao 1).
## - checksum ou tamanho invalidos => recusa e informa em last_error.
## - escrita em arquivo temporario + rename, para nao perder o save anterior
##   se o app for fechado no meio da gravacao.

const Cfg = preload("res://scripts/core/cfg.gd")

const DIR := "user://saves"
const MAGIC := "CARIOCA-SAVE"
const DEFAULT_SLOT := "slot0"

var last_error: String = ""


func save_path(slot: String = DEFAULT_SLOT) -> String:
	return "%s/%s.carsave" % [DIR, slot]


func has_save(slot: String = DEFAULT_SLOT) -> bool:
	return FileAccess.file_exists(save_path(slot))


func save_state(state: Dictionary, slot: String = DEFAULT_SLOT) -> bool:
	last_error = ""
	DirAccess.make_dir_recursive_absolute(DIR)
	var payload: Dictionary = state.duplicate(true)
	payload["schema"] = Cfg.SAVE_SCHEMA
	payload["version"] = Cfg.APP_VERSION
	payload["saved_unix"] = Time.get_unix_time_from_system()

	var blob: PackedByteArray = JSON.stringify(payload).to_utf8_buffer().compress(FileAccess.COMPRESSION_GZIP)
	if blob.is_empty():
		last_error = "compressao falhou"
		return false
	var header := "%s;%d;%s;%s;%d\n" % [MAGIC, Cfg.SAVE_SCHEMA, Cfg.APP_VERSION, _digest(blob), blob.size()]

	var final_path := save_path(slot)
	var tmp_path := final_path + ".tmp"
	var f := FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		last_error = "nao abriu %s (%s)" % [tmp_path, error_string(FileAccess.get_open_error())]
		return false
	f.store_buffer(header.to_utf8_buffer())
	f.store_buffer(blob)
	f.close()
	if FileAccess.file_exists(final_path):
		DirAccess.remove_absolute(final_path)
	var err := DirAccess.rename_absolute(tmp_path, final_path)
	if err != OK:
		last_error = "rename falhou: %s" % error_string(err)
		return false
	return true


func load_state(slot: String = DEFAULT_SLOT) -> Dictionary:
	last_error = ""
	var path := save_path(slot)
	if not FileAccess.file_exists(path):
		last_error = "sem save em %s" % path
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		last_error = "nao foi possivel ler o save"
		return {}
	var header := f.get_line()
	var blob := f.get_buffer(f.get_length() - f.get_position())
	f.close()

	var parts := header.split(";")
	if parts.size() != 5 or parts[0] != MAGIC:
		last_error = "cabecalho invalido"
		return {}
	var schema := int(parts[1])
	if schema > Cfg.SAVE_SCHEMA:
		last_error = "save de versao mais nova (schema %d > %d)" % [schema, Cfg.SAVE_SCHEMA]
		return {}
	if int(parts[4]) != blob.size():
		last_error = "tamanho do blob nao confere"
		return {}
	if _digest(blob) != parts[3]:
		last_error = "checksum invalido (arquivo corrompido)"
		return {}

	var text := blob.decompress_dynamic(1 << 26, FileAccess.COMPRESSION_GZIP).get_string_from_utf8()
	if text.is_empty():
		last_error = "conteudo vazio"
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		last_error = "JSON invalido"
		return {}
	var state: Dictionary = parsed
	var file_schema := int(state.get("schema", schema))
	if file_schema < Cfg.SAVE_SCHEMA:
		state = _migrate(state, file_schema)
	return state


## Migracoes sequenciais: cada passo leva o schema N para N+1.
## Nao existe nenhuma ainda: o schema 1 e o primeiro.
func _migrate(state: Dictionary, from_schema: int) -> Dictionary:
	var s := from_schema
	while s < Cfg.SAVE_SCHEMA:
		last_error = "sem rota de migracao do schema %d" % s
		return {}
	return state


func list_saves() -> PackedStringArray:
	var out := PackedStringArray()
	var d := DirAccess.open(DIR)
	if d == null:
		return out
	for fname in d.get_files():
		if fname.ends_with(".carsave"):
			out.append(fname.get_basename())
	return out


func delete_save(slot: String = DEFAULT_SLOT) -> void:
	if has_save(slot):
		DirAccess.remove_absolute(save_path(slot))


func _digest(blob: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(blob)
	return ctx.finish().hex_encode()
