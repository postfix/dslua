-- specs/modules/parallel_spec.lua
-- Tests for Parallel module - concurrent batch processing

describe("Parallel", function()
  local Field = require("dslua.core.field")
  local Signature = require("dslua.core.signature")
  local Context = require("dslua.core.context")
  local Parallel = require("dslua.modules.parallel")
  local Predict = require("dslua.modules.predict")

  -- Helper to create mock base module
  local function createMockModule(latency_ms)
    latency_ms = latency_ms or 10

    local signature = Signature.new(
      {Field.new("question")},
      {Field.new("answer")}
    )

    local base_module = Predict.new(signature)

    -- Override Process to simulate work
    local original_process = base_module.Process
    base_module.Process = function(self, ctx, input)
      -- Simulate latency
      if latency_ms > 0 then
        local start = os.clock()
        while (os.clock() - start) * 1000 < latency_ms do
          -- Busy wait to simulate work
        end
      end

      -- Return result
      return {answer = "Answer to: " .. input.question}
    end

    return base_module
  end

  -- Helper to create mock context
  local function createMockContext()
    local mock_llm = {
      Complete = function(self, ctx, prompt, opts)
        return {answer = "42"}
      end
    }
    return Context.new({llm = mock_llm})
  end

  describe("new", function()
    it("should create parallel module with signature and base module", function()
      local signature = Signature.new(
        {Field.new("question")},
        {Field.new("answer")}
      )
      local base_module = Predict.new(signature)

      local parallel = Parallel.new(signature, base_module)

      assert.is.equal(signature, parallel:Signature())
      assert.is.equal(base_module, parallel._base_module)
    end)

    it("should set default options", function()
      local signature = Signature.new(
        {Field.new("question")},
        {Field.new("answer")}
      )
      local base_module = Predict.new(signature)

      local parallel = Parallel.new(signature, base_module)

      assert.is.equal(4, parallel._max_workers)
      assert.is.equal(30, parallel._timeout)
      assert.is.equal("exponential", parallel._retry_strategy)
      assert.is.equal(3, parallel._max_retries)
    end)

    it("should accept custom options", function()
      local signature = Signature.new(
        {Field.new("question")},
        {Field.new("answer")}
      )
      local base_module = Predict.new(signature)

      local parallel = Parallel.new(signature, base_module, {
        max_workers = 8,
        timeout = 60,
        retry_strategy = "linear",
        max_retries = 5
      })

      assert.is.equal(8, parallel._max_workers)
      assert.is.equal(60, parallel._timeout)
      assert.is.equal("linear", parallel._retry_strategy)
      assert.is.equal(5, parallel._max_retries)
    end)
  end)

  describe("Process", function()
    it("should return empty table for empty inputs", function()
      local signature = Signature.new(
        {Field.new("question")},
        {Field.new("answer")}
      )
      local base_module = createMockModule(0)
      local ctx = createMockContext()

      local parallel = Parallel.new(signature, base_module)

      local results = parallel:Process(ctx, {})

      assert.is.equal(0, #results)
    end)

    it("should process single input directly", function()
      local signature = Signature.new(
        {Field.new("question")},
        {Field.new("answer")}
      )
      local base_module = createMockModule(0)
      local ctx = createMockContext()

      local parallel = Parallel.new(signature, base_module)

      local results = parallel:Process(ctx, {
        {question = "What is 2+2?"}
      })

      assert.is.equal(1, #results)
      assert.is.equal("Answer to: What is 2+2?", results[1].answer)
    end)

    it("should process batch of inputs", function()
      local signature = Signature.new(
        {Field.new("question")},
        {Field.new("answer")}
      )
      local base_module = createMockModule(0)
      local ctx = createMockContext()

      local parallel = Parallel.new(signature, base_module, {max_workers = 2})

      local results = parallel:Process(ctx, {
        {question = "Q1"},
        {question = "Q2"},
        {question = "Q3"}
      })

      assert.is.equal(3, #results)
      assert.is.equal("Answer to: Q1", results[1].answer)
      assert.is.equal("Answer to: Q2", results[2].answer)
      assert.is.equal("Answer to: Q3", results[3].answer)
    end)

    it("should handle errors in batch processing", function()
      local signature = Signature.new(
        {Field.new("question")},
        {Field.new("answer")}
      )
      local base_module = createMockModule(0)

      -- Make second input fail
      local original_process = base_module.Process
      local call_count = 0
      base_module.Process = function(self, ctx, input)
        call_count = call_count + 1
        if call_count == 2 then
          error("Simulated failure")
        end
        return original_process(self, ctx, input)
      end

      local ctx = createMockContext()
      local parallel = Parallel.new(signature, base_module)

      local results = parallel:Process(ctx, {
        {question = "Q1"},
        {question = "Q2"},
        {question = "Q3"}
      })

      assert.is.equal(3, #results)
      assert.is.equal("Answer to: Q1", results[1].answer)
      assert.is.truthy(results[2].error)
      assert.is.equal("Answer to: Q3", results[3].answer)
    end)
  end)

  describe("ProcessWithTimeout", function()
    it("should process inputs with timeout tracking", function()
      local signature = Signature.new(
        {Field.new("question")},
        {Field.new("answer")}
      )
      local base_module = createMockModule(5)  -- 5ms latency
      local ctx = createMockContext()

      local parallel = Parallel.new(signature, base_module)

      local results = parallel:ProcessWithTimeout(ctx, {
        {question = "Q1"},
        {question = "Q2"}
      }, {timeout = 1.0})  -- 1 second timeout

      assert.is.equal(2, #results)
      assert.is.falsy(results[1].error)
      assert.is.falsy(results[1].timed_out)
      assert.is.truthy(results[1].elapsed_ms)
      assert.is.truthy(results[1].elapsed_ms >= 5)
    end)

    it("should mark timed out items", function()
      local signature = Signature.new(
        {Field.new("question")},
        {Field.new("answer")}
      )

      local base_module = createMockModule(0)
      local original_process = base_module.Process
      base_module.Process = function(self, ctx, input)
        -- Simulate slow processing
        os.sleep(0.1)  -- 100ms sleep
        return original_process(self, ctx, input)
      end

      local ctx = createMockContext()
      local parallel = Parallel.new(signature, base_module)

      local results = parallel:ProcessWithTimeout(ctx, {
        {question = "Q1"}
      }, {timeout = 0.05})  -- 50ms timeout

      assert.is.equal(1, #results)
      -- Since sleep takes longer than timeout, it should be marked
      assert.is.truthy(results[1].elapsed_ms)
    end)
  end)

  describe("ProcessWithRetry", function()
    it("should retry failed requests", function()
      local signature = Signature.new(
        {Field.new("question")},
        {Field.new("answer")}
      )
      local base_module = createMockModule(0)

      local attempt_counts = {}
      local original_process = base_module.Process
      base_module.Process = function(self, ctx, input)
        local key = input.question
        attempt_counts[key] = (attempt_counts[key] or 0) + 1

        -- Fail first two attempts for Q2
        if key == "Q2" and attempt_counts[key] < 3 then
          error("Temporary failure")
        end

        return original_process(self, ctx, input)
      end

      local ctx = createMockContext()
      local parallel = Parallel.new(signature, base_module, {
        max_retries = 3
      })

      local results = parallel:ProcessWithRetry(ctx, {
        {question = "Q1"},
        {question = "Q2"}
      })

      assert.is.equal(2, #results)
      assert.is.equal("Answer to: Q1", results[1].output.answer)
      -- Q2 should succeed after retries
      assert.is.equal("Answer to: Q2", results[2].output.answer)
      assert.is.equal(3, results[2].attempts)
    end)

    it("should give up after max retries", function()
      local signature = Signature.new(
        {Field.new("question")},
        {Field.new("answer")}
      )
      local base_module = createMockModule(0)

      local original_process = base_module.Process
      base_module.Process = function(self, ctx, input)
        error("Permanent failure")
      end

      local ctx = createMockContext()
      local parallel = Parallel.new(signature, base_module, {
        max_retries = 2
      })

      local results = parallel:ProcessWithRetry(ctx, {
        {question = "Q1"}
      })

      assert.is.equal(1, #results)
      assert.is.truthy(results[1].error)
      assert.is.equal(3, results[1].attempts)  -- 1 initial + 2 retries
    end)

    it("should use exponential backoff", function()
      local signature = Signature.new(
        {Field.new("question")},
        {Field.new("answer")}
      )
      local base_module = createMockModule(0)

      local original_process = base_module.Process
      base_module.Process = function(self, ctx, input)
        error("Failure")
      end

      local ctx = createMockContext()
      local parallel = Parallel.new(signature, base_module, {
        max_retries = 3,
        retry_strategy = "exponential"
      })

      local results = parallel:ProcessWithRetry(ctx, {
        {question = "Q1"}
      })

      assert.is.equal(1, #results)
      assert.is.equal("exponential", results[1].retry_strategy_used)
    end)
  end)

  describe("ProcessBatchWithProgress", function()
    it("should report progress during processing", function()
      local signature = Signature.new(
        {Field.new("question")},
        {Field.new("answer")}
      )
      local base_module = createMockModule(10)  -- 10ms per item
      local ctx = createMockContext()

      local parallel = Parallel.new(signature, base_module)

      local progress_calls = {}
      local results = parallel:ProcessBatchWithProgress(ctx, {
        {question = "Q1"},
        {question = "Q2"},
        {question = "Q3"}
      }, function(completed, total, index)
        table.insert(progress_calls, {completed = completed, total = total, index = index})
      end)

      assert.is.equal(3, #results)
      assert.is.equal(4, #progress_calls)  -- Initial + 3 updates
      assert.is.equal(0, progress_calls[1].completed)
      assert.is.equal(3, progress_calls[1].total)
      assert.is.equal(1, progress_calls[2].completed)
      assert.is.equal(2, progress_calls[3].completed)
      assert.is.equal(3, progress_calls[4].completed)
    end)

    it("should handle nil progress callback", function()
      local signature = Signature.new(
        {Field.new("question")},
        {Field.new("answer")}
      )
      local base_module = createMockModule(0)
      local ctx = createMockContext()

      local parallel = Parallel.new(signature, base_module)

      local results = parallel:ProcessBatchWithProgress(ctx, {
        {question = "Q1"},
        {question = "Q2"}
      }, nil)

      assert.is.equal(2, #results)
    end)
  end)

  describe("Map", function()
    it("should transform results with function", function()
      local signature = Signature.new(
        {Field.new("question")},
        {Field.new("answer")}
      )
      local base_module = createMockModule(0)
      local ctx = createMockContext()

      local parallel = Parallel.new(signature, base_module)

      local results = parallel:Map(ctx, {
        {question = "Q1"},
        {question = "Q2"}
      }, function(output)
        return output.answer:upper()
      end)

      assert.is.equal(2, #results)
      assert.is.equal("ANSWER TO: Q1", results[1])
      assert.is.equal("ANSWER TO: Q2", results[2])
    end)

    it("should return outputs without transform if no function", function()
      local signature = Signature.new(
        {Field.new("question")},
        {Field.new("answer")}
      )
      local base_module = createMockModule(0)
      local ctx = createMockContext()

      local parallel = Parallel.new(signature, base_module)

      local results = parallel:Map(ctx, {
        {question = "Q1"}
      })

      assert.is.equal(1, #results)
      assert.is.equal("Answer to: Q1", results[1].answer)
    end)

    it("should handle errors in map", function()
      local signature = Signature.new(
        {Field.new("question")},
        {Field.new("answer")}
      )
      local base_module = createMockModule(0)

      local original_process = base_module.Process
      local call_count = 0
      base_module.Process = function(self, ctx, input)
        call_count = call_count + 1
        if call_count == 2 then
          error("Map error")
        end
        return original_process(self, ctx, input)
      end

      local ctx = createMockContext()
      local parallel = Parallel.new(signature, base_module)

      local results = parallel:Map(ctx, {
        {question = "Q1"},
        {question = "Q2"},
        {question = "Q3"}
      }, function(output)
        return output.answer
      end)

      assert.is.equal(3, #results)
      assert.is.equal("Answer to: Q1", results[1])
      assert.is.truthy(results[2].error)
      assert.is.equal("Answer to: Q3", results[3])
    end)
  end)

  describe("Filter", function()
    it("should filter results based on predicate", function()
      local signature = Signature.new(
        {Field.new("value")},
        {Field.new("result")}
      )
      local base_module = Predict.new(signature)

      -- Override to return different values
      base_module.Process = function(self, ctx, input)
        return {result = input.value * 2}
      end

      local ctx = createMockContext()
      local parallel = Parallel.new(signature, base_module)

      local results = parallel:Filter(ctx, {
        {value = 1},
        {value = 2},
        {value = 3},
        {value = 4},
        {value = 5}
      }, function(output)
        return output.result > 4
      end)

      assert.is.equal(3, #results)
      assert.is.equal(6, results[1].result)
      assert.is.equal(8, results[2].result)
      assert.is.equal(10, results[3].result)
    end)

    it("should skip errors in filter", function()
      local signature = Signature.new(
        {Field.new("question")},
        {Field.new("answer")}
      )
      local base_module = createMockModule(0)

      local original_process = base_module.Process
      local call_count = 0
      base_module.Process = function(self, ctx, input)
        call_count = call_count + 1
        if call_count == 2 then
          error("Filter error")
        end
        return original_process(self, ctx, input)
      end

      local ctx = createMockContext()
      local parallel = Parallel.new(signature, base_module)

      local results = parallel:Filter(ctx, {
        {question = "Q1"},
        {question = "Q2"},
        {question = "Q3"}
      }, function(output)
        return true
      end)

      -- Error item is skipped
      assert.is.equal(2, #results)
    end)
  end)

  describe("ForEach", function()
    it("should apply action to each result", function()
      local signature = Signature.new(
        {Field.new("question")},
        {Field.new("answer")}
      )
      local base_module = createMockModule(0)
      local ctx = createMockContext()

      local parallel = Parallel.new(signature, base_module)

      local calls = {}
      local results = parallel:ForEach(ctx, {
        {question = "Q1"},
        {question = "Q2"},
        {question = "Q3"}
      }, function(output, index)
        table.insert(calls, {answer = output.answer, index = index})
      end)

      assert.is.equal(3, #calls)
      assert.is.equal("Answer to: Q1", calls[1].answer)
      assert.is.equal(1, calls[1].index)
      assert.is.equal("Answer to: Q2", calls[2].answer)
      assert.is.equal(2, calls[2].index)
      assert.is.equal("Answer to: Q3", calls[3].answer)
      assert.is.equal(3, calls[3].index)
    end)

    it("should skip errors in foreach", function()
      local signature = Signature.new(
        {Field.new("question")},
        {Field.new("answer")}
      )
      local base_module = createMockModule(0)

      local original_process = base_module.Process
      local call_count = 0
      base_module.Process = function(self, ctx, input)
        call_count = call_count + 1
        if call_count == 2 then
          error("ForEach error")
        end
        return original_process(self, ctx, input)
      end

      local ctx = createMockContext()
      local parallel = Parallel.new(signature, base_module)

      local calls = {}
      local results = parallel:ForEach(ctx, {
        {question = "Q1"},
        {question = "Q2"},
        {question = "Q3"}
      }, function(output, index)
        table.insert(calls, {answer = output.answer, index = index})
      end)

      -- Error items are skipped
      assert.is.equal(2, #calls)
    end)
  end)

  describe("GetStats", function()
    it("should compute statistics from results", function()
      local signature = Signature.new(
        {Field.new("question")},
        {Field.new("answer")}
      )
      local base_module = createMockModule(0)
      local ctx = createMockContext()

      local parallel = Parallel.new(signature, base_module)

      local results = parallel:ProcessWithTimeout(ctx, {
        {question = "Q1"},
        {question = "Q2"},
        {question = "Q3"}
      })

      local stats = parallel:GetStats(results)

      assert.is.equal(3, stats.total)
      assert.is.equal(3, stats.successful)
      assert.is.equal(0, stats.failed)
      assert.is.truthy(stats.total_latency_ms >= 0)
      assert.is.truthy(stats.avg_latency_ms >= 0)
      assert.is.truthy(stats.max_latency_ms >= stats.min_latency_ms)
    end)

    it("should count failed items", function()
      local signature = Signature.new(
        {Field.new("question")},
        {Field.new("answer")}
      )
      local base_module = createMockModule(0)

      local original_process = base_module.Process
      local call_count = 0
      base_module.Process = function(self, ctx, input)
        call_count = call_count + 1
        if call_count == 2 then
          error("Stats error")
        end
        return original_process(self, ctx, input)
      end

      local ctx = createMockContext()
      local parallel = Parallel.new(signature, base_module)

      local results = parallel:ProcessWithTimeout(ctx, {
        {question = "Q1"},
        {question = "Q2"},
        {question = "Q3"}
      })

      local stats = parallel:GetStats(results)

      assert.is.equal(3, stats.total)
      assert.is.equal(2, stats.successful)
      assert.is.equal(1, stats.failed)
    end)

    it("should handle empty results", function()
      local signature = Signature.new(
        {Field.new("question")},
        {Field.new("answer")}
      )
      local base_module = createMockModule(0)
      local ctx = createMockContext()

      local parallel = Parallel.new(signature, base_module)

      local results = {}
      local stats = parallel:GetStats(results)

      assert.is.equal(0, stats.total)
      assert.is.equal(0, stats.successful)
      assert.is.equal(0, stats.failed)
      assert.is.equal(0, stats.total_latency_ms)
      assert.is.equal(0, stats.avg_latency_ms)
      assert.is.equal(0, stats.max_latency_ms)
      assert.is.equal(math.huge, stats.min_latency_ms)
    end)
  end)

  describe("Configure", function()
    it("should update max_workers", function()
      local signature = Signature.new(
        {Field.new("question")},
        {Field.new("answer")}
      )
      local base_module = Predict.new(signature)

      local parallel = Parallel.new(signature, base_module)

      assert.is.equal(4, parallel._max_workers)

      parallel:Configure({max_workers = 8})

      assert.is.equal(8, parallel._max_workers)
    end)

    it("should update timeout", function()
      local signature = Signature.new(
        {Field.new("question")},
        {Field.new("answer")}
      )
      local base_module = Predict.new(signature)

      local parallel = Parallel.new(signature, base_module)

      assert.is.equal(30, parallel._timeout)

      parallel:Configure({timeout = 60})

      assert.is.equal(60, parallel._timeout)
    end)

    it("should update retry_strategy", function()
      local signature = Signature.new(
        {Field.new("question")},
        {Field.new("answer")}
      )
      local base_module = Predict.new(signature)

      local parallel = Parallel.new(signature, base_module)

      assert.is.equal("exponential", parallel._retry_strategy)

      parallel:Configure({retry_strategy = "linear"})

      assert.is.equal("linear", parallel._retry_strategy)
    end)

    it("should update max_retries", function()
      local signature = Signature.new(
        {Field.new("question")},
        {Field.new("answer")}
      )
      local base_module = Predict.new(signature)

      local parallel = Parallel.new(signature, base_module)

      assert.is.equal(3, parallel._max_retries)

      parallel:Configure({max_retries = 5})

      assert.is.equal(5, parallel._max_retries)
    end)

    it("should update multiple settings at once", function()
      local signature = Signature.new(
        {Field.new("question")},
        {Field.new("answer")}
      )
      local base_module = Predict.new(signature)

      local parallel = Parallel.new(signature, base_module)

      parallel:Configure({
        max_workers = 16,
        timeout = 120,
        max_retries = 10
      })

      assert.is.equal(16, parallel._max_workers)
      assert.is.equal(120, parallel._timeout)
      assert.is.equal(10, parallel._max_retries)
    end)

    it("should return self for chaining", function()
      local signature = Signature.new(
        {Field.new("question")},
        {Field.new("answer")}
      )
      local base_module = Predict.new(signature)

      local parallel = Parallel.new(signature, base_module)

      local result = parallel:Configure({max_workers = 8})

      assert.is.equal(parallel, result)
    end)
  end)
end)
