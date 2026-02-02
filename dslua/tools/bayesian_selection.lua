-- dslua/tools/bayesian_selection.lua
-- Bayesian Tool Selection based on historical success rates

local M = {}

-- =============================================================================
-- Bayesian Selector
-- =============================================================================

M.BayesianSelector = {}
M.BayesianSelector.__index = M.BayesianSelector

function M.BayesianSelector.new(opts)
  opts = opts or {}

  local self = {
    -- Tool performance tracking
    tool_stats = {},  -- {tool_name = {successes = N, attempts = N}}

    -- Prior beliefs (Beta distribution parameters)
    alpha = opts.alpha or 1,    -- Pseudo-counts for success
    beta = opts.beta or 1,      -- Pseudo-counts for failure

    -- Exploration vs exploitation
    exploration_bonus = opts.exploration_bonus or 0.1,

    -- Minimum samples before using posterior
    min_samples = opts.min_samples or 3,

    -- UCB (Upper Confidence Bound) parameter
    ucb_c = opts.ucb_c or 1.4
  }

  setmetatable(self, M.BayesianSelector)
  return self
end

-- Record tool execution result
function M.BayesianSelector:record_result(tool_name, success)
  if not self.tool_stats[tool_name] then
    self.tool_stats[tool_name] = {successes = 0, attempts = 0}
  end

  self.tool_stats[tool_name].attempts = self.tool_stats[tool_name].attempts + 1
  if success then
    self.tool_stats[tool_name].successes = self.tool_stats[tool_name].successes + 1
  end
end

-- Get estimated success probability for a tool
function M.BayesianSelector:get_success_probability(tool_name)
  local stats = self.tool_stats[tool_name]

  if not stats or stats.attempts == 0 then
    -- Uniform prior: expected value = alpha / (alpha + beta)
    return self.alpha / (self.alpha + self.beta)
  end

  -- Posterior mean: (alpha + successes) / (alpha + beta + attempts)
  return (self.alpha + stats.successes) / (self.alpha + self.beta + stats.attempts)
end

-- Get upper confidence bound (UCB) for exploration
function M.BayesianSelector:get_ucb(tool_name, total_attempts)
  local stats = self.tool_stats[tool_name]
  local n = stats and stats.attempts or 0

  if total_attempts == nil then
    total_attempts = n
    for _, s in pairs(self.tool_stats) do
      total_attempts = total_attempts + s.attempts
    end
  end

  local mean = self:get_success_probability(tool_name)

  if n == 0 then
    -- Maximum uncertainty for untried tools
    return mean + self.ucb_c
  end

  -- UCB = mean + c * sqrt(ln(total_attempts) / n)
  local exploration = self.ucb_c * math.sqrt(math.log(total_attempts + 1) / n)
  return mean + exploration
end

-- Select best tool using Thompson Sampling
function M.BayesianSelector:select_tool_thompson(tools, context)
  -- Thompson Sampling: sample from posterior distribution for each tool
  -- and select the one with highest sample

  local best_tool = nil
  local best_sample = -1

  for _, tool_name in ipairs(tools) do
    local stats = self.tool_stats[tool_name]

    local alpha_post = self.alpha + (stats and stats.successes or 0)
    local beta_post = self.beta + (stats and stats.attempts or 0) - (stats and stats.successes or 0)

    -- Sample from Beta(alpha, beta)
    local sample = self:_sample_beta(alpha_post, beta_post)

    if sample > best_sample then
      best_sample = sample
      best_tool = tool_name
    end
  end

  return best_tool
end

-- Select best tool using UCB (Upper Confidence Bound)
function M.BayesianSelector:select_tool_ucb(tools, context)
  local best_tool = nil
  local best_ucb = -1

  -- Calculate total attempts for exploration bonus
  local total_attempts = 0
  for _, tool_name in ipairs(tools) do
    local stats = self.tool_stats[tool_name]
    total_attempts = total_attempts + (stats and stats.attempts or 0)
  end

  for _, tool_name in ipairs(tools) do
    local ucb = self:get_ucb(tool_name, total_attempts)

    if ucb > best_ucb then
      best_ucb = ucb
      best_tool = tool_name
    end
  end

  return best_tool
end

-- Select best tool using epsilon-greedy with adaptive epsilon
function M.BayesianSelector:select_tool_epsilon_greedy(tools, context, epsilon)
  epsilon = epsilon or 0.1

  -- Adaptive epsilon: decay as we gather more data
  local total_attempts = 0
  for _, tool_name in ipairs(tools) do
    local stats = self.tool_stats[tool_name]
    total_attempts = total_attempts + (stats and stats.attempts or 0)
  end

  if total_attempts > 0 then
    epsilon = epsilon / math.sqrt(total_attempts)
  end

  -- Explore with probability epsilon
  if math.random() < epsilon then
    -- Random exploration
    return tools[math.random(#tools)]
  else
    -- Exploit: select best known tool
    local best_tool = nil
    local best_prob = -1

    for _, tool_name in ipairs(tools) do
      local prob = self:get_success_probability(tool_name)
      if prob > best_prob then
        best_prob = prob
        best_tool = tool_name
      end
    end

    return best_tool
  end
end

-- Sample from Beta distribution using rejection sampling
function M.BayesianSelector:_sample_beta(alpha, beta)
  -- Gamma distribution approximation
  local function gamma(z)
    -- Lanczos approximation for gamma function
    local g = 7
    local c = {[0]=0.99999999999980993, 676.5203681218851, -1259.1392167224028,
      771.32342877765313, -176.61502916214059, 12.507343278686905,
      -0.13857109526572012, 9.9843695780195716e-6, 1.5056327351493116e-7}

    if z < 0.5 then
      return math.pi / (math.sin(math.pi * z) * gamma(1 - z))
    end

    z = z - 1
    local x = c[0]
    for i = 1, g do
      x = x + c[i] / (z + i)
    end
    local t = z + g + 0.5
    return math.sqrt(2 * math.pi) * t^(z + 0.5) * math.exp(-t) * x
  end

  -- Marsaglia and Tsang's method for Gamma(alpha, 1)
  local function gamma_sample(alpha)
    if alpha < 1 then
      return gamma_sample(alpha + 1) * math.random()^(1 / alpha)
    end

    local d = alpha - 1/3
    local c = 1 / math.sqrt(9 * d)

    while true do
      local x, v
      while true do
        x = math.random_normal()  -- Standard normal
        v = 1 + c * x
        if v > 0 then break end
      end
      v = v^3
      local u = math.random()

      if u < 1 - 0.0331 * (x^2)^2 then
        return d * v * u^(1/alpha)
      end

      if math.log(u) < 0.5 * x^2 + d * (1 - v + math.log(v)) then
        return d * v
      end
    end
  end

  -- Simple approximation: use gamma distribution ratio
  -- For production, use a proper library
  local x1 = math.random()^(1/alpha)
  local x2 = math.random()^(1/beta)

  return x1 / (x1 + x2)
end

-- Get statistics for all tools
function M.BayesianSelector:get_stats()
  local stats = {}

  for tool_name, data in pairs(self.tool_stats) do
    stats[tool_name] = {
      successes = data.successes,
      attempts = data.attempts,
      success_rate = data.attempts > 0 and data.successes / data.attempts or 0,
      expected_prob = self:get_success_probability(tool_name)
    }
  end

  return stats
end

-- Reset statistics for a tool or all tools
function M.BayesianSelector:reset(tool_name)
  if tool_name then
    self.tool_stats[tool_name] = nil
  else
    self.tool_stats = {}
  end
end

-- =============================================================================
-- Helper Functions
-- =============================================================================

function M.bayesian_selector(opts)
  return M.BayesianSelector.new(opts)
end

return M
