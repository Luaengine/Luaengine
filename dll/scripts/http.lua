-----------------------------------------------------------------------------
-- HTTP/1.1 client support for the Lua language.
-- LuaSocket toolkit.
-- Author: Diego Nehab
-- RCS ID: $Id: http.lua,v 1.71 2007/10/13 23:55:20 diego Exp $
-----------------------------------------------------------------------------

-----------------------------------------------------------------------------
-- Declare module and import dependencies
-------------------------------------------------------------------------------
local base = _G
-- local string = require("string")
-- local table = require("table")
local sock = require("socket.core")
-- local socket = require("socket")
dofile(core.dir.."dll/scripts/socket.lua")
-- local url = require("socket.url")
dofile(core.dir.."dll/scripts/url.lua")
-- local ltn12 = require("ltn12")
dofile(core.dir.."dll/scripts/ltn12.lua")
-- local mime = require("mime")
dofile(core.dir.."dll/scripts/mime.lua")
-- module("socket.http")
http={}

-----------------------------------------------------------------------------
-- Program constants
-----------------------------------------------------------------------------
-- connection timeout in seconds
http.TIMEOUT = 60
-- default port for document retrieval
http.PORT = 80
-- user agent field sent in request
http.USERAGENT = socket._VERSION

-----------------------------------------------------------------------------
-- Reads MIME headers from a connection, unfolding where needed
-----------------------------------------------------------------------------
function http.receiveheaders(sock, headers)
    local line, name, value, err
    headers = headers or {}
    -- get first line
    line, err = sock:receive()
    if err then return nil, err end
    -- headers go until a blank line is found
    while line ~= "" do
        -- get field-name and value
        name, value = socket.skip(2, string.find(line, "^(.-):%s*(.*)"))
        if not (name and value) then return nil, "malformed reponse headers" end
        name = string.lower(name)
        -- get next line (value might be folded)
        line, err  = sock:receive()
        if err then return nil, err end
        -- unfold any folded values
        while string.find(line, "^%s") do
            value = value .. line
            line = sock:receive()
            if err then return nil, err end
        end
        -- save pair in table
        if headers[name] then headers[name] = headers[name] .. ", " .. value
        else headers[name] = value end
    end
    return headers
end

-----------------------------------------------------------------------------
-- Extra sources and sinks
-----------------------------------------------------------------------------
socket.sourcet["http-chunked"] = function(sock, headers)
    return base.setmetatable({
        getfd = function() return sock:getfd() end,
        dirty = function() return sock:dirty() end
    }, {
        __call = function()
            -- get chunk size, skip extention
            local line, err = sock:receive()
            if err then return nil, err end
            local size = base.tonumber(string.gsub(line, ";.*", ""), 16)
            if not size then return nil, "invalid chunk size" end
            -- was it the last chunk?
            if size > 0 then
                -- if not, get chunk and skip terminating CRLF
                local chunk, err, part = sock:receive(size)
                if chunk then sock:receive() end
                return chunk, err
            else
                -- if it was, read trailers into headers table
                headers, err = http.receiveheaders(sock, headers)
                if not headers then return nil, err end
            end
        end
    })
end

socket.sinkt["http-chunked"] = function(sock)
    return base.setmetatable({
        getfd = function() return sock:getfd() end,
        dirty = function() return sock:dirty() end
    }, {
        __call = function(self, chunk, err)
            if not chunk then return sock:send("0\r\n\r\n") end
            local size = string.format("%X\r\n", string.len(chunk))
            return sock:send(size ..  chunk .. "\r\n")
        end
    })
end

-----------------------------------------------------------------------------
-- Low level HTTP API
-----------------------------------------------------------------------------
http.metat = { __index = {} }

function http.open(host, port, create)
    -- create socket with user connect function, or with default
    local c = socket.try((create or socket.tcp)())
    local h = base.setmetatable({ c = c }, http.metat)
    -- create finalized try
    h.try = socket.newtry(function() h:close() end)
    -- set timeout before connecting
    h.try(c:settimeout(http.TIMEOUT))
    h.try(c:connect(host, port or http.PORT))
    -- here everything worked
    return h
end

function http.metat.__index:sendrequestline(method, uri)
    local reqline = string.format("%s %s HTTP/1.1\r\n", method or "GET", uri)
    return self.try(self.c:send(reqline))
end

function http.metat.__index:sendheaders(headers)
    local h = "\r\n"
    for i, v in base.pairs(headers) do
        h = i .. ": " .. v .. "\r\n" .. h
    end
    self.try(self.c:send(h))
    return 1
end

function http.metat.__index:sendbody(headers, source, step)
    source = source or ltn12.source.empty()
    step = step or ltn12.pump.step
    -- if we don't know the size in advance, send chunked and hope for the best
    local mode = "http-chunked"
    if headers["content-length"] then mode = "keep-open" end
    return self.try(ltn12.pump.all(source, socket.sink(mode, self.c), step))
end

function http.metat.__index:receivestatusline()
    local status = self.try(self.c:receive(5))
    -- identify HTTP/0.9 responses, which do not contain a status line
    -- this is just a heuristic, but is what the RFC recommends
    if status ~= "HTTP/" then return nil, status end
    -- otherwise proceed reading a status line
    status = self.try(self.c:receive("*l", status))
    local code = socket.skip(2, string.find(status, "HTTP/%d*%.%d* (%d%d%d)"))
    return self.try(base.tonumber(code), status)
end

function http.metat.__index:receiveheaders()
    return self.try(http.receiveheaders(self.c))
end

function http.metat.__index:receivebody(headers, sink, step)
    sink = sink or ltn12.sink.null()
    step = step or ltn12.pump.step
    local length = base.tonumber(headers["content-length"])
    local t = headers["transfer-encoding"] -- shortcut
    local mode = "default" -- connection close
    if t and t ~= "identity" then mode = "http-chunked"
    elseif base.tonumber(headers["content-length"]) then mode = "by-length" end
    return self.try(ltn12.pump.all(socket.source(mode, self.c, length),
        sink, step))
end

function http.metat.__index:receive09body(status, sink, step)
    local source = ltn12.source.rewind(socket.source("until-closed", self.c))
    source(status)
    return self.try(ltn12.pump.all(source, sink, step))
end

function http.metat.__index:close()
    return self.c:close()
end

-----------------------------------------------------------------------------
-- High level HTTP API
-----------------------------------------------------------------------------
function http.adjusturi(reqt)
    local u = reqt
    -- if there is a proxy, we need the full url. otherwise, just a part.
    if not reqt.proxy and not PROXY then
        u = {
           path = socket.try(reqt.path, "invalid path 'nil'"),
           params = reqt.params,
           query = reqt.query,
           fragment = reqt.fragment
        }
    end
    return url.build(u)
end

function http.adjustproxy(reqt)
    local proxy = reqt.proxy or PROXY
    if proxy then
        proxy = url.parse(proxy)
        return proxy.host, proxy.port or 3128
    else
        return reqt.host, reqt.port
    end
end

function http.adjustheaders(reqt)
    -- default headers
    local lower = {
        ["user-agent"] = http.USERAGENT,
        ["host"] = reqt.host,
        ["connection"] = "close, TE",
        ["te"] = "trailers"
    }
    -- if we have authentication information, pass it along
    if reqt.user and reqt.password then
        lower["authorization"] = 
            "Basic " ..  (mime.b64(reqt.user .. ":" .. reqt.password))
    end
    -- override with user headers
    for i,v in base.pairs(reqt.headers or lower) do
        lower[string.lower(i)] = v
    end
    return lower
end

-- default url parts
http.default = {
    host = "",
    port = http.PORT,
    path ="/",
    scheme = "http"
}

function http.adjustrequest(reqt)
    -- parse url if provided
    local nreqt = reqt.url and url.parse(reqt.url, http.default) or {}
    -- explicit components override url
    for i,v in base.pairs(reqt) do nreqt[i] = v end
    if nreqt.port == "" then nreqt.port = 80 end
    socket.try(nreqt.host and nreqt.host ~= "", 
        "invalid host '" .. base.tostring(nreqt.host) .. "'")
    -- compute uri if user hasn't overriden
    nreqt.uri = reqt.uri or http.adjusturi(nreqt)
    -- ajust host and port if there is a proxy
    nreqt.host, nreqt.port = http.adjustproxy(nreqt)
    -- adjust headers in request
    nreqt.headers = http.adjustheaders(nreqt)
    return nreqt
end

function http.shouldredirect(reqt, code, headers)
    return headers.location and
           string.gsub(headers.location, "%s", "") ~= "" and
           (reqt.redirect ~= false) and
           (code == 301 or code == 302) and
           (not reqt.method or reqt.method == "GET" or reqt.method == "HEAD")
           and (not reqt.nredirects or reqt.nredirects < 5)
end

function http.shouldreceivebody(reqt, code)
    if reqt.method == "HEAD" then return nil end
    if code == 204 or code == 304 then return nil end
    if code >= 100 and code < 200 then return nil end
    return 1
end

-- forward declarations
http.trequest=nil
http.tredirect=nil

function http.tredirect(reqt, location)
    local result, code, headers, status = http.trequest {
        -- the RFC says the redirect URL has to be absolute, but some
        -- servers do not respect that
        url = url.absolute(reqt.url, location),
        source = reqt.source,
        sink = reqt.sink,
        headers = reqt.headers,
        proxy = reqt.proxy, 
        nredirects = (reqt.nredirects or 0) + 1,
        create = reqt.create
    }   
    -- pass location header back as a hint we redirected
    headers = headers or {}
    headers.location = headers.location or location
    return result, code, headers, status
end

function http.trequest(reqt)
    -- we loop until we get what we want, or
    -- until we are sure there is no way to get it
    local nreqt = http.adjustrequest(reqt)
    local h = http.open(nreqt.host, nreqt.port, nreqt.create)
    -- send request line and headers
    h:sendrequestline(nreqt.method, nreqt.uri)
    h:sendheaders(nreqt.headers)
    -- if there is a body, send it
    if nreqt.source then
        h:sendbody(nreqt.headers, nreqt.source, nreqt.step) 
    end
    local code, status = h:receivestatusline()
    -- if it is an HTTP/0.9 server, simply get the body and we are done
    if not code then
        h:receive09body(status, nreqt.sink, nreqt.step)
        return 1, 200
    end
    local headers
    -- ignore any 100-continue messages
    while code == 100 do 
        headers = h:receiveheaders()
        code, status = h:receivestatusline()
    end
    headers = h:receiveheaders()
    -- at this point we should have a honest reply from the server
    -- we can't redirect if we already used the source, so we report the error 
    if http.shouldredirect(nreqt, code, headers) and not nreqt.source then
        h:close()
        return http.tredirect(reqt, headers.location)
    end
    -- here we are finally done
    if http.shouldreceivebody(nreqt, code) then
        h:receivebody(headers, nreqt.sink, nreqt.step)
    end
    h:close()
    return 1, code, headers, status
end

function http.srequest(u, b)
    local t = {}
    local reqt = {
        url = u,
        sink = ltn12.sink.table(t)
    }
    if b then
        reqt.source = ltn12.source.string(b)
        reqt.headers = {
            ["content-length"] = string.len(b),
            ["content-type"] = "application/x-www-form-urlencoded"
        }
        reqt.method = "POST"
    end
    local code, headers, status = socket.skip(1, http.trequest(reqt))
    return table.concat(t), code, headers, status
end

http.request = sock.protect(function(reqt, body)
    if base.type(reqt) == "string" then return http.srequest(reqt, body)
    else return http.trequest(reqt) end
end)
