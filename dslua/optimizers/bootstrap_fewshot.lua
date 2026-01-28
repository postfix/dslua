local BaseOptimizer = require("dslua.optimizers.base")
local FewShot = require("dslua.modules.fewshot")

local BootstrapFewShot = {}
BootstrapFewShot.__index = BootstrapFewShot
setmetatable(BootstrapFewShot, {__index = BaseOptimizer})

function BootstrapFewShot.new(module, opts)
    opts = opts or {}
    local self = BaseOptimizer.new(module, opts)
    setmetatable(self, BootstrapFewShot)

    self._trainset = opts.trainset or {}
    self._valset = opts.valset or opts.dataset or {}
    self._max_bootstraps = opts.max_bootstraps or 10
    self._max_labeled_demos = opts.max_labeled_demos or 5

    return self
end

function BootstrapFewShot:Compile(ctx, num_trials)
    num_trials = num_trials or self._max_bootstraps

    if #self._trainset == 0 then
        -- Return base module with no demonstrations
        return FewShot.new(self._module, {})
    end

    local best_program = nil
    local best_score = -1

    -- Try different subset sizes
    for trial = 1, num_trials do
        -- Sample random subset of training examples
        local subset_size = math.min(math.random(1, self._max_labeled_demos), #self._trainset)
        local subset = self:_sampleSubset(subset_size)

        -- Create fewshot program with these demonstrations
        local program = FewShot.new(self._module, subset)

        -- Evaluate on validation set
        local score = self:Evaluate(ctx, program)

        if score > best_score then
            best_score = score
            best_program = program
        end
    end

    return best_program or FewShot.new(self._module, {})
end

function BootstrapFewShot:_sampleSubset(size)
    local shuffled = {}
    for i = 1, #self._trainset do
        shuffled[i] = self._trainset[i]
    end

    -- Fisher-Yates shuffle
    for i = #shuffled, 2, -1 do
        local j = math.random(i)
        shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
    end

    -- Take first `size` elements
    local subset = {}
    for i = 1, size do
        subset[i] = shuffled[i]
    end

    return subset
end

return BootstrapFewShot
