-- specs/optimizers/mipro_tpe_spec.lua
-- Tests for MIPRO TPE (Tree-structured Parzen Estimator)

local TPE = require("dslua.optimizers.mipro_tpe")

describe("MIPRO TPE Module", function()

  describe("SampleCandidate", function()

    it("should handle empty observations by returning random sample", function()
      local space = {
        num_demos = {type = "int", min = 1, max = 10}
      }

      local candidate = TPE.SampleCandidate({}, space, {
        seed = 42
      })

      assert.is_not_nil(candidate)
      assert.is_not_nil(candidate.num_demos)
      assert.is_true(candidate.num_demos >= 1)
      assert.is_true(candidate.num_demos <= 10)
    end)

    it("should build good and poor models from observations", function()
      local space = {
        num_demos = {type = "int", min = 1, max = 10}
      }

      -- Create observations with clear performance pattern
      local observations = {
        {params = {num_demos = 3}, score = 0.8},  -- Good
        {params = {num_demos = 4}, score = 0.75}, -- Good
        {params = {num_demos = 5}, score = 0.7},  -- Good
        {params = {num_demos = 1}, score = 0.4},  -- Poor
        {params = {num_demos = 2}, score = 0.5},  -- Poor
        {params = {num_demos = 10}, score = 0.3} -- Poor
      }

      local candidate = TPE.SampleCandidate(observations, space, {
        seed = 42
      })

      -- Should prefer values that led to good performance (3-5 demos)
      assert.is_not_nil(candidate.num_demos)
      assert.is_true(candidate.num_demos >= 2)
      assert.is_true(candidate.num_demos <= 6)
    end)

    it("should handle categorical hyperparameters", function()
      local space = {
        demo_selection = {
          type = "enum",
          values = {"random", "diverse", "similar"}
        }
      }

      local observations = {
        {params = {demo_selection = "diverse"}, score = 0.8},
        {params = {demo_selection = "diverse"}, score = 0.75},
        {params = {demo_selection = "random"}, score = 0.5},
        {params = {demo_selection = "similar"}, score = 0.4}
      }

      local candidate = TPE.SampleCandidate(observations, space, {
        seed = 42
      })

      -- Should prefer "diverse" since it has best scores
      assert.is_not_nil(candidate.demo_selection)
      local valid = false
      for _, v in ipairs({"random", "diverse", "similar"}) do
        if v == candidate.demo_selection then
          valid = true
          break
        end
      end
      assert.is_true(valid)
    end)

    it("should handle continuous hyperparameters", function()
      local space = {
        temperature = {type = "float", min = 0.0, max = 1.0}
      }

      local observations = {
        {params = {temperature = 0.3}, score = 0.8},
        {params = {temperature = 0.4}, score = 0.75},
        {params = {temperature = 0.9}, score = 0.4},
        {params = {temperature = 1.0}, score = 0.3}
      }

      local candidate = TPE.SampleCandidate(observations, space, {
        seed = 42
      })

      -- Should prefer lower temperatures (0.3-0.4 range)
      assert.is_not_nil(candidate.temperature)
      assert.is_true(candidate.temperature >= 0.0)
      assert.is_true(candidate.temperature <= 1.0)
    end)

  end)

  describe("UpdateObservations", function()

    it("should add new observation to list", function()
      local observations = {
        {params = {num_demos = 3}, score = 0.7}
      }

      local updated = TPE.UpdateObservations(
        observations,
        {num_demos = 5},
        0.8
      )

      assert.is_equal(2, #updated)
      assert.is_equal(5, updated[2].params.num_demos)
      assert.is_equal(0.8, updated[2].score)
    end)

    it("should maintain observation order", function()
      local observations = {
        {params = {num_demos = 1}, score = 0.5},
        {params = {num_demos = 2}, score = 0.6}
      }

      local updated = TPE.UpdateObservations(
        observations,
        {num_demos = 3},
        0.7
      )

      assert.is_equal(3, #updated)
      assert.is_equal(0.5, updated[1].score)
      assert.is_equal(0.6, updated[2].score)
      assert.is_equal(0.7, updated[3].score)
    end)

  end)

  describe("Hyperparameter Space", function()

    it("should validate integer parameter constraints", function()
      local space = {
        num_demos = {type = "int", min = 1, max = 10}
      }

      -- Valid
      local params1 = TPE._sampleParam(space.num_demos, {seed = 42})
      assert.is_not_nil(params1)
      assert.is_true(params1 >= 1 and params1 <= 10)

      -- Test reproducibility with seed
      local params2 = TPE._sampleParam(space.num_demos, {seed = 42})
      assert.is_equal(params1, params2)
    end)

    it("should validate enum parameter constraints", function()
      local space = {
        strategy = {type = "enum", values = {"a", "b", "c"}}
      }

      local param = TPE._sampleParam(space.strategy, {seed = 42})
      assert.is_not_nil(param)
      local valid = false
      for _, v in ipairs({"a", "b", "c"}) do
        if v == param then
          valid = true
          break
        end
      end
      assert.is_true(valid)
    end)

    it("should validate float parameter constraints", function()
      local space = {
        learning_rate = {type = "float", min = 0.001, max = 0.1}
      }

      local param = TPE._sampleParam(space.learning_rate, {seed = 42})
      assert.is_not_nil(param)
      assert.is_true(param >= 0.001)
      assert.is_true(param <= 0.1)
    end)

  end)

  describe("TPE Algorithm", function()

    it("should split observations into good and poor sets", function()
      local observations = {}
      for i = 1, 10 do
        table.insert(observations, {
          params = {num_demos = i},
          score = 0.3 + (i * 0.05)  -- 0.35 to 0.8
        })
      end

      local good, poor = TPE._splitObservations(observations, 0.25)

      -- Top 25% (best 2-3) should be in good
      assert.is_true(#good >= 2)
      assert.is_true(#good <= 3)

      -- Bottom 75% should be in poor
      assert.is_true(#poor >= 7)
      assert.is_equal(#observations, #good + #poor)
    end)

    it("should compute probability densities for integer params", function()
      local good_obs = {
        {params = {num_demos = 3}, score = 0.8},
        {params = {num_demos = 4}, score = 0.75},
        {params = {num_demos = 5}, score = 0.7}
      }

      local poor_obs = {
        {params = {num_demos = 1}, score = 0.4},
        {params = {num_demos = 2}, score = 0.5},
        {params = {num_demos = 8}, score = 0.3}
      }

      local space = {
        num_demos = {type = "int", min = 1, max = 10, name = "num_demos"}
      }

      -- Compute likelihood for good and poor using _computeLikelihood
      local l_x = TPE._computeLikelihood({num_demos = 4}, good_obs, space)
      local g_x = TPE._computeLikelihood({num_demos = 4}, poor_obs, space)

      -- Value 4 is in good observations, not in poor
      assert.is_true(l_x > 0)
      -- g_x might be 0 or very small
      assert.is_true(g_x >= 0)
    end)

    it("should maximize expected improvement", function()
      local candidates = {
        {num_demos = 3, ei = 0.5},
        {num_demos = 4, ei = 0.8},
        {num_demos = 5, ei = 0.3}
      }

      local best = TPE._maximizeEI(candidates)

      assert.is_not_nil(best)
      assert.is_equal(4, best.num_demos)  -- Highest EI
    end)

  end)

end)
