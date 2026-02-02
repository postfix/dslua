-- dslua/modules/rlm.lua
-- RLM: Retrieve Language Model - Context exploration for RAG

local M = {}
local Base = require("dslua.modules.base")
local Signature = require("dslua.core.signature")
local Field = require("dslua.core.field")

M.__index = M
setmetatable(M, {__index = Base})

-- =============================================================================
-- RLM.new - Create RLM module
-- =============================================================================

function M.new(signature, opts)
  opts = opts or {}

  local self = Base.new(signature)
  setmetatable(self, M)

  self._retriever = opts.retriever
  self._max_passes = opts.max_passes or 3
  self._threshold = opts.threshold or 0.5
  self._verbose = opts.verbose or false

  return self
end

-- =============================================================================
-- Process - Retrieve and explore context iteratively
-- =============================================================================

function M:Process(ctx, input)
  local query = self:_buildQuery(input)
  local all_retrieved = {}
  local current_context = ""
  local actual_passes = 0

  -- Multiple retrieval passes
  for pass = 1, self._max_passes do
    if self._verbose then
      print(string.format("[RLM] Pass %d", pass))
    end

    -- Retrieve documents
    local docs = {}
    if self._retriever then
      local ok, result = pcall(function()
        return self._retriever:Retrieve(query, {
          max_docs = 5,
          min_similarity = self._threshold
        })
      end)

      if ok and result then
        docs = result
      end
    end

    if #docs == 0 then
      if self._verbose then
        print("[RLM] No more documents found")
      end
      break
    end

    -- Check if we have new information
    local new_info = self:_extractNewInfo(docs, all_retrieved)

    if not new_info then
      if self._verbose then
        print("[RLM] No new information, stopping")
      end
      break
    end

    -- Add to retrieved set
    for _, doc in ipairs(docs) do
      local doc_id = doc.id or doc.text
      if not all_retrieved[doc_id] then
        all_retrieved[doc_id] = doc
      end
    end

    -- Update context with new documents
    current_context = self:_formatContext(docs, pass)

    -- Refine query based on retrieved context
    query = self:_refineQuery(query, docs, input)

    actual_passes = pass

    if self._verbose then
      print(string.format("[RLM] Retrieved %d documents, %d unique",
        #docs, self:_countUnique(all_retrieved)))
    end
  end

  -- Augment input with final context
  local augmented = {}
  for k, v in pairs(input) do
    augmented[k] = v
  end

  augmented.rlm_passes = actual_passes
  if current_context and #current_context > 0 then
    augmented.context = current_context
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
  local query_fields = {"query", "question", "text", "input", "prompt", "instruction"}
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

function M:_extractNewInfo(docs, retrieved)
  -- Check if documents contain new information
  local new_count = 0

  for _, doc in ipairs(docs) do
    local doc_id = doc.id or doc.text
    if not retrieved[doc_id] then
      new_count = new_count + 1
    end
  end

  return new_count > 0
end

function M:_countUnique(retrieved)
  local count = 0
  for _ in pairs(retrieved) do
    count = count + 1
  end
  return count
end

function M:_formatContext(docs, pass)
  if #docs == 0 then
    return ""
  end

  local parts = {}
  table.insert(parts, string.format("[Pass %d]", pass))

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
        table.insert(parts, string.format("  (meta: %s)", table.concat(meta_str, ", ")))
      end
    end
  end

  return table.concat(parts, "\n")
end

function M:_refineQuery(query, docs, original_input)
  -- Refine query based on retrieved context
  local refined = query

  -- Extract key terms from documents
  local key_terms = {}
  for _, doc in ipairs(docs) do
    local text = doc.text or doc.content or ""

    -- Extract important terms (simple heuristic: longer words)
    for word in text:gmatch("[%w]+") do
      if #word > 4 then  -- Only longer words
        table.insert(key_terms, word)
      end
    end
  end

  -- If we found key terms, augment query
  if #key_terms > 0 then
    local unique_terms = {}
    for _, term in ipairs(key_terms) do
      unique_terms[term] = true
    end

    local terms_list = {}
    for term, _ in pairs(unique_terms) do
      table.insert(terms_list, term)
    end

    if #terms_list > 0 then
      refined = query .. " " .. table.concat(terms_list, " ")
    end
  end

  return refined
end

-- =============================================================================
-- RLMRetriever - Advanced retriever with exploration
-- =============================================================================

M.RLMRetriever = {}
M.RLMRetriever.__index = M.RLMRetriever

function M.RLMRetriever.new(opts)
  opts = opts or {}

  local self = {
    base_retriever = opts.base_retriever,
    max_expansions = opts.max_expansions or 3,
    expansion_threshold = opts.expansion_threshold or 0.3,
    context_window = opts.context_window or 5
  }
  setmetatable(self, M.RLMRetriever)
  return self
end

function M.RLMRetriever:Retrieve(query, opts)
  opts = opts or {}

  -- Initial retrieval
  local results = {}
  if self.base_retriever then
    local ok, result = pcall(function()
      return self.base_retriever:Retrieve(query, opts)
    end)

    if ok and result then
      results = result
    end
  end

  if #results == 0 then
    return results
  end

  -- Query expansion based on initial results
  local expanded_query = self:_expandQuery(query, results)

  if expanded_query ~= query then
    -- Retrieve with expanded query
    local expansion_results = {}
    if self.base_retriever then
      local ok, result = pcall(function()
        return self.base_retriever:Retrieve(expanded_query, opts)
      end)

      if ok and result then
        expansion_results = result
      end
    end

    -- Merge results, removing duplicates
    local seen = {}
    local merged = {}

    for _, doc in ipairs(results) do
      local doc_id = doc.id or doc.text
      if not seen[doc_id] then
        table.insert(merged, doc)
        seen[doc_id] = true
      end
    end

    for _, doc in ipairs(expansion_results) do
      local doc_id = doc.id or doc.text
      if not seen[doc_id] then
        table.insert(merged, doc)
        seen[doc_id] = true
      end
    end

    results = merged
  end

  return results
end

function M.RLMRetriever:_expandQuery(query, results)
  -- Expand query based on retrieved context
  local expansion_terms = {}

  -- Extract terms from top results
  local top_n = math.min(self.context_window, #results)
  for i = 1, top_n do
    local text = results[i].text or results[i].content or ""

    -- Extract important terms
    for word in text:gmatch("[%w]+") do
      if #word > 4 then
        expansion_terms[word] = (expansion_terms[word] or 0) + 1
      end
    end
  end

  -- If enough expansion terms found, expand query
  if #results >= self.expansion_threshold * 10 then  -- Only expand if good results
    local sorted_terms = {}
    for term, count in pairs(expansion_terms) do
      table.insert(sorted_terms, {term = term, count = count})
    end

    table.sort(sorted_terms, function(a, b)
      return b.count > a.count
    end)

    -- Add top expansion terms to query
    local top_terms = {}
    for i = 1, math.min(3, #sorted_terms) do
      table.insert(top_terms, sorted_terms[i].term)
    end

    if #top_terms > 0 then
      return query .. " " .. table.concat(top_terms, " ")
    end
  end

  return query
end

-- =============================================================================
-- ContextBuilder - Build enhanced context for RAG
-- =============================================================================

M.ContextBuilder = {}
M.ContextBuilder.__index = M.ContextBuilder

function M.ContextBuilder.new(opts)
  opts = opts or {}

  local self = {
    max_length = opts.max_length or 2000,
    include_metadata = opts.include_metadata or false,
    format = opts.format or "sequential"  -- "sequential", "clustered", "hierarchical"
  }
  setmetatable(self, M.ContextBuilder)
  return self
end

function M.ContextBuilder:Build(documents, query)
  local formatted = ""

  if self.format == "sequential" then
    formatted = self:_buildSequential(documents, query)
  elseif self.format == "clustered" then
    formatted = self:_buildClustered(documents, query)
  elseif self.format == "hierarchical" then
    formatted = self:_buildHierarchical(documents, query)
  end

  -- Truncate if too long
  if self.max_length > 0 and #formatted > self.max_length then
    formatted = string.sub(formatted, 1, self.max_length) .. "..."
  end

  return formatted
end

function M.ContextBuilder:_buildSequential(documents, query)
  local parts = {}

  table.insert(parts, "Query: " .. query)
  table.insert(parts, "")
  table.insert(parts, "Relevant Context:")

  for i, doc in ipairs(documents) do
    local text = doc.text or doc.content or ""

    if self.include_metadata and doc.metadata then
      local meta_str = {}
      for k, v in pairs(doc.metadata) do
        table.insert(meta_str, string.format("%s=%s", k, tostring(v)))
      end
      table.insert(parts, string.format("[%d] %s (meta: %s)", i, text, table.concat(meta_str, ", ")))
    else
      table.insert(parts, string.format("[%d] %s", i, text))
    end
  end

  return table.concat(parts, "\n")
end

function M.ContextBuilder:_buildClustered(documents, query)
  local parts = {}

  table.insert(parts, "Query: " .. query)
  table.insert(parts, "")

  -- Simple clustering by similarity (could be enhanced)
  local clusters = self:_clusterBySimilarity(documents)

  for cluster_id, cluster in ipairs(clusters) do
    table.insert(parts, string.format("Cluster %d:", cluster_id))

    for _, doc in ipairs(cluster) do
      local text = doc.text or doc.content or ""
      table.insert(parts, string.format("  - %s", text))
    end

    table.insert(parts, "")
  end

  return table.concat(parts, "\n")
end

function M.ContextBuilder:_buildHierarchical(documents, query)
  local parts = {}

  table.insert(parts, "Query: " .. query)
  table.insert(parts, "")

  -- Build hierarchy by similarity/relevance
  local sorted = self:_sortByRelevance(documents, query)

  for level = 1, math.ceil(#sorted / 3) do
    local start_idx = (level - 1) * 3 + 1
    local end_idx = math.min(level * 3, #sorted)

    table.insert(parts, string.format("Level %d:", level))

    for i = start_idx, end_idx do
      if sorted[i] then
        local text = sorted[i].text or sorted[i].content or ""
        table.insert(parts, string.format("  - %s", text))
      end
    end

    table.insert(parts, "")
  end

  return table.concat(parts, "\n")
end

function M.ContextBuilder:_clusterBySimilarity(documents)
  -- Simple clustering by similarity
  local clusters = {}

  for _, doc in ipairs(documents) do
    local placed = false

    -- Try to add to existing cluster
    for _, cluster in ipairs(clusters) do
      if #cluster < 3 and self:_similarToCluster(doc, cluster) then
        table.insert(cluster, doc)
        placed = true
        break
      end
    end

    -- Create new cluster if not placed
    if not placed then
      table.insert(clusters, {doc})
    end
  end

  return clusters
end

function M.ContextBuilder:_similarToCluster(doc, cluster)
  -- Check if document is similar to cluster
  for _, cluster_doc in ipairs(cluster) do
    local similarity = self:_jaccardSimilarity(
      doc.text or doc.content or "",
      cluster_doc.text or cluster_doc.content or ""
    )

    if similarity > 0.3 then
      return true
    end
  end

  return false
end

function M.ContextBuilder:_sortByRelevance(documents, query)
  -- Sort documents by relevance to query
  local scored = {}

  for _, doc in ipairs(documents) do
    local text = doc.text or doc.content or ""
    local score = self:_relevanceScore(query, text)

    table.insert(scored, {doc = doc, score = score})
  end

  table.sort(scored, function(a, b)
    return b.score > a.score
  end)

  local sorted = {}
  for _, item in ipairs(scored) do
    table.insert(sorted, item.doc)
  end

  return sorted
end

function M.ContextBuilder:_jaccardSimilarity(text1, text2)
  local words1 = self:_tokenize(text1)
  local words2 = self:_tokenize(text2)

  local intersection = 0
  for w1, _ in pairs(words1) do
    if words2[w1] then
      intersection = intersection + 1
    end
  end

  local union = 0
  for _ in pairs(words1) do union = union + 1 end
  for _ in pairs(words2) do union = union + 1 end

  if union == 0 then
    return 0
  end

  return intersection / union
end

function M.ContextBuilder:_relevanceScore(query, text)
  -- Calculate relevance score
  local query_words = self:_tokenize(query)
  local text_words = self:_tokenize(text)

  local score = 0
  for word, _ in pairs(query_words) do
    if text_words[word] then
      score = score + 1
    end
  end

  return score / #query_words
end

function M.ContextBuilder:_tokenize(text)
  local tokens = {}
  for word in text:gmatch("[%w]+") do
    tokens[word] = true
  end
  return tokens
end

-- =============================================================================
-- Helper Functions
-- =============================================================================

function M.rlm_retriever(opts)
  return M.RLMRetriever.new(opts)
end

function M.context_builder(opts)
  return M.ContextBuilder.new(opts)
end

return M
