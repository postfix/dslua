-- examples/math_knowledge_module.lua
-- Simple module that can handle math and factual questions

local MathKnowledgeModule = {}

function MathKnowledgeModule:Signature()
  return {
    name = "MathKnowledgeModule",
    description = "Handles math calculations and factual questions",
    input_schema = {
      type = "object",
      properties = {
        question = {type = "string"}
      },
      required = {"question"}
    }
  }
end

function MathKnowledgeModule:Process(ctx, input)
  local question = input.question or ""
  local lower_q = string.lower(question)

  -- Math: Arithmetic operations
  if lower_q:match("what is %d+%s*[%+%-*/]%s*%d") or
     lower_q:match("calculat") or
     lower_q:match("%d+%s*[%+%-*/]%s*%d") then
    local result = self:_Calculate(question)
    return {
      content = string.format("Answer: %s", result),
      answer = result
    }
  end

  -- Factual: Capital cities
  if lower_q:match("what is the capital of") or
     lower_q:match("capital of") then
    local country = question:match("capital of ([%w%s]+)")
    local capital = self:_GetCapital(country)
    return {
      content = string.format("Answer: The capital of %s is %s", country, capital),
      answer = capital
    }
  end

  -- Factual: Basic facts
  if lower_q:match("who is") or lower_q:match("what is") then
    local fact = self:_LookupFact(question)
    return {
      content = string.format("Answer: %s", fact),
      answer = fact
    }
  end

  -- Default: General reasoning
  return {
    content = "Answer: I need more information to answer that question.",
    answer = "Insufficient information"
  }
end

function MathKnowledgeModule:_Calculate(question)
  -- Extract simple arithmetic: "what is 5 + 3"
  local expr = question:match("what is (%d+%s*[%+%-*/]%s*%d)")
  if not expr then
    expr = question:match("(%d+%s*[%+%-*/]%s*%d)")
  end

  if expr then
    -- Safe evaluation: only allow digits and operators
    local clean = expr:gsub("%s+", "")
    local num1, op, num2 = clean:match("(%d+)([%+%-*/])(%d+)")
    if num1 and op and num2 then
      num1 = tonumber(num1)
      num2 = tonumber(num2)

      if op == "+" then return num1 + num2 end
      if op == "-" then return num1 - num2 end
      if op == "*" then return num1 * num2 end
      if op == "/" then return num1 / num2 end
    end
  end

  return "Could not calculate"
end

function MathKnowledgeModule:_GetCapital(country)
  local capitals = {
    ["france"] = "Paris",
    ["germany"] = "Berlin",
    ["japan"] = "Tokyo",
    ["italy"] = "Rome",
    ["spain"] = "Madrid",
    ["england"] = "London",
    ["uk"] = "London",
    ["united states"] = "Washington DC",
    ["usa"] = "Washington DC",
    ["china"] = "Beijing",
    ["india"] = "New Delhi"
  }

  local key = string.lower(country:gsub("^[%s]+", ""):gsub("[%s]+$", ""))
  return capitals[key] or "Unknown"
end

function MathKnowledgeModule:_LookupFact(question)
  local facts = {
    ["who is the president of the united states"] = "The President of the United States is Joe Biden (as of 2024)",
    ["what is the largest planet"] = "Jupiter is the largest planet in our solar system",
    ["who wrote romeo and juliet"] = "William Shakespeare wrote Romeo and Juliet",
    ["what is the boiling point of water"] = "Water boils at 100 degrees Celsius (212 degrees Fahrenheit) at sea level"
  }

  local lower_q = string.lower(question:gsub("?", ""))
  for pattern, answer in pairs(facts) do
    if lower_q:match(pattern) or pattern:match(lower_q) then
      return answer
    end
  end

  return "I don't have that information"
end

return MathKnowledgeModule
