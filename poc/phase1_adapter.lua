local Phase1Adapter = {}
Phase1Adapter.__index = Phase1Adapter

function Phase1Adapter.new()
    return setmetatable({}, Phase1Adapter)
end

-- Default values for optional fields
local DEFAULTS = {
    task = {
        input_length = 0.0,
        entity_count = 0.0,
        tool_requirements = {}
    },
    self = {
        prev_action = nil
    }
}

function Phase1Adapter:NormalizeState(snapshot)
    -- Check if already normalized (has task and self layers)
    if snapshot.task and snapshot.self then
        -- Apply defaults for any missing optional fields
        local task = {}
        for k, v in pairs(snapshot.task) do
            task[k] = v
        end
        for k, v in pairs(DEFAULTS.task) do
            if task[k] == nil then
                task[k] = v
            end
        end

        local self = {}
        for k, v in pairs(snapshot.self) do
            self[k] = v
        end
        for k, v in pairs(DEFAULTS.self) do
            if self[k] == nil then
                self[k] = v
            end
        end

        return {
            task = task,
            self = self
        }
    end

    -- Raw snapshot passed through unchanged (assume already structured)
    return snapshot
end

return Phase1Adapter
