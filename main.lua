local WaveBoard = require('waveboard/skaarhoj_waveboard_eth_driver_v_1_0_0')
local Server = require('waveboard/qsys_mock_eth_server_v_1_0_0')

local server = Server.TcpSocketServer:New()
local interface = Server.DriverInterface:New()
local waveboard = WaveBoard:new()
local registered = false

local Slider = {
  new = function(self, object)
    object = object or {}
    setmetatable(object, self)
    self.__index = self
    return object
  end,

  trigger = function(self, directive, status, interface)
    print(directive, status, interface)
    if self.adapter ~= nil then
      self.adapter:relay(status, interface)
    end
  end,

  send = function(self, value)
    self.interface:Put({
      ['directive'] = 'HWCx',
      ['value'] = self.slider,
      ['parameters'] = {
        ['Percent'] = value,
        ['OutputType'] = 'Strength'
      }
    })
  end
}

local Meter = {
  new = function(self, object)
    object = object or {}
    setmetatable(object, self)
    self.__index = self
    return object
  end,

  trigger = function(self, directive, status, interface)
    local hundreds = 0
    status = status['status']
    hundreds = math.floor(status / 100)
    if status - hundreds * 100 >= 50 then
      hundreds = hundreds + 1
    end
    status = hundreds * 100
    status = status * .1
    interface:Put({
      ['directive'] = 'HWCxValue',
      ['value'] = self.meter,
      ['parameters'] = {
        ['Percent'] = status,
        ['OutputType'] = 'Strength'
      }
    })
  end
}

local Fader = {
  new = function(self, object)
    object = object or {}
    setmetatable(object, self)
    self.__index = self
    return object
  end,

  trigger = function(self, directive, status, interface)
    print(directive, status, interface, 'callback values')
    self.meter:trigger(directive, status, interface)
    self.slider:trigger(directive, status, interface)
  end
}


local ToggleButton = {
  new = function(self, object)
    object = object or {}
    setmetatable(object, self)
    self.__index = self
    return object
  end,

  trigger = function(self, directive, status, interface)
    status = status['status']
    if status == 'Down' then
      if self.toggled then
        interface:Put({
          ['directive'] = self.command,
          ['value'] = self.hwc,
          ['parameters'] = {
            [self.parameter] = self.off
          }
        })
        self.toggled = false
      else
        interface:Put({
          ['directive'] = self.command,
          ['value'] = self.hwc,
          ['parameters'] = {
            ['Color'] = self.on
          }
        })
        self.toggled = true
      end
    end
  end
}

local TriggerButton = {
  new = function(self, object)
    object = object or {}
    setmetatable(object, self)
    self.__index = self
    return object
  end,

  trigger = function(self, directive, status, interface)
    status = status['status']
    if status == 'Down' then
      interface:Put({
        ['directive'] = 'HWCValue',
        ['value'] = self.hwc,
        ['parameters'] = {
          ['Color'] = 'White'
        }
      })
      interface:Put({
        ['directive'] = 'HWCcValue',
        ['value'] = self.hwc,
        ['parameters'] = {
          ['RGB'] = self.color
        }
      })
    else
      interface:Put({
        ['directive'] = 'HWCValue',
        ['value'] = self.hwc,
        ['parameters'] = {
          ['Color'] = 'Off'
        }
      })
      interface:Put({
        ['directive'] = 'HWCcValue',
        ['value'] = self.hwc,
        ['parameters'] = {
          ['RGB'] = 'Default'
        }
      })
    end
  end
}

interface.Driver = waveboard

function wait(seconds)
    local start = os.time()
    repeat until os.time() > start + seconds
end

function eventHandler(server, data)
  interface.Client = server,
  interface.Driver:SetInterface(interface)
  interface.Driver:ParseData(data)
  if interface.Driver.Groups ~= nil and not registered then
    for index, group in pairs(interface.Driver.Groups) do
      if string.find(index, 'Group') then
        local slider = Slider:new({
          interface = interface.Driver,
          slider = group['Fader']
        })
        local meter = Meter:new({
          meter = group['MTR']
        })
        local fader = Fader:new({
          meter = meter,
          slider = slider
        })
        local mute = ToggleButton:new({
          toggled = false,
          hwc = tostring(group['A']),
          command = 'HWCValue',
          on = 'Red',
          off = 'Green',
          parameter = 'Color'
        })
        local cue = TriggerButton:new({
          hwc = tostring(group['B']),
          color = 'Amber'
        })
        local vu = TriggerButton:new({
          hwc = tostring(group['D']),
          color = 'Mint'
        })
        interface.Driver:Watcher(
          'HWC',
          tostring(group['A']),
          {},
          mute
        )
        interface.Driver:Watcher(
          'HWC',
          tostring(group['D']),
          {},
          vu
        )
        interface.Driver:Watcher(
          'HWC',
          tostring(group['B']),
          {},
          cue
        )
        interface.Driver:Watcher(
          'HWC',
          tostring(group['Fader']),
          {},
          fader
        )
      end
    end
    registered = true
  end
end

server.EventHandler = eventHandler
server:Listen(9923)
