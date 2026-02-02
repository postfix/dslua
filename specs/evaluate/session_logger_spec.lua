-- specs/evaluate/session_logger_spec.lua
-- Tests for Session Logger

describe("Session Logger", function()
  local SessionLogger = require("dslua.evaluate.session_logger")

  describe("SessionLogger", function()
    it("should create session logger", function()
      local logger = SessionLogger.SessionLogger.new()

      assert.is.equal(true, logger.enabled)
      assert.is.equal("/tmp/dslua_sessions", logger.log_dir)
      assert.is.falsy(logger.current_session)
    end)

    it("should accept custom options", function()
      local logger = SessionLogger.SessionLogger.new({
        log_dir = "/tmp/custom_logs",
        enabled = false
      })

      assert.is.equal(false, logger.enabled)
      assert.is.equal("/tmp/custom_logs", logger.log_dir)
    end)

    it("should start session", function()
      local logger = SessionLogger.SessionLogger.new()
      local session_id = logger:start_session("test_session", {module = "RLM"})

      assert.is.equal("test_session", session_id)
      assert.is.equal("test_session", logger.current_session)

      local session = logger:get_session("test_session")
      assert.is.truthy(session)
      assert.is.equal("test_session", session.id)
      assert.is.equal("RLM", session.metadata.module)
      assert.is.truthy(session.start_time)
    end)

    it("should log events", function()
      local logger = SessionLogger.SessionLogger.new()
      logger:start_session("test_session")

      logger:log("retrieval", {query = "test query", docs_count = 5})
      logger:log("context_update", {context_length = 100})
      logger:log("error", {message = "Test error"})

      local session = logger:get_session("test_session")
      assert.is.equal(3, session.stats.event_count)
      assert.is.equal(1, session.stats.error_count)
      assert.is.equal(3, #session.events)

      assert.is.equal("retrieval", session.events[1].type)
      assert.is.equal(5, session.events[1].data.docs_count)
    end)

    it("should track warnings", function()
      local logger = SessionLogger.SessionLogger.new()
      logger:start_session("test_session")

      logger:log("warning", {message = "Low similarity"})
      logger:log("warning", {message = "No documents found"})

      local session = logger:get_session("test_session")
      assert.is.equal(2, session.stats.warning_count)
    end)

    it("should end session", function()
      local logger = SessionLogger.SessionLogger.new()
      logger:start_session("test_session")
      logger:log("test", {})

      local start_time = os.time()
      local session_id = logger:end_session({success = true})

      assert.is.equal("test_session", session_id)
      assert.is.falsy(logger.current_session)

      local session = logger:get_session("test_session")
      assert.is.truthy(session.end_time)
      assert.is.truthy(session.duration)
      assert.is.equal(true, session.result.success)
    end)

    it("should list sessions", function()
      local logger = SessionLogger.SessionLogger.new()

      logger:start_session("session1", {module = "RLM"})
      logger:end_session()
      logger:start_session("session2", {module = "MIPRO"})
      logger:end_session()

      local sessions = logger:list_sessions()
      assert.is.equal(2, #sessions)

      -- Both sessions should be in the list (order not guaranteed due to same timestamp)
      local ids = {}
      for _, s in ipairs(sessions) do
        table.insert(ids, s.id)
      end
      table.sort(ids)

      assert.is.equal("session1", ids[1])
      assert.is.equal("session2", ids[2])
    end)

    it("should save session to file", function()
      local logger = SessionLogger.SessionLogger.new({
        log_dir = "/tmp/test_session_logs"
      })

      logger:start_session("test_save", {test = true})
      logger:log("event", {data = "test"})
      logger:end_session()

      local filename, err = logger:save_session("test_save")

      assert.is.truthy(filename)
      assert.is.falsy(err)
      assert.is.truthy(filename:find("test_save"))

      -- Cleanup
      os.execute("rm -rf /tmp/test_session_logs")
    end)

    it("should load session from file", function()
      local logger = SessionLogger.SessionLogger.new({
        log_dir = "/tmp/test_session_load"
      })

      logger:start_session("test_load", {loaded = false})
      logger:log("original", {value = 42})
      local filename = logger:save_session("test_load")

      -- Clear in-memory session
      logger.session_data = {}

      -- Load from file
      local session, err = logger:load_session(filename)

      assert.is.truthy(session)
      assert.is.falsy(err)
      assert.is.equal("test_load", session.id)
      assert.is.equal(42, session.events[1].data.value)

      -- Cleanup
      os.execute("rm -rf /tmp/test_session_load")
    end)

    it("should handle disabled logger", function()
      local logger = SessionLogger.SessionLogger.new({enabled = false})

      local session_id = logger:start_session("test")
      assert.is.falsy(session_id)

      logger:log("event", {})
      -- Should not crash

      local ended = logger:end_session()
      assert.is.falsy(ended)
    end)
  end)

  describe("SessionViewer", function()
    it("should create viewer with logger", function()
      local logger = SessionLogger.SessionLogger.new()
      local viewer = SessionLogger.SessionViewer.new(logger)

      assert.is.equal(logger, viewer.logger)
    end)

    it("should create viewer with default logger", function()
      local viewer = SessionLogger.SessionViewer.new()

      assert.is.truthy(viewer.logger)
    end)

    it("should display session summary", function()
      local logger = SessionLogger.SessionLogger.new()
      logger:start_session("summary_test", {module = "RLM", version = "1.0"})
      logger:log("event", {})
      logger:end_session({success = true})

      local viewer = SessionLogger.SessionViewer.new(logger)
      local summary = viewer:display_summary("summary_test")

      assert.is.truthy(summary)
      assert.is.truthy(summary:find("Session Summary"))
      assert.is.truthy(summary:find("summary_test"))
      assert.is.truthy(summary:find("Events: 1"))
      assert.is.truthy(summary:find("module: RLM"))
      assert.is.truthy(summary:find("version: 1.0"))
    end)

    it("should display events", function()
      local logger = SessionLogger.SessionLogger.new()
      logger:start_session("events_test")
      logger:log("retrieval", {query = "test", docs = 5})
      logger:log("context", {length = 100})
      logger:log("error", {message = "Test error"})
      logger:end_session()

      local viewer = SessionLogger.SessionViewer.new(logger)
      local events = viewer:display_events("events_test")

      assert.is.truthy(events:find("Session Events"))
      assert.is.truthy(events:find("retrieval"))
      assert.is.truthy(events:find("query: test"))
      assert.is.truthy(events:find("docs: 5"))
      assert.is.truthy(events:find("error"))
    end)

    it("should filter events by type", function()
      local logger = SessionLogger.SessionLogger.new()
      logger:start_session("filter_test")
      logger:log("retrieval", {query = "test"})
      logger:log("context", {length = 100})
      logger:log("error", {message = "error"})
      logger:end_session()

      local viewer = SessionLogger.SessionViewer.new(logger)
      local errors = viewer:display_events("filter_test", {event_type = "error"})

      assert.is.truthy(errors:find("error"))
      assert.is.falsy(errors:find("retrieval"))
      assert.is.falsy(errors:find("context"))
    end)

    it("should limit events displayed", function()
      local logger = SessionLogger.SessionLogger.new()
      logger:start_session("limit_test")
      for i = 1, 10 do
        logger:log("event", {index = i})
      end
      logger:end_session()

      local viewer = SessionLogger.SessionViewer.new(logger)
      local events = viewer:display_events("limit_test", {max_events = 3})

      -- Should show 3 events + "more events" message
      assert.is.truthy(events:find("event"))
      assert.is.truthy(events:find("7 more events"))
    end)

    it("should display timeline", function()
      local logger = SessionLogger.SessionLogger.new()
      logger:start_session("timeline_test")
      logger:log("retrieval", {query = "test"})
      logger:log("retrieval", {query = "test2"})
      logger:log("context", {length = 100})
      logger:end_session()

      local viewer = SessionLogger.SessionViewer.new(logger)
      local timeline = viewer:display_timeline("timeline_test")

      assert.is.truthy(timeline)
      assert.is.truthy(timeline:find("Session Timeline"))
      assert.is.truthy(timeline:find("retrieval"))
      assert.is.truthy(timeline:find("2 events"))
      assert.is.truthy(timeline:find("context"))
      assert.is.truthy(timeline:find("1 event"))
    end)

    it("should display issues", function()
      local logger = SessionLogger.SessionLogger.new()
      logger:start_session("issues_test")
      logger:log("error", {message = "Error 1", trace = "trace1"})
      logger:log("warning", {message = "Warning 1"})
      logger:log("error", {message = "Error 2"})
      logger:end_session()

      local viewer = SessionLogger.SessionViewer.new(logger)
      local issues = viewer:display_issues("issues_test")

      assert.is.truthy(issues:find("Issues"))
      assert.is.truthy(issues:find("[ERROR]"))
      assert.is.truthy(issues:find("Error 1"))
      assert.is.truthy(issues:find("trace1"))
      assert.is.truthy(issues:find("[WARNING]"))
      assert.is.truthy(issues:find("Warning 1"))
    end)

    it("should handle no issues", function()
      local logger = SessionLogger.SessionLogger.new()
      logger:start_session("no_issues_test")
      logger:log("info", {message = "Info"})
      logger:end_session()

      local viewer = SessionLogger.SessionViewer.new(logger)
      local issues = viewer:display_issues("no_issues_test")

      assert.is.truthy(issues:find("No issues found"))
    end)

    it("should return nil for non-existent session", function()
      local logger = SessionLogger.SessionLogger.new()
      local viewer = SessionLogger.SessionViewer.new(logger)

      local summary = viewer:display_summary("non_existent")
      assert.is.falsy(summary)

      local events = viewer:display_events("non_existent")
      assert.is.falsy(events)

      local timeline = viewer:display_timeline("non_existent")
      assert.is.falsy(timeline)
    end)
  end)

  describe("Helper Functions", function()
    it("should create logger with helper", function()
      local logger = SessionLogger.session_logger({
        log_dir = "/tmp/helper_test"
      })

      assert.is.truthy(logger)
      assert.is.equal("/tmp/helper_test", logger.log_dir)
    end)

    it("should create viewer with helper", function()
      local logger = SessionLogger.session_logger()
      local viewer = SessionLogger.session_viewer(logger)

      assert.is.truthy(viewer)
      assert.is.equal(logger, viewer.logger)
    end)
  end)

  describe("Integration Tests", function()
    it("should handle complete RLM session workflow", function()
      local logger = SessionLogger.SessionLogger.new()
      logger:start_session("rlm_workflow", {
        module = "RLM",
        max_passes = 3,
        threshold = 0.5
      })

      -- Simulate RLM passes
      for pass = 1, 3 do
        logger:log("pass_start", {pass_number = pass})

        logger:log("retrieval", {
          query = "test query",
          docs_retrieved = 5,
          pass = pass
        })

        logger:log("context_update", {
          context_length = 100 * pass,
          unique_docs = 5 * pass
        })

        logger:log("query_refinement", {
          original_terms = 3,
          new_terms = 5
        })

        logger:log("pass_end", {pass_number = pass})
      end

      logger:end_session({success = true, total_passes = 3})

      local viewer = SessionLogger.SessionViewer.new(logger)

      -- Check summary
      local summary = viewer:display_summary("rlm_workflow")
      assert.is.truthy(summary:find("rlm_workflow"))
      assert.is.truthy(summary:find("max_passes: 3"))

      -- Check events
      local events = viewer:display_events("rlm_workflow")
      assert.is.truthy(events:find("pass_start"))
      assert.is.truthy(events:find("retrieval"))
      assert.is.truthy(events:find("context_update"))

      -- Check timeline
      local timeline = viewer:display_timeline("rlm_workflow")
      assert.is.truthy(timeline:find("pass_start %(3 events%)"))
      assert.is.truthy(timeline:find("retrieval %(3 events%)"))
    end)

    it("should handle error scenarios", function()
      local logger = SessionLogger.SessionLogger.new()
      logger:start_session("error_scenario")

      logger:log("retrieval", {query = "test"})
      logger:log("error", {
        message = "Connection failed",
        trace = "at retriever:line 42"
      })
      logger:log("warning", {message = "Retrying with fallback"})

      logger:end_session({success = false, error = "Connection failed"})

      local viewer = SessionLogger.SessionViewer.new(logger)

      local issues = viewer:display_issues("error_scenario")
      assert.is.truthy(issues:find("Connection failed"))
      assert.is.truthy(issues:find("Retrying with fallback"))
    end)
  end)

  describe("RLM Integration", function()
    it("should integrate with RLM module", function()
      local RLM = require("dslua.modules.rlm")
      local logger = SessionLogger.SessionLogger.new()

      -- Create mock retriever
      local mock_retriever = {
        Retrieve = function(self, query, opts)
          return {
            {id = "doc1", text = "Document 1 content"},
            {id = "doc2", text = "Document 2 content"}
          }
        end
      }

      -- Create RLM with logger
      local rlm = RLM.new(nil, {
        retriever = mock_retriever,
        max_passes = 2
      })

      -- Simulate logging
      logger:start_session("rlm_integration", {module = "RLM"})

      logger:log("module_process", {
        module = "RLM",
        input = {query = "test query"}
      })

      -- Log RLM passes
      logger:log("pass_start", {pass = 1})
      logger:log("retrieval", {docs_count = 2})
      logger:log("pass_end", {pass = 1})

      logger:log("pass_start", {pass = 2})
      logger:log("retrieval", {docs_count = 2})
      logger:log("pass_end", {pass = 2})

      logger:end_session({success = true})

      local session = logger:get_session("rlm_integration")
      assert.is.equal(7, session.stats.event_count)
    end)
  end)
end)
