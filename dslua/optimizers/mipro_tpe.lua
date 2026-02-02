-- dslua/optimizers/mipro_tpe.lua
-- MIPRO TPE (Tree-structured Parzen Estimator) Module

local M = {}

-- Default split ratio for good vs poor observations
local DEFAULT_GOOD_RATIO = 0.25  -- Top 25% are "good"

-- =============================================================================
-- SampleCandidate - Generate next candidate using TPE algorithm
-- =============================================================================

function M.SampleCandidate(observations, space, opts)
  opts = opts or {}

  -- If no observations, sample random from space
  if #observations == 0 then
    return M._sampleFromSpace(space, opts)
  end

  -- Split observations into good and poor
  local good_obs, poor_obs = M._splitObservations(
    observations,
    opts.good_ratio or DEFAULT_GOOD_RATIO
  )

  -- If not enough observations, sample random
  if #good_obs == 0 or #poor_obs == 0 then
    return M._sampleFromSpace(space, opts)
  end

  -- Generate candidates and compute EI for each
  local candidates = {}
  local num_candidates = opts.num_candidates or 10

  for i = 1, num_candidates do
    local candidate = M._sampleFromSpace(space, opts)

    -- Compute Expected Improvement
    candidate.ei = M._computeEI(candidate, good_obs, poor_obs, space)
    table.insert(candidates, candidate)
  end

  -- Return candidate with maximum EI
  return M._maximizeEI(candidates)
end

-- =============================================================================
-- UpdateObservations - Add new trial result
-- =============================================================================

function M.UpdateObservations(observations, params, score)
  -- Create new observation
  local obs = {
    params = params,
    score = score
  }

  -- Add to observations
  table.insert(observations, obs)

  return observations
end

-- =============================================================================
-- Private helper functions
-- =============================================================================

function M._sampleFromSpace(space, opts)
  local candidate = {}

  for param_name, param_def in pairs(space) do
    candidate[param_name] = M._sampleParam(param_def, opts)
  end

  return candidate
end

function M._sampleParam(param_def, opts)
  local seed = opts.seed or math.random()

  if seed then
    -- Ensure seed is an integer for randomseed
    math.randomseed(math.floor(seed))
  end

  if param_def.type == "int" then
    return math.random(param_def.min, param_def.max)

  elseif param_def.type == "enum" then
    local idx = math.random(1, #param_def.values)
    return param_def.values[idx]

  elseif param_def.type == "float" then
    return param_def.min + (math.random() * (param_def.max - param_def.min))

  else
    error("Unknown parameter type: " .. tostring(param_def.type))
  end
end

function M._splitObservations(observations, good_ratio)
  -- Sort observations by score (descending)
  local sorted = {}
  for i, obs in ipairs(observations) do
    sorted[i] = obs
  end

  table.sort(sorted, function(a, b)
    return a.score > b.score
  end)

  -- Split into good (top) and poor (rest)
  local good_count = math.max(1, math.floor(#sorted * good_ratio))
  local good_obs = {}
  local poor_obs = {}

  for i, obs in ipairs(sorted) do
    if i <= good_count then
      table.insert(good_obs, obs)
    else
      table.insert(poor_obs, obs)
    end
  end

  return good_obs, poor_obs
end

function M._computeEI(candidate, good_obs, poor_obs, space)
  -- Compute Expected Improvement
  -- EI(x) = ∫(x - γ) * p(x)dx ≈ (max_good - γ) * g(x) / l(x)

  -- Find threshold (best score in poor observations)
  local gamma = poor_obs[1].score
  for _, obs in ipairs(poor_obs) do
    if obs.score > gamma then
      gamma = obs.score
    end
  end

  -- Find best score in good observations (expected performance)
  local max_good = good_obs[1].score
  for _, obs in ipairs(good_obs) do
    if obs.score > max_good then
      max_good = obs.score
    end
  end

  -- Estimate expected improvement
  local improvement = max_good - gamma

  -- Compute likelihoods l(x) and g(x)
  local l_x = M._computeLikelihood(candidate, good_obs, space)
  local g_x = M._computeLikelihood(candidate, poor_obs, space)

  -- Avoid division by zero
  if l_x < 1e-9 then
    l_x = 1e-9
  end

  -- Expected Improvement
  local ei = improvement * (g_x / l_x)

  return ei
end

function M._computeLikelihood(candidate, observations, space)
  -- Compute probability density using kernel density estimation
  -- Simplified: count how many obs have similar param values

  local likelihood = 0

  for _, obs in ipairs(observations) do
    local sim = M._computeSimilarity(candidate, obs.params, space)
    likelihood = likelihood + sim
  end

  return likelihood / #observations
end

function M._computeSimilarity(params1, params2, space)
  local similarity = 1.0
  local count = 0
  local bandwidth = 1.0  -- Kernel bandwidth

  for param_name, param_def in pairs(space) do
    local val1 = params1[param_name]
    local val2 = params2[param_name]

    if val1 and val2 then
      count = count + 1

      if param_def.type == "int" or param_def.type == "float" then
        -- Continuous: Gaussian kernel
        local range = param_def.max - param_def.min
        local dist = math.abs(val1 - val2) / range
        local kernel = math.exp(-(dist * dist) / (2 * bandwidth * bandwidth))
        similarity = similarity * kernel
      elseif param_def.type == "enum" then
        -- Categorical: match or not
        if val1 == val2 then
          -- similarity = similarity (no change)
        else
          similarity = similarity * 0.1  -- Penalty for mismatch
        end
      end
    end
  end

  return count > 0 and similarity or 0
end

function M._computeDensity(value, observations, param_def)
  -- Simplified kernel density estimation
  local density = 0
  local bandwidth = 1.0

  for _, obs in ipairs(observations) do
    local obs_val = obs.params[param_def.name or value]

    if obs_val then
      if param_def.type == "int" or param_def.type == "float" then
        local range = param_def.max - param_def.min
        local dist = math.abs(value - obs_val) / range
        local kernel = math.exp(-(dist * dist) / (2 * bandwidth * bandwidth))
        density = density + kernel
      elseif param_def.type == "enum" then
        if value == obs_val then
          density = density + 1.0
        end
      end
    end
  end

  return density / #observations
end

function M._maximizeEI(candidates)
  if #candidates == 0 then
    return nil
  end

  local best = candidates[1]
  for _, candidate in ipairs(candidates) do
    if candidate.ei > best.ei then
      best = candidate
    end
  end

  -- Remove ei field before returning
  best.ei = nil
  return best
end

return M
