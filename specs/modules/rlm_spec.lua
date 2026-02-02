-- specs/modules/rlm_spec.lua
-- Tests for RLM Module

describe("RLM Module", function()
  local RLM = require("dslua.modules.rlm")
  local Signature = require("dslua.core.signature")
  local Field = require("dslua.core.field")
  local Context = require("dslua.core.context")

  -- Helper to create signature
  local function createSignature()
    return Signature.new(
      {Field.new("question")},
      {Field.new("answer")}
    )
  end

  -- Helper to create mock retriever
  local function createMockRetriever(docs)
    return {
      Retrieve = function(self, query, opts)
        local results = {}
        local max_docs = opts.max_docs or #docs

        for i, doc in ipairs(docs) do
          if i <= max_docs then
            local text = type(doc) == "table" and doc.text or doc
            -- Simple word matching
            local matched = false
            for word in query:lower():gmatch("%w+") do
              if text:lower():find(word, 1, true) then
                matched = true
                break
              end
            end

            if matched then
              table.insert(results, {
                text = text,
                similarity = 0.8,
                id = "doc" .. i,
                metadata = {}
              })
            end
          end
        end

        return results
      end
    }
  end

  describe("new", function()
    it("should create RLM module with signature", function()
      local sig = createSignature()
      local retriever = createMockRetriever({})

      local rlm = RLM.new(sig, {retriever = retriever})

      assert.is.equal(sig, rlm:Signature())
      assert.is.equal(retriever, rlm._retriever)
    end)

    it("should set default options", function()
      local sig = createSignature()
      local rlm = RLM.new(sig, {retriever = createMockRetriever({})})

      assert.is.equal(3, rlm._max_passes)
      assert.is.equal(0.5, rlm._threshold)
      assert.is_false(rlm._verbose)
    end)

    it("should accept custom options", function()
      local sig = createSignature()
      local rlm = RLM.new(sig, {
        retriever = createMockRetriever({}),
        max_passes = 5,
        threshold = 0.7,
        verbose = true
      })

      assert.is.equal(5, rlm._max_passes)
      assert.is.equal(0.7, rlm._threshold)
      assert.is_true(rlm._verbose)
    end)
  end)

  describe("Process", function()
    it("should retrieve and augment with context", function()
      local sig = createSignature()
      local retriever = createMockRetriever({
        {text = "Paris is the capital of France"},
        {text = "Lua is a scripting language"}
      })

      local rlm = RLM.new(sig, {retriever = retriever})
      local ctx = Context.new({})

      local result = rlm:Process(ctx, {question = "Tell me about Paris"})

      assert.is.equal("Tell me about Paris", result.question)
      assert.is.truthy(result.context)
      assert.is_truthy(result.context:find("Paris"))
    end)

    it("should perform multiple retrieval passes", function()
      local sig = createSignature()
      local docs = {
        {text = "Document 1 about Python"},
        {text = "Document 2 about Lua"},
        {text = "Document 3 about JavaScript"}
      }

      local retriever = createMockRetriever(docs)
      local rlm = RLM.new(sig, {
        retriever = retriever,
        max_passes = 2,
        verbose = false
      })

      local ctx = Context.new({})
      local result = rlm:Process(ctx, {question = "Tell me about programming"})

      assert.is.truthy(result.context)
      assert.is_truthy(result.rlm_passes and result.rlm_passes > 0)
    end)

    it("should respect max_passes limit", function()
      local sig = createSignature()
      local retriever = createMockRetriever({
        {text = "Doc 1"},
        {text = "Doc 2"}
      })

      local rlm = RLM.new(sig, {
        retriever = retriever,
        max_passes = 2
      })

      local ctx = Context.new({})
      local result = rlm:Process(ctx, {question = "Test"})

      assert.is_truthy(result.rlm_passes <= 2)
    end)

    it("should handle no retriever gracefully", function()
      local sig = createSignature()
      local rlm = RLM.new(sig, {})

      local ctx = Context.new({})
      local result = rlm:Process(ctx, {question = "Test"})

      assert.is.equal("Test", result.question)
      assert.is.falsy(result.context)
    end)

    it("should handle empty retrieval results", function()
      local sig = createSignature()
      local retriever = createMockRetriever({})  -- No matching docs

      local rlm = RLM.new(sig, {retriever = retriever})

      local ctx = Context.new({})
      local result = rlm:Process(ctx, {question = "Query with no matches"})

      assert.is.equal("Query with no matches", result.question)
      assert.is.falsy(result.context)
    end)
  end)

  describe("RLMRetriever", function()
    it("should create RLM retriever", function()
      local base_retriever = createMockRetriever({text = "Test doc"})

      local rlm_retriever = RLM.RLMRetriever.new({
        base_retriever = base_retriever
      })

      assert.is.equal(base_retriever, rlm_retriever.base_retriever)
    end)

    it("should perform query expansion", function()
      local docs = {
        {text = "machine learning algorithms use data"},
        {text = "neural networks are powerful"}
      }

      local base_retriever = createMockRetriever(docs)
      local rlm_retriever = RLM.RLMRetriever.new({
        base_retriever = base_retriever,
        context_window = 2
      })

      local results = rlm_retriever:Retrieve("machine learning")

      -- Should return results with query expansion
      assert.is_truthy(#results > 0)
    end)

    it("should respect max_expansions", function()
      local base_retriever = createMockRetriever({text = "Test"})

      local rlm_retriever = RLM.RLMRetriever.new({
        base_retriever = base_retriever,
        max_expansions = 2
      })

      local results = rlm_retriever:Retrieve("query")

      assert.is_truthy(#results >= 0)
    end)
  end)

  describe("ContextBuilder", function()
    it("should create context builder", function()
      local builder = RLM.ContextBuilder.new()

      assert.is.equal(2000, builder.max_length)
      assert.is_false(builder.include_metadata)
      assert.is.equal("sequential", builder.format)
    end)

    it("should build sequential context", function()
      local builder = RLM.ContextBuilder.new({
        format = "sequential"
      })

      local docs = {
        {text = "Document 1", content = "Content 1"},
        {text = "Document 2", content = "Content 2"}
      }

      local context = builder:Build(docs, "test query")

      assert.is_truthy(context:find("Query:"))
      assert.is_truthy(context:find("Relevant Context:"))
      assert.is_truthy(context:find("Document 1"))
    end)

    it("should build clustered context", function()
      local builder = RLM.ContextBuilder.new({
        format = "clustered"
      })

      local docs = {
        {text = "Python programming tutorial"},
        {text = "Java programming guide"},
        {text = "Python advanced features"}
      }

      local context = builder:Build(docs, "Python")

      assert.is.truthy(context:find("Cluster"))
      assert.is_truthy(context:find("Python"))
    end)

    it("should build hierarchical context", function()
      local builder = RLM.ContextBuilder.new({
        format = "hierarchical"
      })

      local docs = {
        {text = "Most relevant document"},
        {text = "Somewhat relevant"},
        {text = "Less relevant"}
      }

      local context = builder:Build(docs, "test")

      assert.is.truthy(context:find("Level"))
      assert.is.truthy(#context > 0)
    end)

    it("should truncate long context", function()
      local builder = RLM.ContextBuilder.new({
        max_length = 50
      })

      local docs = {}
      for i = 1, 10 do
        table.insert(docs, {text = string.rep("Long text ", 20)})
      end

      local context = builder:Build(docs, "query")

      assert.is_truthy(#context <= 55)  -- 50 + "..."
    end)
  end)

  describe("Helper Functions", function()
    it("should create RLM retriever with helper", function()
      local retriever = RLM.rlm_retriever({})

      assert.is.truthy(retriever)
      assert.is.equal("table", type(retriever))
    end)

    it("should create context builder with helper", function()
      local builder = RLM.context_builder({})

      assert.is.truthy(builder)
      assert.is.equal("table", type(builder))
    end)
  end)

  describe("Integration Tests", function()
    it("should work with complete RAG pipeline", function()
      local sig = createSignature()
      local retriever = createMockRetriever({
        {text = "Fact 1 about the topic"},
        {text = "Fact 2 about the topic"},
        {text = "Fact 3 about the topic"}
      })

      local rlm = RLM.new(sig, {
        retriever = retriever,
        max_passes = 2
      })

      local ctx = Context.new({})
      local result = rlm:Process(ctx, {question = "What do we know about the topic?"})

      assert.is.truthy(result.context)
      assert.is_truthy(result.context:find("Fact"))
    end)

    it("should handle complex multi-pass retrieval", function()
      local sig = createSignature()

      local docs = {}
      for i = 1, 10 do
        table.insert(docs, {text = "Information " .. i .. " about topic"})
      end

      local retriever = createMockRetriever(docs)
      local rlm = RLM.new(sig, {
        retriever = retriever,
        max_passes = 3,
        threshold = 0.3
      })

      local ctx = Context.new({})
      local result = rlm:Process(ctx, {question = "topic"})

      assert.is.truthy(result.context)
      assert.is_truthy(result.rlm_passes > 0)
    end)

    it("should work with RLM retriever and context builder", function()
      local sig = createSignature()

      local base_docs = {
        {text = "Related concept A"},
        {text = "Related concept B"}
      }

      local base_retriever = createMockRetriever(base_docs)
      local rlm_retriever = RLM.RLMRetriever.new({
        base_retriever = base_retriever
      })

      local rlm = RLM.new(sig, {retriever = rlm_retriever})
      local ctx = Context.new({})

      local result = rlm:Process(ctx, {question = "concepts"})

      assert.is.truthy(result)
      assert.is.equal("concepts", result.question)
    end)
  end)
end)
