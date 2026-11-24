extends SceneTree
## Minimal test runner: godot --headless -s tests/run_tests.gd
## Runs every test_* method in the test files below; exits non-zero on failure.

const FILES := [
	"res://tests/test_physics.gd",
	"res://tests/test_course.gd",
	"res://tests/test_swing.gd",
]


func _init() -> void:
	var passed := 0
	var failed := 0
	var only: Array = Array(OS.get_cmdline_user_args())
	for path in FILES:
		if not ResourceLoader.exists(path):
			continue
		var script: GDScript = load(path)
		var inst = script.new()
		for m in script.get_script_method_list():
			var name: String = m["name"]
			if not name.begins_with("test_"):
				continue
			if only.size() > 0 and not only.any(func(o): return name.contains(o)):
				continue
			inst.failures = []
			inst.call(name)
			if inst.failures.is_empty():
				passed += 1
				print("  ok   ", name)
			else:
				failed += 1
				print("  FAIL ", name)
				for f in inst.failures:
					print("         ", f)
	print("\n%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
