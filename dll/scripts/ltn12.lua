-----------------------------------------------------------------------------
-- LTN12 - Filters, sources, sinks and pumps.
-- LuaSocket toolkit.
-- Author: Diego Nehab
-- RCS ID: $Id: ltn12.lua,v 1.31 2006/04/03 04:45:42 diego Exp $
-----------------------------------------------------------------------------

-----------------------------------------------------------------------------
-- Declare module
-----------------------------------------------------------------------------
local base = _G
-- local string = require("string")
-- local table = require("table")
-- module("ltn12")
ltn12={}

ltn12.filter = {}
ltn12.source = {}
ltn12.sink = {}
ltn12.pump = {}

-- 2048 seems to be better in windows...
ltn12.BLOCKSIZE = 2048
ltn12._VERSION = "LTN12 1.0.1"

-----------------------------------------------------------------------------
-- Filter stuff
-----------------------------------------------------------------------------
-- returns a high level ltn12.filter that cycles a low-level ltn12.filter
function ltn12.filter.cycle(low, ctx, extra)
    base.assert(low)
    return function(chunk)
        local ret
        ret, ctx = low(ctx, chunk, extra)
        return ret
    end
end

-- chains a bunch of filters together
-- (thanks to Wim Couwenberg)
function ltn12.filter.chain(...)
    local n = table.getn(arg)
    local top, index = 1, 1
    local retry = ""
    return function(chunk)
        retry = chunk and retry
        while true do
            if index == top then
                chunk = arg[index](chunk)
                if chunk == "" or top == n then return chunk
                elseif chunk then index = index + 1
                else
                    top = top+1
                    index = top
                end
            else
                chunk = arg[index](chunk or "")
                if chunk == "" then
                    index = index - 1
                    chunk = retry
                elseif chunk then
                    if index == n then return chunk
                    else index = index + 1 end
                else base.error("Filter returned inappropriate nil") end
            end
        end
    end
end

-----------------------------------------------------------------------------
-- Source stuff
-----------------------------------------------------------------------------
-- create an empty ltn12.source
function ltn12.empty()
    return nil
end

function ltn12.source.empty()
    return ltn12.empty
end

-- returns a ltn12.source that just outputs an error
function ltn12.source.error(err)
    return function()
        return nil, err
    end
end

-- creates a file ltn12.source
function ltn12.source.file(handle, io_err)
    if handle then
        return function()
            local chunk = handle:read(ltn12.BLOCKSIZE)
            if not chunk then handle:close() end
            return chunk
        end
    else return ltn12.source.error(io_err or "unable to open file") end
end

-- turns a fancy ltn12.source into a simple ltn12.source
function ltn12.source.simplify(src)
    base.assert(src)
    return function()
        local chunk, err_or_new = src()
        src = err_or_new or src
        if not chunk then return nil, err_or_new
        else return chunk end
    end
end

-- creates string ltn12.source
function ltn12.source.string(s)
    if s then
        local i = 1
        return function()
            local chunk = string.sub(s, i, i+ltn12.BLOCKSIZE-1)
            i = i + ltn12.BLOCKSIZE
            if chunk ~= "" then return chunk
            else return nil end
        end
    else return ltn12.source.empty() end
end

-- creates rewindable ltn12.source
function ltn12.source.rewind(src)
    base.assert(src)
    local t = {}
    return function(chunk)
        if not chunk then
            chunk = table.remove(t)
            if not chunk then return src()
            else return chunk end
        else
            table.insert(t, chunk)
        end
    end
end

function ltn12.source.chain(src, f)
    base.assert(src and f)
    local last_in, last_out = "", ""
    local state = "feeding"
    local err
    return function()
        if not last_out then
            base.error('Source is empty!', 2)
        end
        while true do
            if state == "feeding" then
                last_in, err = src()
                if err then return nil, err end
                last_out = f(last_in)
                if not last_out then
                    if last_in then
                        base.error('Filter returned inappropriate nil')
                    else
                        return nil
                    end
                elseif last_out ~= "" then
                    state = "eating"
                    if last_in then last_in = "" end
                    return last_out
                end
            else
                last_out = f(last_in)
                if last_out == "" then
                    if last_in == "" then
                        state = "feeding"
                    else
                        base.error('Filter returned ""')
                    end
                elseif not last_out then
                    if last_in then
                        base.error('Filter returned inappropriate nil')
                    else
                        return nil
                    end
                else
                    return last_out
                end
            end
        end
    end
end

-- creates a ltn12.source that produces contents of several sources, one after the
-- other, as if they were concatenated
-- (thanks to Wim Couwenberg)
function ltn12.source.cat(...)
    local src = table.remove(arg, 1)
    return function()
        while src do
            local chunk, err = src()
            if chunk then return chunk end
            if err then return nil, err end
            src = table.remove(arg, 1)
        end
    end
end

-----------------------------------------------------------------------------
-- Sink stuff
-----------------------------------------------------------------------------
-- creates a ltn12.sink that stores into a table
function ltn12.sink.table(t)
    t = t or {}
    local f = function(chunk, err)
        if chunk then table.insert(t, chunk) end
        return 1
    end
    return f, t
end

-- turns a fancy ltn12.sink into a simple ltn12.sink
function ltn12.sink.simplify(snk)
    base.assert(snk)
    return function(chunk, err)
        local ret, err_or_new = snk(chunk, err)
        if not ret then return nil, err_or_new end
        snk = err_or_new or snk
        return 1
    end
end

-- creates a file ltn12.sink
function ltn12.sink.file(handle, io_err)
    if handle then
        return function(chunk, err)
            if not chunk then
                handle:close()
                return 1
            else return handle:write(chunk) end
        end
    else return ltn12.sink.error(io_err or "unable to open file") end
end

-- creates a ltn12.sink that discards data
function ltn12.null()
    return 1
end

function ltn12.sink.null()
    return ltn12.null
end

-- creates a ltn12.sink that just returns an error
function ltn12.sink.error(err)
    return function()
        return nil, err
    end
end

-- chains a ltn12.sink with a ltn12.filter
function ltn12.sink.chain(f, snk)
    base.assert(f and snk)
    return function(chunk, err)
        if chunk ~= "" then
            local filtered = f(chunk)
            local done = chunk and ""
            while true do
                local ret, snkerr = snk(filtered, err)
                if not ret then return nil, snkerr end
                if filtered == done then return 1 end
                filtered = f(done)
            end
        else return 1 end
    end
end

-----------------------------------------------------------------------------
-- Pump stuff
-----------------------------------------------------------------------------
-- pumps one chunk from the ltn12.source to the ltn12.sink
function ltn12.pump.step(src, snk)
    local chunk, src_err = src()
    local ret, snk_err = snk(chunk, src_err)
    if chunk and ret then return 1
    else return nil, src_err or snk_err end
end

-- pumps all data from a ltn12.source to a ltn12.sink, using a step function
function ltn12.pump.all(src, snk, step)
    base.assert(src and snk)
    step = step or ltn12.pump.step
    while true do
        local ret, err = step(src, snk)
        if not ret then
            if err then return nil, err
            else return 1 end
        end
    end
end

