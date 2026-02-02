-- dslua/modules/parallel.lua
-- Parallel module - Concurrent batch processing for improved throughput

local M = {}
local Base = require("dslua.modules.base")

M.__index = M
setmetatable(M, {__index = Base})

-- =============================================================================
-- Parallel.new - Create parallel processing module
-- =============================================================================

function M.new(signature, base_module, opts)
  opts = opts or {}

  local self = Base.new(signature, opts)
  setmetatable(self, M)

  self._base_module = base_module
  self._max_workers = opts.max_workers or 4
  self._timeout = opts.timeout or 30
  self._retry_strategy = opts.retry_strategy or "exponential"
  self._max_retries = opts.max_retries or 3

  return self
end

-- =============================================================================
-- Process - Process batch of inputs in parallel
-- =============================================================================

function M:Process(ctx, inputs)
  if not inputs or #inputs == 0 then
    return {}
  end

  if #inputs == 1 then
    -- Single input: process directly
    local result = self:_ProcessSingle(ctx, inputs[1])
    return {result}
  end

  -- Batch: process in parallel
  local results = {}
  local n = #inputs

  -- Create worker pool
  local num_workers = math.min(self._max_workers, n)

  -- Process in batches
  local batch_size = math.ceil(n / num_workers)

  for i = 1, n, batch_size do
    local batch_start = i
    local batch_end = math.min(i + batch_size - 1, n)

    local batch_results = self:_ProcessBatch(
      ctx,
      inputs,
      batch_start,
      batch_end
    )

    -- Merge results
    for j, result in ipairs(batch_results) do
      table.insert(results, result)
    end
  end

  return results
end

-- =============================================================================
-- ProcessAsync - Process batch asynchronously with callbacks
-- =============================================================================

function M:ProcessAsync(ctx, inputs, callback, error_handler)
  error_handler = error_handler or function(err)
  end

  if not inputs or #inputs == 0 then
    callback({})
    return
  end

  local results = {}
  local pending = #inputs
  local completed = 0

  -- Process each input
  for i, input in ipairs(inputs) do
    local success, result = pcall(function()
      return self:_ProcessSingle(ctx, input)
    end)

    if success then
      results[i] = result
      completed = completed + 1
      pending = pending - 1
    else
      if error_handler then
        error_handler(result)
      end
      results[i] = {error = tostring(result)}
      completed = completed + 1
      pending = pending - 1
    end

    -- Check if all complete
    if completed >= #inputs then
      callback(results)
      return
    end
  end
end

-- =============================================================================
-- ProcessWithTimeout - Process with per-item timeout
-- =============================================================================

function M:ProcessWithTimeout(ctx, inputs, opts)
  opts = opts or {}

  local timeout = opts.timeout or self._timeout

  local results = {}

  for i, input in ipairs(inputs) do
    local start_time = os.clock()

    -- Process with timeout
    local success, result = pcall(function()
      return self:_ProcessSingle(ctx, input)
    end)

    local end_time = os.clock()
    local elapsed = end_time - start_time

    if success then
      results[i] = {
        output = result,
        timed_out = false,
        elapsed_ms = elapsed * 1000
      }
    else
      results[i] = {
        error = tostring(result),
        timed_out = false,
        elapsed_ms = elapsed * 1000
      }
    end

    -- Check for timeout
    if elapsed > timeout and not results[i].error then
      results[i].timed_out = true
      results[i].error = "Timeout"
    end
  end

  return results
end

-- =============================================================================
-- ProcessWithRetry - Process with automatic retry on failure
-- =============================================================================

function M:ProcessWithRetry(ctx, inputs, opts)
  opts = opts or {}

  local max_retries = opts.max_retries or self._max_retries
  local retry_strategy = opts.retry_strategy or self._retry_strategy
  local backoff_base = opts.backoff_base or 1.0
  local backoff_max = opts.backoff_max or 10.0

  local results = {}

  for i, input in ipairs(inputs) do
    local result = self:_ProcessWithRetrySingle(
      ctx,
      input,
      max_retries,
      retry_strategy,
      backoff_base,
      backoff_max
    )

    results[i] = result
  end

  return results
end

-- =============================================================================
-- ProcessBatchWithProgress - Process batch with progress tracking
-- =============================================================================

function M:ProcessBatchWithProgress(ctx, inputs, progress_callback, opts)
  opts = opts or {}

  local n = #inputs
  local results = {}
  local completed = 0

  -- Initial progress
  if progress_callback then
    progress_callback(0, n, nil)
  end

  for i, input in ipairs(inputs) do
    local success, result = pcall(function()
      return self:_ProcessSingle(ctx, input)
    end)

    results[i] = success and result or {error = tostring(result)}

    completed = completed + 1

    -- Update progress
    if progress_callback then
      progress_callback(completed, n, i)
    end
  end

  return results
end

-- =============================================================================
-- Private helper methods
-- =============================================================================

function M:_ProcessSingle(ctx, input)
  -- Delegate to base module
  return self._base_module:Process(ctx, input)
end

function M:_ProcessBatch(ctx, inputs, start_idx, end_idx)
  local results = {}

  for i = start_idx, end_idx do
    local success, result = pcall(function()
      return self:_ProcessSingle(ctx, inputs[i])
    end)

    results[i - start_idx + 1] = success and result or {error = tostring(result)}
  end

  return results
end

function M:_ProcessWithRetrySingle(ctx, input, max_retries, retry_strategy, backoff_base, backoff_max)
  local attempt = 0
  local last_error = nil

  while attempt <= max_retries do
    local success, result = pcall(function()
      return self:_ProcessSingle(ctx, input)
    end)

    if success then
      return {
        output = result,
        attempts = attempt + 1,
        retry_strategy_used = retry_strategy
      }
    end

    last_error = result
    attempt = attempt + 1

    -- Wait before retry (exponential backoff)
    if attempt <= max_retries then
      local delay = math.min(backoff_base * math.pow(2, attempt - 1), backoff_max)
      -- Busy wait for delay (os.sleep doesn't exist in standard Lua)
      local start_time = os.clock()
      while os.clock() - start_time < delay do
        -- Busy wait
      end
    end
  end

  return {
    error = last_error and tostring(last_error) or "Max retries exceeded",
    attempts = max_retries + 1,
    retry_strategy_used = retry_strategy
  }
end

-- =============================================================================
-- Batch operations
-- =============================================================================

function M:Map(ctx, inputs, transform_fn)
  -- Process inputs and transform results
  local results = self:Process(ctx, inputs)

  local mapped = {}
  for i, result in ipairs(results) do
    if type(result) == "table" and result.error then
      mapped[i] = {error = result.error}
    elseif transform_fn then
      mapped[i] = transform_fn(result)
    else
      mapped[i] = result
    end
  end

  return mapped
end

function M:Filter(ctx, inputs, predicate_fn)
  -- Process and filter results
  local results = self:Process(ctx, inputs)

  local filtered = {}
  for i, result in ipairs(results) do
    if type(result) == "table" and result.error then
      -- Skip errors
    elseif predicate_fn(result) then
      table.insert(filtered, result)
    end
  end

  return filtered
end

function M:ForEach(ctx, inputs, action_fn)
  -- Process all inputs and apply action to each
  local results = self:Process(ctx, inputs)

  for i, result in ipairs(results) do
    if not (type(result) == "table" and result.error) then
      action_fn(result, i)
    end
  end

  return results
end

-- =============================================================================
-- Batch statistics
-- =============================================================================

function M:GetStats(last_results)
  -- Compute statistics from batch processing results
  local stats = {
    total = #last_results,
    successful = 0,
    failed = 0,
    total_latency_ms = 0,
    avg_latency_ms = 0,
    max_latency_ms = 0,
    min_latency_ms = math.huge
  }

  for _, result in ipairs(last_results) do
    if result.error then
      stats.failed = stats.failed + 1
    else
      stats.successful = stats.successful + 1

      if result.elapsed_ms then
        local latency = result.elapsed_ms
        stats.total_latency_ms = stats.total_latency_ms + latency
        stats.max_latency_ms = math.max(stats.max_latency_ms, latency)
        stats.min_latency_ms = math.min(stats.min_latency_ms, latency)
      end
    end
  end

  if stats.total_latency_ms > 0 and stats.successful > 0 then
    stats.avg_latency_ms = stats.total_latency_ms / stats.successful
  end

  return stats
end

-- =============================================================================
-- Configure - Update parallel processing settings
-- =============================================================================

function M:Configure(opts)
  for key, value in pairs(opts) do
    if key == "max_workers" then
      self._max_workers = value
    elseif key == "timeout" then
      self._timeout = value
    elseif key == "retry_strategy" then
      self._retry_strategy = value
    elseif key == "max_retries" then
      self._max_retries = value
    end
  end

  return self
end

return M
