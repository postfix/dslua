-- dslua/evaluate/session_logger.lua
-- Session logging for execution trace analysis

local M = {}

-- =============================================================================
-- Session Logger
-- =============================================================================

M.SessionLogger = {}
M.SessionLogger.__index = M.SessionLogger

function M.SessionLogger.new(opts)
  opts = opts or {}

  local self = {
    enabled = opts.enabled ~= false,
    log_dir = opts.log_dir or "/tmp/dslua_sessions",
    current_session = nil,
    session_data = {}
  }

  setmetatable(self, M.SessionLogger)
  return self
end

-- Start a new session
function M.SessionLogger:start_session(session_id, metadata)
  if not self.enabled then
    return nil
  end

  self.current_session = session_id or os.date("%Y%m%d_%H%M%S")
  self.session_data[self.current_session] = {
    id = self.current_session,
    metadata = metadata or {},
    start_time = os.time(),
    events = {},
    stats = {
      event_count = 0,
      error_count = 0,
      warning_count = 0
    }
  }

  return self.current_session
end

-- Log an event
function M.SessionLogger:log(event_type, data)
  if not self.enabled or not self.current_session then
    return
  end

  local session = self.session_data[self.current_session]
  if not session then
    return
  end

  local event = {
    type = event_type,
    timestamp = os.time(),
    time_offset = os.time() - session.start_time,
    data = data or {}
  }

  table.insert(session.events, event)
  session.stats.event_count = session.stats.event_count + 1

  -- Track errors and warnings
  if event_type == "error" then
    session.stats.error_count = session.stats.error_count + 1
  elseif event_type == "warning" then
    session.stats.warning_count = session.stats.warning_count + 1
  end
end

-- End current session
function M.SessionLogger:end_session(result)
  if not self.enabled or not self.current_session then
    return nil
  end

  local session = self.session_data[self.current_session]
  if session then
    session.end_time = os.time()
    session.duration = session.end_time - session.start_time
    session.result = result
  end

  local session_id = self.current_session
  self.current_session = nil

  return session_id
end

-- Get session data
function M.SessionLogger:get_session(session_id)
  return self.session_data[session_id]
end

-- List all sessions
function M.SessionLogger:list_sessions()
  local sessions = {}
  for id, session in pairs(self.session_data) do
    table.insert(sessions, {
      id = id,
      start_time = session.start_time,
      duration = session.duration or (os.time() - session.start_time),
      event_count = session.stats.event_count,
      metadata = session.metadata
    })
  end

  -- Sort by start time (newest first)
  table.sort(sessions, function(a, b)
    return a.start_time > b.start_time
  end)

  return sessions
end

-- Save session to file
function M.SessionLogger:save_session(session_id, filename)
  local session = self.session_data[session_id]
  if not session then
    return nil, "Session not found"
  end

  filename = filename or self.log_dir .. "/" .. session_id .. ".json"

  -- Create directory if needed
  local mkdir_cmd = string.format("mkdir -p %s", self.log_dir)
  os.execute(mkdir_cmd)

  -- Convert to JSON
  local json = require("cjson")
  local ok, content = pcall(function()
    return json.encode(session)
  end)

  if not ok then
    return nil, content or "JSON encoding failed"
  end

  -- Write to file
  local file = io.open(filename, "w")
  if not file then
    return nil, "Failed to open file: " .. filename
  end

  file:write(content)
  file:close()

  return filename
end

-- Load session from file
function M.SessionLogger:load_session(filename)
  filename = filename or self.log_dir .. "/" .. self.current_session .. ".json"

  local file = io.open(filename, "r")
  if not file then
    return nil, "Failed to open file: " .. filename
  end

  local content = file:read("*all")
  file:close()

  local json = require("cjson")
  local ok, session = pcall(function()
    return json.decode(content)
  end)

  if not ok then
    return nil, session or "JSON decoding failed"
  end

  self.session_data[session.id] = session
  return session
end

-- =============================================================================
-- Session Viewer
-- =============================================================================

M.SessionViewer = {}
M.SessionViewer.__index = M.SessionViewer

function M.SessionViewer.new(logger)
  local self = {
    logger = logger or M.SessionLogger.new()
  }

  setmetatable(self, M.SessionViewer)
  return self
end

-- Display session summary
function M.SessionViewer:display_summary(session_id)
  local session = self.logger:get_session(session_id)
  if not session then
    return nil, "Session not found"
  end

  local lines = {}
  table.insert(lines, "")
  table.insert(lines, "=== Session Summary ===")
  table.insert(lines, string.format("ID: %s", session.id))
  table.insert(lines, string.format("Start: %s", os.date("%Y-%m-%d %H:%M:%S", session.start_time)))
  table.insert(lines, string.format("Duration: %d seconds", session.duration or 0))
  table.insert(lines, "")
  table.insert(lines, "Statistics:")
  table.insert(lines, string.format("  Events: %d", session.stats.event_count))
  table.insert(lines, string.format("  Errors: %d", session.stats.error_count))
  table.insert(lines, string.format("  Warnings: %d", session.stats.warning_count))
  table.insert(lines, "")

  if session.metadata and next(session.metadata) ~= nil then
    table.insert(lines, "Metadata:")
    for k, v in pairs(session.metadata) do
      table.insert(lines, string.format("  %s: %s", k, tostring(v)))
    end
    table.insert(lines, "")
  end

  return table.concat(lines, "\n")
end

-- Display session events
function M.SessionViewer:display_events(session_id, opts)
  opts = opts or {}

  local session = self.logger:get_session(session_id)
  if not session then
    return nil, "Session not found"
  end

  local lines = {}
  table.insert(lines, "")
  table.insert(lines, "=== Session Events ===")
  table.insert(lines, string.format("Session: %s", session_id))
  table.insert(lines, "")

  -- Filter by event type if specified
  local events = session.events
  if opts.event_type then
    local filtered = {}
    for _, event in ipairs(events) do
      if event.type == opts.event_type then
        table.insert(filtered, event)
      end
    end
    events = filtered
  end

  -- Limit events if specified
  local max_events = opts.max_events or #events
  local start_idx = opts.start_idx or 1

  for i = start_idx, math.min(start_idx + max_events - 1, #events) do
    local event = events[i]
    table.insert(lines, string.format("[%d] %s (+%ds)",
      i, event.type, event.time_offset))

    -- Display event data
    if event.data and next(event.data) ~= nil then
      for k, v in pairs(event.data) do
        local value = tostring(v)
        -- Truncate long values
        if #value > 100 then
          value = value:sub(1, 97) .. "..."
        end
        table.insert(lines, string.format("    %s: %s", k, value))
      end
    end
    table.insert(lines, "")
  end

  if #events > max_events then
    table.insert(lines, string.format("(%d more events...)", #events - max_events))
  end

  return table.concat(lines, "\n")
end

-- Display timeline view
function M.SessionViewer:display_timeline(session_id)
  local session = self.logger:get_session(session_id)
  if not session then
    return nil, "Session not found"
  end

  if #session.events == 0 then
    return "No events to display"
  end

  local lines = {}
  table.insert(lines, "")
  table.insert(lines, "=== Session Timeline ===")
  table.insert(lines, string.format("Session: %s", session_id))
  table.insert(lines, "")

  -- Group events by type
  local timeline = {}
  for _, event in ipairs(session.events) do
    if not timeline[event.type] then
      timeline[event.type] = {}
    end
    table.insert(timeline[event.type], event)
  end

  -- Display timeline
  for event_type, events in pairs(timeline) do
    table.insert(lines, string.format("%s (%d events)", event_type, #events))
    for _, event in ipairs(events) do
      table.insert(lines, string.format("  +%ds: %s",
        event.time_offset,
        self:_format_event_data(event.data)))
    end
    table.insert(lines, "")
  end

  return table.concat(lines, "\n")
end

-- Display errors and warnings
function M.SessionViewer:display_issues(session_id)
  local session = self.logger:get_session(session_id)
  if not session then
    return nil, "Session not found"
  end

  local lines = {}
  table.insert(lines, "")
  table.insert(lines, "=== Issues ===")
  table.insert(lines, string.format("Session: %s", session_id))
  table.insert(lines, "")

  local has_issues = false

  -- Display errors
  for _, event in ipairs(session.events) do
    if event.type == "error" then
      has_issues = true
      table.insert(lines, string.format("[ERROR] +%ds", event.time_offset))
      if event.data then
        if event.data.message then
          table.insert(lines, string.format("  Message: %s", event.data.message))
        end
        if event.data.trace then
          table.insert(lines, string.format("  Trace: %s", event.data.trace))
        end
      end
      table.insert(lines, "")
    end
  end

  -- Display warnings
  for _, event in ipairs(session.events) do
    if event.type == "warning" then
      has_issues = true
      table.insert(lines, string.format("[WARNING] +%ds", event.time_offset))
      if event.data then
        if event.data.message then
          table.insert(lines, string.format("  Message: %s", event.data.message))
        end
      end
      table.insert(lines, "")
    end
  end

  if not has_issues then
    table.insert(lines, "No issues found.")
  end

  return table.concat(lines, "\n")
end

-- Format event data for display
function M.SessionViewer:_format_event_data(data)
  if not data then
    return ""
  end

  local parts = {}
  for k, v in pairs(data) do
    local value = tostring(v)
    if #value > 50 then
      value = value:sub(1, 47) .. "..."
    end
    table.insert(parts, string.format("%s=%s", k, value))
  end

  return table.concat(parts, " ")
end

-- =============================================================================
-- Helper Functions
-- =============================================================================

function M.session_logger(opts)
  return M.SessionLogger.new(opts)
end

function M.session_viewer(logger)
  return M.SessionViewer.new(logger)
end

return M
