-----------------------------------------------------------------------------
-- Unified SMTP/FTP subsystem
-- LuaSocket toolkit.
-- Author: Diego Nehab
-- RCS ID: $Id: tp.lua,v 1.22 2006/03/14 09:04:15 diego Exp $
-----------------------------------------------------------------------------

-----------------------------------------------------------------------------
-- Declare module and import dependencies
-----------------------------------------------------------------------------
local base = _G
-- local string = require("string")
-- local socket = require("socket")
dofile(core.dir.."dll/scripts/socket.lua")
-- local ltn12 = require("ltn12")
dofile(core.dir.."dll/scripts/ltn12.lua")
-- module("socket.tp")
tp={}

-----------------------------------------------------------------------------
-- Program constants
-----------------------------------------------------------------------------
tp.TIMEOUT = 60

-----------------------------------------------------------------------------
-- Implementation
-----------------------------------------------------------------------------
-- gets server reply (works for SMTP and FTP)
function tp.get_reply(c)
    local code, current, sep
    local line, err = c:receive()
    local reply = line
    if err then return nil, err end
    code, sep = socket.skip(2, string.find(line, "^(%d%d%d)(.?)"))
    if not code then return nil, "invalid server reply" end
    if sep == "-" then -- reply is multiline
        repeat
            line, err = c:receive()
            if err then return nil, err end
            current, sep = socket.skip(2, string.find(line, "^(%d%d%d)(.?)"))
            reply = reply .. "\n" .. line
        -- reply ends with same code
        until code == current and sep == " "
    end
    return code, reply
end

-- metatable for sock object
tp.metat = { __index = {} }

function tp.metat.__index:check(ok)
    local code, reply = tp.get_reply(self.c)
    if not code then return nil, reply end
    if base.type(ok) ~= "function" then
        if base.type(ok) == "table" then
            for i, v in base.ipairs(ok) do
                if string.find(code, v) then
                    return base.tonumber(code), reply
                end
            end
            return nil, reply
        else
            if string.find(code, ok) then return base.tonumber(code), reply
            else return nil, reply end
        end
    else return ok(base.tonumber(code), reply) end
end

function tp.metat.__index:command(cmd, arg)
    if arg then
        return self.c:send(cmd .. " " .. arg.. "\r\n")
    else
        return self.c:send(cmd .. "\r\n")
    end
end

function tp.metat.__index:sink(snk, pat)
    local chunk, err = c:receive(pat)
    return snk(chunk, err)
end

function tp.metat.__index:send(data)
    return self.c:send(data)
end

function tp.metat.__index:receive(pat)
    return self.c:receive(pat)
end

function tp.metat.__index:getfd()
    return self.c:getfd()
end

function tp.metat.__index:dirty()
    return self.c:dirty()
end

function tp.metat.__index:getcontrol()
    return self.c
end

function tp.metat.__index:source(source, step)
    local sink = socket.sink("keep-open", self.c)
    local ret, err = ltn12.pump.all(source, sink, step or ltn12.pump.step)
    return ret, err
end

-- closes the underlying c
function tp.metat.__index:close()
    self.c:close()
	return 1
end

-- connect with server and return c object
function tp.connect(host, port, timeout, create)
    local c, e = (create or socket.tcp)()
    if not c then return nil, e end
    c:settimeout(timeout or tp.TIMEOUT)
    local r, e = c:tp.connect(host, port)
    if not r then
        c:close()
        return nil, e
    end
    return base.setmetatable({c = c}, tp.metat)
end

