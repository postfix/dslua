-- dslua/evaluate/metrics.lua
-- Evaluation metrics for measuring LLM program performance

local M = {}

-- =============================================================================
-- Accuracy Metrics
-- =============================================================================

function M.accuracy(predictions, ground_truth)
  -- Calculate accuracy: correct / total
  local correct = 0
  local total = #predictions

  for i = 1, math.min(#predictions, #ground_truth) do
    if predictions[i] == ground_truth[i] then
      correct = correct + 1
    end
  end

  if total == 0 then
    return 0
  end

  return correct / total
end

function M.precision(predictions, ground_truth, positive_class)
  -- TP / (TP + FP)
  local tp = 0  -- True Positives
  local fp = 0  -- False Positives

  positive_class = positive_class or "true"

  for i = 1, math.min(#predictions, #ground_truth) do
    local pred = predictions[i]
    local truth = ground_truth[i]

    if pred == positive_class and truth == positive_class then
      tp = tp + 1
    elseif pred == positive_class and truth ~= positive_class then
      fp = fp + 1
    end
  end

  if tp + fp == 0 then
    return 0
  end

  return tp / (tp + fp)
end

function M.recall(predictions, ground_truth, positive_class)
  -- TP / (TP + FN)
  local tp = 0  -- True Positives
  local fn = 0  -- False Negatives

  positive_class = positive_class or "true"

  for i = 1, math.min(#predictions, #ground_truth) do
    local pred = predictions[i]
    local truth = ground_truth[i]

    if pred == positive_class and truth == positive_class then
      tp = tp + 1
    elseif pred ~= positive_class and truth == positive_class then
      fn = fn + 1
    end
  end

  if tp + fn == 0 then
    return 0
  end

  return tp / (tp + fn)
end

function M.f1_score(predictions, ground_truth, positive_class)
  -- Harmonic mean of precision and recall
  local p = M.precision(predictions, ground_truth, positive_class)
  local r = M.recall(predictions, ground_truth, positive_class)

  if p + r == 0 then
    return 0
  end

  return 2 * (p * r) / (p + r)
end

function M.confusion_matrix(predictions, ground_truth, classes)
  -- Build confusion matrix
  classes = classes or {}

  -- Auto-detect classes if not provided
  if #classes == 0 then
    local seen = {}
    for i = 1, #ground_truth do
      seen[ground_truth[i]] = true
      seen[predictions[i]] = true
    end
    for class, _ in pairs(seen) do
      table.insert(classes, class)
    end
    table.sort(classes)
  end

  -- Initialize matrix
  local matrix = {}
  for i, true_class in ipairs(classes) do
    matrix[true_class] = {}
    for j, pred_class in ipairs(classes) do
      matrix[true_class][pred_class] = 0
    end
  end

  -- Fill matrix
  for i = 1, math.min(#predictions, #ground_truth) do
    local truth = ground_truth[i]
    local pred = predictions[i]
    if matrix[truth] and matrix[truth][pred] then
      matrix[truth][pred] = matrix[truth][pred] + 1
    end
  end

  return matrix, classes
end

-- =============================================================================
-- Similarity Metrics
-- =============================================================================

function M.rouge_l(reference, candidate)
  -- ROUGE-L: Longest Common Subsequence
  local function lcs_length(s1, s2)
    local m, n = #s1, #s2
    local dp = {}

    for i = 0, m do
      dp[i] = {}
      for j = 0, n do
        dp[i][j] = 0
      end
    end

    for i = 1, m do
      for j = 1, n do
        if s1:sub(i, i) == s2:sub(j, j) then
          dp[i][j] = dp[i-1][j-1] + 1
        else
          dp[i][j] = math.max(dp[i-1][j], dp[i][j-1])
        end
      end
    end

    return dp[m][n]
  end

  local lcs = lcs_length(reference, candidate)
  local denom = #reference + #candidate

  if denom == 0 then
    return 0
  end

  -- F-measure of precision and recall
  local precision = lcs / #candidate
  local recall = lcs / #reference

  if precision + recall == 0 then
    return 0
  end

  return (2 * precision * recall) / (precision + recall)
end

function M.bleu_score(reference, candidate, n)
  -- BLEU score for n-grams (default n=4)
  n = n or 4

  local function get_ngrams(text, n)
    local words = {}
    for word in text:gmatch("%S+") do
      table.insert(words, word)
    end

    local ngrams = {}
    for i = 1, #words - n + 1 do
      local ngram = {}
      for j = i, i + n - 1 do
        table.insert(ngram, words[j])
      end
      table.insert(ngrams, table.concat(ngram, " "))
    end

    return ngrams
  end

  local function count_matches(ref_ngrams, cand_ngrams)
    local ref_counts = {}
    for _, ngram in ipairs(ref_ngrams) do
      ref_counts[ngram] = (ref_counts[ngram] or 0) + 1
    end

    local matches = 0
    for _, ngram in ipairs(cand_ngrams) do
      if ref_counts[ngram] and ref_counts[ngram] > 0 then
        matches = matches + 1
        ref_counts[ngram] = ref_counts[ngram] - 1
      end
    end

    return matches, #cand_ngrams
  end

  -- Calculate geometric mean of n-gram precisions
  local precisions = {}
  for i = 1, n do
    local ref_ngrams = get_ngrams(reference, i)
    local cand_ngrams = get_ngrams(candidate, i)

    if #cand_ngrams == 0 then
      table.insert(precisions, 0)
    else
      local matches, total = count_matches(ref_ngrams, cand_ngrams)
      table.insert(precisions, matches / total)
    end
  end

  -- Geometric mean
  local product = 1
  for _, p in ipairs(precisions) do
    product = product * p
  end

  if product == 0 then
    return 0
  end

  local geo_mean = product ^ (1 / n)

  -- Brevity penalty
  local function count_words(text)
    local count = 0
    for _ in text:gmatch("%S+") do
      count = count + 1
    end
    return count
  end

  local ref_len = count_words(reference)
  local cand_len = count_words(candidate)

  if cand_len >= ref_len then
    return geo_mean
  end

  local bp = math.exp(1 - ref_len / cand_len)
  return bp * geo_mean
end

function M.jaccard_similarity(s1, s2)
  -- Jaccard similarity between two strings
  local function tokenize(text)
    local tokens = {}
    for word in text:gmatch("%w+") do
      tokens[word] = true
    end
    return tokens
  end

  local tokens1 = tokenize(s1)
  local tokens2 = tokenize(s2)

  local intersection = 0
  for token, _ in pairs(tokens1) do
    if tokens2[token] then
      intersection = intersection + 1
    end
  end

  local union1 = 0
  for _ in pairs(tokens1) do union1 = union1 + 1 end
  local union2 = 0
  for _ in pairs(tokens2) do union2 = union2 + 1 end
  local union = union1 + union2 - intersection

  if union == 0 then
    return 0
  end

  return intersection / union
end

-- =============================================================================
-- Latency and Performance Metrics
-- =============================================================================

function M.latency_stats(execution_times)
  -- Calculate latency statistics from execution times (in ms)
  if #execution_times == 0 then
    return {
      avg_ms = 0,
      min_ms = 0,
      max_ms = 0,
      median_ms = 0,
      p50_ms = 0,
      p95_ms = 0,
      p99_ms = 0
    }
  end

  table.sort(execution_times)

  local sum = 0
  for _, t in ipairs(execution_times) do
    sum = sum + t
  end

  local function percentile(arr, p)
    local idx = math.ceil((p / 100) * #arr)
    return arr[math.min(idx, #arr)]
  end

  return {
    avg_ms = sum / #execution_times,
    min_ms = execution_times[1],
    max_ms = execution_times[#execution_times],
    median_ms = percentile(execution_times, 50),
    p50_ms = percentile(execution_times, 50),
    p95_ms = percentile(execution_times, 95),
    p99_ms = percentile(execution_times, 99)
  }
end

function M.throughput(execution_times, unit)
  -- Calculate throughput (requests per second/minute)
  unit = unit or "second"

  if #execution_times == 0 then
    return 0
  end

  local total_time_ms = 0
  for _, t in ipairs(execution_times) do
    total_time_ms = total_time_ms + t
  end

  local total_time_sec = total_time_ms / 1000

  if unit == "second" then
    return #execution_times / total_time_sec
  elseif unit == "minute" then
    return (#execution_times / total_time_sec) * 60
  else
    error("Invalid unit: " .. tostring(unit) .. ". Use 'second' or 'minute'")
  end
end

-- =============================================================================
-- Cost Metrics
-- =============================================================================

function M.estimate_cost(tokens, model, pricing)
  -- Estimate cost based on token count and pricing
  -- pricing can be: {input_per_1k, output_per_1k} or {model = {input, output}, ...}

  local input_tokens = tokens.input or 0
  local output_tokens = tokens.output or 0

  local price

  -- Check if pricing is a direct tuple or a model map
  if pricing and #pricing == 2 then
    -- Direct tuple: {input_price, output_price}
    price = pricing
  else
    pricing = pricing or {}

    -- Default pricing (in USD)
    local default_pricing = {
      ["gpt-4"] = {0.03, 0.06},
      ["gpt-3.5-turbo"] = {0.0015, 0.002},
      ["claude-3-opus"] = {0.015, 0.075},
      ["claude-3-sonnet"] = {0.003, 0.015},
      ["gemini-pro"] = {0.00025, 0.0005}
    }

    price = pricing[model] or default_pricing[model] or {0.001, 0.002}
  end

  local input_cost = (input_tokens / 1000) * price[1]
  local output_cost = (output_tokens / 1000) * price[2]

  return {
    input_cost = input_cost,
    output_cost = output_cost,
    total_cost = input_cost + output_cost,
    currency = "USD"
  }
end

-- =============================================================================
-- Aggregated Metrics
-- =============================================================================

function M.evaluate_dataset(predictions, ground_truth, metrics)
  -- Evaluate dataset with multiple metrics
  metrics = metrics or {"accuracy", "precision", "recall", "f1_score"}

  local results = {}

  for _, metric_name in ipairs(metrics) do
    if M[metric_name] then
      results[metric_name] = M[metric_name](predictions, ground_truth)
    end
  end

  return results
end

function M.aggregate_metrics(metric_sets)
  -- Aggregate metrics from multiple runs
  if #metric_sets == 0 then
    return {}
  end

  local aggregated = {}

  -- Collect all metric names
  local metric_names = {}
  for _, metrics in ipairs(metric_sets) do
    for name, _ in pairs(metrics) do
      metric_names[name] = true
    end
  end

  -- Calculate mean and std for each metric
  for name, _ in pairs(metric_names) do
    local values = {}
    for _, metrics in ipairs(metric_sets) do
      if type(metrics[name]) == "number" then
        table.insert(values, metrics[name])
      end
    end

    if #values > 0 then
      local sum = 0
      for _, v in ipairs(values) do
        sum = sum + v
      end
      local mean = sum / #values

      -- Standard deviation
      local variance = 0
      for _, v in ipairs(values) do
        variance = variance + (v - mean) ^ 2
      end
      local std = math.sqrt(variance / #values)

      aggregated[name] = {
        mean = mean,
        std = std,
        min = math.min(table.unpack(values)),
        max = math.max(table.unpack(values))
      }
    end
  end

  return aggregated
end

-- =============================================================================
-- Error Analysis
-- =============================================================================

function M.error_analysis(predictions, ground_truth, inputs)
  -- Analyze prediction errors
  local errors = {}

  for i = 1, math.min(#predictions, #ground_truth) do
    if predictions[i] ~= ground_truth[i] then
      table.insert(errors, {
        index = i,
        input = inputs and inputs[i],
        predicted = predictions[i],
        ground_truth = ground_truth[i]
      })
    end
  end

  return {
    total_errors = #errors,
    error_rate = #errors / #predictions,
    errors = errors
  }
end

-- =============================================================================
-- Formatting and Reporting
-- =============================================================================

function M.format_metrics(metrics)
  -- Format metrics for display
  local lines = {}

  table.insert(lines, "=== Evaluation Metrics ===")

  -- Sort metrics by name
  local names = {}
  for name, _ in pairs(metrics) do
    table.insert(names, name)
  end
  table.sort(names)

  for _, name in ipairs(names) do
    local value = metrics[name]

    if type(value) == "table" then
      -- Complex metric (e.g., latency stats)
      table.insert(lines, string.format("\n%s:", name))
      for k, v in pairs(value) do
        table.insert(lines, string.format("  %s: %.4f", k, v))
      end
    elseif type(value) == "number" then
      table.insert(lines, string.format("%s: %.4f", name, value))
    else
      table.insert(lines, string.format("%s: %s", name, tostring(value)))
    end
  end

  return table.concat(lines, "\n")
end

return M
