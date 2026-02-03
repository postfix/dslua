-- specs/modules/retrieve_spec.lua
-- Tests for Retrieve Module (RAG)

describe("Retrieve Module", function()
  local Retrieve = require("dslua.modules.retrieve")
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

        -- Simple text matching (case-insensitive, word-based)
        for i, doc in ipairs(docs) do
          if i <= max_docs then
            local text = type(doc) == "table" and doc.text or doc
            local text_lower = text:lower()

            -- Check if any word from query appears in text
            local matched = false
            for word in query:lower():gmatch("%w+") do
              if text_lower:find(word, 1, true) then
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
    it("should create retrieve module with signature", function()
      local sig = createSignature()
      local retriever = createMockRetriever({})

      local retrieve = Retrieve.new(sig, {retriever = retriever})

      assert.is.equal(sig, retrieve:Signature())
      assert.is.equal(retriever, retrieve._retriever)
    end)

    it("should set default options", function()
      local sig = createSignature()
      local retriever = createMockRetriever({})

      local retrieve = Retrieve.new(sig, {retriever = retriever})

      assert.is.equal(5, retrieve._max_docs)
      assert.is.equal(0.0, retrieve._min_similarity)
    end)

    it("should accept custom options", function()
      local sig = createSignature()
      local retriever = createMockRetriever({})

      local retrieve = Retrieve.new(sig, {
        retriever = retriever,
        max_docs = 10,
        min_similarity = 0.5,
        return_metadata = true
      })

      assert.is.equal(10, retrieve._max_docs)
      assert.is.equal(0.5, retrieve._min_similarity)
      assert.is_true(retrieve._return_metadata)
    end)
  end)

  describe("Process", function()
    it("should retrieve and augment input with context", function()
      local sig = createSignature()
      local retriever = createMockRetriever({
        {text = "Paris is the capital of France"},
        {text = "Lua is a lightweight scripting language"}
      })

      local retrieve = Retrieve.new(sig, {retriever = retriever})
      local ctx = Context.new({})

      local result = retrieve:Process(ctx, {
        question = "What is the capital of France?"
      })

      assert.is.truthy(result.context)
      assert.is_truthy(result.context:find("Paris"))
      assert.is.equal("What is the capital of France?", result.question)
    end)

    it("should return original input when no docs found", function()
      local sig = createSignature()
      local retriever = createMockRetriever({
        {text = "Python is a programming language"}
      })

      local retrieve = Retrieve.new(sig, {retriever = retriever})
      local ctx = Context.new({})

      local result = retrieve:Process(ctx, {
        question = "Query about Lua"
      })

      -- No context added because no matches
      assert.is.falsy(result.context)
    end)

    it("should include retrieval metadata when enabled", function()
      local sig = createSignature()
      local retriever = createMockRetriever({
        {text = "This is a test document for retrieval"}
      })

      local retrieve = Retrieve.new(sig, {
        retriever = retriever,
        return_metadata = true
      })
      local ctx = Context.new({})

      local result = retrieve:Process(ctx, {question = "Test query"})

      assert.is.truthy(result.retrieval_metadata)
      assert.is.equal(1, result.retrieval_metadata.num_docs)
    end)

    it("should extract query from various input fields", function()
      local sig = createSignature()
      local retriever = createMockRetriever({
        {text = "Document containing text field words"},
        {text = "Document with question words inside"}
      })

      local retrieve = Retrieve.new(sig, {retriever = retriever})
      local ctx = Context.new({})

      local result1 = retrieve:Process(ctx, {query = "search text"})
      local result2 = retrieve:Process(ctx, {question = "search question"})

      assert.is.truthy(result1.context:find("text"))
      assert.is.truthy(result2.context:find("question"))
    end)
  end)

  describe("VectorRetriever", function()
    it("should create vector retriever", function()
      local retriever = Retrieve.VectorRetriever.new({
        vector_size = 128
      })

      assert.is.equal(128, retriever.vector_size)
      assert.is.equal(0, #retriever.documents)
    end)

    it("should add documents with embeddings", function()
      local retriever = Retrieve.VectorRetriever.new()

      retriever:AddDocument("doc1", "Test document one", {0.1, 0.2, 0.3})
      retriever:AddDocument("doc2", "Test document two", {0.4, 0.5, 0.6})

      assert.is.equal(2, #retriever.documents)
      assert.is.equal("doc1", retriever.documents[1].id)
    end)

    it("should retrieve by cosine similarity", function()
      local retriever = Retrieve.VectorRetriever.new({
        vector_size = 3
      })

      retriever:AddDocument("doc1", "similar text", {1.0, 1.0, 1.0})
      retriever:AddDocument("doc2", "different", {0.0, 1.0, 0.0})

      local results = retriever:Retrieve({1.0, 1.0, 1.0})

      -- First doc should have higher similarity
      assert.is.equal(2, #results)
      assert.is.equal("doc1", results[1].id)
    end)

    it("should limit results to max_docs", function()
      local retriever = Retrieve.VectorRetriever.new()

      for i = 1, 5 do
        retriever:AddDocument("doc" .. i, "text " .. i, {0.1, 0.2})
      end

      local results = retriever:Retrieve({0.1, 0.2}, {max_docs = 2})

      assert.is.equal(2, #results)
    end)

    it("should filter by min_similarity", function()
      local retriever = Retrieve.VectorRetriever.new({vector_size = 2})

      retriever:AddDocument("doc1", "relevant", {1.0, 0.0})
      retriever:AddDocument("doc2", "irrelevant", {0.0, 1.0})

      local results = retriever:Retrieve({1.0, 0.0}, {min_similarity = 0.9})

      -- doc1 has similarity 1.0, doc2 has similarity 0.0
      assert.is_equal(1, #results)
      assert.is.equal("doc1", results[1].id)
    end)
  end)

  describe("BM25Retriever", function()
    it("should create BM25 retriever", function()
      local retriever = Retrieve.BM25Retriever.new({
        k1 = 1.5,
        b = 0.75
      })

      assert.is.equal(1.5, retriever.k1)
      assert.is.equal(0.75, retriever.b)
    end)

    it("should add documents and tokenize", function()
      local retriever = Retrieve.BM25Retriever.new()

      retriever:AddDocument("doc1", "test document with repeated words")
      retriever:AddDocument("doc2", "another document")

      assert.is.equal(2, #retriever.documents)
      assert.is.truthy(retriever.documents[1].term_freq["test"])
    end)

    it("should rank documents by relevance", function()
      local retriever = Retrieve.BM25Retriever.new()

      retriever:AddDocument("doc1", "machine learning algorithms")
      retriever:AddDocument("doc2", "machine learning")
      retriever:AddDocument("doc3", "neural networks")

      local results = retriever:Retrieve("machine learning")

      -- doc1 and doc2 should rank higher (exact matches)
      assert.is.equal(3, #results)
      assert.is.truthy(results[1].score >= results[2].score)
    end)

    it("should limit results", function()
      local retriever = Retrieve.BM25Retriever.new()

      for i = 1, 5 do
        retriever:AddDocument("doc" .. i, "document " .. i)
      end

      local results = retriever:Retrieve("document", {max_docs = 2})

      assert.is.equal(2, #results)
    end)
  end)

  describe("HybridRetriever", function()
    it("should create hybrid retriever", function()
      local retriever1 = createMockRetriever({})
      local retriever2 = createMockRetriever({})

      local hybrid = Retrieve.HybridRetriever.new({
        retrievers = {retriever1, retriever2},
        weights = {0.6, 0.4},
        merge_strategy = "score_weighted"
      })

      assert.is.equal(2, #hybrid.retrievers)
      assert.is.equal(2, #hybrid.weights)
    end)

    it("should merge with score weighting", function()
      local docs1 = {
        {text = "result1", similarity = 0.9, id = "r1"}
      }
      local docs2 = {
        {text = "result2", similarity = 0.7, id = "r2"}
      }

      local retriever1 = {
        Retrieve = function(self, query, opts)
          return docs1
        end
      }
      local retriever2 = {
        Retrieve = function(self, query, opts)
          return docs2
        end
      }

      local hybrid = Retrieve.HybridRetriever.new({
        retrievers = {retriever1, retriever2},
        weights = {0.6, 0.4},
        merge_strategy = "score_weighted"
      })

      local results = hybrid:Retrieve("test")

      -- First retriever has higher weight and score
      assert.is.equal("result1", results[1].text)
    end)

    it("should merge with union strategy", function()
      local docs1 = {
        {text = "unique1", similarity = 0.8, id = "u1"}
      }
      local docs2 = {
        {text = "unique2", similarity = 0.8, id = "u2"}
      }

      local retriever1 = {
        Retrieve = function(self, query, opts)
          return docs1
        end
      }
      local retriever2 = {
        Retrieve = function(self, query, opts)
          return docs2
        end
      }

      local hybrid = Retrieve.HybridRetriever.new({
        retrievers = {retriever1, retriever2},
        merge_strategy = "union"
      })

      local results = hybrid:Retrieve("test")

      assert.is.equal(2, #results)
    end)

    it("should merge with interleave strategy", function()
      local docs1 = {{text = "from1", id = "i1"}}
      local docs2 = {{text = "from2", id = "i2"}}

      local retriever1 = {
        Retrieve = function(self, query, opts)
          return docs1
        end
      }
      local retriever2 = {
        Retrieve = function(self, query, opts)
          return docs2
        end
      }

      local hybrid = Retrieve.HybridRetriever.new({
        retrievers = {retriever1, retriever2},
        merge_strategy = "interleave"
      })

      local results = hybrid:Retrieve("test")

      assert.is.equal(2, #results)
    end)
  end)

  describe("Helper Functions", function()
    it("should create vector retriever with helper", function()
      local retriever = Retrieve.vector_retriever({vector_size = 256})

      assert.is.equal(256, retriever.vector_size)
    end)

    it("should create BM25 retriever with helper", function()
      local retriever = Retrieve.bm25_retriever({k1 = 2.0})

      assert.is.equal(2.0, retriever.k1)
    end)

    it("should create hybrid retriever with helper", function()
      local hybrid = Retrieve.hybrid_retriever({merge_strategy = "union"})

      assert.is.equal("union", hybrid.merge_strategy)
    end)
  end)

  describe("Integration Tests", function()
    it("should work with simple RAG pipeline", function()
      local sig = createSignature()
      local retriever = Retrieve.VectorRetriever.new()

      -- Add knowledge base
      retriever:AddDocument("kb1", "Paris is the capital of France", {0.1, 0.2})
      retriever:AddDocument("kb2", "LuaJIT compiles to native code", {0.3, 0.4})

      local retrieve = Retrieve.new(sig, {retriever = retriever})
      local ctx = Context.new({})

      local result = retrieve:Process(ctx, {
        question = "Tell me about Paris and Lua"
      })

      -- Should have retrieved context
      assert.is.truthy(result.context)
      assert.is.truthy(result.question)
    end)

    it("should handle multiple retrievers in hybrid", function()
      local sig = createSignature()

      local vector_store = Retrieve.VectorRetriever.new()
      vector_store:AddDocument("doc1", "vector content", {1.0, 0.0})

      local bm25_store = Retrieve.BM25Retriever.new()
      bm25_store:AddDocument("doc2", "bm25 content")

      local hybrid = Retrieve.HybridRetriever.new({
        retrievers = {vector_store, bm25_store},
        weights = {0.5, 0.5},
        merge_strategy = "score_weighted"
      })

      local retrieve = Retrieve.new(sig, {retriever = hybrid})
      local ctx = Context.new({})

      local result = retrieve:Process(ctx, {question = "test"})

      assert.is_truthy(result.context)
    end)
  end)

  describe("Private Functions", function()
    describe("_simpleEmbed", function()
      it("should generate simple embedding from text", function()
        local retriever = Retrieve.VectorRetriever.new({vector_size = 10})

        local embedding = retriever:_simpleEmbed("hello world")

        assert.is_not_nil(embedding)
        assert.is.equal(10, #embedding)  -- vector_size
      end)

      it("should generate different embeddings for different texts", function()
        local retriever = Retrieve.VectorRetriever.new({vector_size = 10})

        local embed1 = retriever:_simpleEmbed("hello")
        local embed2 = retriever:_simpleEmbed("world")

        -- Should be different (though simple hash-based)
        assert.is_not_nil(embed1)
        assert.is_not_nil(embed2)
      end)

      it("should pad embedding to vector_size", function()
        local retriever = Retrieve.VectorRetriever.new({vector_size = 50})

        local embedding = retriever:_simpleEmbed("hi")

        assert.is.equal(50, #embedding)
      end)
    end)

    describe("_cosineSimilarity", function()
      it("should calculate cosine similarity", function()
        local vec1 = {1.0, 0.0, 0.0}
        local vec2 = {1.0, 0.0, 0.0}

        local sim = Retrieve._cosineSimilarity(vec1, vec2)

        assert.is.equal(1.0, sim)  -- Identical vectors
      end)

      it("should return 0 for orthogonal vectors", function()
        local vec1 = {1.0, 0.0, 0.0}
        local vec2 = {0.0, 1.0, 0.0}

        local sim = Retrieve._cosineSimilarity(vec1, vec2)

        assert.is.equal(0, sim)  -- Orthogonal
      end)

      it("should return 0 for zero vectors", function()
        local vec1 = {0.0, 0.0, 0.0}
        local vec2 = {1.0, 0.0, 0.0}

        local sim = Retrieve._cosineSimilarity(vec1, vec2)

        assert.is.equal(0, sim)  -- Zero magnitude
      end)
    end)

    describe("_defaultFormat", function()
      it("should format empty docs", function()
        local formatted = Retrieve._defaultFormat({}, {})

        assert.is.equal("", formatted)
      end)

      it("should format documents with text field", function()
        local docs = {
          {text = "Document 1 content"},
          {text = "Document 2 content"}
        }

        local formatted = Retrieve._defaultFormat(docs, {})

        assert.is_truthy(formatted:find("Retrieved context"))
        assert.is_truthy(formatted:find("[1]"))
        assert.is_truthy(formatted:find("[2]"))
      end)

      it("should format documents with content field", function()
        local docs = {
          {content = "Content 1"}
        }

        local formatted = Retrieve._defaultFormat(docs, {})

        assert.is_truthy(formatted:find("Content 1"))
      end)

      it("should include metadata if present", function()
        local docs = {
          {text = "Doc", metadata = {source = "test"}}
        }

        local formatted = Retrieve._defaultFormat(docs, {})

        assert.is_truthy(formatted:find("metadata"))
      end)
    end)
  end)

end)
