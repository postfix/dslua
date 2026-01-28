-- Luacheck configuration
std = "luajit"
max_line_length = 120

ignore = {
  "631",  -- max_line_length
}

files["dslua/"].ignore = {
  "212",  -- unused argument (for interface methods)
}

globals = {
  -- Add any custom globals here
}
