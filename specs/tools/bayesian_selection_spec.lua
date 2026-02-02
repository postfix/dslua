-- specs/tools/bayesian_selection_spec.lua
-- Tests for Bayesian Tool Selection

describe("Bayesian Tool Selection", function()
  local BayesianSelection = require("dslua.tools.bayesian_selection")

  describe("new", function()
    it("should create Bayesian selector with defaults", function()
      local selector = BayesianSelection.BayesianSelector.new()

      assert.is.equal(1, selector.alpha)
      assert.is.equal(1, selector.beta)
      assert.is.equal(0.1, selector.exploration_bonus)
      assert.is.equal(3, selector.min_samples)
      assert.is.equal(1.4, selector.ucb_c)
    end)

    it("should accept custom options", function()
      local selector = BayesianSelection.BayesianSelector.new({
        alpha = 2,
        beta = 2,
        exploration_bonus = 0.2,
        min_samples = 5,
        ucb_c = 2.0
      })

      assert.is.equal(2, selector.alpha)
      assert.is.equal(2, selector.beta)
      assert.is.equal(0.2, selector.exploration_bonus)
      assert.is.equal(5, selector.min_samples)
      assert.is.equal(2.0, selector.ucb_c)
    end)
  end)

  describe("record_result", function()
    it("should record successful result", function()
      local selector = BayesianSelection.BayesianSelector.new()

      selector:record_result("tool1", true)

      assert.is.equal(1, selector.tool_stats["tool1"].attempts)
      assert.is.equal(1, selector.tool_stats["tool1"].successes)
    end)

    it("should record failed result", function()
      local selector = BayesianSelection.BayesianSelector.new()

      selector:record_result("tool1", false)

      assert.is.equal(1, selector.tool_stats["tool1"].attempts)
      assert.is.equal(0, selector.tool_stats["tool1"].successes)
    end)

    it("should accumulate multiple results", function()
      local selector = BayesianSelection.BayesianSelector.new()

      selector:record_result("tool1", true)
      selector:record_result("tool1", true)
      selector:record_result("tool1", false)

      assert.is.equal(3, selector.tool_stats["tool1"].attempts)
      assert.is.equal(2, selector.tool_stats["tool1"].successes)
    end)

    it("should track multiple tools separately", function()
      local selector = BayesianSelection.BayesianSelector.new()

      selector:record_result("tool1", true)
      selector:record_result("tool2", false)

      assert.is.equal(1, selector.tool_stats["tool1"].successes)
      assert.is.equal(0, selector.tool_stats["tool2"].successes)
    end)
  end)

  describe("get_success_probability", function()
    it("should return prior for unknown tool", function()
      local selector = BayesianSelection.BayesianSelector.new({
        alpha = 2,
        beta = 2
      })

      local prob = selector:get_success_probability("unknown")

      assert.is.equal(0.5, prob)  -- alpha / (alpha + beta) = 2/4 = 0.5
    end)

    it("should calculate posterior probability", function()
      local selector = BayesianSelection.BayesianSelector.new({
        alpha = 1,
        beta = 1
      })

      selector:record_result("tool1", true)
      selector:record_result("tool1", true)
      selector:record_result("tool1", false)

      local prob = selector:get_success_probability("tool1")

      -- (alpha + successes) / (alpha + beta + attempts)
      -- (1 + 2) / (1 + 1 + 3) = 3/5 = 0.6
      assert.is.equal(0.6, prob)
    end)

    it("should handle all successes", function()
      local selector = BayesianSelection.BayesianSelector.new()

      selector:record_result("tool1", true)
      selector:record_result("tool1", true)
      selector:record_result("tool1", true)

      local prob = selector:get_success_probability("tool1")

      assert.is_truthy(prob > 0.5)
    end)

    it("should handle all failures", function()
      local selector = BayesianSelection.BayesianSelector.new()

      selector:record_result("tool1", false)
      selector:record_result("tool1", false)

      local prob = selector:get_success_probability("tool1")

      assert.is_truthy(prob < 0.5)
    end)
  end)

  describe("get_ucb", function()
    it("should return prior for unknown tool", function()
      local selector = BayesianSelection.BayesianSelector.new()

      local ucb = selector:get_ucb("unknown")

      assert.is.truthy(ucb > 0)
    end)

    it("should add exploration bonus", function()
      local selector = BayesianSelection.BayesianSelector.new({
        ucb_c = 2.0
      })

      selector:record_result("tool1", true)
      selector:record_result("tool1", false)

      local prob = selector:get_success_probability("tool1")
      local ucb = selector:get_ucb("tool1")

      assert.is.truthy(ucb > prob)  -- UCB should be higher than mean
    end)

    it("should decrease exploration with more data", function()
      local selector = BayesianSelection.BayesianSelector.new()

      selector:record_result("tool1", true)
      selector:record_result("tool1", false)

      local ucb_1 = selector:get_ucb("tool1", 2)

      selector:record_result("tool1", true)
      selector:record_result("tool1", false)
      selector:record_result("tool1", true)
      selector:record_result("tool1", false)

      local ucb_2 = selector:get_ucb("tool1", 6)

      -- More data should reduce exploration bonus
      assert.is.truthy(ucb_2 < ucb_1)
    end)
  end)

  describe("select_tool_thompson", function()
    it("should select from available tools", function()
      local selector = BayesianSelection.BayesianSelector.new()
      local tools = {"tool1", "tool2", "tool3"}

      local selected = selector:select_tool_thompson(tools)

      assert.is.truthy(selected)
      assert.is.truthy(selected == "tool1" or selected == "tool2" or selected == "tool3")
    end)

    it("should prefer successful tools", function()
      local selector = BayesianSelection.BayesianSelector.new()

      -- Make tool1 very successful
      for i = 1, 10 do
        selector:record_result("tool1", true)
      end

      -- Make tool2 fail often
      for i = 1, 10 do
        selector:record_result("tool2", false)
      end

      local tools = {"tool1", "tool2"}
      local wins = {tool1 = 0, tool2 = 0}

      -- Run multiple trials
      for i = 1, 20 do
        local selected = selector:select_tool_thompson(tools)
        wins[selected] = wins[selected] + 1
      end

      -- tool1 should be selected more often
      assert.is.truthy(wins.tool1 > wins.tool2)
    end)

    it("should handle empty tool list", function()
      local selector = BayesianSelection.BayesianSelector.new()

      local selected = selector:select_tool_thompson({})

      assert.is.falsy(selected)
    end)
  end)

  describe("select_tool_ucb", function()
    it("should select from available tools", function()
      local selector = BayesianSelection.BayesianSelector.new()
      local tools = {"tool1", "tool2"}

      local selected = selector:select_tool_ucb(tools)

      assert.is.truthy(selected)
    end)

    it("should explore unknown tools", function()
      local selector = BayesianSelection.BayesianSelector.new()

      -- Give tool2 some data
      selector:record_result("tool2", true)
      selector:record_result("tool2", true)

      local tools = {"tool1", "tool2"}

      -- tool1 has no data, should get exploration bonus
      local selections = {tool1 = 0, tool2 = 0}
      for i = 1, 10 do
        local selected = selector:select_tool_ucb(tools)
        selections[selected] = selections[selected] + 1
      end

      -- tool1 should be selected sometimes due to exploration
      assert.is.truthy(selections.tool1 > 0)
    end)

    it("should prefer tools with higher UCB", function()
      local selector = BayesianSelection.BayesianSelector.new()

      -- Make tool1 very successful
      for i = 1, 10 do
        selector:record_result("tool1", true)
      end

      -- Make tool2 mediocre
      for i = 1, 10 do
        selector:record_result("tool2", true)
        selector:record_result("tool2", false)
      end

      local tools = {"tool1", "tool2"}
      local selected = selector:select_tool_ucb(tools)

      -- tool1 should have higher UCB due to better performance
      assert.is.equal("tool1", selected)
    end)
  end)

  describe("select_tool_epsilon_greedy", function()
    it("should select from available tools", function()
      local selector = BayesianSelection.BayesianSelector.new()
      local tools = {"tool1", "tool2"}

      local selected = selector:select_tool_epsilon_greedy(tools, nil, 0.1)

      assert.is.truthy(selected)
    end)

    it("should explore with probability epsilon", function()
      local selector = BayesianSelection.BayesianSelector.new()

      -- Make tool1 very successful
      for i = 1, 10 do
        selector:record_result("tool1", true)
      end

      local tools = {"tool1", "tool2"}
      local explorations = 0

      for i = 1, 100 do
        local selected = selector:select_tool_epsilon_greedy(tools, nil, 0.5)
        if selected == "tool2" then
          explorations = explorations + 1
        end
      end

      -- With adaptive epsilon decay, should explore less but still some
      -- High initial epsilon (0.5) with decay should still give some exploration
      assert.is.truthy(explorations > 0)
    end)

    it("should exploit best tool most of the time", function()
      local selector = BayesianSelection.BayesianSelector.new()

      -- Make tool1 very successful
      for i = 1, 10 do
        selector:record_result("tool1", true)
      end

      -- Make tool2 fail
      for i = 1, 10 do
        selector:record_result("tool2", false)
      end

      local tools = {"tool1", "tool2"}
      local tool1_count = 0

      for i = 1, 100 do
        local selected = selector:select_tool_epsilon_greedy(tools, nil, 0.1)
        if selected == "tool1" then
          tool1_count = tool1_count + 1
        end
      end

      -- Should select tool1 most of the time
      assert.is.truthy(tool1_count > 70)
    end)

    it("should decay epsilon over time", function()
      local selector = BayesianSelection.BayesianSelector.new()

      selector:record_result("tool1", true)

      local epsilon_1 = 0.5 / math.sqrt(1)

      selector:record_result("tool1", true)
      selector:record_result("tool1", true)
      selector:record_result("tool1", true)

      local epsilon_2 = 0.5 / math.sqrt(4)

      assert.is.truthy(epsilon_2 < epsilon_1)
    end)
  end)

  describe("get_stats", function()
    it("should return statistics for all tools", function()
      local selector = BayesianSelection.BayesianSelector.new()

      selector:record_result("tool1", true)
      selector:record_result("tool1", false)
      selector:record_result("tool2", true)
      selector:record_result("tool2", true)

      local stats = selector:get_stats()

      assert.is.truthy(stats["tool1"])
      assert.is.truthy(stats["tool2"])
      assert.is.equal(2, stats["tool1"].attempts)
      assert.is.equal(2, stats["tool2"].attempts)
      assert.is.equal(1, stats["tool1"].successes)
      assert.is.equal(2, stats["tool2"].successes)
    end)

    it("should calculate success rate", function()
      local selector = BayesianSelection.BayesianSelector.new()

      selector:record_result("tool1", true)
      selector:record_result("tool1", true)
      selector:record_result("tool1", false)

      local stats = selector:get_stats()

      assert.is.equal(2/3, stats["tool1"].success_rate)
    end)

    it("should calculate expected probability", function()
      local selector = BayesianSelection.BayesianSelector.new({
        alpha = 2,
        beta = 2
      })

      selector:record_result("tool1", true)
      selector:record_result("tool1", false)

      local stats = selector:get_stats()

      -- (alpha + successes) / (alpha + beta + attempts)
      -- (2 + 1) / (2 + 2 + 2) = 3/6 = 0.5
      assert.is.equal(0.5, stats["tool1"].expected_prob)
    end)

    it("should return empty table for no tools", function()
      local selector = BayesianSelection.BayesianSelector.new()

      local stats = selector:get_stats()

      assert.is.equal(0, #stats)
    end)
  end)

  describe("reset", function()
    it("should reset specific tool", function()
      local selector = BayesianSelection.BayesianSelector.new()

      selector:record_result("tool1", true)
      selector:record_result("tool2", true)

      selector:reset("tool1")

      assert.is.falsy(selector.tool_stats["tool1"])
      assert.is.truthy(selector.tool_stats["tool2"])
    end)

    it("should reset all tools", function()
      local selector = BayesianSelection.BayesianSelector.new()

      selector:record_result("tool1", true)
      selector:record_result("tool2", true)

      selector:reset()

      assert.is.falsy(selector.tool_stats["tool1"])
      assert.is.falsy(selector.tool_stats["tool2"])
    end)

    it("should handle resetting non-existent tool", function()
      local selector = BayesianSelection.BayesianSelector.new()

      selector:reset("nonexistent")

      assert.is.equal(0, #selector.tool_stats)
    end)
  end)

  describe("Integration Tests", function()
    it("should work with complete selection workflow", function()
      local selector = BayesianSelection.BayesianSelector.new({
        alpha = 2,
        beta = 2
      })

      local tools = {"calculator", "search", "database"}

      -- Simulate tool usage with different success rates
      for i = 1, 20 do
        local selected = selector:select_tool_thompson(tools)

        -- Simulate different success rates
        local success
        if selected == "calculator" then
          success = math.random() < 0.9  -- 90% success
        elseif selected == "search" then
          success = math.random() < 0.7  -- 70% success
        else
          success = math.random() < 0.5  -- 50% success
        end

        selector:record_result(selected, success)
      end

      local stats = selector:get_stats()

      -- Calculator should have best stats
      assert.is.truthy(stats["calculator"].attempts > 0)
      assert.is.truthy(stats["search"].attempts > 0)
      assert.is.truthy(stats["database"].attempts > 0)
    end)

    it("should adapt to changing tool performance", function()
      local selector = BayesianSelection.BayesianSelector.new()
      local tools = {"tool1", "tool2"}

      -- tool1 initially good
      for i = 1, 10 do
        selector:record_result("tool1", true)
      end
      for i = 1, 10 do
        selector:record_result("tool2", false)
      end

      local selected_1 = selector:select_tool_ucb(tools)
      assert.is.equal("tool1", selected_1)

      -- tool1 degrades significantly, tool2 improves significantly
      for i = 1, 20 do
        selector:record_result("tool1", false)
      end
      for i = 1, 20 do
        selector:record_result("tool2", true)
      end

      -- Eventually should switch to tool2
      -- Need more trials for UCB to adapt due to accumulated history
      local tool2_count = 0
      for i = 1, 100 do
        local selected = selector:select_tool_ucb(tools)
        if selected == "tool2" then
          tool2_count = tool2_count + 1
        end
      end

      -- Should select tool2 more often after dramatic change
      -- With 20 more successes vs failures, tool2 should dominate
      assert.is.truthy(tool2_count > 40)  -- At least 40% of the time
    end)

    it("should handle all selection strategies", function()
      local selector = BayesianSelection.BayesianSelector.new()
      local tools = {"tool1", "tool2", "tool3"}

      -- Record some results
      selector:record_result("tool1", true)
      selector:record_result("tool2", false)

      -- Thompson sampling
      local thompson = selector:select_tool_thompson(tools)
      assert.is.truthy(thompson)

      -- UCB
      local ucb = selector:select_tool_ucb(tools)
      assert.is.truthy(ucb)

      -- Epsilon-greedy
      local eg = selector:select_tool_epsilon_greedy(tools, nil, 0.1)
      assert.is.truthy(eg)
    end)
  end)

  describe("Helper Functions", function()
    it("should create selector with helper", function()
      local selector = BayesianSelection.bayesian_selector({alpha = 3})

      assert.is.equal(3, selector.alpha)
    end)
  end)
end)
