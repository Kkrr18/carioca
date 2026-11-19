extends Node
## World (autoload): estado global minimo e informacao de build.
## Logica pura fica em scripts/core/cfg.gd (testavel sem a arvore de cena).

const Cfg = preload("res://scripts/core/cfg.gd")

var world_seed: int = 20260922
var build: Dictionary = {}


func _ready() -> void:
	build = {
		"version": Cfg.APP_VERSION,
		"schema": Cfg.SAVE_SCHEMA,
		"engine": str(Engine.get_version_info().get("string", "?")),
		"renderer": str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "?")),
	}
