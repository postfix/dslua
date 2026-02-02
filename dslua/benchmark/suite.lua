-- dslua/benchmark/suite.lua
-- Performance Benchmarking Suite - Measure and analyze performance

local M = {}

-- =============================================================================
-- Benchmark - Individual benchmark case
-- =============================================================================

M.Benchmark = {}
M.Benchmark.__index = M.Benchmark

function M.Benchmark.new(name, fn, opts)
  opts = opts or {}

  local self = {
    name = name,
    fn = fn,
    iterations = opts.iterations or 1000,
    warmup_iterations = opts.warmup_iterations or 10,
    timeout = opts.timeout or 30,
    metadata = opts.metadata or {}
  }
  setmetatable(self, M.Benchmark)
  return self
end

function M.Benchmark:Run()
  -- Warmup
  for i = 1, self.warmup_iterations do
    self.fn(i)
  end

  -- Collect samples
  local times = {}
  local start_time = os.clock()

  for i = 1, self.iterations do
    local iter_start = os.clock()
    self.fn(i)
    local iter_end = os.clock()

    table.insert(times, (iter_end - iter_start) * 1000)  -- Convert to ms

    -- Timeout check
    if (os.clock() - start_time) > self.timeout then
      break
    end
  end

  -- Calculate statistics
  table.sort(times)

  local stats = {
    name = self.name,
    iterations = #times,
    total_time = (os.clock() - start_time) * 1000,
    times = times,
    min = times[1],
    max = times[#times],
    mean = 0,
    median = times[math.floor(#times / 2)],
    percentile_95 = times[math.floor(#times * 0.95)],
    percentile_99 = times[math.floor(#times * 0.99)],
    std_dev = 0
  }

  -- Calculate mean
  local sum = 0
  for _, time in ipairs(times) do
    sum = sum + time
  end
  stats.mean = sum / #times

  -- Calculate standard deviation
  local variance = 0
  for _, time in ipairs(times) do
    variance = variance + (time - stats.mean) ^ 2
  end
  stats.std_dev = math.sqrt(variance / #times)

  stats.ops_per_second = 1000 / stats.mean
  stats.throughput = stats.iterations / (stats.total_time / 1000)

  return stats
end

-- =============================================================================
-- Comparison - Compare multiple benchmarks
-- =============================================================================

M.Comparison = {}
M.Comparison.__index = M.Comparison

function M.Comparison.new(name)
  local self = {
    name = name or "comparison",
    benchmarks = {},
    results = {}
  }
  setmetatable(self, M.Comparison)
  return self
end

function M.Comparison:AddBenchmark(benchmark)
  table.insert(self.benchmarks, benchmark)
  return self
end

function M.Comparison:Run()
  self.results = {}

  for _, benchmark in ipairs(self.benchmarks) do
    local stats = benchmark:Run()
    table.insert(self.results, stats)
  end

  return self.results
end

function M.Comparison:Compare(metric)
  metric = metric or "mean"

  local comparison = {
    name = self.name,
    metric = metric,
    results = {}
  }

  for _, result in ipairs(self.results) do
    table.insert(comparison.results, {
      name = result.name,
      value = result[metric],
      rank = 0  -- Will be set below
    })
  end

  -- Sort by value (ascending for time, descending for throughput)
  local is_time_metric = (metric == "mean" or metric == "min" or metric == "max" or
                          metric == "median" or metric == "percentile_95" or
                          metric == "percentile_99" or metric == "std_dev")

  table.sort(comparison.results, function(a, b)
    if is_time_metric then
      return a.value < b.value
    else
      return a.value > b.value
    end
  end)

  -- Assign ranks
  for i, result in ipairs(comparison.results) do
    result.rank = i
  end

  return comparison
end

function M.Comparison:GetSpeedup(baseline_name, candidate_name)
  local baseline = nil
  local candidate = nil

  for _, result in ipairs(self.results) do
    if result.name == baseline_name then
      baseline = result
    elseif result.name == candidate_name then
      candidate = result
    end
  end

  if not baseline or not candidate then
    return nil, "Benchmark not found"
  end

  return baseline.mean / candidate.mean, candidate.mean, baseline.mean
end

-- =============================================================================
-- Suite - Collection of benchmarks
-- =============================================================================

M.Suite = {}
M.Suite.__index = M.Suite

function M.Suite.new(name)
  local self = {
    name = name or "benchmark_suite",
    benchmarks = {},
    comparisons = {},
    metadata = {}
  }
  setmetatable(self, M.Suite)
  return self
end

function M.Suite:AddBenchmark(name, fn, opts)
  local benchmark = M.Benchmark.new(name, fn, opts)
  table.insert(self.benchmarks, benchmark)
  return self
end

function M.Suite:AddComparison(name, benchmark_fns)
  local comparison = M.Comparison.new(name)

  for bench_name, bench_fn in pairs(benchmark_fns) do
    local bench = M.Benchmark.new(bench_name, bench_fn)
    comparison:AddBenchmark(bench)
  end

  table.insert(self.comparisons, comparison)
  return self
end

function M.Suite:Run()
  local results = {
    suite_name = self.name,
    start_time = os.time(),
    benchmarks = {},
    comparisons = {},
    total_duration = 0
  }

  -- Run individual benchmarks
  for _, benchmark in ipairs(self.benchmarks) do
    local stats = benchmark:Run()
    table.insert(results.benchmarks, stats)
  end

  -- Run comparisons
  for _, comparison in ipairs(self.comparisons) do
    local comp_results = comparison:Run()
    table.insert(results.comparisons, comp_results)
  end

  results.end_time = os.time()
  results.total_duration = results.end_time - results.start_time

  return results
end

function M.Suite:GenerateReport(results)
  local report = {
    suite_name = results.suite_name,
    timestamp = os.date("%Y-%m-%d %H:%M:%S"),
    duration = results.total_duration,
    benchmarks = {},
    comparisons = {}
  }

  -- Benchmark reports
  for _, stats in ipairs(results.benchmarks) do
    table.insert(report.benchmarks, {
      name = stats.name,
      iterations = stats.iterations,
      mean_ms = string.format("%.4f", stats.mean),
      min_ms = string.format("%.4f", stats.min),
      max_ms = string.format("%.4f", stats.max),
      median_ms = string.format("%.4f", stats.median),
      p95_ms = string.format("%.4f", stats.percentile_95),
      p99_ms = string.format("%.4f", stats.percentile_99),
      std_dev_ms = string.format("%.4f", stats.std_dev),
      ops_per_sec = string.format("%.2f", stats.ops_per_second)
    })
  end

  -- Comparison reports
  for _, comparison in ipairs(results.comparisons) do
    local comp_report = {
      name = comparison.name,
      metric = comparison.metric,
      results = {}
    }

    for _, result in ipairs(comparison.results) do
      table.insert(comp_report.results, {
        name = result.name,
        value = string.format("%.4f", result.value),
        rank = result.rank
      })
    end

    table.insert(report.comparisons, comp_report)
  end

  return report
end

-- =============================================================================
-- Profiler - Memory and performance profiling
-- =============================================================================

M.Profiler = {}
M.Profiler.__index = M.Profiler

function M.Profiler.new()
  local self = {
    start_time = nil,
    end_time = nil,
    samples = {},
    active = false
  }
  setmetatable(self, M.Profiler)
  return self
end

function M.Profiler:Start()
  self.start_time = os.clock()
  self.active = true
  self.samples = {}
  return self
end

function M.Profiler:Sample(label)
  if not self.active then
    error("Profiler not active. Call Start() first.")
  end

  local current_time = os.clock()

  table.insert(self.samples, {
    label = label,
    time = (current_time - self.start_time) * 1000,  -- ms from start
    timestamp = current_time
  })
end

function M.Profiler:Stop()
  self.end_time = os.clock()
  self.active = false

  return {
    total_duration = (self.end_time - self.start_time) * 1000,  -- ms
    samples = self.samples,
    sample_count = #self.samples
  }
end

function M.Profiler:Analyze()
  if self.active then
    error("Profiler still active. Call Stop() first.")
  end

  local analysis = {
    total_duration = (self.end_time - self.start_time) * 1000,
    phases = {},
    gaps = {}
  }

  -- Analyze phases between samples
  for i = 1, #self.samples do
    local sample = self.samples[i]
    local prev_sample = i > 1 and self.samples[i - 1] or {time = 0}

    table.insert(analysis.phases, {
      label = sample.label,
      start_time = prev_sample.time,
      end_time = sample.time,
      duration = sample.time - prev_sample.time,
      percentage = ((sample.time - prev_sample.time) / analysis.total_duration) * 100
    })
  end

  -- Analyze gaps between samples
  for i = 2, #self.samples do
    local gap_start = self.samples[i - 1].timestamp
    local gap_end = self.samples[i].timestamp

    if gap_end - gap_start > 0 then
      table.insert(analysis.gaps, {
        after_label = self.samples[i - 1].label,
        before_label = self.samples[i].label,
        duration = (gap_end - gap_start) * 1000
      })
    end
  end

  return analysis
end

-- =============================================================================
-- MemoryMonitor - Track memory usage
-- =============================================================================

M.MemoryMonitor = {}
M.MemoryMonitor.__index = M.MemoryMonitor

function M.MemoryMonitor.new()
  local self = {
    snapshots = {},
    active = false
  }
  setmetatable(self, M.MemoryMonitor)
  return self
end

function M.MemoryMonitor:Snapshot(label)
  local snapshot = {
    label = label,
    timestamp = os.time(),
    -- Note: LuaJIT doesn't provide direct memory access
    -- This is a placeholder for future implementation
    memory_kb = collectgarbage("count")  -- Approximate
  }

  table.insert(self.snapshots, snapshot)
  return snapshot
end

function M.MemoryMonitor:Compare(label1, label2)
  local snap1, snap2 = nil, nil

  for _, snap in ipairs(self.snapshots) do
    if snap.label == label1 then snap1 = snap end
    if snap.label == label2 then snap2 = snap end
  end

  if not snap1 or not snap2 then
    return nil, "Snapshot not found"
  end

  return {
    label1 = label1,
    label2 = label2,
    memory1_kb = snap1.memory_kb,
    memory2_kb = snap2.memory_kb,
    delta_kb = snap2.memory_kb - snap1.memory_kb,
    time_delta = snap2.timestamp - snap1.timestamp
  }
end

function M.MemoryMonitor:GetTrend()
  if #self.snapshots < 2 then
    return nil, "Need at least 2 snapshots"
  end

  local trend = {
    start_memory = self.snapshots[1].memory_kb,
    end_memory = self.snapshots[#self.snapshots].memory_kb,
    delta = self.snapshots[#self.snapshots].memory_kb - self.snapshots[1].memory_kb,
    samples = #self.snapshots
  }

  return trend
end

-- =============================================================================
-- Helper Functions
-- =============================================================================

-- Create a simple benchmark
function M.benchmark(name, fn, opts)
  return M.Benchmark.new(name, fn, opts)
end

-- Create a suite
function M.suite(name)
  return M.Suite.new(name)
end

-- Format benchmark results for display
function M.format_results(stats)
  local lines = {}

  table.insert(lines, string.rep("=", 60))
  table.insert(lines, "Benchmark: " .. stats.name)
  table.insert(lines, string.rep("=", 60))
  table.insert(lines, "")
  table.insert(lines, "Iterations: " .. stats.iterations)
  table.insert(lines, "Total time: " .. string.format("%.2f ms", stats.total_time))
  table.insert(lines, "")
  table.insert(lines, "Latency (ms):")
  table.insert(lines, "  Mean:      " .. string.format("%.4f", stats.mean))
  table.insert(lines, "  Median:    " .. string.format("%.4f", stats.median))
  table.insert(lines, "  Min:       " .. string.format("%.4f", stats.min))
  table.insert(lines, "  Max:       " .. string.format("%.4f", stats.max))
  table.insert(lines, "  Std Dev:   " .. string.format("%.4f", stats.std_dev))
  table.insert(lines, "  95th %ile: " .. string.format("%.4f", stats.percentile_95))
  table.insert(lines, "  99th %ile: " .. string.format("%.4f", stats.percentile_99))
  table.insert(lines, "")
  table.insert(lines, "Throughput:")
  table.insert(lines, "  " .. string.format("%.2f ops/sec", stats.ops_per_second))
  table.insert(lines, "")

  return table.concat(lines, "\n")
end

-- Format comparison results
function M.format_comparison(comparison)
  local lines = {}

  table.insert(lines, string.rep("=", 60))
  table.insert(lines, "Comparison: " .. comparison.name .. " (by " .. comparison.metric .. ")")
  table.insert(lines, string.rep("=", 60))
  table.insert(lines, "")

  for _, result in ipairs(comparison.results) do
    table.insert(lines, string.format("%d. %s: %.4f", result.rank, result.name, result.value))
  end

  table.insert(lines, "")

  return table.concat(lines, "\n")
end

return M
