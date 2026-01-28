local BaseOptimizer = {}
BaseOptimizer.__index = BaseOptimizer

function BaseOptimizer.new(module, opts)
    opts = opts or {}
    local self = setmetatable({}, BaseOptimizer)

    self._module = module
    self._dataset = opts.dataset or {}
    self._metric = opts.metric or function(result, expected)
        -- Default metric: exact match of all fields
        for key, expected_val in pairs(expected) do
            if result[key] ~= expected_val then
                return 0
            end
        end
        return 1
    end

    return self
end

function BaseOptimizer:Compile(ctx, num_trials)
    error("Compile must be implemented by subclass")
end

function BaseOptimizer:Evaluate(ctx, program)
    if #self._dataset == 0 then
        return 0
    end

    local total_score = 0

    for _, example in ipairs(self._dataset) do
        local result = program:Process(ctx, example.input)
        local score = self._metric(result, example.output)
        total_score = total_score + score
    end

    return total_score / #self._dataset
end

return BaseOptimizer
