local socket = require('socket')

local TcpSocketServer = {
  __Server = nil,
  __Port = nil,
  __Client = nil,
  EventHandler = nil,

  New = function(self, object)
    object = object or {}
    setmetatable(object, self)
    self.__index = self
    return object
  end,

  Listen = function(self, port)
    self.__Port = port
    self.__Server = assert(socket.bind('*', self.__Port))
    self.__TCP = assert(socket.tcp())
    self:__Receive()
  end,

  __Receive = function(self)
    while true do
      local client = self.__Server:accept()
      local data, err = client:receive()
      while not err do
        if data then
          if self.EventHandler ~= nil then
            self.EventHandler(client, data)
          end
        end
        data, err = client:receive()
      end
    end
  end

}

local DriverInterface = {
  Driver = nil,
  Log = function(self, error)
    print(error)
  end,

  New = function(self, object)
    object = object or {}
    setmetatable(object, self)
    self.__index = self
    return object
  end,

  Send = function(self, directive)
    self.Client:send(directive)
  end,

  Error = function(self, error)
    self:Log(error)
  end,

  EventHandler = function(self, server, data)
    self.Client = server
    self.Driver:ParseData(data)
  end
}

return {
  TcpSocketServer = TcpSocketServer,
  DriverInterface = DriverInterface
}
