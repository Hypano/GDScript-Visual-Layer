@tool
extends EditorPlugin

const DockScene = preload("res://addons/GDScript Visual Layer/vs_dock.gd")

var main_view: Control
var main_screen: Control


func _enter_tree() -> void:
	main_view = DockScene.new()
	main_view.editor_interface = get_editor_interface()
	main_view.name = "GDScript Visual Layer"
	main_view.visible = false
	main_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Main screen plugins are attached directly to the editor main screen in Godot 4.
	main_screen = get_editor_interface().get_editor_main_screen()
	main_screen.add_child(main_view)
	main_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fit_main_view()
	if not main_screen.resized.is_connected(_fit_main_view):
		main_screen.resized.connect(_fit_main_view)


func _exit_tree() -> void:
	_flush_layout()

	if main_screen != null and main_screen.resized.is_connected(_fit_main_view):
		main_screen.resized.disconnect(_fit_main_view)

	if main_view != null:
		main_view.queue_free()
		main_view = null
	main_screen = null


func _has_main_screen() -> bool:
	return true


func _make_visible(visible: bool) -> void:
	if main_view != null:
		main_view.visible = visible
		_fit_main_view()
		if visible and main_view.has_method("on_main_screen_visible"):
			main_view.call("on_main_screen_visible")


func _fit_main_view() -> void:
	if main_view == null:
		return
	var parent := main_view.get_parent()
	if parent is Control:
		main_view.position = Vector2.ZERO
		main_view.size = (parent as Control).size
	main_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _get_plugin_name() -> String:
	return "GDScript Visual Layer"


func _get_plugin_icon() -> Texture2D:
	if get_editor_interface() == null:
		return null

	var base := get_editor_interface().get_base_control()
	return base.get_theme_icon("VisualShader", "EditorIcons")


func _apply_changes() -> void:
	_flush_layout()


func _save_external_data() -> void:
	_flush_layout()


func _resource_saved(resource: Resource) -> void:
	if main_view != null and main_view.has_method("on_resource_saved"):
		main_view.call("on_resource_saved", resource)


func _flush_layout() -> void:
	if main_view != null and main_view.has_method("flush_layout"):
		main_view.call("flush_layout")
