-- dslua/agents/a2a.lua
-- A2A (Agent-to-Agent) Protocol - Multi-agent coordination and communication

local M = {}

-- =============================================================================
-- Message - A2A communication message
-- =============================================================================

M.Message = {}
M.Message.__index = M.Message

function M.Message.new(sender, receiver, content, opts)
  opts = opts or {}

  local self = {
    id = opts.id or tostring(os.time()) .. "_" .. tostring(math.random(1, 10000)),
    sender = sender,
    receiver = receiver,
    content = content,
    type = opts.type or "inform",
    timestamp = opts.timestamp or os.time(),
    reply_to = opts.reply_to,
    metadata = opts.metadata or {}
  }
  setmetatable(self, M.Message)
  return self
end

function M.Message:Reply(content, opts)
  opts = opts or {}
  opts.reply_to = self.id
  return M.Message.new(self.receiver, self.sender, content, opts)
end

function M.Message:Forward(to, opts)
  opts = opts or {}
  opts.reply_to = self.reply_to
  return M.Message.new(self.sender, to, self.content, opts)
end

function M.Message:Id()
  return self.id
end

function M.Message:Sender()
  return self.sender
end

function M.Message:Receiver()
  return self.receiver
end

function M.Message:Content()
  return self.content
end

function M.Message:Type()
  return self.type
end

-- =============================================================================
-- MessageQueue - Message queue for agent
-- =============================================================================

M.MessageQueue = {}
M.MessageQueue.__index = M.MessageQueue

function M.MessageQueue.new(agent_id)
  local self = {
    _agent_id = agent_id,
    _messages = {},
    _pending_replies = {},
    _handlers = {}
  }
  setmetatable(self, M.MessageQueue)
  return self
end

function M.MessageQueue:Push(message)
  -- Allow broadcast messages (receiver = "*")
  if message.receiver ~= "*" and message.receiver ~= self._agent_id then
    error("Message receiver mismatch: expected " .. self._agent_id .. ", got " .. message.receiver)
  end

  table.insert(self._messages, message)

  -- If this is a reply, resolve pending
  if message.reply_to then
    self:_resolvePendingReply(message.reply_to, message)
  end

  return self
end

function M.MessageQueue:Pop(filter)
  filter = filter or function() return true end

  for i, message in ipairs(self._messages) do
    if filter(message) then
      table.remove(self._messages, i)
      return message
    end
  end

  return nil
end

function M.MessageQueue:Peek(filter)
  filter = filter or function() return true end

  for _, message in ipairs(self._messages) do
    if filter(message) then
      return message
    end
  end

  return nil
end

function M.MessageQueue:Count(filter)
  filter = filter or function() return true end

  local count = 0
  for _, message in ipairs(self._messages) do
    if filter(message) then
      count = count + 1
    end
  end

  return count
end

function M.MessageQueue:AwaitReply(message_id, timeout)
  timeout = timeout or 30
  local start_time = os.time()

  while os.time() - start_time < timeout do
    if self._pending_replies[message_id] then
      local reply = self._pending_replies[message_id]
      self._pending_replies[message_id] = nil
      return reply
    end
  end

  return nil, "timeout"
end

function M.MessageQueue:RegisterHandler(message_type, handler)
  self._handlers[message_type] = handler
end

function M.MessageQueue:Handle(message)
  local handler = self._handlers[message.type]

  if handler then
    return handler(message)
  else
    -- Default handler: just return message
    return message
  end
end

function M.MessageQueue:_resolvePendingReply(message_id, reply)
  self._pending_replies[message_id] = reply
end

function M.MessageQueue:Clear()
  self._messages = {}
end

-- =============================================================================
-- Agent - A2A participant
-- =============================================================================

M.Agent = {}
M.Agent.__index = M.Agent

function M.Agent.new(id, opts)
  opts = opts or {}

  local self = {
    id = id,
    name = opts.name or id,
    role = opts.role or "participant",
    capabilities = opts.capabilities or {},
    state = opts.state or {},
    queue = M.MessageQueue.new(id),
    protocol = nil,  -- Set by Protocol
    running = false
  }
  setmetatable(self, M.Agent)
  return self
end

function M.Agent:Start()
  self.running = true
  return self
end

function M.Agent:Stop()
  self.running = false
  return self
end

function M.Agent:IsRunning()
  return self.running
end

function M.Agent:Send(to, content, opts)
  if not self.protocol then
    error("Agent not registered with a protocol")
  end

  local message = M.Message.new(self.id, to, content, opts)
  return self.protocol:Send(message)
end

function M.Agent:ReplyTo(message, content, opts)
  local reply = message:Reply(content, opts)
  return self:Send(reply.receiver, reply.content, reply)
end

function M.Agent:Broadcast(content, opts)
  if not self.protocol then
    error("Agent not registered with a protocol")
  end

  local message = M.Message.new(self.id, "*", content, opts)
  return self.protocol:Broadcast(message)
end

function M.Agent:Receive(filter)
  while self.running do
    local message = self.queue:Pop(filter)

    if message then
      return self:Handle(message)
    end
  end

  return nil
end

function M.Agent:Peek(filter)
  return self.queue:Peek(filter)
end

function M.Agent:Handle(message)
  return self.queue:Handle(message)
end

function M.Agent:AwaitReply(message_id, timeout)
  return self.queue:AwaitReply(message_id, timeout)
end

function M.Agent:RegisterHandler(message_type, handler)
  self.queue:RegisterHandler(message_type, handler)
end

function M.Agent:Id()
  return self.id
end

function M.Agent:Name()
  return self.name
end

function M.Agent:Role()
  return self.role
end

function M.Agent:State()
  return self.state
end

function M.Agent:SetState(key, value)
  self.state[key] = value
  return self
end

function M.Agent:GetState(key)
  return self.state[key]
end

-- =============================================================================
-- Protocol - A2A communication protocol
-- =============================================================================

M.Protocol = {}
M.Protocol.__index = M.Protocol

function M.Protocol.new(opts)
  opts = opts or {}

  local self = {
    name = opts.name or "a2a_protocol",
    agents = {},
    message_log = {},
    max_log_size = opts.max_log_size or 10000,
    timeout = opts.timeout or 30,
    running = false
  }
  setmetatable(self, M.Protocol)
  return self
end

function M.Protocol:Register(agent)
  if self.agents[agent:Id()] then
    error("Agent already registered: " .. agent:Id())
  end

  self.agents[agent:Id()] = agent
  agent.protocol = self

  return self
end

function M.Protocol:Unregister(agent_id)
  local agent = self.agents[agent_id]

  if agent then
    agent.protocol = nil
    self.agents[agent_id] = nil
  end

  return self
end

function M.Protocol:Get(agent_id)
  return self.agents[agent_id]
end

function M.Protocol:List(filter)
  filter = filter or function() return true end

  local result = {}
  for id, agent in pairs(self.agents) do
    if filter(agent) then
      table.insert(result, agent)
    end
  end

  return result
end

function M.Protocol:Send(message)
  -- Validate message
  if not message.receiver then
    error("Message receiver is required")
  end

  -- Log message
  self:_logMessage(message)

  -- Broadcast
  if message.receiver == "*" then
    return self:Broadcast(message)
  end

  -- Unicast
  local receiver = self.agents[message.receiver]

  if not receiver then
    return nil, "Receiver not found: " .. message.receiver
  end

  receiver.queue:Push(message)

  return {
    sent = true,
    message_id = message.id,
    receiver = message.receiver
  }
end

function M.Protocol:Broadcast(message)
  local sent_count = 0
  local failures = {}

  for id, agent in pairs(self.agents) do
    -- Skip sender
    if id ~= message.sender then
      local success = agent.queue:Push(message)
      if success then
        sent_count = sent_count + 1
      else
        table.insert(failures, id)
      end
    end
  end

  return {
    sent = true,
    broadcast = true,
    message_id = message.id,
    sent_count = sent_count,
    failures = failures
  }
end

function M.Protocol:Multicast(messages)
  local results = {}

  for _, message in ipairs(messages) do
    local result, err = self:Send(message)
    results[message.id] = {
      result = result,
      error = err
    }
  end

  return results
end

function M.Protocol:CreateConversation(participants, opts)
  opts = opts or {}

  local conversation = {
    id = opts.id or tostring(os.time()) .. "_conv",
    participants = {},
    started = os.time(),
    metadata = opts.metadata or {}
  }

  -- Register participants
  for _, participant_id in ipairs(participants) do
    local agent = self.agents[participant_id]

    if not agent then
      error("Participant not found: " .. participant_id)
    end

    table.insert(conversation.participants, participant_id)
  end

  return conversation
end

function M.Protocol:Route(message, router_fn)
  -- Custom routing logic
  local receivers = router_fn(message, self.agents)

  if type(receivers) == "string" then
    return self:Send(M.Message.new(message.sender, receivers, message.content))
  elseif type(receivers) == "table" then
    local results = {}
    for _, receiver in ipairs(receivers) do
      local result = self:Send(M.Message.new(message.sender, receiver, message.content))
      table.insert(results, result)
    end
    return results
  else
    return nil, "Router must return string or table"
  end
end

function M.Protocol:GetMetrics()
  local total_messages = #self.message_log
  local messages_by_type = {}
  local messages_by_sender = {}

  for _, msg in ipairs(self.message_log) do
    messages_by_type[msg.type] = (messages_by_type[msg.type] or 0) + 1
    messages_by_sender[msg.sender] = (messages_by_sender[msg.sender] or 0) + 1
  end

  return {
    total_messages = total_messages,
    messages_by_type = messages_by_type,
    messages_by_sender = messages_by_sender,
    active_agents = self:_countActiveAgents()
  }
end

function M.Protocol:_logMessage(message)
  table.insert(self.message_log, {
    id = message.id,
    sender = message.sender,
    receiver = message.receiver,
    type = message.type,
    timestamp = message.timestamp,
    logged_at = os.time()
  })

  -- Prune if necessary
  if #self.message_log > self.max_log_size then
    table.remove(self.message_log, 1)
  end
end

function M.Protocol:_countActiveAgents()
  local count = 0
  for _, agent in pairs(self.agents) do
    if agent:IsRunning() then
      count = count + 1
    end
  end
  return count
end

function M.Protocol:StartAll()
  for _, agent in pairs(self.agents) do
    agent:Start()
  end
  self.running = true
  return self
end

function M.Protocol:StopAll()
  self.running = false
  for _, agent in pairs(self.agents) do
    agent:Stop()
  end
  return self
end

function M.Protocol:IsRunning()
  return self.running
end

-- =============================================================================
-- Helper Functions
-- =============================================================================

-- Create a new agent with default configuration
function M.create_agent(id, opts)
  return M.Agent.new(id, opts)
end

-- Create a new protocol
function M.create_protocol(opts)
  return M.Protocol.new(opts)
end

-- Create message helpers
function M.message(sender, receiver, content, opts)
  return M.Message.new(sender, receiver, content, opts)
end

function M.request(sender, receiver, content, opts)
  opts = opts or {}
  opts.type = "request"
  return M.Message.new(sender, receiver, content, opts)
end

function M.response(sender, receiver, content, opts)
  opts = opts or {}
  opts.type = "response"
  return M.Message.new(sender, receiver, content, opts)
end

function M.notify(sender, receiver, content, opts)
  opts = opts or {}
  opts.type = "notify"
  return M.Message.new(sender, receiver, content, opts)
end

return M
