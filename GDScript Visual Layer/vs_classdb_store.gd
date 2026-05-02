@tool
extends RefCounted

const GLOBAL_CLASS_NAMES := ["@GlobalScope", "@GDScript"]
const VS_TYPE_VARIANT := -1

const SEARCH_CLASS_PRIORITY := [
	"Node", "Node2D", "Node3D", "Control", "CanvasItem", "Object", "Resource",
	"SceneTree", "Input", "OS", "ResourceLoader", "FileAccess", "DirAccess", "PackedScene",
	"AnimationPlayer", "Tween", "Camera2D", "Camera3D", "Sprite2D", "MeshInstance3D",
	"CharacterBody2D", "CharacterBody3D", "RigidBody2D", "RigidBody3D", "Area2D", "Area3D",
	"Timer", "AudioStreamPlayer", "AudioStreamPlayer2D", "AudioStreamPlayer3D"
]

const GLOBAL_METHOD_FALLBACKS := {
	"print": {"name": "print", "return": {"type": TYPE_NIL}, "vararg": true, "args": [{"name": "args", "type": VS_TYPE_VARIANT}], "category": "Core/Builtins", "description": "print(...args)"},
	"printerr": {"name": "printerr", "return": {"type": TYPE_NIL}, "vararg": true, "args": [{"name": "args", "type": VS_TYPE_VARIANT}], "category": "Core/Builtins", "description": "printerr(...args)"},
	"print_rich": {"name": "print_rich", "return": {"type": TYPE_NIL}, "vararg": true, "args": [{"name": "args", "type": VS_TYPE_VARIANT}], "category": "Core/Builtins", "description": "print_rich(...args)"},
	"push_warning": {"name": "push_warning", "return": {"type": TYPE_NIL}, "vararg": true, "args": [{"name": "args", "type": VS_TYPE_VARIANT}], "category": "Core/Builtins", "description": "push_warning(...args)"},
	"push_error": {"name": "push_error", "return": {"type": TYPE_NIL}, "vararg": true, "args": [{"name": "args", "type": VS_TYPE_VARIANT}], "category": "Core/Builtins", "description": "push_error(...args)"},
	"str": {"name": "str", "return": {"type": TYPE_STRING}, "vararg": true, "args": [{"name": "value", "type": VS_TYPE_VARIANT}], "category": "Core/Conversions", "description": "str(value) -> String"},
	"int": {"name": "int", "return": {"type": TYPE_INT}, "args": [{"name": "value", "type": VS_TYPE_VARIANT}], "category": "Core/Conversions", "description": "int(value) -> int"},
	"float": {"name": "float", "return": {"type": TYPE_FLOAT}, "args": [{"name": "value", "type": VS_TYPE_VARIANT}], "category": "Core/Conversions", "description": "float(value) -> float"},
	"bool": {"name": "bool", "return": {"type": TYPE_BOOL}, "args": [{"name": "value", "type": VS_TYPE_VARIANT}], "category": "Core/Conversions", "description": "bool(value) -> bool"}
}

static var _engine_classes_cache: Array = []
static var _global_methods_cache: Dictionary = {}
static var _method_cache: Dictionary = {}
static var _property_cache: Dictionary = {}


static func has_global_method(method_name: String) -> bool:
	return _get_global_methods().has(method_name)


static func get_global_method_data(method_name: String) -> Dictionary:
	var methods := _get_global_methods()
	if methods.has(method_name):
		return (methods[method_name] as Dictionary).duplicate(true)
	return {}


static func search_global_methods(filter_text := "", limit := 120) -> Array:
	var result: Array = []
	var filter := filter_text.to_lower().strip_edges()
	var methods := _get_global_methods()
	var names := methods.keys()
	names.sort()

	for method_name in names:
		var data: Dictionary = methods[method_name] as Dictionary
		var title := str(data.get("name", method_name))
		var signature := global_method_signature(title, data)
		var category := str(data.get("category", category_from_method_name(title)))
		var description := str(data.get("description", signature))
		var haystack := "%s %s %s %s" % [title, signature, category, description]
		if filter != "" and not matches_tokens(haystack.to_lower(), filter):
			continue
		result.append({
			"kind": "global_method",
			"class": str(data.get("class", "@GlobalScope")),
			"name": title,
			"title": title,
			"signature": signature,
			"category": category,
			"description": description,
			"method_data": data
		})
		if result.size() >= limit:
			break
	return result


static func global_method_signature(method_name: String, method_data: Dictionary) -> String:
	var args: Array = []
	for arg in method_data.get("args", []):
		if typeof(arg) != TYPE_DICTIONARY:
			continue
		args.append("%s: %s" % [str(arg.get("name", "arg")), _type_name_from_any(arg.get("type", VS_TYPE_VARIANT))])
	if bool(method_data.get("vararg", false)):
		if args.is_empty():
			args.append("...args: Variant")
		elif not str(args[0]).begins_with("..."):
			args[0] = "..." + str(args[0])
	return "%s(%s) -> %s" % [method_name, ", ".join(args), method_return_type(method_data)]


static func _get_global_methods() -> Dictionary:
	if not _global_methods_cache.is_empty():
		return _global_methods_cache

	var methods: Dictionary = {}
	for _class_name in GLOBAL_CLASS_NAMES:
		if not ClassDB.class_exists(_class_name):
			continue
		for method_data in ClassDB.class_get_method_list(_class_name, true):
			if typeof(method_data) != TYPE_DICTIONARY:
				continue
			var method_name := str(method_data.get("name", ""))
			if method_name == "" or method_name.begins_with("_"):
				continue
			methods[method_name] = _decorate_global_method(method_data, _class_name)

	for fallback_name in GLOBAL_METHOD_FALLBACKS.keys():
		if not methods.has(fallback_name):
			methods[fallback_name] = (GLOBAL_METHOD_FALLBACKS[fallback_name] as Dictionary).duplicate(true)

	_global_methods_cache = methods
	return _global_methods_cache


static func _decorate_global_method(method_data: Dictionary, _class_name: String) -> Dictionary:
	var data := method_data.duplicate(true)
	var method_name := str(data.get("name", "function"))
	data["class"] = _class_name
	data["category"] = _global_category(method_name, _class_name)
	data["description"] = global_method_signature(method_name, data)
	return data


static func _global_category(method_name: String, _class_name: String) -> String:
	var clean := method_name.to_lower()
	if clean in ["print", "printerr", "print_rich", "push_error", "push_warning"]:
		return "Core/Builtins"
	if clean in ["str", "int", "float", "bool", "type_convert"]:
		return "Core/Conversions"
	if clean.find("rand") >= 0:
		return "Random"
	if clean in ["sin", "cos", "tan", "asin", "acos", "atan", "atan2", "deg_to_rad", "rad_to_deg"]:
		return "Math/Trig"
	if clean in ["min", "max", "clamp", "abs", "sign", "floor", "ceil", "round", "sqrt", "pow", "lerp", "move_toward", "pingpong", "wrapf", "wrapi", "snapped"]:
		return "Math"
	if _class_name == "@GDScript":
		return "GDScript"
	return "Global"


static func _type_name_from_any(value) -> String:
	if typeof(value) == TYPE_INT:
		return variant_type_to_name(int(value))
	return str(value)


static func normalize_type(type_name: String, fallback := "Variant") -> String:
	var clean := type_name.strip_edges()
	if clean == "" or clean == "var":
		return fallback
	if clean.begins_with("Array["):
		return "Array"
	if clean.begins_with("Dictionary["):
		return "Dictionary"
	return clean


static func get_methods_for_type(type_name: String, filter_text := "", limit := 120) -> Array:
	var target := normalize_type(type_name, "")
	var result: Array = []
	if target == "" or not ClassDB.class_exists(target):
		return result

	var filter := filter_text.to_lower().strip_edges()
	for method_data in _get_class_methods(target):
		if typeof(method_data) != TYPE_DICTIONARY:
			continue

		var method_name := str(method_data.get("name", ""))
		if method_name == "" or method_name.begins_with("_") or method_name.begins_with("@"):
			continue

		var signature := method_signature(target, method_data)
		var category := category_from_method_name(method_name)
		var haystack := "%s %s %s %s" % [target, method_name, signature, category]
		if filter != "" and not matches_tokens(haystack.to_lower(), filter):
			continue

		result.append({
			"kind": "method",
			"class": target,
			"name": method_name,
			"title": method_name,
			"signature": signature,
			"category": category,
			"description": signature,
			"method_data": method_data
		})
		if result.size() >= limit:
			break
	return result


static func search_common_methods(filter_text: String, limit := 160) -> Array:
	var result: Array = []
	var filter := filter_text.to_lower().strip_edges()
	var per_class_limit := 8 if filter.length() >= 2 else 4

	for type_name in _get_engine_classes_for_search():
		if filter != "" and not str(type_name).to_lower().contains(filter) and not _class_has_matching_method(str(type_name), filter):
			continue
		for item in get_methods_for_type(str(type_name), filter, per_class_limit):
			result.append(item)
			if result.size() >= limit:
				return result
	return result


static func get_method_data(type_name: String, method_name: String) -> Dictionary:
	var target := normalize_type(type_name, "")
	if target == "" or not ClassDB.class_exists(target):
		return {}
	for method_data in _get_class_methods(target):
		if typeof(method_data) == TYPE_DICTIONARY and str(method_data.get("name", "")) == method_name:
			return method_data.duplicate(true)
	return {}


static func get_properties_for_type(type_name: String, filter_text := "", limit := 120) -> Array:
	var target := normalize_type(type_name, "")
	var result: Array = []
	if target == "" or not ClassDB.class_exists(target):
		return result

	var filter := filter_text.to_lower().strip_edges()
	for property_data in _get_class_properties(target):
		if typeof(property_data) != TYPE_DICTIONARY:
			continue
		var property_name := str(property_data.get("name", ""))
		if property_name == "" or property_name.begins_with("_"):
			continue
		var type_out := variant_type_to_name(int(property_data.get("type", TYPE_NIL)))
		var haystack := "%s %s %s property" % [target, property_name, type_out]
		if filter != "" and not matches_tokens(haystack.to_lower(), filter):
			continue
		result.append({
			"kind": "property",
			"class": target,
			"name": property_name,
			"title": property_name,
			"type": type_out,
			"category": "Properties",
			"description": "%s.%s: %s" % [target, property_name, type_out],
			"property_data": property_data
		})
		if result.size() >= limit:
			break
	return result


static func _get_class_methods(type_name: String) -> Array:
	if _method_cache.has(type_name):
		return _method_cache[type_name] as Array
	_method_cache[type_name] = ClassDB.class_get_method_list(type_name, true)
	return _method_cache[type_name] as Array


static func _get_class_properties(type_name: String) -> Array:
	if _property_cache.has(type_name):
		return _property_cache[type_name] as Array
	_property_cache[type_name] = ClassDB.class_get_property_list(type_name, true)
	return _property_cache[type_name] as Array


static func _get_engine_classes_for_search() -> Array:
	if not _engine_classes_cache.is_empty():
		return _engine_classes_cache

	var all_classes: Array = []
	for _class_name in ClassDB.get_class_list():
		var clean := str(_class_name)
		if clean == "" or clean.begins_with("@"):
			continue
		all_classes.append(clean)
	all_classes.sort()

	var ordered: Array = []
	for priority_name in SEARCH_CLASS_PRIORITY:
		if all_classes.has(priority_name):
			ordered.append(priority_name)

	for _class_name in all_classes:
		if not ordered.has(_class_name):
			ordered.append(_class_name)

	_engine_classes_cache = ordered
	return _engine_classes_cache


static func _class_has_matching_method(type_name: String, filter: String) -> bool:
	if filter == "":
		return true
	for method_data in _get_class_methods(type_name):
		if typeof(method_data) != TYPE_DICTIONARY:
			continue
		var method_name := str(method_data.get("name", "")).to_lower()
		if method_name.contains(filter):
			return true
	return false


static func method_signature(target_type: String, method_data: Dictionary) -> String:
	var args: Array = []
	for arg in method_data.get("args", []):
		if typeof(arg) != TYPE_DICTIONARY:
			continue
		args.append("%s: %s" % [str(arg.get("name", "arg")), variant_type_to_name(int(arg.get("type", TYPE_NIL)))])
	if bool(method_data.get("vararg", false)):
		if args.is_empty():
			args.append("...args: Variant")
		elif not str(args[0]).begins_with("..."):
			args[0] = "..." + str(args[0])
	return "%s.%s(%s) -> %s" % [target_type, str(method_data.get("name", "method")), ", ".join(args), method_return_type(method_data)]


static func method_return_type(method_data: Dictionary) -> String:
	var ret = method_data.get("return", {})
	if typeof(ret) == TYPE_DICTIONARY:
		return variant_type_to_name(int(ret.get("type", TYPE_NIL)))
	return "void"


static func category_from_method_name(method_name: String) -> String:
	var clean := method_name.to_lower()
	if clean.begins_with("get_") or clean.begins_with("set_") or clean.find("property") >= 0:
		return "Properties"
	if clean.find("signal") >= 0 or clean.find("connect") >= 0 or clean.find("emit") >= 0:
		return "Signals"
	if clean.find("input") >= 0 or clean.find("mouse") >= 0 or clean.find("key") >= 0:
		return "Input"
	if clean.find("child") >= 0 or clean.find("parent") >= 0 or clean.find("tree") >= 0 or clean.find("node") >= 0:
		return "Scene Tree"
	if clean.find("position") >= 0 or clean.find("rotation") >= 0 or clean.find("transform") >= 0 or clean.find("scale") >= 0:
		return "Transform"
	if clean.find("file") >= 0 or clean.find("load") >= 0 or clean.find("save") >= 0:
		return "Files"
	return "Methods"


static func matches_tokens(haystack: String, search: String) -> bool:
	for token in search.split(" ", false):
		if haystack.find(str(token)) < 0:
			return false
	return true


static func variant_type_to_name(type_id: int) -> String:
	match type_id:
		TYPE_NIL: return "void"
		TYPE_BOOL: return "bool"
		TYPE_INT: return "int"
		TYPE_FLOAT: return "float"
		TYPE_STRING: return "String"
		TYPE_VECTOR2: return "Vector2"
		TYPE_VECTOR2I: return "Vector2i"
		TYPE_RECT2: return "Rect2"
		TYPE_RECT2I: return "Rect2i"
		TYPE_VECTOR3: return "Vector3"
		TYPE_VECTOR3I: return "Vector3i"
		TYPE_TRANSFORM2D: return "Transform2D"
		TYPE_VECTOR4: return "Vector4"
		TYPE_VECTOR4I: return "Vector4i"
		TYPE_PLANE: return "Plane"
		TYPE_QUATERNION: return "Quaternion"
		TYPE_AABB: return "AABB"
		TYPE_BASIS: return "Basis"
		TYPE_TRANSFORM3D: return "Transform3D"
		TYPE_PROJECTION: return "Projection"
		TYPE_COLOR: return "Color"
		TYPE_STRING_NAME: return "StringName"
		TYPE_NODE_PATH: return "NodePath"
		TYPE_RID: return "RID"
		TYPE_OBJECT: return "Object"
		TYPE_CALLABLE: return "Callable"
		TYPE_SIGNAL: return "Signal"
		TYPE_DICTIONARY: return "Dictionary"
		TYPE_ARRAY: return "Array"
		_: return "Variant"
