-- specs/agents/a2a_spec.lua
-- Tests for A2A (Agent-to-Agent) Protocol

describe("A2A Protocol", function()
  local A2A = require("dslua.agents.a2a")

  -- Helper to create mock agent behavior
  local function createMockAgent(id, role)
    return A2A.Agent.new(id, {
      name = id,
      role = role or "participant"
    })
  end

  describe("Message", function()
    it("should create message with required fields", function()
      local msg = A2A.Message.new("agent1", "agent2", {data = "test"})

      assert.is_truthy(msg.id)
      assert.is.equal("agent1", msg:Sender())
      assert.is.equal("agent2", msg:Receiver())
      assert.is.same({data = "test"}, msg:Content())
    end)

    it("should create message with custom type", function()
      local msg = A2A.Message.new("agent1", "agent2", {data = "test"}, {
        type = "request"
      })

      assert.is.equal("request", msg:Type())
    end)

    it("should create reply to message", function()
      local original = A2A.Message.new("agent1", "agent2", {question = "what?"})

      local reply = original:Reply({answer = "result"})

      assert.is.equal("agent2", reply:Sender())
      assert.is.equal("agent1", reply:Receiver())
      assert.is.equal(original.id, reply.reply_to)
    end)

    it("should forward message to different receiver", function()
      local original = A2A.Message.new("agent1", "agent2", {data = "test"})

      local forwarded = original:Forward("agent3")

      assert.is.equal("agent1", forwarded:Sender())
      assert.is.equal("agent3", forwarded:Receiver())
      assert.is.equal(original.content, forwarded.content)
    end)
  end)

  describe("MessageQueue", function()
    it("should create queue for agent", function()
      local queue = A2A.MessageQueue.new("agent1")

      assert.is.equal("agent1", queue._agent_id)
      assert.is.equal(0, queue:Count())
    end)

    it("should push and pop messages", function()
      local queue = A2A.MessageQueue.new("agent1")
      local msg = A2A.Message.new("agent2", "agent1", {data = "test"})

      queue:Push(msg)

      assert.is.equal(1, queue:Count())

      local popped = queue:Pop()

      assert.is.equal(msg.id, popped.id)
      assert.is.equal(0, queue:Count())
    end)

    it("should filter messages when popping", function()
      local queue = A2A.MessageQueue.new("agent1")

      queue:Push(A2A.Message.new("agent2", "agent1", {priority = 1}, {type = "low"}))
      queue:Push(A2A.Message.new("agent3", "agent1", {priority = 2}, {type = "high"}))

      local high_priority = queue:Pop(function(msg)
        return msg.type == "high"
      end)

      assert.is.truthy(high_priority)
      assert.is.equal("high", high_priority.type)
      assert.is.equal(1, queue:Count())
    end)

    it("should peek without removing", function()
      local queue = A2A.MessageQueue.new("agent1")
      local msg = A2A.Message.new("agent2", "agent1", {data = "test"})

      queue:Push(msg)

      local peeked = queue:Peek()

      assert.is.equal(msg.id, peeked.id)
      assert.is.equal(1, queue:Count())
    end)

    it("should count messages with filter", function()
      local queue = A2A.MessageQueue.new("agent1")

      queue:Push(A2A.Message.new("agent2", "agent1", {}, {type = "info"}))
      queue:Push(A2A.Message.new("agent3", "agent1", {}, {type = "alert"}))
      queue:Push(A2A.Message.new("agent4", "agent1", {}, {type = "info"}))

      local info_count = queue:Count(function(msg)
        return msg.type == "info"
      end)

      assert.is.equal(2, info_count)
    end)

    it("should handle message type handlers", function()
      local queue = A2A.MessageQueue.new("agent1")

      local handled = false
      queue:RegisterHandler("greeting", function(msg)
        handled = true
        return {greeted = true}
      end)

      local msg = A2A.Message.new("agent2", "agent1", {text = "hello"}, {type = "greeting"})
      local result = queue:Handle(msg)

      assert.is_true(handled)
      assert.is_true(result.greeted)
    end)
  end)

  describe("Agent", function()
    it("should create agent with id and config", function()
      local agent = A2A.Agent.new("agent1", {
        name = "Test Agent",
        role = "worker"
      })

      assert.is.equal("agent1", agent:Id())
      assert.is.equal("Test Agent", agent:Name())
      assert.is.equal("worker", agent:Role())
    end)

    it("should manage agent state", function()
      local agent = A2A.Agent.new("agent1")

      agent:SetState("counter", 5)

      assert.is.equal(5, agent:GetState("counter"))
    end)

    it("should start and stop agent", function()
      local agent = A2A.Agent.new("agent1")

      agent:Start()

      assert.is_true(agent:IsRunning())

      agent:Stop()

      assert.is_false(agent:IsRunning())
    end)

    it("should send message through protocol", function()
      local protocol = A2A.Protocol.new()
      local agent1 = createMockAgent("agent1")
      local agent2 = createMockAgent("agent2")

      protocol:Register(agent1)
      protocol:Register(agent2)

      local result = agent1:Send("agent2", {data = "test"})

      assert.is_true(result.sent)
      assert.is.equal("agent2", result.receiver)

      -- Verify message arrived
      local received = agent2:Peek()
      assert.is_truthy(received)
      assert.is.equal("agent1", received.sender)
    end)

    it("should reply to message", function()
      local protocol = A2A.Protocol.new()
      local agent1 = createMockAgent("agent1")
      local agent2 = createMockAgent("agent2")

      protocol:Register(agent1)
      protocol:Register(agent2)

      -- Send initial message
      agent1:Send("agent2", {question = "what?"})

      local original = agent2:Peek()

      -- Reply
      local result = agent2:ReplyTo(original, {answer = "result"})

      assert.is_true(result.sent)

      -- Check reply arrived at agent1
      local reply = agent1:Peek(function(msg)
        return msg.reply_to == original.id
      end)

      assert.is_truthy(reply)
      assert.is.equal("result", reply.content.answer)
    end)

    it("should broadcast to all agents", function()
      local protocol = A2A.Protocol.new()
      local agent1 = createMockAgent("agent1")
      local agent2 = createMockAgent("agent2")
      local agent3 = createMockAgent("agent3")

      protocol:Register(agent1)
      protocol:Register(agent2)
      protocol:Register(agent3)

      local result = agent1:Broadcast({data = "announce"})

      assert.is_true(result.broadcast)
      assert.is.equal(2, result.sent_count)  -- All except sender

      -- Verify others received
      assert.is_equal(1, agent2.queue:Count())
      assert.is_equal(1, agent3.queue:Count())
    end)

    it("should receive messages", function()
      local protocol = A2A.Protocol.new()
      local agent1 = createMockAgent("agent1")
      local agent2 = createMockAgent("agent2")

      protocol:Register(agent1)
      protocol:Register(agent2)
      agent2:Start()

      -- Send message
      agent1:Send("agent2", {data = "test"})

      -- Receive
      local received = agent2:Receive()

      assert.is_truthy(received)
      assert.is.equal("test", received.content.data)
    end)

    it("should register message handlers", function()
      local agent = A2A.Agent.new("agent1")

      local handled = false
      agent:RegisterHandler("greeting", function(msg)
        handled = true
        return {handled = true}
      end)

      local msg = A2A.Message.new("agent2", "agent1", {}, {type = "greeting"})
      local result = agent:Handle(msg)

      assert.is_true(handled)
      assert.is_true(result.handled)
    end)
  end)

  describe("Protocol", function()
    it("should create protocol with name", function()
      local protocol = A2A.Protocol.new({name = "test_proto"})

      assert.is.equal("test_proto", protocol.name)
    end)

    it("should register and unregister agents", function()
      local protocol = A2A.Protocol.new()
      local agent = createMockAgent("agent1")

      protocol:Register(agent)

      assert.is.equal(agent, protocol:Get("agent1"))

      protocol:Unregister("agent1")

      assert.is_falsy(protocol:Get("agent1"))
    end)

    it("should list agents with filter", function()
      local protocol = A2A.Protocol.new()
      protocol:Register(createMockAgent("agent1", "worker"))
      protocol:Register(createMockAgent("agent2", "supervisor"))
      protocol:Register(createMockAgent("agent3", "worker"))

      local workers = protocol:List(function(agent)
        return agent:Role() == "worker"
      end)

      assert.is.equal(2, #workers)
    end)

    it("should send message between agents", function()
      local protocol = A2A.Protocol.new()
      local agent1 = createMockAgent("agent1")
      local agent2 = createMockAgent("agent2")

      protocol:Register(agent1)
      protocol:Register(agent2)

      local msg = A2A.Message.new("agent1", "agent2", {data = "test"})
      local result = protocol:Send(msg)

      assert.is_true(result.sent)
      assert.is.equal(msg.id, result.message_id)
    end)

    it("should fail to send to unknown agent", function()
      local protocol = A2A.Protocol.new()
      local agent1 = createMockAgent("agent1")

      protocol:Register(agent1)

      local msg = A2A.Message.new("agent1", "unknown", {data = "test"})
      local result, err = protocol:Send(msg)

      assert.is_falsy(result)
      assert.is.truthy(err:find("not found"))
    end)

    it("should broadcast message", function()
      local protocol = A2A.Protocol.new()
      local agent1 = createMockAgent("agent1")
      local agent2 = createMockAgent("agent2")
      local agent3 = createMockAgent("agent3")

      protocol:Register(agent1)
      protocol:Register(agent2)
      protocol:Register(agent3)

      local msg = A2A.Message.new("agent1", "*", {data = "broadcast"})
      local result = protocol:Broadcast(msg)

      assert.is_true(result.broadcast)
      assert.is.equal(2, result.sent_count)
    end)

    it("should send multiple messages", function()
      local protocol = A2A.Protocol.new()
      local agent1 = createMockAgent("agent1")
      local agent2 = createMockAgent("agent2")

      protocol:Register(agent1)
      protocol:Register(agent2)

      local messages = {
        A2A.Message.new("agent1", "agent2", {seq = 1}),
        A2A.Message.new("agent1", "agent2", {seq = 2}),
        A2A.Message.new("agent1", "agent2", {seq = 3})
      }

      local results = protocol:Multicast(messages)

      -- Should have 3 results (one per message)
      local count = 0
      for msg_id, result_info in pairs(results) do
    if result_info.result and result_info.result.sent then
      count = count + 1
    end
  end

      assert.is.equal(3, count)

      -- Verify agent2 received all messages
      assert.is.equal(3, agent2.queue:Count())
    end)

    it("should route messages with custom router", function()
      local protocol = A2A.Protocol.new()
      local agent1 = createMockAgent("agent1")
      local agent2 = createMockAgent("agent2")
      local agent3 = createMockAgent("agent3")

      protocol:Register(agent1)
      protocol:Register(agent2)
      protocol:Register(agent3)

      -- Route based on content
      local msg = A2A.Message.new("agent1", nil, {region = "west"})
      local result = protocol:Route(msg, function(message, agents)
        if message.content.region == "west" then
          return "agent2"
        else
          return "agent3"
        end
      end)

      assert.is_true(result.sent)
      assert.is.equal(1, agent2.queue:Count())
      assert.is.equal(0, agent3.queue:Count())
    end)

    it("should track metrics", function()
      local protocol = A2A.Protocol.new()
      local agent1 = createMockAgent("agent1")
      local agent2 = createMockAgent("agent2")

      protocol:Register(agent1)
      protocol:Register(agent2)
      agent1:Start()
      agent2:Start()

      -- Send various messages
      agent1:Send("agent2", {}, {type = "request"})
      agent1:Send("agent2", {}, {type = "notify"})
      agent2:Send("agent1", {}, {type = "response"})

      local metrics = protocol:GetMetrics()

      assert.is.equal(3, metrics.total_messages)
      assert.is.equal(1, metrics.messages_by_type.request)
      assert.is.equal(1, metrics.messages_by_type.notify)
      assert.is.equal(1, metrics.messages_by_type.response)
    end)

    it("should start and stop all agents", function()
      local protocol = A2A.Protocol.new()
      protocol:Register(createMockAgent("agent1"))
      protocol:Register(createMockAgent("agent2"))

      protocol:StartAll()

      assert.is_true(protocol:IsRunning())
      assert.is_true(protocol:Get("agent1"):IsRunning())
      assert.is_true(protocol:Get("agent2"):IsRunning())

      protocol:StopAll()

      assert.is_false(protocol:IsRunning())
      assert.is_false(protocol:Get("agent1"):IsRunning())
      assert.is_false(protocol:Get("agent2"):IsRunning())
    end)
  end)

  describe("Helper Functions", function()
    it("should create agent with helper", function()
      local agent = A2A.create_agent("test", {role = "worker"})

      assert.is.equal("test", agent:Id())
      assert.is.equal("worker", agent:Role())
    end)

    it("should create protocol with helper", function()
      local protocol = A2A.create_protocol({name = "test"})

      assert.is.equal("test", protocol.name)
    end)

    it("should create message helpers", function()
      local msg = A2A.message("a1", "a2", {data = "test"})
      assert.is.equal("inform", msg:Type())

      local req = A2A.request("a1", "a2", {data = "test"})
      assert.is.equal("request", req:Type())

      local res = A2A.response("a2", "a1", {data = "result"})
      assert.is.equal("response", res:Type())

      local notif = A2A.notify("a1", "a2", {data = "alert"})
      assert.is.equal("notify", notif:Type())
    end)
  end)

  describe("Integration Tests", function()
    it("should handle multi-agent conversation", function()
      local protocol = A2A.Protocol.new()

      local coordinator = A2A.Agent.new("coordinator", {role = "coordinator"})
      local worker1 = A2A.Agent.new("worker1", {role = "worker"})
      local worker2 = A2A.Agent.new("worker2", {role = "worker"})

      protocol:Register(coordinator)
      protocol:Register(worker1)
      protocol:Register(worker2)

      -- Start all
      protocol:StartAll()

      -- Coordinator assigns tasks
      coordinator:Send("worker1", {task = "task1", data = "data1"})
      coordinator:Send("worker2", {task = "task2", data = "data2"})

      -- Workers receive and reply
      local task1 = worker1:Receive()
      local task2 = worker2:Receive()

      assert.is.truthy(task1)
      assert.is.truthy(task2)

      worker1:ReplyTo(task1, {result = "result1", status = "done"})
      worker2:ReplyTo(task2, {result = "result2", status = "done"})

      -- Coordinator receives replies
      local reply1 = coordinator:Peek(function(msg)
        return msg.reply_to == task1.id
      end)
      local reply2 = coordinator:Peek(function(msg)
        return msg.reply_to == task2.id
      end)

      assert.is.truthy(reply1)
      assert.is.truthy(reply2)

      protocol:StopAll()
    end)

    it("should support publish-subscribe pattern", function()
      local protocol = A2A.Protocol.new()

      local publisher = A2A.Agent.new("publisher")
      local subscriber1 = A2A.Agent.new("sub1")
      local subscriber2 = A2A.Agent.new("sub2")

      protocol:Register(publisher)
      protocol:Register(subscriber1)
      protocol:Register(subscriber2)

      -- Register handlers
      local sub1_received = false
      local sub2_received = false

      subscriber1:RegisterHandler("update", function(msg)
        sub1_received = true
        return msg
      end)

      subscriber2:RegisterHandler("update", function(msg)
        sub2_received = true
        return msg
      end)

      protocol:StartAll()

      -- Publisher broadcasts update
      publisher:Broadcast({event = "update"}, {type = "update"})

      -- Subscribers receive
      subscriber1:Receive()
      subscriber2:Receive()

      assert.is_true(sub1_received)
      assert.is_true(sub2_received)

      protocol:StopAll()
    end)

    it("should support request-response pattern", function()
      local protocol = A2A.Protocol.new()

      local client = A2A.Agent.new("client")
      local server = A2A.Agent.new("server")

      protocol:Register(client)
      protocol:Register(server)

      -- Server handler
      server:RegisterHandler("request", function(msg)
        return msg:Reply({answer = 42}, {type = "response"})
      end)

      protocol:StartAll()

      -- Client sends request
      local result = client:Send("server", {question = "what?"}, {type = "request"})

      assert.is_true(result.sent)

      -- Server receives and replies
      local request = server:Receive(function(msg)
        return msg.type == "request"
      end)

      server:Send("client", request.content, {type = "response", reply_to = request.id})

      -- Client receives response
      local response = client:Receive(function(msg)
        return msg.type == "response" and msg.reply_to == request.id
      end)

      assert.is.truthy(response)
      assert.is.equal(42, response.content.answer)

      protocol:StopAll()
    end)
  end)
end)
