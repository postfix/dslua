-- dslua/modules/retrieve.lua
-- Retrieve Module - Retrieval-Augmented Generation (RAG)

local M = {}
local Base = require("dslua.modules.base")
local Signature = require("dslua.core.signature")
local Field = require("dslua.core.field")

M.__index = M
setmetatable(M, {__index = Base})

-- =============================================================================
-- Retrieve.new - Create retrieval module
-- =============================================================================

function M.new(signature, opts)
  opts = opts or {}

  local self = Base.new(signature)
  setmetatable(self, M)

  self._retriever = opts.retriever
  self._max_docs = opts.max_docs or 5
  self._min_similarity = opts.min_similarity or 0.0
  self._format_fn = opts.format_fn or M._defaultFormat
  self._return_metadata = opts.return_metadata or false

  return self
end

-- =============================================================================
-- Process - Retrieve context and augment input
-- =============================================================================

function M:Process(ctx, input)
  local query = self:_buildQuery(input)

  -- Retrieve documents
  local ok, docs = pcall(function()
    return self._retriever:Retrieve(query, {
      max_docs = self._max_docs,
      min_similarity = self._min_similarity
    })
  end)

  if not ok or not docs or #docs == 0 then
    -- No retrieval found, return original input
    return input
  end

  -- Format retrieved context
  local formatted = self._format_fn(docs, input)

  -- Augment input with retrieved context
  local augmented = {}
  for k, v in pairs(input) do
    augmented[k] = v
  end
  augmented.context = formatted

  if self._return_metadata then
    augmented.retrieval_metadata = {
      num_docs = #docs,
      query = query,
      timestamps = docs[1] and docs[1].timestamps or {}
    }
  end

  return augmented
end

-- =============================================================================
-- Private Helper Methods
-- =============================================================================

function M:_buildQuery(input)
  -- Extract query from input
  local query_parts = {}

  -- Try common query field names
  local query_fields = {"query", "question", "text", "input", "prompt"}
  for _, field in ipairs(query_fields) do
    if input[field] then
      table.insert(query_parts, tostring(input[field]))
    end
  end

  -- Fall back to all input values
  if #query_parts == 0 then
    for _, v in pairs(input) do
      if type(v) == "string" then
        table.insert(query_parts, v)
      end
    end
  end

  return table.concat(query_parts, " ")
end

function M._defaultFormat(docs, input)
  if #docs == 0 then
    return ""
  end

  local parts = {}
  table.insert(parts, "Retrieved context:")

  for i, doc in ipairs(docs) do
    if doc.text then
      table.insert(parts, string.format("[%d] %s", i, doc.text))
    elseif doc.content then
      table.insert(parts, string.format("[%d] %s", i, doc.content))
    end

    -- Add metadata if available
    if doc.metadata and next(doc.metadata) ~= nil then
      local meta_str = {}
      for k, v in pairs(doc.metadata) do
        table.insert(meta_str, string.format("%s=%s", k, tostring(v)))
      end
      if #meta_str > 0 then
        table.insert(parts, string.format("  (metadata: %s)", table.concat(meta_str, ", ")))
      end
    end
  end

  return table.concat(parts, "\n")
end

-- =============================================================================
-- VectorRetriever - Simple in-memory vector store retriever
-- =============================================================================

M.VectorRetriever = {}
M.VectorRetriever.__index = M.VectorRetriever

function M.VectorRetriever.new(opts)
  opts = opts or {}

  local self = {
    documents = {},  -- {id, text, embedding, metadata}
    vector_size = opts.vector_size or 384,  -- Common embedding size
    similarity_fn = opts.similarity_fn or M._cosineSimilarity,
    case_sensitive = opts.case_sensitive ~= false
  }
  setmetatable(self, M.VectorRetriever)
  return self
end

function M.VectorRetriever:AddDocument(id, text, embedding, metadata)
  table.insert(self.documents, {
    id = id,
    text = text,
    embedding = embedding,
    metadata = metadata or {}
  })
  return self
end

function M.VectorRetriever:Retrieve(query, opts)
  opts = opts or {}

  if #self.documents == 0 then
    return {}, "No documents in store"
  end

  -- If query is string, need to get embedding (simulate for now)
  local query_embedding = opts.query_embedding
  if type(query) == "string" then
    if not query_embedding then
      -- In production, would call embedding model here
      -- For now, use simple bag-of-words approximation
      query_embedding = self:_simpleEmbed(query)
    end
  elseif type(query) == "table" then
    -- Query is already an embedding vector
    query_embedding = query
  end

  if not query_embedding or #query_embedding == 0 then
    return {}
  end

  -- Calculate similarities
  local results = {}
  for _, doc in ipairs(self.documents) do
    local similarity = self:_similarity(query_embedding, doc.embedding)

    if similarity >= (opts.min_similarity or 0.0) then
      table.insert(results, {
        text = doc.text,
        content = doc.text,  -- Alias
        embedding = doc.embedding,
        similarity = similarity,
        metadata = doc.metadata,
        id = doc.id,
        timestamps = {retrieved_at = os.time()}
      })
    end
  end

  -- Sort by similarity (descending)
  table.sort(results, function(a, b)
    return a.similarity > b.similarity
  end)

  -- Limit to max_docs
  local max_docs = opts.max_docs or #results
  local limited = {}
  for i = 1, math.min(max_docs, #results) do
    table.insert(limited, results[i])
  end

  return limited
end

function M.VectorRetriever:_similarity(vec1, vec2)
  if self.similarity_fn then
    return self.similarity_fn(vec1, vec2)
  end
  return M._cosineSimilarity(vec1, vec2)
end

function M._cosineSimilarity(vec1, vec2)
  -- Dot product / (magnitude1 * magnitude2)
  local dot = 0
  local mag1 = 0
  local mag2 = 0

  for i = 1, math.min(#vec1, #vec2) do
    dot = dot + (vec1[i] or 0) * (vec2[i] or 0)
    mag1 = mag1 + (vec1[i] or 0) ^ 2
    mag2 = mag2 + (vec2[i] or 0) ^ 2
  end

  mag1 = math.sqrt(mag1)
  mag2 = math.sqrt(mag2)

  if mag1 == 0 or mag2 == 0 then
    return 0
  end

  return dot / (mag1 * mag2)
end

function M.VectorRetriever:_simpleEmbed(text)
  -- Very simple word-based embedding (placeholder)
  local words = {}
  for word in text:gmatch("[%w]+") do
    table.insert(words, word)
  end

  local embedding = {}
  local hash = 0
  for i, word in ipairs(words) do
    -- Simple hash-based embedding
    hash = hash * 31 + string.byte(word, i % #word + 1)
    hash = math.floor(hash)
    table.insert(embedding, (hash % 100) / 100)
  end

  -- Pad/truncate to vector_size
  while #embedding < self.vector_size do
    table.insert(embedding, 0)
  end

  return embedding
end

-- =============================================================================
-- BM25Retriever - BM25 ranking retrieval
-- =============================================================================

M.BM25Retriever = {}
M.BM25Retriever.__index = M.BM25Retriever

function M.BM25Retriever.new(opts)
  opts = opts or {}

  local self = {
    documents = {},
    k1 = opts.k1 or 1.5,
    b = opts.b or 0.75,
    avg_doc_length = opts.avg_doc_length or 100,
    idf_cache = {},
    case_sensitive = opts.case_sensitive ~= false
  }
  setmetatable(self, M.BM25Retriever)
  return self
end

function M.BM25Retriever:AddDocument(id, text, metadata)
  -- Tokenize
  local tokens = self:_tokenize(text)

  -- Calculate document length
  local doc_length = #tokens

  table.insert(self.documents, {
    id = id,
    text = text,
    tokens = tokens,
    doc_length = doc_length,
    metadata = metadata or {},
    term_freq = self:_calculateTermFreq(tokens)
  })

  -- Update average doc length
  local total_length = 0
  for _, doc in ipairs(self.documents) do
    total_length = total_length + doc.doc_length
  end
  self.avg_doc_length = total_length / #self.documents

  -- Reset IDF cache
  self.idf_cache = {}

  return self
end

function M.BM25Retriever:Retrieve(query, opts)
  opts = opts or {}

  if #self.documents == 0 then
    return {}, "No documents in store"
  end

  local query_tokens = self:_tokenize(query)
  local max_docs = opts.max_docs or #self.documents

  -- Calculate scores for each document
  local scores = {}
  for _, doc in ipairs(self.documents) do
    local score = self:_calculateBM25(query_tokens, doc)
    table.insert(scores, {
      text = doc.text,
      content = doc.text,
      score = score,
      metadata = doc.metadata,
      id = doc.id,
      timestamps = {retrieved_at = os.time()}
    })
  end

  -- Sort by score (descending)
  table.sort(scores, function(a, b)
    return a.score > b.score
  end)

  -- Limit results
  local limited = {}
  for i = 1, math.min(max_docs, #scores) do
    table.insert(limited, scores[i])
  end

  return limited
end

function M.BM25Retriever:_tokenize(text)
  local tokens = {}
  for word in text:gmatch("[%w]+") do
    table.insert(tokens, word)
  end
  return tokens
end

function M.BM25Retriever:_calculateTermFreq(tokens)
  local tf = {}
  for _, token in ipairs(tokens) do
    tf[token] = (tf[token] or 0) + 1
  end
  return tf
end

function M.BM25Retriever:_calculateIDF(term)
  if self.idf_cache[term] then
    return self.idf_cache[term]
  end

  local doc_count = 0
  for _, doc in ipairs(self.documents) do
    if doc.term_freq[term] then
      doc_count = doc_count + 1
    end
  end

  local idf = math.log((#self.documents - doc_count + 0.5) / (doc_count + 0.5))
  self.idf_cache[term] = idf

  return idf
end

function M.BM25Retriever:_calculateBM25(query_tokens, doc)
  local score = 0

  for _, term in ipairs(query_tokens) do
    local tf = doc.term_freq[term] or 0
    local idf = self:_calculateIDF(term)

    -- BM25 formula
    local numerator = tf * (self.k1 + 1)
    local denominator = tf + self.k1 * (1 - self.b + self.b * (doc.doc_length / self.avg_doc_length))
    local term_score = idf * (numerator / denominator)

    score = score + term_score
  end

  return score
end

-- =============================================================================
-- HybridRetriever - Combine multiple retrievers
-- =============================================================================

M.HybridRetriever = {}
M.HybridRetriever.__index = M.HybridRetriever

function M.HybridRetriever.new(opts)
  opts = opts or {}

  local self = {
    retrievers = opts.retrievers or {},
    weights = opts.weights or {},
    merge_strategy = opts.merge_strategy or "score_weighted"  -- "score_weighted", "union", "interleave"
  }
  setmetatable(self, M.HybridRetriever)
  return self
end

function M.HybridRetriever:AddRetriever(retriever, weight)
  table.insert(self.retrievers, retriever)
  if weight then
    table.insert(self.weights, weight)
  end
  return self
end

function M.HybridRetriever:Retrieve(query, opts)
  opts = opts or {}

  if #self.retrievers == 0 then
    return {}, "No retrievers configured"
  end

  if self.merge_strategy == "score_weighted" then
    return self:_retrieveScoreWeighted(query, opts)
  elseif self.merge_strategy == "union" then
    return self:_retrieveUnion(query, opts)
  elseif self.merge_strategy == "interleave" then
    return self:_retrieveInterleave(query, opts)
  else
    return {}, "Unknown merge strategy: " .. self.merge_strategy
  end
end

function M.HybridRetriever:_retrieveScoreWeighted(query, opts)
  -- Collect results from all retrievers with scores
  local all_results = {}

  for i, retriever in ipairs(self.retrievers) do
    local docs, err = retriever:Retrieve(query, opts)

    if docs and #docs > 0 then
      for _, doc in ipairs(docs) do
        local doc_id = doc.id or doc.text

        if not all_results[doc_id] then
          all_results[doc_id] = {
            doc = doc,
            retrievers = {},
            total_score = 0
          }
        end

        -- Add retriever contribution
        table.insert(all_results[doc_id].retrievers, i)

        -- Weight the score
        local weight = self.weights[i] or (1 / #self.retrievers)
        local score = doc.similarity or doc.score or 1.0
        all_results[doc_id].total_score = all_results[doc_id].total_score + (score * weight)
      end
    end
  end

  -- Sort by combined score
  local sorted = {}
  for doc_id, result in pairs(all_results) do
    table.insert(sorted, result)
  end

  table.sort(sorted, function(a, b)
    return a.total_score > b.total_score
  end)

  -- Limit and return
  local max_docs = opts.max_docs or #sorted
  local limited = {}
  for i = 1, math.min(max_docs, #sorted) do
    table.insert(limited, sorted[i].doc)
  end

  return limited
end

function M.HybridRetriever:_retrieveUnion(query, opts)
  local seen_ids = {}
  local results = {}

  -- Get max_docs from each retriever
  local per_retriever_max = opts.max_docs or 5

  for _, retriever in ipairs(self.retrievers) do
    local docs, err = retriever:Retrieve(query, {max_docs = per_retriever_max})

    if docs and #docs > 0 then
      for _, doc in ipairs(docs) do
        local doc_id = doc.id or doc.text

        if not seen_ids[doc_id] then
          seen_ids[doc_id] = true
          table.insert(results, doc)
        end
      end
    end
  end

  -- Limit total
  local max_docs = opts.max_docs or #results
  local limited = {}
  for i = 1, math.min(max_docs, #results) do
    table.insert(limited, results[i])
  end

  return limited
end

function M.HybridRetriever:_retrieveInterleave(query, opts)
  local results = {}
  local max_per = opts.max_docs or 3

  -- Interleave results from each retriever
  for i, retriever in ipairs(self.retrievers) do
    local docs, err = retriever:Retrieve(query, {max_docs = max_per})

    if docs and #docs > 0 then
      for _, doc in ipairs(docs) do
        doc.retriever_index = i
        table.insert(results, doc)
      end
    end
  end

  return results
end

-- =============================================================================
-- Helper Functions
-- =============================================================================

-- Create vector retriever
function M.vector_retriever(opts)
  return M.VectorRetriever.new(opts)
end

-- Create BM25 retriever
function M.bm25_retriever(opts)
  return M.BM25Retriever.new(opts)
end

-- Create hybrid retriever
function M.hybrid_retriever(opts)
  return M.HybridRetriever.new(opts)
end

return M
