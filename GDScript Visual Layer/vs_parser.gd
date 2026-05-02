@tool
extends RefCounted

const LIFECYCLE_TEMPLATES := {
	"_enter_tree": "func _enter_tree() -> void:\n\tpass\n",
	"_ready": "func _ready() -> void:\n\tpass\n",
	"_process": "func _process(delta: float) -> void:\n\tpass\n",
	"_physics_process": "func _physics_process(delta: float) -> void:\n\tpass\n",
	"_input": "func _input(event: InputEvent) -> void:\n\tpass\n",
	"_unhandled_input": "func _unhandled_input(event: InputEvent) -> void:\n\tpass\n",
	"_exit_tree": "func _exit_tree() -> void:\n\tpass\n"
}

const CALL_EXCLUDE := [
	"if", "elif", "for", "while", "match", "return", "await", "func", "var",
	"assert", "preload", "load"
]


static func parse_script(path: String) -> Dictionary:
	var text := _read_text(path)
	var lines := text.split("\n", false)
	var parsed := {
		"path": path,
		"text": text,
		"extends": "Node",
		"script_class": "",
		"variables": [],
		"functions": [],
		"variable_map": {},
		"function_map": {},
		"local_maps": {}
	}

	var pending_annotations: Array = []
	var pending_comments: Array = []
	var i := 0

	while i < lines.size():
		var raw := str(lines[i])
		var stripped := raw.strip_edges()
		var indent := _indent_of(raw)

		if indent == "" and stripped.begins_with("extends "):
			parsed["extends"] = stripped.substr(8).strip_edges().get_slice(" ", 0)
			i += 1
			continue

		if indent == "" and stripped.begins_with("class_name "):
			parsed["script_class"] = stripped.substr(11).strip_edges().get_slice(" ", 0)
			i += 1
			continue

		if indent == "" and stripped.begins_with("@"): 
			pending_annotations.append(stripped)
			i += 1
			continue

		if indent == "" and stripped.begins_with("##"):
			pending_comments.append(stripped)
			i += 1
			continue

		if indent == "" and _is_var_line(stripped):
			var variable := _parse_variable(stripped, pending_annotations, i + 1)
			if not variable.is_empty():
				parsed["variables"].append(variable)
				parsed["variable_map"][str(variable.get("name", ""))] = variable
			pending_annotations.clear()
			pending_comments.clear()
			i += 1
			continue

		if indent == "" and _is_func_line(stripped):
			var end_index := _find_function_end(lines, i)
			var function_lines := PackedStringArray()
			for j in range(i, end_index):
				function_lines.append(str(lines[j]))

			var function_data := _parse_function(stripped, function_lines, pending_comments, pending_annotations, i + 1, end_index)
			parsed["functions"].append(function_data)
			parsed["function_map"][str(function_data.get("id", ""))] = function_data
			pending_annotations.clear()
			pending_comments.clear()
			i = end_index
			continue

		if stripped != "":
			pending_annotations.clear()
			pending_comments.clear()

		i += 1

	for function_index in range(parsed["functions"].size()):
		var function_data: Dictionary = parsed["functions"][function_index]
		var local_map := {}
		function_data["statements"] = _parse_statements(function_data["body_lines"], int(function_data.get("line_start", 1)) + 1, parsed, local_map)
		parsed["functions"][function_index] = function_data
		parsed["function_map"][str(function_data.get("id", ""))] = function_data
		parsed["local_maps"][str(function_data.get("id", ""))] = local_map

	return parsed


static func lifecycle_names() -> Array:
	return LIFECYCLE_TEMPLATES.keys()


static func callback_template(callback_name: String) -> String:
	return str(LIFECYCLE_TEMPLATES.get(callback_name, "func %s() -> void:\n\tpass\n" % callback_name))


static func _parse_variable(line: String, annotations: Array, line_number: int) -> Dictionary:
	var rest := line
	var is_static := false

	if rest.begins_with("static var "):
		is_static = true
		rest = rest.substr(11)
	elif rest.begins_with("var "):
		rest = rest.substr(4)
	else:
		return {}

	var assignment := _split_assignment(rest)
	var name_part := str(assignment.get("left", rest)).strip_edges()
	var default_value := str(assignment.get("right", ""))
	var variable_name := name_part
	var type_name := "Variant"

	var colon_pos := name_part.find(":")
	if colon_pos >= 0:
		variable_name = name_part.substr(0, colon_pos).strip_edges()
		type_name = name_part.substr(colon_pos + 1).strip_edges()
		if type_name == "":
			type_name = _guess_type_from_expression(default_value)
	else:
		type_name = _guess_type_from_expression(default_value)

	var kind := "member"
	for annotation in annotations:
		var annotation_text := str(annotation)
		if annotation_text.begins_with("@export"):
			kind = "export"
		elif annotation_text.begins_with("@onready"):
			kind = "onready"

	return {
		"id": _sanitize_id(variable_name),
		"name": variable_name,
		"type": type_name,
		"default": default_value,
		"kind": kind,
		"is_static": is_static,
		"line": line_number,
		"annotations": annotations.duplicate()
	}


static func _parse_function(header: String, function_lines: PackedStringArray, comments: Array, annotations: Array, start_line: int, end_index: int) -> Dictionary:
	var clean_header := header
	var is_static := false

	if clean_header.begins_with("static func "):
		is_static = true
		clean_header = "func " + clean_header.substr(12)

	var name_start := clean_header.find("func ") + 5
	var paren_start := clean_header.find("(", name_start)
	var paren_end := clean_header.rfind(")")
	var function_name := clean_header.substr(name_start, paren_start - name_start).strip_edges()
	var params_text := ""

	if paren_start >= 0 and paren_end > paren_start:
		params_text = clean_header.substr(paren_start + 1, paren_end - paren_start - 1)

	var return_type := "void"
	var arrow_pos := clean_header.find("->", paren_end)
	if arrow_pos >= 0:
		var colon_pos := clean_header.find(":", arrow_pos)
		if colon_pos < 0:
			colon_pos = clean_header.length()
		return_type = clean_header.substr(arrow_pos + 2, colon_pos - arrow_pos - 2).strip_edges()

	var marker := _parse_vs_marker(comments)
	var function_id := str(marker.get("id", ""))
	if function_id == "":
		function_id = function_name

	var marked := bool(marker.get("marked", false))
	var function_kind := "code"
	if LIFECYCLE_TEMPLATES.has(function_name):
		function_kind = "lifecycle"
	elif marked:
		function_kind = "custom"

	var body_lines := PackedStringArray()
	for i in range(1, function_lines.size()):
		body_lines.append(function_lines[i])

	return {
		"id": _sanitize_id(function_id),
		"name": function_name,
		"title": str(marker.get("title", _title_from_name(function_name))),
		"category": str(marker.get("category", "Script")),
		"params": _parse_params(params_text),
		"return_type": return_type,
		"line_start": start_line,
		"line_end": end_index,
		"header": header,
		"body": "\n".join(body_lines),
		"body_lines": body_lines,
		"statements": [],
		"comments": comments.duplicate(),
		"annotations": annotations.duplicate(),
		"marked": marked,
		"kind": function_kind,
		"is_static": is_static
	}


static func _parse_statements(body_lines: PackedStringArray, first_body_line: int, parsed: Dictionary, local_map: Dictionary) -> Array:
	var result: Array = []
	var function_names := {}

	for function_data in parsed.get("functions", []):
		function_names[str(function_data.get("name", ""))] = function_data

	var i := 0
	var occurrence := 0

	while i < body_lines.size():
		var raw_line := str(body_lines[i])
		var stripped := raw_line.strip_edges()

		if stripped == "" or stripped.begins_with("#"):
			i += 1
			continue

		var line_number := first_body_line + i

		if stripped.begins_with("if ") and stripped.ends_with(":"):
			var branch_data := _parse_if_block(body_lines, i, first_body_line, parsed, local_map, function_names, occurrence)
			result.append(branch_data.get("statement", {}))
			i = int(branch_data.get("next_index", i + 1))
			occurrence += 1
			continue

		var statement := _parse_single_statement(stripped, raw_line, line_number, parsed, local_map, function_names, occurrence)
		result.append(statement)
		occurrence += 1
		i += 1

	return result


static func _parse_if_block(body_lines: PackedStringArray, start_index: int, first_body_line: int, parsed: Dictionary, local_map: Dictionary, function_names: Dictionary, occurrence: int) -> Dictionary:
	var if_line := str(body_lines[start_index]).strip_edges()
	var base_indent := _indent_of(str(body_lines[start_index]))
	var child_indent := ""
	var condition := if_line.substr(3, if_line.length() - 4).strip_edges()
	var true_lines := PackedStringArray()
	var false_lines := PackedStringArray()
	var i := start_index + 1
	var in_false := false

	while i < body_lines.size():
		var raw := str(body_lines[i])
		var stripped := raw.strip_edges()
		var indent := _indent_of(raw)

		if stripped == "":
			i += 1
			continue

		if indent.length() <= base_indent.length():
			if stripped == "else:" and indent == base_indent:
				in_false = true
				i += 1
				continue
			break

		if child_indent == "":
			child_indent = indent

		var normalized := raw.substr(min(child_indent.length(), raw.length()))
		if in_false:
			false_lines.append(normalized)
		else:
			true_lines.append(normalized)
		i += 1

	var true_local := local_map
	var false_local := local_map
	var statement := {
		"id": "branch_%s_%s" % [first_body_line + start_index, occurrence],
		"kind": "branch",
		"line": first_body_line + start_index,
		"text": if_line,
		"condition": condition,
		"condition_expr": parse_expression(condition, parsed, local_map),
		"true_statements": _parse_statements(true_lines, first_body_line + start_index + 1, parsed, true_local),
		"false_statements": _parse_statements(false_lines, first_body_line + start_index + 1 + true_lines.size() + 1, parsed, false_local)
	}

	return {"statement": statement, "next_index": i}


static func _parse_single_statement(stripped: String, raw_line: String, line_number: int, parsed: Dictionary, local_map: Dictionary, function_names: Dictionary, occurrence: int) -> Dictionary:
	if stripped == "return" or stripped.begins_with("return "):
		var return_text := ""
		if stripped.length() > 6:
			return_text = stripped.substr(6).strip_edges()
		return {
			"id": "return_%s_%s" % [line_number, occurrence],
			"kind": "return",
			"line": line_number,
			"text": stripped,
			"value_text": return_text,
			"value_expr": parse_expression(return_text, parsed, local_map) if return_text != "" else {}
		}

	var assignment := _split_assignment(stripped)
	if not assignment.is_empty():
		var left := str(assignment.get("left", "")).strip_edges()
		var right := str(assignment.get("right", "")).strip_edges()
		var operator_text := str(assignment.get("operator", "="))
		var value_expr := parse_expression(right, parsed, local_map)
		var value_type := str(value_expr.get("value_type", _guess_type_from_expression(right)))

		if left.begins_with("var "):
			var declaration := left.substr(4).strip_edges()
			var local_name := declaration
			var local_type := value_type
			var colon_pos := declaration.find(":")
			if colon_pos >= 0:
				local_name = declaration.substr(0, colon_pos).strip_edges()
				local_type = declaration.substr(colon_pos + 1).strip_edges()
				if local_type == "":
					local_type = value_type
			local_map[local_name] = {"name": local_name, "type": local_type, "kind": "local", "line": line_number}
			return {
				"id": "local_%s_%s_%s" % [line_number, occurrence, _sanitize_id(local_name)],
				"kind": "local_assign",
				"line": line_number,
				"text": stripped,
				"name": local_name,
				"type": local_type,
				"operator": operator_text,
				"value_expr": value_expr,
				"value_type": local_type
			}

		if left.find(".") >= 0:
			var dot := left.rfind(".")
			var target_expr := left.substr(0, dot).strip_edges()
			var property_name := left.substr(dot + 1).strip_edges()
			return {
				"id": "set_%s_%s_%s" % [line_number, occurrence, _sanitize_id(left)],
				"kind": "set_property",
				"line": line_number,
				"text": stripped,
				"target_expr": target_expr,
				"target_type": _type_for_expression(target_expr, parsed, local_map),
				"property_name": property_name,
				"operator": operator_text,
				"value_expr": value_expr,
				"value_type": value_type
			}

		return {
			"id": "assign_%s_%s_%s" % [line_number, occurrence, _sanitize_id(left)],
			"kind": "assignment",
			"line": line_number,
			"text": stripped,
			"target": left,
			"operator": operator_text,
			"value_expr": value_expr,
			"value_type": value_type
		}

	var expr := parse_expression(stripped, parsed, local_map)
	if str(expr.get("kind", "")) == "call_expr":
		var call_name := str(expr.get("call_name", ""))
		var plain_name := str(expr.get("method_name", call_name))

		if function_names.has(plain_name):
			return {
				"id": "call_%s_%s_%s" % [line_number, occurrence, _sanitize_id(call_name)],
				"kind": "script_call",
				"line": line_number,
				"text": stripped,
				"call_name": plain_name,
				"args": expr.get("args", [])
			}

		return {
			"id": "method_%s_%s_%s" % [line_number, occurrence, _sanitize_id(call_name)],
			"kind": "method_call" if str(expr.get("target_expr", "")) != "" else "builtin_call",
			"line": line_number,
			"text": stripped,
			"method_name": plain_name,
			"target_expr": str(expr.get("target_expr", "")),
			"target_type": str(expr.get("target_type", "")),
			"args": expr.get("args", []),
			"value_type": str(expr.get("value_type", "Variant"))
		}

	return {
		"id": "stmt_%s_%s" % [line_number, occurrence],
		"kind": "statement",
		"line": line_number,
		"text": stripped,
		"indent": _indent_of(raw_line)
	}


static func parse_expression(expression_text: String, parsed: Dictionary, local_map: Dictionary) -> Dictionary:
	var text := expression_text.strip_edges()
	if text == "":
		return {"kind": "expression", "text": "", "value_type": "Variant"}

	var call_data := _parse_entire_call(text)
	if not call_data.is_empty():
		var call_name := str(call_data.get("name", ""))
		var method_name := call_name
		var target_expr := ""
		var target_type := ""

		if call_name.find(".") >= 0:
			var dot := call_name.rfind(".")
			target_expr = call_name.substr(0, dot).strip_edges()
			method_name = call_name.substr(dot + 1).strip_edges()
			target_type = _type_for_expression(target_expr, parsed, local_map)
		elif ClassDB.class_exists(call_name):
			target_expr = call_name
			target_type = call_name

		var script_function := _function_data_by_name(parsed, method_name)
		var value_type := _guess_call_return_type(method_name, target_type, call_name)
		if not script_function.is_empty():
			value_type = str(script_function.get("return_type", "Variant"))
		return {
			"kind": "call_expr",
			"text": text,
			"call_name": call_name,
			"method_name": method_name,
			"target_expr": target_expr,
			"target_type": target_type,
			"script_function": not script_function.is_empty(),
			"function_id": str(script_function.get("id", "")),
			"args_text": str(call_data.get("args", "")),
			"args": _split_call_args(str(call_data.get("args", "")), parsed, local_map),
			"value_type": value_type
		}

	return {"kind": "expression", "text": text, "value_type": _guess_type_from_expression(text)}


static func _function_data_by_name(parsed: Dictionary, function_name: String) -> Dictionary:
	for function_data in parsed.get("functions", []):
		if typeof(function_data) == TYPE_DICTIONARY and str(function_data.get("name", "")) == function_name:
			return function_data
	return {}


static func _split_call_args(args_text: String, parsed: Dictionary, local_map: Dictionary) -> Array:
	var result: Array = []
	for part in _split_top_level(args_text):
		var clean := str(part).strip_edges()
		if clean != "":
			result.append(parse_expression(clean, parsed, local_map))
	return result


static func _type_for_expression(expression_text: String, parsed: Dictionary, local_map: Dictionary) -> String:
	var text := expression_text.strip_edges()
	if text == "self":
		return str(parsed.get("extends", "Node"))
	if local_map.has(text):
		var local_data = local_map[text]
		if typeof(local_data) == TYPE_DICTIONARY:
			return str(local_data.get("type", "Variant"))
	var variable_map: Dictionary = parsed.get("variable_map", {})
	if variable_map.has(text):
		var variable_data = variable_map[text]
		if typeof(variable_data) == TYPE_DICTIONARY:
			return str(variable_data.get("type", "Variant"))
	var root := text.get_slice(".", 0)
	if variable_map.has(root):
		var root_data = variable_map[root]
		if typeof(root_data) == TYPE_DICTIONARY:
			return str(root_data.get("type", "Variant"))
	if ClassDB.class_exists(root):
		return root
	return _guess_type_from_expression(text)


static func _guess_call_return_type(method_name: String, target_type: String, call_name: String) -> String:
	if call_name == "Callable":
		return "Callable"
	match call_name:
		"str": return "String"
		"int", "randi", "randi_range", "len", "typeof", "wrapi": return "int"
		"float", "pingpong", "wrapf", "snapped", "sqrt", "pow", "sin", "cos", "tan", "asin", "acos", "atan", "atan2", "deg_to_rad", "rad_to_deg", "move_toward", "randf", "randf_range": return "float"
		"bool", "is_instance_valid": return "bool"
		"range": return "Array"
		"print", "printerr", "print_rich", "push_warning", "push_error": return "void"

	if target_type != "" and ClassDB.class_exists(target_type):
		for method in ClassDB.class_get_method_list(target_type, true):
			if typeof(method) == TYPE_DICTIONARY and str(method.get("name", "")) == method_name:
				var ret = method.get("return", {})
				if typeof(ret) == TYPE_DICTIONARY:
					return _variant_type_to_name(int(ret.get("type", TYPE_NIL)))
	return "Variant"


static func _guess_type_from_expression(text: String) -> String:
	var clean := text.strip_edges()
	if clean == "true" or clean == "false":
		return "bool"
	if clean.begins_with("\"") or clean.begins_with("'"):
		return "String"
	if clean.is_valid_int():
		return "int"
	if clean.is_valid_float():
		return "float"
	for type_name in ["Vector2", "Vector3", "Vector4", "Color", "Transform3D", "NodePath", "Callable"]:
		if clean.begins_with(type_name + "("):
			return type_name
	return "Variant"


static func _parse_entire_call(text: String) -> Dictionary:
	var open_pos := text.find("(")
	if open_pos <= 0 or not text.ends_with(")"):
		return {}
	var close_pos := _find_matching(text, open_pos, "(", ")")
	if close_pos != text.length() - 1:
		return {}
	var name := text.substr(0, open_pos).strip_edges()
	if name == "" or CALL_EXCLUDE.has(name):
		return {}
	return {"name": name, "args": text.substr(open_pos + 1, close_pos - open_pos - 1)}


static func _split_assignment(line: String) -> Dictionary:
	var operators := [":=", "=", "+=", "-=", "*=", "/=", "%="]
	var depth := 0
	var in_string := false
	var string_char := ""

	for i in range(line.length()):
		var c := line[i]
		if in_string:
			if c == string_char:
				in_string = false
			continue
		if c == "\"" or c == "'":
			in_string = true
			string_char = c
			continue
		if c == "(" or c == "[" or c == "{":
			depth += 1
		elif c == ")" or c == "]" or c == "}":
			depth -= 1
		elif depth == 0:
			for operator_text in operators:
				if line.substr(i, operator_text.length()) == operator_text:
					if operator_text == "=" and i > 0:
						var prev := line[i - 1]
						if prev == "=" or prev == ">" or prev == "<" or prev == "!":
							continue
					if operator_text == "=" and i + 1 < line.length() and line[i + 1] == "=":
						continue
					return {
						"left": line.substr(0, i).strip_edges(),
						"operator": operator_text,
						"right": line.substr(i + operator_text.length()).strip_edges()
					}
	return {}


static func _parse_vs_marker(comments: Array) -> Dictionary:
	var result := {}
	for comment in comments:
		var line := str(comment).strip_edges()
		if line.begins_with("##"):
			line = line.substr(2).strip_edges()
		if line.begins_with("@vs_node"):
			result["marked"] = true
			for part in line.split(" ", false):
				var token := str(part)
				var eq_pos := token.find("=")
				if eq_pos > 0:
					var key := token.substr(0, eq_pos).strip_edges()
					var value := token.substr(eq_pos + 1).strip_edges().trim_prefix("\"").trim_suffix("\"")
					result[key] = value
	return result


static func _parse_params(params_text: String) -> Array:
	var result: Array = []
	for raw_part in _split_top_level(params_text):
		var part := str(raw_part).strip_edges()
		if part == "":
			continue
		var default_pos := part.find("=")
		if default_pos >= 0:
			part = part.substr(0, default_pos).strip_edges()
		var name := part
		var type_name := "Variant"
		var colon_pos := part.find(":")
		if colon_pos >= 0:
			name = part.substr(0, colon_pos).strip_edges()
			type_name = part.substr(colon_pos + 1).strip_edges()
		result.append({"name": name, "type": type_name})
	return result


static func _split_top_level(text: String) -> Array:
	var result: Array = []
	var start := 0
	var depth := 0
	var in_string := false
	var string_char := ""
	for i in range(text.length()):
		var c := text[i]
		if in_string:
			if c == string_char:
				in_string = false
			continue
		if c == "\"" or c == "'":
			in_string = true
			string_char = c
			continue
		if c == "(" or c == "[" or c == "{":
			depth += 1
		elif c == ")" or c == "]" or c == "}":
			depth -= 1
		elif c == "," and depth == 0:
			result.append(text.substr(start, i - start))
			start = i + 1
	result.append(text.substr(start))
	return result


static func _find_matching(text: String, open_index: int, open_char: String, close_char: String) -> int:
	var depth := 0
	var in_string := false
	var string_char := ""
	for i in range(open_index, text.length()):
		var c := text[i]
		if in_string:
			if c == string_char:
				in_string = false
			continue
		if c == "\"" or c == "'":
			in_string = true
			string_char = c
			continue
		if c == open_char:
			depth += 1
		elif c == close_char:
			depth -= 1
			if depth == 0:
				return i
	return -1


static func _is_var_line(stripped: String) -> bool:
	return stripped.begins_with("var ") or stripped.begins_with("static var ")


static func _is_func_line(stripped: String) -> bool:
	return stripped.begins_with("func ") or stripped.begins_with("static func ")


static func _find_function_end(lines: PackedStringArray, header_index: int) -> int:
	var i := header_index + 1
	while i < lines.size():
		var line := str(lines[i])
		var stripped := line.strip_edges()
		if stripped == "":
			i += 1
			continue
		if _indent_of(line) == "" and (_is_func_line(stripped) or stripped.begins_with("@") or stripped.begins_with("##")):
			break
		i += 1
	return i


static func _indent_of(line: String) -> String:
	var result := ""
	for i in line.length():
		var c := line[i]
		if c == "\t" or c == " ":
			result += c
		else:
			break
	return result


static func _title_from_name(function_name: String) -> String:
	var parts := function_name.trim_prefix("_").split("_", false)
	var titled: Array = []
	for part in parts:
		titled.append(str(part).capitalize())
	return " ".join(titled)


static func _variant_type_to_name(type_id: int) -> String:
	match type_id:
		TYPE_NIL: return "void"
		TYPE_BOOL: return "bool"
		TYPE_INT: return "int"
		TYPE_FLOAT: return "float"
		TYPE_STRING: return "String"
		TYPE_VECTOR2: return "Vector2"
		TYPE_VECTOR3: return "Vector3"
		TYPE_VECTOR4: return "Vector4"
		TYPE_COLOR: return "Color"
		TYPE_OBJECT: return "Object"
		TYPE_CALLABLE: return "Callable"
		TYPE_ARRAY: return "Array"
		TYPE_DICTIONARY: return "Dictionary"
		_: return "Variant"


static func _sanitize_id(text: String) -> String:
	var result := ""
	for i in text.length():
		var c := text[i]
		if c == "_" or (c >= "A" and c <= "Z") or (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			result += c
		else:
			result += "_"
	if result == "":
		result = "item"
	if result[0] >= "0" and result[0] <= "9":
		result = "_" + result
	return result


static func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text
