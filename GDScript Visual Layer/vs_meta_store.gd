@tool
extends RefCounted


static func meta_path_for_script(script_path: String) -> String:
	return script_path + ".vsmeta"


static func load_meta(script_path: String) -> Dictionary:
	var meta_path := meta_path_for_script(script_path)
	if not FileAccess.file_exists(meta_path):
		return _default_meta()

	var file := FileAccess.open(meta_path, FileAccess.READ)
	if file == null:
		return _default_meta()

	var text := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return _default_meta()

	var result: Dictionary = parsed
	if not result.has("views"):
		result["views"] = {}
	if not result.has("version"):
		result["version"] = 2
	return result


static func save_meta(script_path: String, meta: Dictionary) -> bool:
	if script_path == "":
		return false

	meta["version"] = 2
	var file := FileAccess.open(meta_path_for_script(script_path), FileAccess.WRITE)
	if file == null:
		return false

	file.store_string(JSON.stringify(meta, "\t"))
	file.close()
	return true


static func get_view(meta: Dictionary, view_key: String) -> Dictionary:
	if not meta.has("views"):
		meta["views"] = {}

	var views: Dictionary = meta["views"]
	if not views.has(view_key):
		views[view_key] = {"nodes": {}, "connections": [], "groups": [], "scroll": {"x": 0, "y": 0}, "zoom": 1.0}

	return views[view_key]


static func get_node_position(meta: Dictionary, view_key: String, node_name: String, fallback: Vector2) -> Vector2:
	var view := get_view(meta, view_key)
	var nodes: Dictionary = view.get("nodes", {})
	if not nodes.has(node_name):
		return fallback

	var value = nodes[node_name]
	if typeof(value) == TYPE_DICTIONARY:
		return Vector2(float(value.get("x", fallback.x)), float(value.get("y", fallback.y)))
	if typeof(value) == TYPE_ARRAY and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return fallback


static func set_node_position(meta: Dictionary, view_key: String, node_name: String, position: Vector2) -> void:
	var view := get_view(meta, view_key)
	if not view.has("nodes"):
		view["nodes"] = {}
	view["nodes"][node_name] = {"x": position.x, "y": position.y}


static func view_has_saved_nodes(meta: Dictionary, view_key: String) -> bool:
	var view := get_view(meta, view_key)
	var nodes: Dictionary = view.get("nodes", {})
	return not nodes.is_empty()


static func set_connections(meta: Dictionary, view_key: String, connections: Array) -> void:
	var view := get_view(meta, view_key)
	var clean: Array = []
	for connection in connections:
		if typeof(connection) != TYPE_DICTIONARY:
			continue
		clean.append({
			"from_node": str(connection.get("from_node", "")),
			"from_port": int(connection.get("from_port", 0)),
			"to_node": str(connection.get("to_node", "")),
			"to_port": int(connection.get("to_port", 0))
		})
	view["connections"] = clean


static func get_connections(meta: Dictionary, view_key: String) -> Array:
	var view := get_view(meta, view_key)
	return view.get("connections", [])


static func set_groups(meta: Dictionary, view_key: String, groups: Array) -> void:
	var view := get_view(meta, view_key)
	view["groups"] = groups


static func get_groups(meta: Dictionary, view_key: String) -> Array:
	var view := get_view(meta, view_key)
	return view.get("groups", [])


static func set_camera(meta: Dictionary, view_key: String, scroll: Vector2, zoom: float) -> void:
	var view := get_view(meta, view_key)
	view["scroll"] = {"x": scroll.x, "y": scroll.y}
	view["zoom"] = zoom


static func get_scroll(meta: Dictionary, view_key: String) -> Vector2:
	var view := get_view(meta, view_key)
	var scroll = view.get("scroll", {"x": 0, "y": 0})
	if typeof(scroll) == TYPE_DICTIONARY:
		return Vector2(float(scroll.get("x", 0)), float(scroll.get("y", 0)))
	return Vector2.ZERO


static func get_zoom(meta: Dictionary, view_key: String) -> float:
	var view := get_view(meta, view_key)
	return float(view.get("zoom", 1.0))


static func _default_meta() -> Dictionary:
	return {"version": 2, "views": {}}
