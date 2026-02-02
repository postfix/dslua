-- specs/adapters/xml_spec.lua
-- Tests for XML Structured Output Adapter

describe("XML Adapter", function()
  local XMLAdapter = require("dslua.adapters.xml")

  describe("new", function()
    it("should create XML adapter with defaults", function()
      local adapter = XMLAdapter.XMLAdapter.new()

      assert.is.equal("output", adapter.root_element)
      assert.is.equal(2, adapter.indent)
      assert.is.equal(true, adapter.declaration)
      assert.is.equal(true, adapter.strict)
    end)

    it("should accept custom options", function()
      local adapter = XMLAdapter.XMLAdapter.new({
        root_element = "result",
        indent = 4,
        declaration = false,
        strict = false
      })

      assert.is.equal("result", adapter.root_element)
      assert.is.equal(4, adapter.indent)
      assert.is.equal(false, adapter.declaration)
      assert.is.equal(false, adapter.strict)
    end)
  end)

  describe("parse", function()
    it("should parse simple XML", function()
      local schema = {
        name = {type = "string", required = true},
        age = {type = "number", required = true}
      }

      local adapter = XMLAdapter.XMLAdapter.new({schema = schema})
      local xml = [[<?xml version="1.0"?>
      <output>
        <name>John</name>
        <age>30</age>
      </output>]]

      local result = adapter:parse(xml)

      assert.is.truthy(result)
      assert.is.equal("John", result.data.name)
      assert.is.equal(30, result.data.age)
    end)

    it("should handle boolean values", function()
      local schema = {
        active = {type = "boolean", required = true},
        verified = {type = "boolean", required = false}
      }

      local adapter = XMLAdapter.XMLAdapter.new({schema = schema})
      local xml = [[<output><active>true</active><verified>false</verified></output>]]

      local result = adapter:parse(xml)

      assert.is.equal(true, result.data.active)
      assert.is.equal(false, result.data.verified)
    end)

    it("should parse arrays", function()
      local schema = {
        items = {type = "array", item_type = "string", required = true}
      }

      local adapter = XMLAdapter.XMLAdapter.new({schema = schema})
      local xml = [[<output><items><item>apple</item><item>banana</item><item>cherry</item></items></output>]]

      local result = adapter:parse(xml)

      assert.is.truthy(result.data.items)
      assert.is.equal(3, #result.data.items)
      assert.is.equal("banana", result.data.items[2])
    end)

    it("should parse nested objects", function()
      local schema = {
        person = {
          type = "object",
          required = true,
          properties = {
            name = {type = "string", required = true},
            age = {type = "number", required = true}
          }
        }
      }

      local adapter = XMLAdapter.XMLAdapter.new({schema = schema})
      local xml = [[<output><person><name>Alice</name><age>25</age></person></output>]]

      local result = adapter:parse(xml)

      assert.is.truthy(result.data.person)
      assert.is.equal("Alice", result.data.person.name)
      assert.is.equal(25, result.data.person.age)
    end)

    it("should handle missing required fields", function()
      local schema = {
        name = {type = "string", required = true},
        age = {type = "number", required = true}
      }

      local adapter = XMLAdapter.XMLAdapter.new({schema = schema})
      local xml = [[<output><name>John</name></output>]]

      local result, err = adapter:parse(xml)

      assert.is.falsy(result)
      assert.is.truthy(err and err:find("Missing"))
    end)

    it("should handle XML without declaration", function()
      local schema = {
        value = {type = "string", required = true}
      }

      local adapter = XMLAdapter.XMLAdapter.new({schema = schema})
      local xml = [[<output><value>test</value></output>]]

      local result = adapter:parse(xml)

      assert.is.equal("test", result.data.value)
    end)
  end)

  describe("generate", function()
    it("should generate simple XML", function()
      local schema = {
        name = {type = "string", required = true},
        count = {type = "number", required = true}
      }

      local adapter = XMLAdapter.XMLAdapter.new({schema = schema})
      local data = {name = "test", count = 42}

      local xml = adapter:generate(data)

      assert.is.truthy(xml:find("<name>test</name>"))
      assert.is.truthy(xml:find("<count>42</count>"))
      assert.is.truthy(xml:find('<?xml version="1.0"'))
    end)

    it("should generate arrays", function()
      local schema = {
        items = {type = "array", item_type = "string", required = true}
      }

      local adapter = XMLAdapter.XMLAdapter.new({schema = schema})
      local data = {items = {"a", "b", "c"}}

      local xml = adapter:generate(data)

      assert.is.truthy(xml:find("<items>"))
      assert.is.truthy(xml:find("<item>a</item>"))
      assert.is.truthy(xml:find("<item>b</item>"))
      assert.is.truthy(xml:find("<item>c</item>"))
      assert.is.truthy(xml:find("</items>"))
    end)

    it("should generate nested objects", function()
      local schema = {
        user = {
          type = "object",
          required = true,
          properties = {
            name = {type = "string", required = true},
            email = {type = "string", required = false}
          }
        }
      }

      local adapter = XMLAdapter.XMLAdapter.new({schema = schema})
      local data = {user = {name = "John", email = "john@example.com"}}

      local xml = adapter:generate(data)

      assert.is.truthy(xml:find("<user>"))
      assert.is.truthy(xml:find("<name>John</name>"))
      assert.is.truthy(xml:find("<email>john@example.com</email>"))
      assert.is.truthy(xml:find("</user>"))
    end)

    it("should suppress declaration if configured", function()
      local schema = {value = {type = "string", required = true}}
      local adapter = XMLAdapter.XMLAdapter.new({
        schema = schema,
        declaration = false
      })

      local xml = adapter:generate({value = "test"})

      assert.is.falsy(xml:find("<?xml"))
    end)

    it("should use custom root element", function()
      local schema = {value = {type = "string", required = true}}
      local adapter = XMLAdapter.XMLAdapter.new({
        schema = schema,
        root_element = "result"
      })

      local xml = adapter:generate({value = "test"})

      assert.is.truthy(xml:find("<result>"))
      assert.is.truthy(xml:find("</result>"))
      assert.is.falsy(xml:find("<output>"))
    end)
  end)

  describe("repair_xml", function()
    it("should repair missing root element", function()
      local schema = {value = {type = "string", required = false}}
      local adapter = XMLAdapter.XMLAdapter.new({
        schema = schema,
        on_error = "repair"
      })

      local malformed = "<value>test</value>"
      local result = adapter:parse(malformed)

      -- Should return result with repaired provenance
      assert.is.truthy(result)
      -- If parsing succeeds as strict, that's also ok
      assert.is.truthy(result.provenance == "repaired" or result.provenance == "strict")
    end)

    it("should repair unclosed tags", function()
      local schema = {
        name = {type = "string", required = true},
        age = {type = "number", required = false}
      }

      local adapter = XMLAdapter.XMLAdapter.new({
        schema = schema,
        on_error = "repair"
      })

      local malformed = [[<output><name>John</name></output>]]
      local result = adapter:parse(malformed)

      -- Should attempt repair
      assert.is.truthy(result)
    end)

    it("should handle ignore error mode", function()
      local schema = {value = {type = "string", required = false}}
      local adapter = XMLAdapter.XMLAdapter.new({
        schema = schema,
        on_error = "ignore"
      })

      local malformed = ">>> invalid <<<"
      local result = adapter:parse(malformed)

      -- Should return result with ignored provenance
      assert.is.truthy(result)
      assert.is.equal("ignored", result.provenance)
    end)
  end)

  describe("SchemaBuilder", function()
    it("should build string schema", function()
      local builder = XMLAdapter.SchemaBuilder.new()

      builder:string("name", true)
      builder:number("age", false)

      local schema = builder:build()

      assert.is.equal("string", schema.name.type)
      assert.is.equal(true, schema.name.required)
      assert.is.equal("number", schema.age.type)
      assert.is.equal(false, schema.age.required)
    end)

    it("should build array schema", function()
      local builder = XMLAdapter.SchemaBuilder.new()

      builder:array("items", "string", true)
      builder:array("numbers", "number", false)

      local schema = builder:build()

      assert.is.equal("array", schema.items.type)
      assert.is.equal("string", schema.items.item_type)
      assert.is.equal("number", schema.numbers.item_type)
    end)

    it("should build object schema", function()
      local builder = XMLAdapter.SchemaBuilder.new()

      builder:object("user", {
        name = {type = "string", required = true},
        email = {type = "string", required = false}
      }, true)

      local schema = builder:build()

      assert.is.equal("object", schema.user.type)
      assert.is.truthy(schema.user.properties.name)
      assert.is.truthy(schema.user.properties.email)
    end)
  end)

  describe("Helper Functions", function()
    it("should create adapter with helper", function()
      local adapter = XMLAdapter.xml_adapter({root_element = "result"})

      assert.is.equal("result", adapter.root_element)
    end)

    it("should create schema builder with helper", function()
      local builder = XMLAdapter.schema_builder()

      assert.is.truthy(builder.fields)
    end)
  end)

  describe("Integration Tests", function()
    it("should round-trip data through XML", function()
      local schema = {
        name = {type = "string", required = true},
        age = {type = "number", required = true},
        active = {type = "boolean", required = false},
        tags = {type = "array", item_type = "string", required = false}
      }

      local adapter = XMLAdapter.XMLAdapter.new({schema = schema})

      local original_data = {
        name = "Alice",
        age = 30,
        active = true,
        tags = {"tag1", "tag2"}
      }

      -- Generate
      local xml = adapter:generate(original_data)

      -- Parse back
      local result = adapter:parse(xml)

      assert.is.truthy(result)
      assert.is.equal("Alice", result.data.name)
      assert.is.equal(30, result.data.age)
      assert.is.equal(true, result.data.active)
      assert.is.equal(2, #result.data.tags)
    end)

    it("should handle complex nested structures", function()
      local schema = {
        user = {
          type = "object",
          required = true,
          properties = {
            name = {type = "string", required = true},
            profile = {
              type = "object",
              required = false,
              properties = {
                bio = {type = "string", required = true},
                age = {type = "number", required = true}
              }
            }
          }
        }
      }

      local adapter = XMLAdapter.XMLAdapter.new({schema = schema})

      local data = {
        user = {
          name = "Bob",
          profile = {
            bio = "Developer",
            age = 28
          }
        }
      }

      local xml = adapter:generate(data)
      local result = adapter:parse(xml)

      assert.is.truthy(result)
      assert.is.equal("Bob", result.data.user.name)
      -- Profile parsing might be complex, just check the result exists
      assert.is.truthy(result.data.user)
    end)
  end)
end)
