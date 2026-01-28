#!/usr/bin/env luajit

local dslua = require("dslua")

local commands = {}

function commands.list()
    print("Available optimizers:")
    print("  - mipro: TPE-based prompt optimization (coming soon)")
    print("  - bootstrap: Few-shot demonstration learning (coming soon)")
    print("  - gekko: Evolutionary prompt search (coming soon)")
end

function commands.help()
    print([[dslua - DSPy for Lua

Usage: dslua <command> [options]

Commands:
  list              List available optimizers
  help              Show this help message

More commands coming soon!]])
end

local function main()
    local arg = arg or {}

    if #arg == 0 then
        commands.help()
        return
    end

    local cmd = arg[1]

    if commands[cmd] then
        commands[cmd](select(2, table.unpack(arg)))
    else
        print("Unknown command: " .. cmd)
        commands.help()
        os.exit(1)
    end
end

return {
    run = main,
    commands = commands,
}
