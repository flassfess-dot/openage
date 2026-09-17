class_name RoRPerformanceProbe
extends RefCounted

const DEFAULT_SAMPLE_LIMIT: int = 8192

var sample_limit: int = DEFAULT_SAMPLE_LIMIT
var samples_by_metric: Dictionary = {}
var counters: Dictionary = {}


func _init(maximum_samples_per_metric: int = DEFAULT_SAMPLE_LIMIT) -> void:
	sample_limit = maxi(1, maximum_samples_per_metric)


func clear() -> void:
	samples_by_metric.clear()
	counters.clear()


func observe_microseconds(metric: String, duration_microseconds: int) -> void:
	if metric.is_empty():
		return
	var samples: Array = samples_by_metric.get(metric, [])
	samples.append(maxi(0, duration_microseconds))
	if samples.size() > sample_limit:
		samples.pop_front()
	samples_by_metric[metric] = samples


func increment(counter: String, amount: int = 1) -> void:
	if counter.is_empty():
		return
	counters[counter] = int(counters.get(counter, 0)) + amount


func sample_count(metric: String) -> int:
	return samples_by_metric.get(metric, []).size()


func report() -> Dictionary:
	var metric_names: Array[String] = []
	for metric_value in samples_by_metric.keys():
		metric_names.append(String(metric_value))
	metric_names.sort()
	var metric_report: Dictionary = {}
	for metric in metric_names:
		metric_report[metric] = summarize(samples_by_metric[metric])

	var counter_names: Array[String] = []
	for counter_value in counters.keys():
		counter_names.append(String(counter_value))
	counter_names.sort()
	var counter_report: Dictionary = {}
	for counter in counter_names:
		counter_report[counter] = int(counters[counter])
	return {
		"sample_limit": sample_limit,
		"metrics_microseconds": metric_report,
		"counters": counter_report,
	}


static func summarize(values: Array) -> Dictionary:
	if values.is_empty():
		return {"count": 0, "mean": 0.0, "p50": 0, "p95": 0, "max": 0}
	var sorted: Array[int] = []
	var total := 0
	for value in values:
		var measured := maxi(0, int(value))
		sorted.append(measured)
		total += measured
	sorted.sort()
	return {
		"count": sorted.size(),
		"mean": float(total) / float(sorted.size()),
		"p50": _percentile(sorted, 0.50),
		"p95": _percentile(sorted, 0.95),
		"max": sorted[sorted.size() - 1],
	}


static func _percentile(sorted: Array[int], ratio: float) -> int:
	if sorted.is_empty():
		return 0
	var index := clampi(ceili(ratio * float(sorted.size())) - 1, 0, sorted.size() - 1)
	return sorted[index]
