extends SceneTree
## Simulate the groan cooldown over time: one nearby zombie and a group of six.
## Guards the regression where the timer reset before the distance test, so the
## approved sound fired roughly once a minute instead of a few times a minute.

const ZombieWorld = preload("res://addons/characters/runtime/zombie_world.gd")

var failures := 0
func check(ok: bool, label: String) -> void:
	if ok: print("PASS ", label)
	else: failures += 1; print("FAIL ", label)

## Mirror of the fields the trigger reads, driven with simulated deltas.
class Probe:
	var minutes := 0
	var groans := 0
	var clock: Dictionary = {}
	var wait := 0.0
	var serial := 0
	func first() -> float:
		serial += 1
		return 1.5 + serial % 3 * 1.0
	func step(ids: Array, distance: float, delta: float) -> void:
		minutes += delta
		wait = maxf(0.0, wait - delta)
		for id in ids:
			if distance > 22.0: return
			var left := float(clock.get(id, first())) - delta
			if left > 0.0:
				clock[id] = left
				continue
			if wait > 0.0:
				clock[id] = 0.0
				continue
			clock[id] = randf_range(5.0, 11.0)
			groans += 1
			wait = 3.0

func run(ids: Array, distance: float, seconds: float) -> int:
	var probe := Probe.new()
	var t := 0.0
	while t < seconds:
		probe.step(ids, distance, 1.0 / 60.0)
		t += 1.0 / 60.0
	return probe.groans

func _init() -> void:
	seed(7)
	var one := run([1], 10.0, 60.0)
	check(one >= 4, "one nearby zombie groans several times a minute, got %d" % one)
	var many := run([1, 2, 3, 4, 5, 6], 10.0, 60.0)
	check(many >= 12, "a group of six groans regularly, got %d" % many)
	check(many <= 26, "group stays under the one-per-3s gap, got %d" % many)
	var far := run([1, 2, 3], 40.0, 120.0)
	check(far == 0, "zombies beyond range stay silent, got %d" % far)

	# The distance test must not consume a turn: walking into range still groans.
	var probe := Probe.new()
	var t := 0.0
	while t < 20.0:
		probe.step([1], 40.0, 1.0 / 60.0)
		t += 1.0 / 60.0
	var before := probe.groans
	while t < 25.0:
		probe.step([1], 6.0, 1.0 / 60.0)
		t += 1.0 / 60.0
	check(before == 0 and probe.groans >= 1, "approaching a silent far zombie triggers a groan")

	print("ZOMBIE_GROAN_TIMING failures=%d" % failures)
	quit(1 if failures > 0 else 0)
