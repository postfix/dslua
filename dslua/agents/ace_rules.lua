local default_rules = {
    -- Complex tasks → Decompose
    {
        name = "complex_decomposition",
        conditions = {
            input_length = {op = ">", threshold = 0.7},
            complexity_estimate = {op = ">", threshold = 0.6}
        },
        action = "DECOMPOSE",
        weight = 0.9,
        id = 1
    },

    -- Factual + low confidence → Retrieve
    {
        name = "factual_retrieval",
        conditions = {
            task_type = {op = "==", value = "factual"},
            confidence = {op = "<", threshold = 0.6},
            entity_count = {op = ">", threshold = 0.3}
        },
        action = "RETRIEVE",
        weight = 0.85,
        id = 2
    },

    -- Math tasks → Use calculator
    {
        name = "math_calculator",
        conditions = {
            task_type = {op = "==", value = "math"}
        },
        action = "RETRIEVE",  -- RETRIEVE will delegate to calculator
        weight = 0.95,
        id = 3
    },

    -- High confidence → Answer directly
    {
        name = "confident_direct_answer",
        conditions = {
            confidence = {op = ">", threshold = 0.8},
            complexity_estimate = {op = "<", threshold = 0.5}
        },
        action = "REASON",
        weight = 0.8,
        id = 4
    },

    -- After synthesis → Verify
    {
        name = "post_synthesis_verify",
        conditions = {
            current_action = {op = "==", value = "SYNTHESIZE"},
            confidence = {op = "<", threshold = 0.7}
        },
        action = "VERIFY",
        weight = 0.75,
        id = 5
    },

    -- Default fallback (always matches)
    {
        name = "default_reason_terminate",
        conditions = {},  -- No conditions = always matches
        action = "REASON",
        weight = 0.2,  -- Low weight, only activates if no better match
        id = 999
    }
}

return default_rules
