#!/usr/bin/env lua

require('test/test-utils')
require('test/test-config-replacer')

local luaunit = require("luaunit")
os.exit(luaunit.LuaUnit.run())

