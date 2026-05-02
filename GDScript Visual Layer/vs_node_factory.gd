@tool
extends RefCounted

const PORT_EXEC := 1
const PORT_VALUE := 2
const PORT_OBJECT := 3
const PORT_BOOL := 4
const PORT_NUMBER := 5
const PORT_STRING := 6
const PORT_VECTOR := 7
const PORT_ANY := 99

const COLOR_EXEC := Color(0.90, 0.90, 0.90)
const COLOR_VALUE := Color(0.72, 0.84, 1.00)
const COLOR_OBJECT := Color(0.74, 0.70, 1.00)
const COLOR_BOOL := Color(1.00, 0.62, 0.62)
const COLOR_NUMBER := Color(0.68, 1.00, 0.70)
const COLOR_STRING := Color(1.00, 0.82, 0.50)
const COLOR_VECTOR := Color(0.60, 1.00, 0.95)

const NODE_COLOR_ENTRY := Color(0.22, 0.66, 0.95)
const NODE_COLOR_FUNCTION := Color(0.42, 0.62, 0.92)
const NODE_COLOR_LIFECYCLE := Color(0.25, 0.72, 0.95)
const NODE_COLOR_VARIABLE := Color(0.45, 0.58, 0.78)
const NODE_COLOR_EXPORT := Color(0.95, 0.62, 0.22)
const NODE_COLOR_ONREADY := Color(0.35, 0.78, 0.48)
const NODE_COLOR_LOCAL := Color(0.46, 0.70, 0.70)
const NODE_COLOR_SCRIPT_CALL := Color(0.58, 0.76, 1.00)
const NODE_COLOR_METHOD := Color(0.72, 0.58, 0.95)
const NODE_COLOR_BUILTIN := Color(0.65, 0.64, 0.86)
const NODE_COLOR_PROPERTY := Color(0.62, 0.70, 0.90)
const NODE_COLOR_MATH := Color(0.82, 0.86, 0.42)
const NODE_COLOR_BRANCH := Color(0.90, 0.58, 0.35)
const NODE_COLOR_RETURN := Color(0.95, 0.42, 0.48)
const NODE_COLOR_LITERAL := Color(0.55, 0.58, 0.64)
const NODE_COLOR_STATEMENT := Color(0.62, 0.62, 0.62)
const NODE_COLOR_GROUP := Color(0.34, 0.38, 0.46)


static func make_entry_node(function_data: Dictionary, position: Vector2) -> GraphNode:
	var node := GraphNode.new()
	node.name = "entry__" + sanitize_id(str(function_data.get("id", "function")))
	node.title = "▶ " + str(function_data.get("name", "function"))
	node.position_offset = position
	node.self_modulate = NODE_COLOR_ENTRY
	node.set_meta("gdvl_type", "entry")
	node.set_meta("function_id", str(function_data.get("id", "")))
	node.set_meta("function_name", str(function_data.get("name", "")))
	node.set_meta("output_ports", [{"name": "exec", "type": "exec"}])

	var label := Label.new()
	label.text = _short_signature(function_data)
	node.add_child(label)
	node.set_slot(0, false, PORT_VALUE, COLOR_VALUE, true, PORT_EXEC, COLOR_EXEC)
	return _finish_node(node, 190)


static func make_function_node(function_data: Dictionary, position: Vector2) -> GraphNode:
	var node := GraphNode.new()
	var function_id := str(function_data.get("id", "function"))
	var function_name := str(function_data.get("name", "function"))
	node.name = "func__" + sanitize_id(function_id)
	node.title = "ƒ " + str(function_data.get("title", function_name))
	node.position_offset = position
	node.self_modulate = NODE_COLOR_LIFECYCLE if str(function_data.get("kind", "")) == "lifecycle" else NODE_COLOR_FUNCTION
	node.set_meta("gdvl_type", "function")
	node.set_meta("function_id", function_id)
	node.set_meta("function_name", function_name)
	node.set_meta("signature", function_signature(function_data))
	node.set_meta("line", int(function_data.get("line_start", 1)))
	node.tooltip_text = function_signature(function_data)

	var label := Label.new()
	label.text = "%s · %s" % [str(function_data.get("kind", "code")), str(function_data.get("category", "Script"))]
	node.add_child(label)
	node.set_slot(0, true, PORT_EXEC, COLOR_EXEC, true, PORT_EXEC, COLOR_EXEC)
	return _finish_node(node, 210)


static func make_variable_node(variable_data: Dictionary, position: Vector2, local := false) -> GraphNode:
	var variable_name := str(variable_data.get("name", "value"))
	var type_name := str(variable_data.get("type", "Variant"))
	var kind := str(variable_data.get("kind", "local" if local else "member"))
	var node := GraphNode.new()

	node.name = ("local__" if local else "var__") + sanitize_id(variable_name)
	node.title = ("local " if local else "var ") + variable_name
	node.position_offset = position
	node.self_modulate = NODE_COLOR_LOCAL if local else _variable_color(kind)
	node.set_meta("gdvl_type", "variable")
	node.set_meta("variable_name", variable_name)
	node.set_meta("value_type", type_name)
	node.set_meta("kind", kind)
	node.set_meta("line", int(variable_data.get("line", 0)))
	node.set_meta("output_ports", [{"name": variable_name, "type": type_name}])
	node.tooltip_text = "%s: %s" % [variable_name, type_name]

	var label := Label.new()
	label.text = type_name
	node.add_child(label)
	node.set_slot(0, false, PORT_VALUE, COLOR_VALUE, true, port_type_for_type_name(type_name), port_color_for_type_name(type_name))
	return _finish_node(node, 170)


static func make_local_assign_node(statement: Dictionary, position: Vector2) -> GraphNode:
	var name := str(statement.get("name", "value"))
	var type_name := str(statement.get("type", "Variant"))
	var node := GraphNode.new()
	node.name = "local_assign__" + sanitize_id(str(statement.get("id", name)))
	node.title = "var " + name
	node.position_offset = position
	node.self_modulate = NODE_COLOR_LOCAL
	node.set_meta("gdvl_type", "local_assign")
	node.set_meta("variable_name", name)
	node.set_meta("value_type", type_name)
	node.set_meta("operator", str(statement.get("operator", ":=")))
	node.set_meta("input_ports", [{"name": "exec", "type": "exec"}, {"name": "value", "type": type_name}])
	node.set_meta("output_ports", [{"name": "exec", "type": "exec"}, {"name": name, "type": type_name}])
	node.set_meta("source_text", str(statement.get("text", "")))

	_add_slot(node, "exec", true, PORT_EXEC, COLOR_EXEC, true, PORT_EXEC, COLOR_EXEC)
	_add_slot(node, "value", true, port_type_for_type_name(type_name), port_color_for_type_name(type_name), true, port_type_for_type_name(type_name), port_color_for_type_name(type_name))
	return _finish_node(node, 190)


static func make_set_property_node(statement: Dictionary, position: Vector2) -> GraphNode:
	var property_name := str(statement.get("property_name", "property"))
	var target_expr := str(statement.get("target_expr", "target"))
	var target_type := str(statement.get("target_type", "Object"))
	var value_type := str(statement.get("value_type", "Variant"))
	var node := GraphNode.new()

	node.name = "set__" + sanitize_id(str(statement.get("id", property_name)))
	node.title = "Set " + property_name
	node.position_offset = position
	node.self_modulate = NODE_COLOR_PROPERTY
	node.set_meta("gdvl_type", "set_property")
	node.set_meta("target_expr", target_expr)
	node.set_meta("target_type", target_type)
	node.set_meta("property_name", property_name)
	node.set_meta("operator", str(statement.get("operator", "=")))
	node.set_meta("value_type", value_type)
	node.set_meta("input_ports", [
		{"name": "exec", "type": "exec"},
		{"name": "target", "type": target_type},
		{"name": "value", "type": value_type}
	])
	node.set_meta("output_ports", [{"name": "exec", "type": "exec"}])
	node.set_meta("source_text", str(statement.get("text", "")))
	node.tooltip_text = str(statement.get("text", ""))

	_add_slot(node, "exec", true, PORT_EXEC, COLOR_EXEC, true, PORT_EXEC, COLOR_EXEC)
	_add_slot(node, target_expr, true, PORT_OBJECT, COLOR_OBJECT, false, PORT_VALUE, COLOR_VALUE)
	_add_slot(node, "value", true, port_type_for_type_name(value_type), port_color_for_type_name(value_type), false, PORT_VALUE, COLOR_VALUE)
	return _finish_node(node, 210)


static func make_assignment_node(statement: Dictionary, position: Vector2) -> GraphNode:
	var target := str(statement.get("target", "value"))
	var value_type := str(statement.get("value_type", "Variant"))
	var node := GraphNode.new()
	node.name = "assign__" + sanitize_id(str(statement.get("id", target)))
	node.title = "Set " + target
	node.position_offset = position
	node.self_modulate = NODE_COLOR_PROPERTY
	node.set_meta("gdvl_type", "assignment")
	node.set_meta("target", target)
	node.set_meta("operator", str(statement.get("operator", "=")))
	node.set_meta("value_type", value_type)
	node.set_meta("input_ports", [{"name": "exec", "type": "exec"}, {"name": "value", "type": value_type}])
	node.set_meta("output_ports", [{"name": "exec", "type": "exec"}])
	node.set_meta("source_text", str(statement.get("text", "")))

	_add_slot(node, "exec", true, PORT_EXEC, COLOR_EXEC, true, PORT_EXEC, COLOR_EXEC)
	_add_slot(node, "value", true, port_type_for_type_name(value_type), port_color_for_type_name(value_type), false, PORT_VALUE, COLOR_VALUE)
	return _finish_node(node, 200)


static func make_branch_node(statement: Dictionary, position: Vector2) -> GraphNode:
	var node := GraphNode.new()
	node.name = "branch__" + sanitize_id(str(statement.get("id", "if")))
	node.title = "If"
	node.position_offset = position
	node.self_modulate = NODE_COLOR_BRANCH
	node.set_meta("gdvl_type", "branch")
	node.set_meta("condition", str(statement.get("condition", "true")))
	node.set_meta("input_ports", [{"name": "exec", "type": "exec"}, {"name": "condition", "type": "bool"}])
	node.set_meta("output_ports", [{"name": "true", "type": "exec"}, {"name": "false", "type": "exec"}])
	node.set_meta("source_text", str(statement.get("text", "")))

	_add_slot(node, "exec → true", true, PORT_EXEC, COLOR_EXEC, true, PORT_EXEC, COLOR_EXEC)
	_add_editable_slot(node, "condition", str(statement.get("condition", "true")), true, PORT_BOOL, COLOR_BOOL, true, PORT_EXEC, COLOR_EXEC)
	return _finish_node(node, 270)


static func make_return_node(statement: Dictionary, position: Vector2) -> GraphNode:
	var value_text := str(statement.get("value_text", ""))
	var value_type := "Variant"
	var value_expr = statement.get("value_expr", {})
	if typeof(value_expr) == TYPE_DICTIONARY:
		value_type = str(value_expr.get("value_type", "Variant"))

	var node := GraphNode.new()
	node.name = "return__" + sanitize_id(str(statement.get("id", "return")))
	node.title = "Return"
	node.position_offset = position
	node.self_modulate = NODE_COLOR_RETURN
	node.set_meta("gdvl_type", "return")
	node.set_meta("value_text", value_text)
	node.set_meta("value_type", value_type)
	node.set_meta("line", int(statement.get("line", 0)))
	node.set_meta("input_ports", [{"name": "exec", "type": "exec"}, {"name": "value", "type": value_type}])
	node.set_meta("output_ports", [])
	node.set_meta("source_text", str(statement.get("text", "")))

	_add_slot(node, "exec", true, PORT_EXEC, COLOR_EXEC, false, PORT_EXEC, COLOR_EXEC)
	_add_editable_slot(node, "value", value_text, true, port_type_for_type_name(value_type), port_color_for_type_name(value_type), false, PORT_VALUE, COLOR_VALUE)
	return _finish_node(node, 230)


static func make_script_call_node(function_data: Dictionary, position: Vector2, occurrence_id := "", arg_defaults: Array = [], exec_enabled := true) -> GraphNode:
	var function_name := str(function_data.get("name", "function"))
	var id_suffix := occurrence_id if occurrence_id != "" else str(randi() % 999999)
	var node := GraphNode.new()
	node.name = "call__" + sanitize_id(function_name) + "__" + sanitize_id(id_suffix)
	node.title = "Call " + function_name
	node.position_offset = position
	node.self_modulate = NODE_COLOR_SCRIPT_CALL
	node.set_meta("gdvl_type", "script_call" if exec_enabled else "script_value_call")
	node.set_meta("function_name", function_name)
	node.set_meta("function_id", str(function_data.get("id", "")))
	node.set_meta("signature", function_signature(function_data))
	node.tooltip_text = function_signature(function_data)

	var input_ports: Array = []
	var output_ports: Array = []
	if exec_enabled:
		input_ports.append({"name": "exec", "type": "exec"})
		output_ports.append({"name": "exec", "type": "exec"})
		_add_slot(node, "exec", true, PORT_EXEC, COLOR_EXEC, true, PORT_EXEC, COLOR_EXEC)

	var param_index := 0
	for param in function_data.get("params", []):
		var param_name := str(param.get("name", "arg"))
		var type_name := str(param.get("type", "Variant"))
		var default_text := ""
		if param_index < arg_defaults.size():
			default_text = str(arg_defaults[param_index])
		input_ports.append({"name": param_name, "type": type_name, "default": default_text})
		_add_editable_slot(node, param_name, default_text, true, port_type_for_type_name(type_name), port_color_for_type_name(type_name), false, PORT_VALUE, COLOR_VALUE)
		param_index += 1

	var return_type := str(function_data.get("return_type", "void"))
	if return_type != "" and (return_type != "void" or not exec_enabled):
		var out_type := return_type if return_type != "void" else "Variant"
		output_ports.append({"name": "result", "type": out_type})
		_add_slot(node, "result", false, PORT_VALUE, COLOR_VALUE, true, port_type_for_type_name(out_type), port_color_for_type_name(out_type))

	node.set_meta("input_ports", input_ports)
	node.set_meta("output_ports", output_ports)
	return _finish_node(node, 210)


static func make_method_node(target_type: String, method_data: Dictionary, position: Vector2, occurrence_id := "", target_expression := "", exec_enabled := true, arg_defaults: Array = []) -> GraphNode:
	var method_name := str(method_data.get("name", "method"))
	var id_suffix := occurrence_id if occurrence_id != "" else str(randi() % 999999)
	var node := GraphNode.new()
	node.name = ("method__" if exec_enabled else "value_call__") + sanitize_id(target_type) + "__" + sanitize_id(method_name) + "__" + sanitize_id(id_suffix)
	node.title = (target_type + "." if target_type != "" else "") + method_name
	node.position_offset = position
	node.self_modulate = NODE_COLOR_METHOD
	node.set_meta("gdvl_type", "method_call" if exec_enabled else "value_call")
	node.set_meta("target_type", target_type)
	node.set_meta("method_name", method_name)
	node.set_meta("target_expression", target_expression)
	node.tooltip_text = _method_signature_for_tooltip(target_type, method_data)

	var input_ports: Array = []
	var output_ports: Array = []

	if exec_enabled:
		input_ports.append({"name": "exec", "type": "exec"})
		output_ports.append({"name": "exec", "type": "exec"})
		_add_slot(node, "exec", true, PORT_EXEC, COLOR_EXEC, true, PORT_EXEC, COLOR_EXEC)

	if target_expression != "" or target_type != "":
		input_ports.append({"name": "target", "type": target_type if target_type != "" else "Object"})
		_add_slot(node, "target", true, PORT_OBJECT, COLOR_OBJECT, false, PORT_VALUE, COLOR_VALUE)

	var arg_index := 0
	for arg in method_data.get("args", []):
		if typeof(arg) != TYPE_DICTIONARY:
			continue

		var arg_name := str(arg.get("name", "arg%s" % arg_index))
		var type_name := _type_name_from_arg(arg)
		var default_text := ""
		if arg_index < arg_defaults.size():
			default_text = str(arg_defaults[arg_index])
		input_ports.append({"name": arg_name, "type": type_name, "default": default_text})
		_add_editable_slot(node, arg_name, default_text, true, port_type_for_type_name(type_name), port_color_for_type_name(type_name), false, PORT_VALUE, COLOR_VALUE)
		arg_index += 1

	var ret_type := return_type_from_method(method_data)
	if ret_type != "void" and ret_type != "Nil":
		output_ports.append({"name": "result", "type": ret_type})
		_add_slot(node, "result", false, PORT_VALUE, COLOR_VALUE, true, port_type_for_type_name(ret_type), port_color_for_type_name(ret_type))

	node.set_meta("input_ports", input_ports)
	node.set_meta("output_ports", output_ports)
	return _finish_node(node, 250)


static func make_builtin_call_node(function_name: String, position: Vector2, exec_enabled := true, arg_count := 1, arg_defaults: Array = [], method_data: Dictionary = {}) -> GraphNode:
	var signature := method_data
	if signature.is_empty():
		signature = _fallback_builtin_method_data(function_name)

	var node := GraphNode.new()
	node.name = ("builtin__" if exec_enabled else "builtin_value__") + sanitize_id(function_name) + "__" + str(randi() % 999999)
	node.title = _builtin_title(function_name)
	node.position_offset = position
	node.self_modulate = NODE_COLOR_BUILTIN
	node.set_meta("gdvl_type", "builtin" if exec_enabled else "builtin_value")
	node.set_meta("builtin_name", function_name)
	node.set_meta("source_text", function_name + "(...)")
	node.tooltip_text = _global_signature_for_tooltip(function_name, signature)

	var input_ports: Array = []
	var output_ports: Array = []

	if exec_enabled:
		input_ports.append({"name": "exec", "type": "exec"})
		output_ports.append({"name": "exec", "type": "exec"})
		_add_slot(node, "exec", true, PORT_EXEC, COLOR_EXEC, true, PORT_EXEC, COLOR_EXEC)

	var args: Array = signature.get("args", [])
	var wanted_count := args.size()
	if bool(signature.get("vararg", false)):
		wanted_count = max(max(arg_count, wanted_count), 1)
	else:
		wanted_count = max(arg_count, wanted_count)

	for index in range(wanted_count):
		var arg_def := _arg_def_for_index(args, index)
		var arg_name := str(arg_def.get("name", _builtin_arg_name(function_name, index)))
		if bool(signature.get("vararg", false)) and args.size() <= 1:
			arg_name = "arg%s" % index if wanted_count > 1 else _builtin_arg_name(function_name, index)
		var type_name := _type_name_from_arg(arg_def)
		var default_text := ""
		if index < arg_defaults.size():
			default_text = str(arg_defaults[index])
		input_ports.append({"name": arg_name, "type": type_name, "default": default_text})
		_add_editable_slot(node, arg_name, default_text, true, port_type_for_type_name(type_name), port_color_for_type_name(type_name), false, PORT_VALUE, COLOR_VALUE)

	var ret_type := _return_type_from_global(signature, function_name)
	if ret_type != "void" or not exec_enabled:
		var out_type := ret_type if ret_type != "void" else "Variant"
		output_ports.append({"name": "result", "type": out_type})
		_add_slot(node, "result", false, PORT_VALUE, COLOR_VALUE, true, port_type_for_type_name(out_type), port_color_for_type_name(out_type))

	node.set_meta("input_ports", input_ports)
	node.set_meta("output_ports", output_ports)
	return _finish_node(node, 250)


static func _arg_def_for_index(args: Array, index: int) -> Dictionary:
	if index >= 0 and index < args.size() and typeof(args[index]) == TYPE_DICTIONARY:
		return args[index]
	return {"name": "arg%s" % index, "type": "Variant"}


static func _type_name_from_arg(arg: Dictionary) -> String:
	var value = arg.get("type", "Variant")
	if typeof(value) == TYPE_INT:
		return variant_type_to_name(int(value))
	return str(value)


static func _return_type_from_global(method_data: Dictionary, function_name: String) -> String:
	if method_data.has("return_type"):
		return str(method_data.get("return_type", "Variant"))
	var ret = method_data.get("return", {})
	if typeof(ret) == TYPE_DICTIONARY:
		var value = ret.get("type", TYPE_NIL)
		if typeof(value) == TYPE_INT:
			return variant_type_to_name(int(value))
		return str(value)
	return _builtin_return_type(function_name)


static func _fallback_builtin_method_data(function_name: String) -> Dictionary:
	var arg_array: Array = []
	var count := 1
	if function_name in ["randf", "randi"]:
		count = 0
	for i in range(count):
		arg_array.append({"name": _builtin_arg_name(function_name, i), "type": "Variant"})
	return {"name": function_name, "return_type": _builtin_return_type(function_name), "args": arg_array}


static func _global_signature_for_tooltip(function_name: String, method_data: Dictionary) -> String:
	var parts: Array = []
	for arg in method_data.get("args", []):
		if typeof(arg) == TYPE_DICTIONARY:
			parts.append("%s: %s" % [str(arg.get("name", "arg")), _type_name_from_arg(arg)])
	if bool(method_data.get("vararg", false)) and parts.size() == 1:
		parts[0] = "..." + str(parts[0])
	return "%s(%s) -> %s" % [function_name, ", ".join(parts), _return_type_from_global(method_data, function_name)]


static func _method_signature_for_tooltip(target_type: String, method_data: Dictionary) -> String:
	var method_name := str(method_data.get("name", "method"))
	var parts: Array = []
	for arg in method_data.get("args", []):
		if typeof(arg) == TYPE_DICTIONARY:
			parts.append("%s: %s" % [str(arg.get("name", "arg")), _type_name_from_arg(arg)])
	var prefix := target_type + "." if target_type != "" else ""
	return "%s%s(%s) -> %s" % [prefix, method_name, ", ".join(parts), return_type_from_method(method_data)]


static func _builtin_arg_is_editable(function_name: String, index: int) -> bool:
	return true


static func make_group_node(title_text: String, position: Vector2, size_hint: Vector2, grouped_nodes: Array = []) -> GraphNode:
	var node := GraphNode.new()
	node.name = "group__" + sanitize_id(title_text) + "__" + str(randi() % 999999)
	node.title = "▣ " + title_text
	node.position_offset = position
	node.self_modulate = NODE_COLOR_GROUP
	node.z_index = -100
	node.resizable = true
	node.custom_minimum_size = Vector2(max(size_hint.x, 260.0), max(size_hint.y, 120.0))
	node.set_meta("gdvl_type", "group")
	node.set_meta("grouped_nodes", grouped_nodes)
	node.set_meta("title_text", title_text)
	var label := Label.new()
	label.text = "%s Nodes" % grouped_nodes.size()
	node.add_child(label)
	return node


static func make_expression_node(expression_text: String, position: Vector2, value_type := "Variant") -> GraphNode:
	var node := GraphNode.new()
	node.name = "expr__" + sanitize_id(expression_text) + "__" + str(randi() % 999999)
	node.title = "Expr"
	node.position_offset = position
	node.self_modulate = NODE_COLOR_LITERAL
	node.set_meta("gdvl_type", "expression")
	node.set_meta("expression_text", expression_text)
	node.set_meta("value_type", value_type)
	node.set_meta("output_ports", [{"name": "value", "type": value_type}])
	node.tooltip_text = expression_text

	_add_editable_slot(node, "expr", expression_text, false, PORT_VALUE, COLOR_VALUE, true, port_type_for_type_name(value_type), port_color_for_type_name(value_type))
	return _finish_node(node, 230)


static func make_literal_node(value_text: String, position: Vector2, value_type := "Variant") -> GraphNode:
	var node := GraphNode.new()
	node.name = "literal__" + sanitize_id(value_text) + "__" + str(randi() % 999999)
	node.title = value_type if value_type != "Variant" else "Literal"
	node.position_offset = position
	node.self_modulate = NODE_COLOR_LITERAL
	node.set_meta("gdvl_type", "literal")
	node.set_meta("literal_value", value_text)
	node.set_meta("value_type", value_type)
	node.set_meta("output_ports", [{"name": "value", "type": value_type}])
	_add_editable_slot(node, "value", _editable_literal_text(value_text), false, PORT_VALUE, COLOR_VALUE, true, port_type_for_type_name(value_type), port_color_for_type_name(value_type))
	return _finish_node(node, 190)


static func _editable_literal_text(value_text: String) -> String:
	var clean := value_text.strip_edges()
	if clean.length() >= 2:
		var first := clean[0]
		var last := clean[clean.length() - 1]
		if (first == "\"" and last == "\"") or (first == "'" and last == "'"):
			return clean.substr(1, clean.length() - 2)
	return clean


static func make_math_node(position: Vector2, operation := "Add") -> GraphNode:
	var node := GraphNode.new()
	node.name = "math__" + str(randi() % 999999)
	node.title = "Math"
	node.position_offset = position
	node.self_modulate = NODE_COLOR_MATH
	node.set_meta("gdvl_type", "math")
	node.set_meta("operation", operation)
	node.set_meta("input_ports", [{"name": "a", "type": "Variant"}, {"name": "b", "type": "Variant"}])
	node.set_meta("output_ports", [{"name": "result", "type": "Variant"}])
	_add_slot(node, math_symbol(operation) + "  A", true, PORT_ANY, COLOR_VALUE, false, PORT_VALUE, COLOR_VALUE)
	_add_slot(node, "B → result", true, PORT_ANY, COLOR_VALUE, true, PORT_ANY, COLOR_VALUE)
	return _finish_node(node, 160)


static func make_statement_node(statement: Dictionary, position: Vector2) -> GraphNode:
	var text := str(statement.get("text", "pass"))
	var node := GraphNode.new()
	node.name = "stmt__" + sanitize_id(str(statement.get("id", "statement")))
	node.title = "Code"
	node.position_offset = position
	node.self_modulate = NODE_COLOR_STATEMENT
	node.set_meta("gdvl_type", "statement")
	node.set_meta("statement_text", text)
	node.set_meta("line", int(statement.get("line", 0)))
	node.set_meta("input_ports", [{"name": "exec", "type": "exec"}])
	node.set_meta("output_ports", [{"name": "exec", "type": "exec"}])
	node.tooltip_text = text
	_add_editable_slot(node, "code", text, true, PORT_EXEC, COLOR_EXEC, true, PORT_EXEC, COLOR_EXEC)
	return _finish_node(node, 300)


static func _add_slot(node: GraphNode, text: String, left_enabled: bool, left_type: int, left_color: Color, right_enabled: bool, right_type: int, right_color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.clip_text = true
	node.add_child(label)
	var slot_index := node.get_child_count() - 1
	node.set_slot(slot_index, left_enabled, left_type, left_color, right_enabled, right_type, right_color)


static func _add_editable_slot(node: GraphNode, text: String, default_text: String, left_enabled: bool, left_type: int, left_color: Color, right_enabled: bool, right_type: int, right_color: Color) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(58, 0)
	row.add_child(label)
	var edit := LineEdit.new()
	edit.name = "gdvl_input_" + str(node.get_child_count())
	edit.text = default_text
	edit.placeholder_text = text
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(edit)
	node.add_child(row)
	var slot_index := node.get_child_count() - 1
	edit.name = "gdvl_input_" + str(slot_index)
	node.set_slot(slot_index, left_enabled, left_type, left_color, right_enabled, right_type, right_color)


static func _finish_node(node: GraphNode, width: int) -> GraphNode:
	node.custom_minimum_size = Vector2(width, 0)
	node.resizable = false
	return node


static func _variable_color(kind: String) -> Color:
	if kind == "export":
		return NODE_COLOR_EXPORT
	if kind == "onready":
		return NODE_COLOR_ONREADY
	return NODE_COLOR_VARIABLE


static func function_signature(function_data: Dictionary) -> String:
	var parts: Array = []
	for param in function_data.get("params", []):
		parts.append("%s: %s" % [str(param.get("name", "")), str(param.get("type", "Variant"))])
	return "func %s(%s) -> %s" % [str(function_data.get("name", "")), ", ".join(parts), str(function_data.get("return_type", "void"))]


static func _short_signature(function_data: Dictionary) -> String:
	var text := function_signature(function_data)
	return _short_text(text, 34)


static func _short_text(text: String, max_len: int) -> String:
	var clean := text.replace("\t", " ").replace("\n", " ").strip_edges()
	if clean.length() <= max_len:
		return clean
	return clean.substr(0, max_len - 1) + "…"


static func return_type_from_method(method_data: Dictionary) -> String:
	if method_data.has("return_type"):
		return str(method_data.get("return_type", "Variant"))
	var ret = method_data.get("return", {})
	if typeof(ret) == TYPE_DICTIONARY:
		var value = ret.get("type", TYPE_NIL)
		if typeof(value) == TYPE_INT:
			return variant_type_to_name(int(value))
		return str(value)
	return "void"


static func _builtin_title(function_name: String) -> String:
	match function_name:
		"print": return "Print"
		"push_warning": return "Warning"
		"push_error": return "Error"
		_: return function_name


static func _builtin_arg_name(function_name: String, index: int) -> String:
	if function_name in ["print", "printerr", "print_rich"] and index == 0:
		return "message"
	if function_name == "push_warning" and index == 0:
		return "warning"
	if function_name == "push_error" and index == 0:
		return "error"
	if function_name in ["str", "int", "float", "bool", "Callable"] and index == 0:
		return "value"
	return "arg%s" % index


static func _builtin_return_type(function_name: String) -> String:
	match function_name:
		"print", "printerr", "print_rich", "push_warning", "push_error":
			return "void"
		"str":
			return "String"
		"int", "randi", "randi_range", "len", "typeof":
			return "int"
		"float", "pingpong", "wrapf", "snapped", "sqrt", "pow", "sin", "cos", "tan", "asin", "acos", "atan", "atan2", "deg_to_rad", "rad_to_deg", "move_toward", "randf", "randf_range":
			return "float"
		"bool", "is_instance_valid":
			return "bool"
		"Callable":
			return "Callable"
		"range":
			return "Array"
		_:
			return "Variant"


static func port_type_for_type_name(type_name: String) -> int:
	var clean := type_name.strip_edges()
	match clean:
		"bool":
			return PORT_BOOL
		"int", "float":
			return PORT_NUMBER
		"String", "StringName", "NodePath":
			return PORT_STRING
		"Vector2", "Vector2i", "Vector3", "Vector3i", "Vector4", "Vector4i", "Color", "Transform2D", "Transform3D", "Basis", "Quaternion", "Rect2", "Rect2i":
			return PORT_VECTOR
		"Variant", "Nil", "":
			return PORT_ANY
		_:
			return PORT_OBJECT


static func port_color_for_type_name(type_name: String) -> Color:
	match port_type_for_type_name(type_name):
		PORT_BOOL:
			return COLOR_BOOL
		PORT_NUMBER:
			return COLOR_NUMBER
		PORT_STRING:
			return COLOR_STRING
		PORT_VECTOR:
			return COLOR_VECTOR
		PORT_OBJECT:
			return COLOR_OBJECT
		_:
			return COLOR_VALUE


static func variant_type_to_name(type_id: int) -> String:
	match type_id:
		TYPE_NIL:
			return "void"
		TYPE_BOOL:
			return "bool"
		TYPE_INT:
			return "int"
		TYPE_FLOAT:
			return "float"
		TYPE_STRING:
			return "String"
		TYPE_VECTOR2:
			return "Vector2"
		TYPE_VECTOR2I:
			return "Vector2i"
		TYPE_RECT2:
			return "Rect2"
		TYPE_RECT2I:
			return "Rect2i"
		TYPE_VECTOR3:
			return "Vector3"
		TYPE_VECTOR3I:
			return "Vector3i"
		TYPE_TRANSFORM2D:
			return "Transform2D"
		TYPE_VECTOR4:
			return "Vector4"
		TYPE_VECTOR4I:
			return "Vector4i"
		TYPE_PLANE:
			return "Plane"
		TYPE_QUATERNION:
			return "Quaternion"
		TYPE_AABB:
			return "AABB"
		TYPE_BASIS:
			return "Basis"
		TYPE_TRANSFORM3D:
			return "Transform3D"
		TYPE_PROJECTION:
			return "Projection"
		TYPE_COLOR:
			return "Color"
		TYPE_STRING_NAME:
			return "StringName"
		TYPE_NODE_PATH:
			return "NodePath"
		TYPE_RID:
			return "RID"
		TYPE_OBJECT:
			return "Object"
		TYPE_CALLABLE:
			return "Callable"
		TYPE_SIGNAL:
			return "Signal"
		TYPE_DICTIONARY:
			return "Dictionary"
		TYPE_ARRAY:
			return "Array"
		_:
			return "Variant"


static func math_symbol(operation: String) -> String:
	match operation:
		"Add":
			return "+"
		"Subtract":
			return "-"
		"Multiply":
			return "×"
		"Divide":
			return "÷"
		"Power":
			return "**"
		"Modulo":
			return "%"
		_:
			return "+"


static func math_operator(operation: String) -> String:
	match operation:
		"Add":
			return "+"
		"Subtract":
			return "-"
		"Multiply":
			return "*"
		"Divide":
			return "/"
		"Power":
			return "**"
		"Modulo":
			return "%"
		_:
			return "+"


static func sanitize_id(text: String) -> String:
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
