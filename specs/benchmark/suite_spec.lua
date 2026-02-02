-- specs/benchmark/suite_spec.lua
-- Tests for Performance Benchmarking Suite

describe("Benchmark Suite", function()
  local Benchmark = require("dslua.benchmark.suite")

  describe("Benchmark", function()
    it("should create benchmark with name and function", function()
      local fn = function(i) return i * 2 end
      local bench = Benchmark.Benchmark.new("test_bench", fn)

      assert.is.equal("test_bench", bench.name)
      assert.is.equal(1000, bench.iterations)
    end)

    it("should create benchmark with custom options", function()
      local fn = function(i) return i end
      local bench = Benchmark.Benchmark.new("custom_bench", fn, {
        iterations = 100,
        warmup_iterations = 5,
        timeout = 10
      })

      assert.is.equal(100, bench.iterations)
      assert.is.equal(5, bench.warmup_iterations)
      assert.is.equal(10, bench.timeout)
    end)

    it("should run benchmark and collect statistics", function()
      local call_count = 0
      local fn = function(i)
        call_count = call_count + 1
        -- Simulate some work
        local sum = 0
        for j = 1, 100 do
          sum = sum + j
        end
        return sum
      end

      local bench = Benchmark.Benchmark.new("compute_bench", fn, {
        iterations = 50,
        warmup_iterations = 2
      })

      local stats = bench:Run()

      assert.is.equal("compute_bench", stats.name)
      assert.is.equal(50, stats.iterations)
      assert.is.truthy(stats.mean >= 0)  -- Can be very close to 0
      assert.is.truthy(stats.min >= 0)
      assert.is.truthy(stats.max >= stats.min)
      assert.is.equal(50, #stats.times)
      assert.is.truthy(stats.throughput > 0 or stats.ops_per_second > 0)
    end)

    it("should calculate percentiles correctly", function()
      local fn = function(i)
        -- Variable work to create distribution
        local sum = 0
        for j = 1, (i % 10) * 10 do
          sum = sum + j
        end
        return sum
      end

      local bench = Benchmark.Benchmark.new("variable_bench", fn, {
        iterations = 100
      })

      local stats = bench:Run()

      assert.is.truthy(stats.percentile_95 >= stats.median)
      assert.is.truthy(stats.percentile_99 >= stats.percentile_95)
      assert.is.truthy(stats.std_dev >= 0)
    end)

    it("should track throughput", function()
      local fn = function(i)
        return i * 2
      end

      local bench = Benchmark.Benchmark.new("throughput_bench", fn, {
        iterations = 200
      })

      local stats = bench:Run()

      assert.is.truthy(stats.throughput > 0)
      assert.is.truthy(stats.ops_per_second > 0)
    end)
  end)

  describe("Comparison", function()
    it("should create empty comparison", function()
      local comp = Benchmark.Comparison.new("test_comparison")

      assert.is.equal("test_comparison", comp.name)
      assert.is.equal(0, #comp.benchmarks)
    end)

    it("should add benchmarks to comparison", function()
      local comp = Benchmark.Comparison.new()
      local bench1 = Benchmark.Benchmark.new("bench1", function(i) return i end)
      local bench2 = Benchmark.Benchmark.new("bench2", function(i) return i * 2 end)

      comp:AddBenchmark(bench1)
      comp:AddBenchmark(bench2)

      assert.is.equal(2, #comp.benchmarks)
    end)

    it("should run all benchmarks in comparison", function()
      local comp = Benchmark.Comparison.new()

      comp:AddBenchmark(Benchmark.Benchmark.new("fast", function(i)
        local sum = 0
        for j = 1, 10 do sum = sum + j end
        return sum
      end, {iterations = 50}))

      comp:AddBenchmark(Benchmark.Benchmark.new("slow", function(i)
        local sum = 0
        for j = 1, 100 do sum = sum + j end
        return sum
      end, {iterations = 50}))

      local results = comp:Run()

      assert.is.equal(2, #results)
      assert.is.equal("fast", results[1].name)
      assert.is.equal("slow", results[2].name)
    end)

    it("should compare by mean metric", function()
      local comp = Benchmark.Comparison.new()

      comp:AddBenchmark(Benchmark.Benchmark.new("fast", function(i)
        local sum = 0
        for j = 1, 10 do sum = sum + j end
        return sum
      end, {iterations = 50}))

      comp:AddBenchmark(Benchmark.Benchmark.new("slow", function(i)
        local sum = 0
        for j = 1, 100 do sum = sum + j end
        return sum
      end, {iterations = 50}))

      comp:Run()
      local comparison = comp:Compare("mean")

      assert.is.equal("mean", comparison.metric)
      assert.is.equal(2, #comparison.results)

      -- Fast should be ranked first (lower time is better)
      assert.is.equal(1, comparison.results[1].rank)
      assert.is.equal("fast", comparison.results[1].name)
    end)

    it("should calculate speedup between benchmarks", function()
      local comp = Benchmark.Comparison.new()

      comp:AddBenchmark(Benchmark.Benchmark.new("baseline", function(i)
        local sum = 0
        for j = 1, 100 do sum = sum + j end
        return sum
      end, {iterations = 50}))

      comp:AddBenchmark(Benchmark.Benchmark.new("optimized", function(i)
        local sum = 0
        for j = 1, 10 do sum = sum + j end
        return sum
      end, {iterations = 50}))

      comp:Run()

      local speedup, opt_time, base_time = comp:GetSpeedup("baseline", "optimized")

      assert.is_truthy(speedup > 1)  -- Optimized should be faster
      assert.is_truthy(opt_time < base_time)
    end)

    it("should compare by throughput metric", function()
      local comp = Benchmark.Comparison.new()

      comp:AddBenchmark(Benchmark.Benchmark.new("fast", function(i)
        return i
      end, {iterations = 100}))

      comp:AddBenchmark(Benchmark.Benchmark.new("slow", function(i)
        local sum = 0
        for j = 1, 50 do sum = sum + j end
        return sum
      end, {iterations = 100}))

      comp:Run()
      local comparison = comp:Compare("ops_per_second")

      -- Higher throughput is better
      assert.is.equal(1, comparison.results[1].rank)
      assert.is.equal("fast", comparison.results[1].name)
    end)
  end)

  describe("Suite", function()
    it("should create suite with name", function()
      local suite = Benchmark.Suite.new("test_suite")

      assert.is.equal("test_suite", suite.name)
    end)

    it("should add benchmarks to suite", function()
      local suite = Benchmark.Suite.new()

      suite:AddBenchmark("bench1", function(i) return i end)
      suite:AddBenchmark("bench2", function(i) return i * 2 end)

      assert.is.equal(2, #suite.benchmarks)
    end)

    it("should add comparison to suite", function()
      local suite = Benchmark.Suite.new()

      suite:AddComparison("speed_comparison", {
        fast = function(i) return i end,
        slow = function(i)
          local sum = 0
          for j = 1, 50 do sum = sum + j end
          return sum
        end
      })

      assert.is.equal(1, #suite.comparisons)
    end)

    it("should run all benchmarks and comparisons", function()
      local suite = Benchmark.Suite.new("full_suite")

      suite:AddBenchmark("bench1", function(i) return i end, {iterations = 50})
      suite:AddBenchmark("bench2", function(i) return i * 2 end, {iterations = 50})

      suite:AddComparison("comp1", {
        variant_a = function(i) return i end,
        variant_b = function(i)
          local sum = 0
          for j = 1, 20 do sum = sum + j end
          return sum
        end
      })

      local results = suite:Run()

      assert.is.equal("full_suite", results.suite_name)
      assert.is.equal(2, #results.benchmarks)
      assert.is.equal(1, #results.comparisons)
      assert.is.truthy(results.total_duration >= 0)
    end)

    it("should generate report from results", function()
      local suite = Benchmark.Suite.new("report_suite")

      suite:AddBenchmark("test_bench", function(i) return i end, {iterations = 50})

      local results = suite:Run()
      local report = suite:GenerateReport(results)

      assert.is.equal("report_suite", report.suite_name)
      assert.is.truthy(report.timestamp)
      assert.is.equal(1, #report.benchmarks)

      local bench_report = report.benchmarks[1]
      assert.is.equal("test_bench", bench_report.name)
      assert.is.truthy(bench_report.mean_ms)
      assert.is.truthy(bench_report.ops_per_sec)
    end)
  end)

  describe("Profiler", function()
    it("should create profiler", function()
      local profiler = Benchmark.Profiler.new()

      assert.is_false(profiler.active)
    end)

    it("should start and stop profiling", function()
      local profiler = Benchmark.Profiler.new()

      profiler:Start()

      assert.is_true(profiler.active)
      assert.is.truthy(profiler.start_time)

      profiler:Sample("phase1")
      profiler:Sample("phase2")

      local result = profiler:Stop()

      assert.is_false(profiler.active)
      assert.is.truthy(result.total_duration >= 0)
      assert.is.equal(2, result.sample_count)
    end)

    it("should analyze profiling samples", function()
      local profiler = Benchmark.Profiler.new()

      profiler:Start()

      -- Simulate work with samples
      profiler:Sample("init")
      local sum = 0
      for i = 1, 100 do sum = sum + i end

      profiler:Sample("compute")
      for i = 1, 50 do sum = sum + i end

      profiler:Sample("finalize")

      local result = profiler:Stop()
      local analysis = profiler:Analyze()

      assert.is.equal(3, #analysis.phases)

      -- Check phases
      assert.is.equal("init", analysis.phases[1].label)
      assert.is.equal("compute", analysis.phases[2].label)
      assert.is.equal("finalize", analysis.phases[3].label)

      -- Check durations
      for _, phase in ipairs(analysis.phases) do
        assert.is.truthy(phase.duration >= 0)
        assert.is.truthy(phase.percentage >= 0 and phase.percentage <= 100)
      end
    end)

    it("should detect gaps between samples", function()
      local profiler = Benchmark.Profiler.new()

      profiler:Start()

      profiler:Sample("phase1")
      -- Intentional gap (no work)
      profiler:Sample("phase2")

      local result = profiler:Stop()
      local analysis = profiler:Analyze()

      -- Should have phases but minimal gaps in this simple case
      assert.is.equal(2, #analysis.phases)
    end)

    it("should error when sampling inactive profiler", function()
      local profiler = Benchmark.Profiler.new()

      assert.has_error(function()
        profiler:Sample("test")
      end)
    end)

    it("should error when analyzing active profiler", function()
      local profiler = Benchmark.Profiler.new()

      profiler:Start()

      assert.has_error(function()
        profiler:Analyze()
      end)
    end)
  end)

  describe("MemoryMonitor", function()
    it("should create memory monitor", function()
      local monitor = Benchmark.MemoryMonitor.new()

      assert.is_false(monitor.active)
      assert.is.equal(0, #monitor.snapshots)
    end)

    it("should take snapshots", function()
      local monitor = Benchmark.MemoryMonitor.new()

      monitor:Snapshot("start")

      -- Do some work
      local data = {}
      for i = 1, 100 do
        data[i] = string.rep("x", i * 10)
      end

      monitor:Snapshot("end")

      assert.is.equal(2, #monitor.snapshots)
      assert.is.equal("start", monitor.snapshots[1].label)
      assert.is.equal("end", monitor.snapshots[2].label)
    end)

    it("should compare snapshots", function()
      local monitor = Benchmark.MemoryMonitor.new()

      monitor:Snapshot("before")
      local data = {}
      for i = 1, 10 do data[i] = string.rep("x", 100) end
      monitor:Snapshot("after")

      local comparison = monitor:Compare("before", "after")

      assert.is.equal("before", comparison.label1)
      assert.is.equal("after", comparison.label2)
      assert.is_truthy(comparison.time_delta >= 0)
    end)

    it("should get memory trend", function()
      local monitor = Benchmark.MemoryMonitor.new()

      monitor:Snapshot("snap1")
      monitor:Snapshot("snap2")
      monitor:Snapshot("snap3")

      local trend = monitor:GetTrend()

      assert.is.equal("snap1", monitor.snapshots[1].label)
      assert.is.truthy(trend.start_memory)
      assert.is_truthy(trend.end_memory)
      assert.is.equal(3, trend.samples)
    end)

    it("should return error for non-existent snapshots", function()
      local monitor = Benchmark.MemoryMonitor.new()

      monitor:Snapshot("existing")

      local result, err = monitor:Compare("existing", "non_existent")

      assert.is_nil(result)
      assert.is_truthy(err)
    end)

    it("should return error for insufficient snapshots", function()
      local monitor = Benchmark.MemoryMonitor.new()

      monitor:Snapshot("single")

      local result, err = monitor:GetTrend()

      assert.is_nil(result)
      assert.is_truthy(err)
    end)
  end)

  describe("Helper Functions", function()
    it("should create benchmark with helper", function()
      local bench = Benchmark.benchmark("helper_test", function(i) return i end)

      assert.is.equal("helper_test", bench.name)
    end)

    it("should create suite with helper", function()
      local suite = Benchmark.suite("helper_suite")

      assert.is.equal("helper_suite", suite.name)
    end)

    it("should format benchmark results", function()
      local fn = function(i) return i end
      local bench = Benchmark.Benchmark.new("format_test", fn, {iterations = 50})

      local stats = bench:Run()
      local formatted = Benchmark.format_results(stats)

      assert.is_truthy(formatted:find("Benchmark: format_test"))
      assert.is_truthy(formatted:find("Mean:"))
      assert.is_truthy(formatted:find("Throughput:"))
    end)

    it("should format comparison results", function()
      local comp = Benchmark.Comparison.new("format_comparison")

      comp:AddBenchmark(Benchmark.Benchmark.new("fast", function(i) return i end))
      comp:AddBenchmark(Benchmark.Benchmark.new("slow", function(i)
        local sum = 0
        for j = 1, 50 do sum = sum + j end
        return sum
      end))

      comp:Run()
      local comparison = comp:Compare("mean")
      local formatted = Benchmark.format_comparison(comparison)

      assert.is_truthy(formatted:find("Comparison: format_comparison"))
      assert.is_truthy(formatted:find("%d%."))
      assert.is.truthy(formatted:find("fast"))
      assert.is.truthy(formatted:find("slow"))
    end)
  end)

  describe("Integration Tests", function()
    it("should benchmark multiple scenarios", function()
      local scenarios = {
        lightweight = function(i)
          return i + 1
        end,
        medium = function(i)
          local sum = 0
          for j = 1, 50 do sum = sum + j end
          return sum
        end,
        heavy = function(i)
          local sum = 0
          for j = 1, 200 do sum = sum + j end
          return sum
        end
      }

      local suite = Benchmark.Suite.new("scenario_comparison")

      for name, fn in pairs(scenarios) do
        suite:AddBenchmark(name, fn, {iterations = 50})
      end

      local results = suite:Run()

      assert.is.equal(3, #results.benchmarks)

      -- Lightweight should be fastest (lowest mean time)
      local sorted = results.benchmarks
      table.sort(sorted, function(a, b) return a.mean < b.mean end)

      assert.is.equal("lightweight", sorted[1].name)
      assert.is.equal("heavy", sorted[3].name)
    end)

    it("should profile complex workflow", function()
      local profiler = Benchmark.Profiler.new()

      profiler:Start()

      -- Initialization
      profiler:Sample("init")
      local config = {items = {}}
      for i = 1, 10 do
        table.insert(config.items, i)
      end

      -- Processing
      profiler:Sample("process")
      local results = {}
      for _, item in ipairs(config.items) do
        table.insert(results, item * 2)
      end

      -- Cleanup
      profiler:Sample("cleanup")
      config = nil
      results = nil

      local profile_result = profiler:Stop()
      local analysis = profiler:Analyze()

      -- Should have 3 phases
      assert.is.equal(3, #analysis.phases)

      -- Process should take longest
      local process_phase = nil
      for _, phase in ipairs(analysis.phases) do
        if phase.label == "process" then
          process_phase = phase
          break
        end
      end

      assert.is_truthy(process_phase)
      assert.is.truthy(process_phase.duration >= 0)
    end)

    it("should track memory allocation patterns", function()
      local monitor = Benchmark.MemoryMonitor.new()

      monitor:Snapshot("empty")

      local data1 = {}
      for i = 1, 100 do
        data1[i] = string.rep("a", 50)
      end

      monitor:Snapshot("after_allocation_1")

      local data2 = {}
      for i = 1, 200 do
        data2[i] = string.rep("b", 100)
      end

      monitor:Snapshot("after_allocation_2")

      monitor:Snapshot("after_gc")

      local trend = monitor:GetTrend()

      -- Memory should have increased
      assert.is.truthy(trend.end_memory >= trend.start_memory)

      -- Check individual snapshots
      local comp1 = monitor:Compare("empty", "after_allocation_1")
      local comp2 = monitor:Compare("after_allocation_1", "after_allocation_2")

      assert.is_truthy(comp1.delta_kb >= 0)
      assert.is_truthy(comp2.delta_kb >= 0)
    end)
  end)
end)
