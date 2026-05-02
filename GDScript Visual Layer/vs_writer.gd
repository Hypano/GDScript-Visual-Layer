@tool
extends RefCounted

var NodeFactory


func _init(node_factory_script = null) -> void:
	NodeFactory = node_factory_script


func generate_function_body(graph: GraphEdit) -> PackedStringArray:
	var lines := PackedStringArray()
	var entry := _find_entry(graph)

	if entry == null:
		for node in _exec_nodes_sorted(graph):
			var line := _line_for_node(graph, node)
			if line.strip_edges() != "":
				lines.append(line)
	else:
		var first := _next_exec_node(graph, entry, 0)
		_follow_exec(graph, first, lines, {})

	if lines.is_empty():
		lines.append("pass")

	return lines


func replace_function_body(script_path: String, function_data: Dictionary, body_lines: PackedStringArray) -> bool:
	var text := build_replaced_function_text(_read_text(script_path), function_data, body_lines)
	if text == "":
		return false
	return _write_text(script_path, text)


func build_replaced_function_text(original_text: String, function_data: Dictionary, body_lines: PackedStringArray) -> String:
	if original_text == "":
		return ""

	var lines := original_text.split("\n", true)
	if lines.size() > 0 and str(lines[lines.size() - 1]) == "":
		lines.remove_at(lines.size() - 1)

	var range_data := _find_function_range(lines, function_data)
	if range_data.is_empty():
		return ""

	var header_index := int(range_data.get("header", -1))
	var end_index := int(range_data.get("end", header_index + 1))
	if header_index < 0 or header_index >= lines.size():
		return ""

	var body_indent := _detect_body_indent(lines, header_index, end_index)
	var output := PackedStringArray()

	for index in range(0, header_index + 1):
		output.append(str(lines[index]))

	for body_line in body_lines:
		var clean := str(body_line).rstrip("\n")
		if clean.strip_edges() == "":
			output.append("")
		else:
			for sub_line in clean.split("\n", true):
				if str(sub_line).strip_edges() == "":
					output.append("")
				else:
					output.append(body_indent + str(sub_line).rstrip(" "))

	for index in range(end_index, lines.size()):
		output.append(str(lines[index]))

	return _format_script_spacing("\n".join(output))


func find_function_line(text: String, function_data: Dictionary) -> int:
	if text == "":
		return int(function_data.get("line_start", 1))

	var lines := text.split("\n", true)
	if lines.size() > 0 and str(lines[lines.size() - 1]) == "":
		lines.remove_at(lines.size() - 1)

	var range_data := _find_function_range(lines, function_data)
	if range_data.is_empty():
		return int(function_data.get("line_start", 1))

	return int(range_data.get("header", 0)) + 1


func _find_function_range(lines: PackedStringArray, function_data: Dictionary) -> Dictionary:
	var function_name := str(function_data.get("name", ""))
	if function_name == "":
		return {}

	var old_header_index := int(function_data.get("line_start", 1)) - 1
	var best_header := -1
	var best_distance := 2147483647

	for index in range(lines.size()):
		var line := str(lines[index])
		if not _is_matching_function_header(line, function_name):
			continue

		var distance := abs(index - old_header_index)
		if best_header == -1 or distance < best_distance:
			best_header = index
			best_distance = distance

	if best_header == -1:
		return {}

	return {
		"header": best_header,
		"end": _find_function_end(lines, best_header)
	}


func _is_matching_function_header(line: String, function_name: String) -> bool:
	if _indent_of(line) != "":
		return false

	var stripped := line.strip_edges()
	if stripped.begins_with("static func "):
		stripped = stripped.substr(7).strip_edges()

	if not stripped.begins_with("func "):
		return false

	var rest := stripped.substr(5).strip_edges()
	return rest.begins_with(function_name + "(")


func _find_function_end(lines: PackedStringArray, header_index: int) -> int:
	var index := header_index + 1
	while index < lines.size():
		var line := str(lines[index])
		var stripped := line.strip_edges()

		if stripped != "" and _indent_of(line) == "":
			return index

		index += 1

	return lines.size()


func append_callback(script_path: String, callback_text: String) -> bool:
	var text := build_appended_callback_text(_read_text(script_path), callback_text)
	if text == "":
		return false
	return _write_text(script_path, text)


func build_appended_callback_text(original_text: String, callback_text: String) -> String:
	var clean_callback := callback_text.strip_edges()
	if original_text == "" or clean_callback == "":
		return ""

	var clean := original_text.rstrip("\n")
	clean += "\n\n\n" + clean_callback + "\n"
	return _format_script_spacing(clean)


func _detect_body_indent(lines: PackedStringArray, header_index: int, end_index: int) -> String:
	for index in range(header_index + 1, end_index):
		var line := str(lines[index])
		if line.strip_edges() == "":
			continue
		var indent := _indent_of(line)
		if indent != "":
			return indent
	return "\t"


func _find_entry(graph: GraphEdit) -> GraphNode:
	for child in graph.get_children():
		if child is GraphNode and str(child.get_meta("gdvl_type", "")) == "entry":
			return child
	return null


func _exec_nodes_sorted(graph: GraphEdit) -> Array:
	var nodes: Array = []
	for child in graph.get_children():
		if child is GraphNode and _is_exec_node(child):
			nodes.append(child)
	nodes.sort_custom(func(a: GraphNode, b: GraphNode) -> bool:
		if abs(a.position_offset.y - b.position_offset.y) > 10.0:
			return a.position_offset.y < b.position_offset.y
		return a.position_offset.x < b.position_offset.x
	)
	return nodes


func _is_exec_node(node: GraphNode) -> bool:
	return ["statement", "script_call", "method_call", "builtin", "set_property", "assignment", "local_assign", "branch", "return"].has(str(node.get_meta("gdvl_type", "")))


func _follow_exec(graph: GraphEdit, node: GraphNode, lines: PackedStringArray, visited: Dictionary) -> void:
	var current := node
	var guard := 0

	while current != null and guard < 1000:
		guard += 1
		var node_name := str(current.name)
		if visited.has(node_name):
			return
		visited[node_name] = true

		var node_type := str(current.get_meta("gdvl_type", ""))
		if node_type == "branch":
			_append_branch(graph, current, lines, visited)
			return
		if node_type == "return":
			var return_line := _line_for_node(graph, current)
			if return_line.strip_edges() != "":
				lines.append(return_line)
			return

		var line := _line_for_node(graph, current)
		if line.strip_edges() != "":
			lines.append(line)

		current = _next_exec_node(graph, current, 0)


func _append_branch(graph: GraphEdit, branch: GraphNode, lines: PackedStringArray, visited: Dictionary) -> void:
	var condition_fallback := _editable_default_for_slot(branch, 1)
	if condition_fallback == "":
		condition_fallback = str(branch.get_meta("condition", "true"))
	var condition := _input_expression(graph, branch, 1, condition_fallback)
	lines.append("if %s:" % condition)

	var true_lines := PackedStringArray()
	_follow_exec(graph, _next_exec_node(graph, branch, 0), true_lines, visited.duplicate())
	if true_lines.is_empty():
		true_lines.append("pass")
	for line in true_lines:
		lines.append("\t" + str(line))

	var false_start := _next_exec_node(graph, branch, 1)
	if false_start != null:
		var false_lines := PackedStringArray()
		_follow_exec(graph, false_start, false_lines, visited.duplicate())
		lines.append("else:")
		if false_lines.is_empty():
			false_lines.append("pass")
		for line in false_lines:
			lines.append("\t" + str(line))


func _next_exec_node(graph: GraphEdit, from_node: GraphNode, from_port: int) -> GraphNode:
	for connection in graph.get_connection_list():
		if typeof(connection) != TYPE_DICTIONARY:
			continue
		if str(connection.get("from_node", "")) == str(from_node.name) and int(connection.get("from_port", -1)) == from_port:
			var to_node = graph.get_node_or_null(NodePath(str(connection.get("to_node", ""))))
			if to_node is GraphNode:
				return to_node
	return null


func _line_for_node(graph: GraphEdit, node: GraphNode) -> String:
	var node_type := str(node.get_meta("gdvl_type", ""))

	match node_type:
		"statement":
			var edited_code := _editable_default_for_slot(node, 0)
			return edited_code if edited_code.strip_edges() != "" else str(node.get_meta("statement_text", "pass"))
		"local_assign":
			var name := str(node.get_meta("variable_name", "value"))
			var operator_text := str(node.get_meta("operator", ":="))
			return "var %s %s %s" % [name, operator_text, _input_expression(graph, node, 1, "TODO_value")]
		"assignment":
			return "%s %s %s" % [str(node.get_meta("target", "value")), str(node.get_meta("operator", "=")), _input_expression(graph, node, 1, "TODO_value")]
		"set_property":
			var target := _input_expression(graph, node, 1, str(node.get_meta("target_expr", "TODO_target")))
			var property_name := str(node.get_meta("property_name", "property"))
			var operator_text := str(node.get_meta("operator", "="))
			return "%s.%s %s %s" % [target, property_name, operator_text, _input_expression(graph, node, 2, "TODO_value")]
		"script_call":
			return "%s(%s)" % [str(node.get_meta("function_name", "function")), _args_for_node(graph, node, 1)]
		"script_value_call":
			return "%s(%s)" % [str(node.get_meta("function_name", "function")), _args_for_node(graph, node, 0)]
		"method_call":
			var method_name := str(node.get_meta("method_name", "method"))
			var target_fallback := str(node.get_meta("target_expression", ""))
			var target := target_fallback
			if _has_input_port(node, 1):
				target = _input_expression(graph, node, 1, target_fallback)
			var first_arg := 2 if target_fallback != "" else 1
			if target == "" or target == "self":
				return "%s(%s)" % [method_name, _args_for_node(graph, node, first_arg)]
			return "%s.%s(%s)" % [target, method_name, _args_for_node(graph, node, first_arg)]
		"builtin":
			return "%s(%s)" % [str(node.get_meta("builtin_name", "print")), _args_for_node(graph, node, 1)]
		"return":
			var fallback := _editable_default_for_slot(node, 1)
			if fallback == "":
				fallback = str(node.get_meta("value_text", ""))
			var value := _input_expression(graph, node, 1, fallback)
			return "return" if value.strip_edges() == "" else "return " + value
	return ""


func _args_for_node(graph: GraphEdit, node: GraphNode, first_input_port: int) -> String:
	var inputs: Array = node.get_meta("input_ports", [])
	var result: Array = []
	for port_index in range(first_input_port, inputs.size()):
		var fallback_name := "arg"
		var fallback_value := ""
		if typeof(inputs[port_index]) == TYPE_DICTIONARY:
			fallback_name = str(inputs[port_index].get("name", "arg"))
			fallback_value = str(inputs[port_index].get("default", ""))
		var used_editable := false
		var edit = node.find_child("gdvl_input_" + str(port_index), true, false)
		if edit is LineEdit:
			fallback_value = str(edit.text)
			used_editable = true
		var fallback := _format_builtin_fallback(str(node.get_meta("builtin_name", "")), port_index, fallback_value, fallback_name, used_editable)
		result.append(_input_expression(graph, node, port_index, fallback))
	return ", ".join(result)


func _editable_default_for_slot(node: GraphNode, slot_index: int) -> String:
	var edit = node.find_child("gdvl_input_" + str(slot_index), true, false)
	if edit is LineEdit:
		return str(edit.text)
	return ""


func _format_builtin_fallback(builtin_name: String, port_index: int, fallback_value: String, fallback_name: String, used_editable := false) -> String:
	if fallback_value != "":
		if builtin_name in ["print", "printerr", "print_rich", "push_warning", "push_error"]:
			return _quote_string_if_needed(fallback_value)
		if builtin_name == "str" and used_editable:
			return _quote_string_if_needed(fallback_value)
		return fallback_value
	return "TODO_" + fallback_name


func _quote_string_if_needed(value: String) -> String:
	var clean := value.strip_edges()
	if _is_already_quoted(clean):
		return clean
	return _quote_string(value)


func _quote_string(value: String) -> String:
	var escaped := value.replace("\\", "\\\\").replace("\"", "\\\"")
	return "\"" + escaped + "\""


func _is_already_quoted(value: String) -> bool:
	if value.length() < 2:
		return false
	var first := value[0]
	var last := value[value.length() - 1]
	return (first == "\"" and last == "\"") or (first == "'" and last == "'")


func _input_expression(graph: GraphEdit, node: GraphNode, input_port: int, fallback: String) -> String:
	for connection in graph.get_connection_list():
		if typeof(connection) != TYPE_DICTIONARY:
			continue
		if str(connection.get("to_node", "")) == str(node.name) and int(connection.get("to_port", -1)) == input_port:
			var from_node = graph.get_node_or_null(NodePath(str(connection.get("from_node", ""))))
			if from_node is GraphNode:
				return _output_expression(graph, from_node, int(connection.get("from_port", 0)))
	return fallback


func _output_expression(graph: GraphEdit, node: GraphNode, output_port: int) -> String:
	var node_type := str(node.get_meta("gdvl_type", ""))

	match node_type:
		"variable":
			return str(node.get_meta("variable_name", "value"))
		"local_assign":
			return str(node.get_meta("variable_name", "value"))
		"literal":
			var edited_literal := _editable_default_for_slot(node, 0)
			if edited_literal != "":
				return _format_literal_output(edited_literal, str(node.get_meta("value_type", "Variant")))
			return str(node.get_meta("literal_value", "0"))
		"expression":
			var edited_expression := _editable_default_for_slot(node, 0)
			if edited_expression != "":
				return edited_expression
			return str(node.get_meta("expression_text", "value"))
		"math":
			return "(%s %s %s)" % [
				_input_expression(graph, node, 0, "TODO_A"),
				NodeFactory.math_operator(str(node.get_meta("operation", "Add"))) if NodeFactory != null else "+",
				_input_expression(graph, node, 1, "TODO_B")
			]
		"value_call", "method_call":
			var method_name := str(node.get_meta("method_name", "method"))
			var target_fallback := str(node.get_meta("target_expression", ""))
			var target := target_fallback
			if target_fallback != "" and _has_input_port(node, 0):
				target = _input_expression(graph, node, 0, target_fallback)
			var first_arg := 1 if target_fallback != "" else 0
			if target == "" or target == "self":
				return "%s(%s)" % [method_name, _args_for_node(graph, node, first_arg)]
			return "%s.%s(%s)" % [target, method_name, _args_for_node(graph, node, first_arg)]
		"builtin_value", "builtin":
			var builtin_name := str(node.get_meta("builtin_name", "str"))
			var first := 1 if node_type == "builtin" else 0
			return "%s(%s)" % [builtin_name, _args_for_node(graph, node, first)]
		"script_call":
			return "%s(%s)" % [str(node.get_meta("function_name", "function")), _args_for_node(graph, node, 1)]
		"script_value_call":
			return "%s(%s)" % [str(node.get_meta("function_name", "function")), _args_for_node(graph, node, 0)]
	return "TODO_value"


func _format_literal_output(value: String, value_type: String) -> String:
	match value_type:
		"String", "StringName", "NodePath":
			return _quote_string_if_needed(value)
		"bool":
			return "true" if value.to_lower() in ["true", "1", "yes", "ja"] else "false"
		_:
			return value

func _has_input_port(node: GraphNode, port_index: int) -> bool:
	var inputs: Array = node.get_meta("input_ports", [])
	return port_index >= 0 and port_index < inputs.size()


func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


func _write_text(path: String, text: String) -> bool:
	if path.ends_with(".gd"):
		var script_res = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
		if script_res is Script:
			script_res.set("source_code", text)
			var result := ResourceSaver.save(script_res, path)
			if script_res.has_method("reload"):
				script_res.call("reload", true)
			if result == OK:
				return true

	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.close()
	return true


func _normalize_spacing(text: String) -> String:
	return _format_script_spacing(text)


func _format_script_spacing(text: String) -> String:
	var input_lines := text.split("\n", true)
	var output := PackedStringArray()
	var in_variable_block := false

	for raw_line in input_lines:
		var line := str(raw_line).rstrip("\r")
		var stripped := line.strip_edges()

		if stripped == "":
			if output.size() > 0 and str(output[output.size() - 1]) != "":
				output.append("")
			continue

		var is_function := _is_top_level_function(line)
		var is_variable := _is_top_level_variable_line(line)

		if is_function:
			_trim_trailing_blank_lines(output)
			_ensure_blank_lines(output, 2)
			in_variable_block = false
		elif is_variable:
			if not in_variable_block:
				_trim_trailing_blank_lines(output)
				_ensure_blank_lines(output, 1)
			in_variable_block = true
		else:
			if in_variable_block:
				_trim_trailing_blank_lines(output)
				_ensure_blank_lines(output, 1)
			in_variable_block = false

		output.append(line)

	_trim_leading_blank_lines(output)
	_trim_trailing_blank_lines(output)
	return "\n".join(output) + "\n"


func _is_top_level_function(line: String) -> bool:
	if _indent_of(line) != "":
		return false
	var stripped := line.strip_edges()
	return stripped.begins_with("func ") or stripped.begins_with("static func ")


func _is_top_level_variable_line(line: String) -> bool:
	if _indent_of(line) != "":
		return false
	var stripped := line.strip_edges()
	if stripped.begins_with("@export") or stripped.begins_with("@onready"):
		return true
	return stripped.begins_with("var ") or stripped.begins_with("static var ") or stripped.begins_with("const ")


func _ensure_blank_lines(lines: PackedStringArray, amount: int) -> void:
	if lines.size() == 0:
		return
	var current := 0
	for index in range(lines.size() - 1, -1, -1):
		if str(lines[index]) == "":
			current += 1
		else:
			break
	while current < amount:
		lines.append("")
		current += 1


func _trim_leading_blank_lines(lines: PackedStringArray) -> void:
	while lines.size() > 0 and str(lines[0]) == "":
		lines.remove_at(0)


func _trim_trailing_blank_lines(lines: PackedStringArray) -> void:
	while lines.size() > 0 and str(lines[lines.size() - 1]) == "":
		lines.remove_at(lines.size() - 1)


func _indent_of(line: String) -> String:
	var result := ""
	for i in line.length():
		var c := line[i]
		if c == "\t" or c == " ":
			result += c
		else:
			break
	return result
