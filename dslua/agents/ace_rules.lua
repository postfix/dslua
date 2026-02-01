local default_rules = {
    -- Math tasks → Use calculator
    {
        key = "math_calculator",
        name = "math_calculator",
        conditions = {
            {feature = "task_type", op = "==", value = "math"}
        },
        action = "RETRIEVE",
        default_weight = 0.95,
        id = 1
    },

    -- Factual + low confidence → Retrieve
    {
        key = "factual_retrieval",
        name = "factual_retrieval",
        conditions = {
            {feature = "task_type", op = "==", value = "factual"},
            {feature = "confidence", op = "<", threshold = 0.6},
            {feature = "entity_count", op = ">", threshold = 0.3}
        },
        action = "RETRIEVE",
        default_weight = 0.85,
        id = 2
    },

    -- Complex tasks → Decompose
    {
        key = "complex_decomposition",
        name = "complex_decomposition",
        conditions = {
            {feature = "input_length", op = ">", threshold = 0.7},
            {feature = "complexity_estimate", op = ">", threshold = 0.6}
        },
        action = "DECOMPOSE",
        default_weight = 0.9,
        id = 3
    },

    -- High confidence → Answer directly
    {
        key = "confident_direct_answer",
        name = "confident_direct_answer",
        conditions = {
            {feature = "confidence", op = ">", threshold = 0.8},
            {feature = "complexity_estimate", op = "<", threshold = 0.5}
        },
        action = "REASON",
        default_weight = 0.8,
        id = 4
    },

    -- After synthesis → Verify
    {
        key = "post_synthesis_verify",
        name = "post_synthesis_verify",
        conditions = {
            {feature = "current_action", op = "==", value = "SYNTHESIZE"},
            {feature = "confidence", op = "<", threshold = 0.7}
        },
        action = "VERIFY",
        default_weight = 0.75,
        id = 5
    },

    -- Default fallback (always matches)
    {
        key = "default_reason_terminate",
        name = "default_reason_terminate",
        conditions = {},  -- No conditions = always matches
        action = "REASON",
        default_weight = 0.2,  -- Low weight, only activates if no better match
        id = 999
    }
}

return default_rules
