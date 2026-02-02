-- specs/evaluate/metrics_spec.lua
-- Tests for Evaluation Metrics

describe("Evaluation Metrics", function()
  local Metrics = require("dslua.evaluate.metrics")

  describe("accuracy", function()
    it("should calculate perfect accuracy", function()
      local predictions = {"A", "B", "C", "A"}
      local ground_truth = {"A", "B", "C", "A"}

      local acc = Metrics.accuracy(predictions, ground_truth)

      assert.is.equal(1.0, acc)
    end)

    it("should calculate zero accuracy", function()
      local predictions = {"A", "B", "C"}
      local ground_truth = {"X", "Y", "Z"}

      local acc = Metrics.accuracy(predictions, ground_truth)

      assert.is.equal(0.0, acc)
    end)

    it("should calculate partial accuracy", function()
      local predictions = {"A", "B", "C", "A"}
      local ground_truth = {"A", "X", "C", "Y"}

      local acc = Metrics.accuracy(predictions, ground_truth)

      assert.is.equal(0.5, acc)
    end)

    it("should handle empty predictions", function()
      local acc = Metrics.accuracy({}, {})

      assert.is.equal(0.0, acc)
    end)

    it("should handle mismatched lengths", function()
      local predictions = {"A", "B"}
      local ground_truth = {"A", "B", "C"}

      local acc = Metrics.accuracy(predictions, ground_truth)

      assert.is.equal(1.0, acc)  -- Only compares first 2
    end)
  end)

  describe("precision", function()
    it("should calculate perfect precision", function()
      local predictions = {"true", "true", "false", "false"}
      local ground_truth = {"true", "true", "false", "false"}

      local prec = Metrics.precision(predictions, ground_truth, "true")

      assert.is.equal(1.0, prec)
    end)

    it("should calculate precision with false positives", function()
      local predictions = {"true", "true", "true"}
      local ground_truth = {"true", "false", "false"}

      local prec = Metrics.precision(predictions, ground_truth, "true")

      assert.is.equal(1/3, prec)
    end)

    it("should handle no positive predictions", function()
      local predictions = {"false", "false"}
      local ground_truth = {"true", "true"}

      local prec = Metrics.precision(predictions, ground_truth, "true")

      assert.is.equal(0.0, prec)
    end)
  end)

  describe("recall", function()
    it("should calculate perfect recall", function()
      local predictions = {"true", "true", "false", "false"}
      local ground_truth = {"true", "true", "false", "false"}

      local rec = Metrics.recall(predictions, ground_truth, "true")

      assert.is.equal(1.0, rec)
    end)

    it("should calculate recall with false negatives", function()
      local predictions = {"true", "false", "false"}
      local ground_truth = {"true", "true", "false"}

      local rec = Metrics.recall(predictions, ground_truth, "true")

      assert.is.equal(0.5, rec)
    end)

    it("should handle no positive ground truth", function()
      local predictions = {"true", "true"}
      local ground_truth = {"false", "false"}

      local rec = Metrics.recall(predictions, ground_truth, "true")

      assert.is.equal(0.0, rec)
    end)
  end)

  describe("f1_score", function()
    it("should calculate perfect F1", function()
      local predictions = {"true", "true", "false", "false"}
      local ground_truth = {"true", "true", "false", "false"}

      local f1 = Metrics.f1_score(predictions, ground_truth, "true")

      assert.is.equal(1.0, f1)
    end)

    it("should calculate F1 with low precision and recall", function()
      local predictions = {"true"}
      local ground_truth = {"false"}

      local f1 = Metrics.f1_score(predictions, ground_truth, "true")

      assert.is.equal(0.0, f1)
    end)

    it("should calculate balanced F1", function()
      local predictions = {"true", "true", "false"}
      local ground_truth = {"true", "false", "false"}

      local f1 = Metrics.f1_score(predictions, ground_truth, "true")

      assert.is_truthy(f1 > 0 and f1 <= 1)
    end)
  end)

  describe("confusion_matrix", function()
    it("should build confusion matrix for binary classification", function()
      local predictions = {"A", "B", "A", "B"}
      local ground_truth = {"A", "A", "B", "B"}

      local matrix, classes = Metrics.confusion_matrix(predictions, ground_truth)

      assert.is.equal(2, #classes)
      assert.is.equal(1, matrix["A"]["A"])  -- TP
      assert.is.equal(1, matrix["A"]["B"])  -- FP
      assert.is.equal(1, matrix["B"]["A"])  -- FN
      assert.is.equal(1, matrix["B"]["B"])  -- TN
    end)

    it("should auto-detect classes", function()
      local predictions = {"A", "B", "C"}
      local ground_truth = {"A", "B", "C"}

      local matrix, classes = Metrics.confusion_matrix(predictions, ground_truth)

      assert.is.equal(3, #classes)
      assert.is.equal(1, matrix["A"]["A"])
      assert.is.equal(1, matrix["B"]["B"])
      assert.is.equal(1, matrix["C"]["C"])
    end)

    it("should use provided classes", function()
      local predictions = {"A", "B"}
      local ground_truth = {"A", "B"}

      local matrix, classes = Metrics.confusion_matrix(predictions, ground_truth, {"A", "B", "C"})

      assert.is.equal(3, #classes)
    end)
  end)

  describe("rouge_l", function()
    it("should calculate perfect ROUGE-L", function()
      local score = Metrics.rouge_l("the cat sat on the mat", "the cat sat on the mat")

      assert.is.equal(1.0, score)
    end)

    it("should calculate zero ROUGE-L for no overlap", function()
      local score = Metrics.rouge_l("the cat", "the dog")

      assert.is_truthy(score < 1.0 and score >= 0)
    end)

    it("should calculate partial ROUGE-L", function()
      local score = Metrics.rouge_l("the cat and the dog", "the cat and the mouse")

      assert.is_truthy(score > 0 and score < 1.0)
    end)

    it("should handle empty strings", function()
      local score = Metrics.rouge_l("", "")

      assert.is.equal(0.0, score)
    end)
  end)

  describe("bleu_score", function()
    it("should calculate perfect BLEU", function()
      local score = Metrics.bleu_score("the cat is on the mat", "the cat is on the mat", 4)

      assert.is_truthy(score >= 0.99)  -- Allow small floating point error
    end)

    it("should calculate BLEU for different texts", function()
      local score = Metrics.bleu_score("the cat is on the mat", "a cat is on the mat", 4)

      assert.is_truthy(score >= 0 and score <= 1.0)
    end)

    it("should handle short texts", function()
      local score = Metrics.bleu_score("hello world", "hello", 2)

      assert.is_truthy(score >= 0 and score <= 1.0)
    end)
  end)

  describe("jaccard_similarity", function()
    it("should calculate perfect Jaccard for identical strings", function()
      local score = Metrics.jaccard_similarity("the cat sat", "the cat sat")

      assert.is.equal(1.0, score)
    end)

    it("should calculate Jaccard for overlapping strings", function()
      local score = Metrics.jaccard_similarity("the cat sat", "the dog sat")

      assert.is_truthy(score > 0 and score < 1.0)
    end)

    it("should calculate zero Jaccard for no overlap", function()
      local score = Metrics.jaccard_similarity("cat", "dog")

      assert.is.equal(0.0, score)
    end)

    it("should handle empty strings", function()
      local score = Metrics.jaccard_similarity("", "")

      assert.is.equal(0.0, score)
    end)
  end)

  describe("latency_stats", function()
    it("should calculate latency statistics", function()
      local times = {10, 20, 30, 40, 50}

      local stats = Metrics.latency_stats(times)

      assert.is.equal(30, stats.avg_ms)
      assert.is.equal(10, stats.min_ms)
      assert.is.equal(50, stats.max_ms)
      assert.is.equal(30, stats.median_ms)
    end)

    it("should handle single value", function()
      local times = {42}

      local stats = Metrics.latency_stats(times)

      assert.is.equal(42, stats.avg_ms)
      assert.is.equal(42, stats.min_ms)
      assert.is.equal(42, stats.max_ms)
    end)

    it("should calculate percentiles correctly", function()
      local times = {}
      for i = 1, 100 do
        table.insert(times, i)
      end

      local stats = Metrics.latency_stats(times)

      assert.is.equal(50, stats.p50_ms)
      assert.is.equal(95, stats.p95_ms)
      assert.is.equal(99, stats.p99_ms)
    end)

    it("should handle empty times", function()
      local stats = Metrics.latency_stats({})

      assert.is.equal(0, stats.avg_ms)
      assert.is.equal(0, stats.min_ms)
      assert.is.equal(0, stats.max_ms)
    end)
  end)

  describe("throughput", function()
    it("should calculate requests per second", function()
      local times = {100, 100, 100}  -- 3 requests, 300ms total

      local tp = Metrics.throughput(times, "second")

      assert.is.equal(10, tp)  -- 3 / 0.3 = 10 req/sec
    end)

    it("should calculate requests per minute", function()
      local times = {1000}  -- 1 request in 1 second

      local tp = Metrics.throughput(times, "minute")

      assert.is.equal(60, tp)  -- 60 requests per minute
    end)

    it("should handle empty times", function()
      local tp = Metrics.throughput({}, "second")

      assert.is.equal(0, tp)
    end)

    it("should error on invalid unit", function()
      local times = {100}

      assert.has_error(function()
        Metrics.throughput(times, "hour")
      end)
    end)
  end)

  describe("estimate_cost", function()
    it("should estimate cost for GPT-4", function()
      local tokens = {input = 1000, output = 500}
      local cost = Metrics.estimate_cost(tokens, "gpt-4")

      assert.is_truthy(cost.total_cost > 0)
      assert.is.equal("USD", cost.currency)
    end)

    it("should estimate cost for custom pricing", function()
      local tokens = {input = 1000, output = 1000}
      local pricing = {0.01, 0.02}
      local cost = Metrics.estimate_cost(tokens, "custom", pricing)

      assert.is.near(0.01, cost.input_cost, 0.0001)
      assert.is.near(0.02, cost.output_cost, 0.0001)
      assert.is.near(0.03, cost.total_cost, 0.0001)
    end)

    it("should handle zero tokens", function()
      local tokens = {input = 0, output = 0}
      local cost = Metrics.estimate_cost(tokens, "gpt-4")

      assert.is.equal(0, cost.total_cost)
    end)
  end)

  describe("evaluate_dataset", function()
    it("should evaluate with multiple metrics", function()
      local predictions = {"A", "B", "A"}
      local ground_truth = {"A", "B", "B"}

      local results = Metrics.evaluate_dataset(predictions, ground_truth,
        {"accuracy", "precision", "recall", "f1_score"})

      assert.is.truthy(results.accuracy)
      assert.is.truthy(results.precision)
      assert.is.truthy(results.recall)
      assert.is.truthy(results.f1_score)
    end)

    it("should use default metrics if not specified", function()
      local predictions = {"A", "B"}
      local ground_truth = {"A", "B"}

      local results = Metrics.evaluate_dataset(predictions, ground_truth)

      assert.is.truthy(results.accuracy)
      assert.is.truthy(results.precision)
    end)
  end)

  describe("aggregate_metrics", function()
    it("should aggregate multiple metric sets", function()
      local metric_sets = {
        {accuracy = 0.8, loss = 0.2},
        {accuracy = 0.9, loss = 0.1},
        {accuracy = 0.85, loss = 0.15}
      }

      local aggregated = Metrics.aggregate_metrics(metric_sets)

      assert.is.near(0.85, aggregated.accuracy.mean, 0.0001)  -- (0.8 + 0.9 + 0.85) / 3
      assert.is.truthy(aggregated.accuracy.std > 0)
      assert.is.equal(0.8, aggregated.accuracy.min)
      assert.is.equal(0.9, aggregated.accuracy.max)
    end)

    it("should handle empty metric sets", function()
      local aggregated = Metrics.aggregate_metrics({})

      assert.is.equal(0, #aggregated)
    end)

    it("should ignore non-numeric values", function()
      local metric_sets = {
        {accuracy = 0.8, name = "run1"},
        {accuracy = 0.9, name = "run2"}
      }

      local aggregated = Metrics.aggregate_metrics(metric_sets)

      assert.is.truthy(aggregated.accuracy.mean)
      assert.is.falsy(aggregated.name)
    end)
  end)

  describe("error_analysis", function()
    it("should identify errors", function()
      local predictions = {"A", "B", "C", "D"}
      local ground_truth = {"A", "X", "C", "Y"}
      local inputs = {"in1", "in2", "in3", "in4"}

      local analysis = Metrics.error_analysis(predictions, ground_truth, inputs)

      assert.is.equal(2, analysis.total_errors)
      assert.is.equal(0.5, analysis.error_rate)
      assert.is.equal(2, #analysis.errors)
      assert.is.equal("in2", analysis.errors[1].input)
      assert.is.equal("B", analysis.errors[1].predicted)
      assert.is.equal("X", analysis.errors[1].ground_truth)
    end)

    it("should handle no errors", function()
      local predictions = {"A", "B"}
      local ground_truth = {"A", "B"}

      local analysis = Metrics.error_analysis(predictions, ground_truth)

      assert.is.equal(0, analysis.total_errors)
      assert.is.equal(0.0, analysis.error_rate)
      assert.is.equal(0, #analysis.errors)
    end)

    it("should work without inputs", function()
      local predictions = {"A", "B"}
      local ground_truth = {"A", "X"}

      local analysis = Metrics.error_analysis(predictions, ground_truth)

      assert.is.equal(1, analysis.total_errors)
      assert.is.falsy(analysis.errors[1].input)
    end)
  end)

  describe("format_metrics", function()
    it("should format simple metrics", function()
      local metrics = {accuracy = 0.85, precision = 0.9}

      local formatted = Metrics.format_metrics(metrics)

      assert.is_truthy(formatted:find("accuracy"))
      assert.is_truthy(formatted:find("0.8500"))
    end)

    it("should format complex metrics", function()
      local metrics = {
        latency = {avg_ms = 100, p95_ms = 200}
      }

      local formatted = Metrics.format_metrics(metrics)

      assert.is_truthy(formatted:find("latency"))
      assert.is_truthy(formatted:find("avg_ms"))
    end)
  end)

  describe("Integration Tests", function()
    it("should work with complete evaluation workflow", function()
      local predictions = {"true", "true", "false", "false", "true"}
      local ground_truth = {"true", "false", "false", "true", "true"}

      -- Evaluate with multiple metrics
      local results = Metrics.evaluate_dataset(predictions, ground_truth,
        {"accuracy", "precision", "recall", "f1_score"})

      assert.is.truthy(results.accuracy >= 0 and results.accuracy <= 1)

      -- Error analysis
      local analysis = Metrics.error_analysis(predictions, ground_truth,
        {"q1", "q2", "q3", "q4", "q5"})

      assert.is.truthy(analysis.total_errors > 0)

      -- Format for display
      local formatted = Metrics.format_metrics(results)

      assert.is_truthy(#formatted > 0)
    end)

    it("should aggregate multiple evaluation runs", function()
      local runs = {}
      for i = 1, 5 do
        table.insert(runs, {
          accuracy = 0.8 + (i * 0.02),
          latency_ms = 100 + i
        })
      end

      local aggregated = Metrics.aggregate_metrics(runs)

      assert.is.truthy(aggregated.accuracy.mean >= 0.8)
      assert.is.truthy(aggregated.accuracy.std > 0)
    end)
  end)
end)
