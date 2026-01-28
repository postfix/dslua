local M = {}

-- Core types
M.Field = require("dslua.core.field")
M.Signature = require("dslua.core.signature")
M.Context = require("dslua.core.context")

-- Modules
M.Predict = require("dslua.modules.predict")
M.ChainOfThought = require("dslua.modules.chain_of_thought")
M.ReAct = require("dslua.modules.react")
M.Refine = require("dslua.modules.refine")
M.FewShot = require("dslua.modules.fewshot")

-- Tools
M.Tool = require("dslua.tools.base")
M.ToolRegistry = require("dslua.tools.registry")

-- Agents
M.BaseAgent = require("dslua.agents.base")
M.ReActAgent = require("dslua.agents.react_agent")

-- Optimizers
M.BaseOptimizer = require("dslua.optimizers.base")
M.BootstrapFewShot = require("dslua.optimizers.bootstrap_fewshot")

-- LLM providers
M.llms = require("dslua.llms")

return M
