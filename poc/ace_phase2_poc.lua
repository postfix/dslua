-- poc/ace_phase2_poc.lua
local Phase1Adapter = require("poc.phase1_adapter")

local Phase2Learner = {}
Phase2Learner.__index = Phase2Learner

local ACTIONS_ORDER = {"REASON", "RETRIEVE", "DECOMPOSE", "SYNTHESIZE", "VERIFY", "TERMINATE"}
local EPS = 1e-9

function Phase2Learner.new(adapter)
    local self = setmetatable({}, Phase2Learner)
    self.adapter = adapter
    self.ACTIONS_ORDER = ACTIONS_ORDER
    return self
end

function Phase2Learner:LearnFromDecision(decision, rules, weights, opts)
    local a_star = decision.demonstrated_action
    local state = self.adapter:NormalizeState(decision.state_snapshot)

    -- Validate demonstrated_action
    local valid_action = false
    for _, action in ipairs(ACTIONS_ORDER) do
        if action == a_star then
            valid_action = true
            break
        end
    end
    if not valid_action then
        error("Invalid demonstrated_action")
    end

    -- Step 1: Compute scores deterministically
    local scores, per_action_matches = self.adapter:ScoreActions(
        state, rules, weights, ACTIONS_ORDER
    )
    local score_star = scores[a_star]

    -- Step 2: Find best competitor (handle no competitors correctly)
    local best = nil
    for _, action in ipairs(ACTIONS_ORDER) do
        if action ~= a_star then
            local s = scores[action] or 0
            if best == nil or s > best then
                best = s
            end
        end
    end
    local score_comp = best or 0  -- 0 if no competitors

    -- Step 3: Build epsilon-band competitors (skip if best == 0)
    local comp_actions = {}
    if score_comp > 0 then  -- Only penalize if competitor has positive score
        for _, action in ipairs(ACTIONS_ORDER) do
            if action ~= a_star then
                local s = scores[action] or 0
                if s >= score_comp - (opts.epsilon or 0.01) then
                    table.insert(comp_actions, action)
                end
            end
        end
    end

    -- Special case: single-action ACTIONS_ORDER
    if #comp_actions == 0 then
        score_comp = 0
    end

    -- Step 4: Find matching rules for demonstrated action
    local R_star = self.adapter:FindMatchingRules(state, a_star, rules, weights)

    -- Step 5: Handle coverage failure
    if #R_star == 0 then
        return {
            updated = false,
            uncovered = true,
            reason = "no_rules_for_demonstrated_action",
            demonstrated_action = a_star
        }
    end

    -- Step 6: Compute contribution mass for R_star (guard against zero mass)
    local mass_star = 0
    for _, pair in ipairs(R_star) do
        mass_star = mass_star + (pair.weight * pair.salience)
    end
    if mass_star <= EPS then
        return {
            updated = false,
            uncovered = false,
            reason = "zero_mass_star",
            mass_star = mass_star
        }
    end

    -- Return early metrics for now (will complete in next task)
    return {
        updated = false,
        score_star = score_star,
        score_comp = score_comp,
        mass_star = mass_star,
        demonstrated_action = a_star
    }
end

return Phase2Learner
