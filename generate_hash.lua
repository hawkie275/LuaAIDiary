#!/usr/bin/env lua
local bcrypt = require("bcrypt")

local password = "admin123"
local hash = bcrypt.digest(password, 10)
print(hash)
