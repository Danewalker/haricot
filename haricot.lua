local socket = require "socket"

-- NOTES:
-- `job` format: {id=...,data=...}

--- low level

local default_cfg = function()
  return {
    max_job_size = 2^16,
  }
end

local is_posint = function(x)
  return ( (type(x) == "number") and (math.floor(x) == x) and (x >= 0) )
end

local mkcmd = function(cmd,...)
  return table.concat({cmd,...}," ") .. "\r\n"
end

local mkcmd2 = function(cmd,data,...)
  return mkcmd(cmd,...) .. data .. "\r\n"
end

local call = function(self,cmd,...)
  self.cnx:send(mkcmd(cmd,...))
  return self.cnx:receive("*l")
end

local call2 = function(self,cmd,data,...)
  self.cnx:send(mkcmd2(cmd,data,...))
  return self.cnx:receive("*l")
end

local recv = function(self,bytes)
  assert(is_posint(bytes))
  local r = self.cnx:receive(bytes+2)
  return r:sub(1,bytes)
end

--- methods

-- connection

local connect = function(self,server,port)
  self.cnx = socket.tcp()
  self.cnx:connect(server,port)
  return true
end

-- producer

local put = function(self,pri,delay,ttr,data)
  assert(
    is_posint(pri) and (pri < 2^32) and
    is_posint(delay) and
    is_posint(ttr) and (ttr > 0)
  )
  local bytes = #data
  assert(bytes < self.cfg.max_job_size)
  local res = call2(self,"put",data,pri,delay,ttr,bytes)
  local id = tonumber(res:match("^INSERTED (%d+)$"))
  if id then
    return true,id
  else
    return false,res
  end
end

-- consumer

local reserve = function(self)
  local res = call(self,"reserve")
  local id,bytes = res:match("^RESERVED (%d+) (%d+)$")
  id,bytes = tonumber(id),tonumber(bytes)
  local data = recv(self,bytes)
  if id --[[and bytes]] then
    return true,{id=id,data=data}
  else
    return false,res
  end
end

local delete = function(self,id)
  local res = call(self,"delete",id)
  local ok = res:match("^DELETED$")
  if ok then
    return true
  else
    return false,res
  end
end

--- class

local methods = {
  -- connection
  connect = connect, -- (server,port) -> ok
  -- producer
  put = put, -- (pri,delay,ttr,data) -> ok,[id|err]
  -- consumer
  reserve = reserve, -- () -> ok,[job|err]
  delete = delete, -- (id) -> ok,[err]
}

local new = function(server,port)
  local r = {cfg = default_cfg()}
  connect(r,server,port)
  return setmetatable(r,{__index = methods})
end

return {
  new = new,
}
