-- poc/rules_poc.lua
local RULES = {
    -- Rule 1: Math → Use Calculator (Demo 1 target)
    {
        id = "math_use_calculator",
        key = "math_use_calculator",
        conditions = {
            {"task_type", "==", "math"},
            {"complexity_estimate", "<", 0.5}
        },
        action = "RETRIEVE",
        default_weight = 0.8
    },

    -- Rule 2: Factual + High Confidence → Reason Direct (Demo 2 part A)
    {
        id = "factual_reason_direct",
        key = "factual_reason_direct",
        conditions = {
            {"task_type", "==", "factual"},
            {"confidence", ">", 0.5}
        },
        action = "REASON",
        default_weight = 0.700  -- Safely inside epsilon band
    },

    -- Rule 3: Factual + Entities → Use Search (Demo 2 part B, epsilon-band partner)
    {
        id = "factual_use_search",
        key = "factual_use_search",
        conditions = {
            {"task_type", "==", "factual"},
            {"entity_count", ">", 0.3}
        },
        action = "RETRIEVE",
        default_weight = 0.695  -- Within epsilon=0.01 (0.700 - 0.695 = 0.005 < 0.01)
    },

    -- Rule 4: General + High Complexity → Retrieve (Demo 3 competitor)
    {
        id = "general_retrieve_when_complex",
        key = "general_retrieve_when_complex",
        conditions = {
            {"task_type", "==", "general"},
            {"complexity_estimate", ">", 0.8}
        },
        action = "RETRIEVE",
        default_weight = 0.8
    },

    -- Rule 5: General + Low Confidence → Fallback Reason (Demo 3 demonstrated action)
    -- FIXED: Scoped to "general" only to prevent matching Demo 1
    {
        id = "fallback_reason",
        key = "fallback_reason",
        conditions = {
            {"task_type", "==", "general"},  -- CRITICAL: Prevents matching Demo 1
            {"confidence", "<", 0.5}
        },
        action = "REASON",
        default_weight = 0.3
    }
}

return RULES
