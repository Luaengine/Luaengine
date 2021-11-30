-----------------------------------------------------------------------------
-- LuaSocket helper module
-- Author: Diego Nehab
-- RCS ID: $Id: socket.lua,v 1.22 2005/11/22 08:33:29 diego Exp $
-----------------------------------------------------------------------------

-----------------------------------------------------------------------------
-- Declare module and import dependencies
-----------------------------------------------------------------------------
local base = _G
-- local string = require("string")
-- local math = require("math")
local sock = require("socket.core")
-- module("socket")
socket={}

-----------------------------------------------------------------------------
-- Exported auxiliar functions
-----------------------------------------------------------------------------
function socket.connect(address, port, laddress, lport)
    local soc, err = sock.tcp()
    if not soc then return nil, err end
    if laddress then
        local res, err = soc:bind(laddress, lport, -1)
        if not res then return nil, err end
    end
    local res, err = soc:connect(address, port)
    if not res then return nil, err end
    return soc
end

function socket.bind(host, port, backlog)
    local soc, err = sock.tcp()
    if not soc then return nil, err end
    soc:setoption("reuseaddr", true)
    local res, err = soc:bind(host, port)
    if not res then return nil, err end
    res, err = soc:listen(backlog)
    if not res then return nil, err end
    return soc
end

socket.try = sock.newtry()

function socket.choose(table)
    return function(name, opt1, opt2)
        if base.type(name) ~= "string" then
            name, opt1, opt2 = "default", name, opt1
        end
        local f = table[name or "nil"]
        if not f then base.error("unknown key (".. base.tostring(name) ..")", 3)
        else return f(opt1, opt2) end
    end
end

-----------------------------------------------------------------------------
-- Socket sources and sinks, conforming to LTN12
-----------------------------------------------------------------------------
-- create namespaces inside LuaSocket namespace
socket.sourcet = {}
socket.sinkt = {}

socket.BLOCKSIZE = 2048

socket.sinkt["close-when-done"] = function(soc)
    return base.setmetatable({
        getfd = function() return soc:getfd() end,
        dirty = function() return soc:dirty() end
    }, {
        __call = function(self, chunk, err)
            if not chunk then
                soc:close()
                return 1
            else return soc:send(chunk) end
        end
    })
end

socket.sinkt["keep-open"] = function(soc)
    return base.setmetatable({
        getfd = function() return soc:getfd() end,
        dirty = function() return soc:dirty() end
    }, {
        __call = function(self, chunk, err)
            if chunk then return soc:send(chunk)
            else return 1 end
        end
    })
end

socket.sinkt["default"] = socket.sinkt["keep-open"]

socket.sink = socket.choose(socket.sinkt)

socket.sourcet["by-length"] = function(soc, length)
    return base.setmetatable({
        getfd = function() return soc:getfd() end,
        dirty = function() return soc:dirty() end
    }, {
        __call = function()
            if length <= 0 then return nil end
            local size = math.min(sock.BLOCKSIZE, length)
            local chunk, err = soc:receive(size)
            if err then return nil, err end
            length = length - string.len(chunk)
            return chunk
        end
    })
end

socket.sourcet["until-closed"] = function(soc)
    local done
    return base.setmetatable({
        getfd = function() return soc:getfd() end,
        dirty = function() return soc:dirty() end
    }, {
        __call = function()
            if done then return nil end
            local chunk, err, partial = soc:receive(sock.BLOCKSIZE)
            if not err then return chunk
            elseif err == "closed" then
                soc:close()
                done = 1
                return partial
            else return nil, err end
        end
    })
end


socket.sourcet["default"] = socket.sourcet["until-closed"]

socket.source = socket.choose(socket.sourcet)

