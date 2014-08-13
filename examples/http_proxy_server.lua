local socket = require "levent.socket"
local levent = require "levent.levent"
local seri = require "levent.tpseri"
local dns    = require "levent.dns"

local mt = {}
mt.__index = mt

BUFLEN = 4096
mt.get_base_header = function(self)
    local start_pos, end_pos
    while true do
        self.client_buffer = self.client_buffer .. self.client:recv(BUFLEN)
        start_pos, end_pos = self.client_buffer:find("\n")
        if start_pos then
            break
        end
    end
    base_header = self.client_buffer:sub(1, start_pos)
    local result = {}
    for i in string.gmatch(base_header, "%S+") do
        table.insert(result, i)
    end
    return table.unpack(result)
end

mt.connect_target = function(self, host)
    local i = host:find(":")
    local port
    if not i then
        port = 80
    else
        host = host:sub(1, i)
        port = tonumber(host:sub(i,-1))
    end
    local ips, err = dns.resolve(host)
    local ip = ips[1]
    self.target, err = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    self.target:connect(ip, port)
end

mt.method_CONNECT = function(self)
    print("enter method connect") 
end

mt.flush_two_socket = function(self)
    local count = 1
    local dirty
    while true do
        self.target:set_timeout(1)
        self.client:set_timeout(1)
        local data, err = self.target:recv(BUFLEN)
        if data and #data > 0 then
            print("recv", data)
            self.client:sendall(data)
            dirty = true
        else
            dirty = false
        end
        local send_data, err = self.client:recv(BUFLEN)
        if send_data and #send_data > 0 then
            print("client keep send:", send_data)
            self.target:sendall(send_data)
            dirty = true
        else
            dirty = false
        end
        if not dirty then
            count = count + 1
        end
        if count > 3 then
            break
        end
    end
end

mt.method_others = function(self)
    self.path = self.path:sub(8, -1)
    local i = self.path:find("/")
    local host = self.path:sub(1, i - 1)
    local path = self.path:sub(i, -1)
    self:connect_target(host)
    local first_data = string.format("%s %s %s \r\n", self.method, path, self.protocol)..self.client_buffer
    print("first_data", first_data)
    self.target:sendall(first_data)
    self:flush_two_socket()
end

local other_method = {
    OPTIONS=1,
    GET = 1,
    HEAD = 1,
    POST=1,
    PUT=1,
    DELETE=1,
    TRACE=1,
}

mt.handle = function(self, csock)
    self.client = csock
    self.client_buffer = ""
    self.timeout = timeout
    self.method, self.path, self.protocol = self:get_base_header()
    print(self.method, self.path, self.protocol)
    if self.method == "CONNECT" then
        self:method_CONNECT()
    elseif other_method[self.method] then
        self:method_others()
    end
    self.client:close()
    self.target:close()
    print("close all socket")
end

local sock, err = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
assert(sock, errmsg)
print("bind:", sock:bind("0.0.0.0", 8858))
print("listen:", sock:listen())

function start_server()
    while true do
        local csock, err = sock:accept()
        if not csock then
            print("accept failed:", err)
            break
        end
        print("new conn from:", csock:getpeername())
        local a = {}
        setmetatable(a, mt)
        levent.spawn(a.handle, a, csock)
    end
end

levent.start(start_server)
