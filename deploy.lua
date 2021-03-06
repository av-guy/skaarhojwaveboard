local json = require("rapidjson")
local CUE_COLOR = 'Amber'
local VU_COLOR = 'Mint'
local MINIMUM = -40
local MAXIMUM = 0
local PORT = 9923
local PhysicalControls = {}
local METER = nil
local VU = nil
local SERVER = nil
local CUES = {}

--- WaveBoard Ethernet Driver Start -----------------------------------------------------------------------------------

local Watcher = {
  callback = nil,
  params = nil,
  status = {},

  new = function(self, object)
    object = object or {}
    setmetatable(object, self)
    self.__index = self
    return object
  end,

  write = function(self, status, params)
    self.status = {
      ['status'] = status,
      ['params'] = params
    }
  end,

  notify = function(self, directive, interface)
    self.status['status'] = self.status['status']:gsub("%s+", "")
    if type(self.callback) == 'table' then
      self.callback:trigger(directive, self.status, interface)
    else
      self.callback(directive, self.status, interface)
    end
  end,

  matches = function(self, params)
    if next(self.params) == nil and next(params) == nil then
      return true
    else
      for index, param in pairs(params) do
        if not self.params[index] then
          return false
        end
      end
      return true
    end
  end
}

local Driver = {
  __ERROR = 'nack',
  __BUFFER = '',
  __MAX_BUFFER = 2048,
  __TERMINATOR = '\n',
  __VALID = {
    ['Commands'] = {
      ['HWCcValue'] = 1,
      ['HWCxValue'] = 1,
      ['HWCValue'] = 1,
      ['HWCxValue'] = 1,
      ['HWCtValue'] = 1,
      ['SleepTimer'] = 1
    },
    ['Watchers'] = {
      ['HWC'] = 1
    }
  },
  __MATCHES = {
    ['list'] = '__SynchronizeActivePanel',
    ['ping'] = '__SynchronizePingMessage',
    ['nack'] = '__InvalidResponse',
    -- ['_panelTopology_HWC=.*}}}'] = '__SynchronizeTopology',
    ['HWC#(%d*)=(.*)'] = '__SynchronizeControl',
    ['HWC#(%d*)(%.%d)=(.*)'] = '__SynchronizeMasterData' -- HWC#75.4=Down
  },
  __WATCHERS = {},
  HWCValues = {
    ['Blinking'] = {
      ['Fast'] = 256,
      ['Slow'] = 1024
    },
    ['Color'] = {
      ['Off'] = 0,
      ['Red'] = 2,
      ['Green'] = 3,
      ['White'] = 4,
      ['Dimmed'] = 5
    },
    ['RGB'] = {
      ['Default'] = 128,
      ['Off'] = 129,
      ['White'] = 130,
      ['Warm White'] = 131,
      ['Red'] = 132,
      ['Rose'] = 133,
      ['Pink'] = 134,
      ['Purple'] = 135,
      ['Amber'] = 136,
      ['Yellow'] = 137,
      ['Dark blue'] = 138,
      ['Blue'] = 139,
      ['Ice'] = 140,
      ['Cyan'] = 141,
      ['Spring'] = 142,
      ['Green'] = 143,
      ['Mint'] = 144
    },
    ['FormatValues'] = {
      ['Integer'] = 0,
      ['Float2Dec'] = 1,
      ['Percent'] = 2,
      ['dB'] = 3,
      ['Frames'] = 4,
      ['Fraction'] = 5,
      ['Kelvin'] = 6,
      ['Hidden'] = 7,
      ['Float3Dec'] = 8,
      ['Float2.0Dec'] = 9,
      ['TextLine'] = 10,
      ['TextLines'] = 11,
    },
    ['ArrayPlacement'] = {
      ['Value'] = 1,
      ['Format'] = 2,
      ['Fine'] = 3,
      ['Title'] = 4,
      ['IsLabel'] = 5,
      ['Label1'] = 6,
      ['Label2'] = 7,
      ['Value2'] = 8,
      ['ValuesPair'] = 9,
      ['Scale'] = 10,
      ['ScaleRangeLow'] = 11,
      ['ScaleRangeHigh'] = 12,
      ['ScaleLimitLow'] = 13,
      ['ScaleLimitHigh'] = 14,
      ['Image'] = 15,
      ['Font'] = 16,
      ['FontSize'] = 17,
      ['Advanced'] = 18
    },
    ['OutputType'] = {
      ['Strength'] = 1,
      ['Directional'] = 2,
      ['ShowSteps'] = 3,
      ['VUMetering'] = 4,
      ['Fader'] = 5,
    }
  },
  BLOCKING = false,

  SetInterface = function(self, interface)
    self.interface = interface
  end,

  new = function(self, object)
    object = object or {}
    setmetatable(object, self)
    self.__index = self
    return object
  end,


  --- String building method.
  --
  -- HWCt Text values adhere to the following format:
  --
  -- [value]|[format]|[fine]|[Title]|[islabel]|[label 1]|[label 2]|[value2]|
  -- [values pair]|[scale]|[scale range low]|[scale range high]|
  -- [scale limit low]|[scale limit high]|[img]|[font]|[font size]|
  -- [advanced settings].
  --
  -- __BuildHWCtString loops through the supplied values and creates a
  -- pipe-delimited string matching the format specified by the Raw Panel API.
  --
  -- @param arr table of values needing concatenation
  --
  -- @return string containing pipe delimited values
  __BuildHWCtString = function(self, arr)
    local text = ''
    for index, value in pairs(arr) do
      if value ~= 'omit' then
        value = self:__ConvertValue(value)
        text = text .. value .. '|'
      else
        text = text .. '|'
      end
    end
    return text
  end,


  --- Helper method for HWC commands.
  --
  -- Verifies, computes, and generates HWC command string matching format
  -- HWC#xx==yy
  --
  -- @param value hwc target
  -- @param parameters table of parameter values
  --
  -- @return string command
  __ComputeHWCValue = function(self, value, parameters)
    local color = 0
    local blinking = 0
    local computed = 0
    local speed = nil
    local command = 'HWC#' .. value
    local HWCValues = self.HWCValues
    local __color = nil

    -- Check if parameters contain Blinking flag
    if self:__HasValue(parameters, 'Blinking') then
      blinking = parameters['Blinking']
      if blinking == 'Fast' or blinking == 'Slow' then
        blinking = HWCValues['Blinking'][blinking]
      else
        self:__Error('Blinking provided, but no speed defined; using slow')
        blinking = HWCValues['Blinking']['Slow'] -- Use default if neither
      end
    end

    if self:__HasValue(parameters, 'Color') then
      __color = parameters['Color']
      if __color == nil then
        self:__Error('No color parameter provided')
      else
        color = self.HWCValues['Color'][__color]
        if color == nil then
          self:__Error('Color value not valid: ' .. __color .. '; using white')
          color = HWCValues['Color']['White']
        end
      end
    else
      self:__Error('No color parameter provided')
    end

    computed = color + blinking
    return command .. '=' .. computed
  end,


  --- Helper method for HWCc commands.
  --
  -- Verifies, computes, and generates HWCc command string matching format
  -- HWCc#xx=yy
  --
  -- @param value hwc target
  -- @param rgb color value
  --
  -- @return string if rgb color is found
  -- @return nil if rgb color is not found
  __ComputeHWCcValue = function(self, value, rgb)
    local color = nil
    local computed = 0
    local command = 'HWCc#' .. value
    local HWCValues = self.HWCValues

    color = HWCValues['RGB'][rgb]

    if color then
      computed = 7 | color -- Lua 5.3 version
      -- computed = bit.bor(7, color) -- Per the demo scripts provided on GitHub
      return command .. '=' .. color
    else
      self:__Error(
          'Supplied RGB value does not exist', rgb
      )
      return nil
    end
  end,


  --- Helper method for HWCt commands.
  --
  --
  -- Verifies, computes, and assigns text elements in the correct order.
  -- Returns a pipe-delimited string.
  --
  -- https://github.com/SKAARHOJ/Support/raw/master/Manuals/DC_SKAARHOJ_RawPanel.pdf
  --
  -- @param value hwc target
  -- @param parameters table defining the text elements
  --
  -- @return string containing pipe-delimited characters
  -- @see __BuildHWCtString
  __ComputeHWCtValue = function(self, value, parameters)
    local arr = {}
    local command = 'HWCt#' .. value
    local format = nil
    local HWCValues = self.HWCValues
    local error = 'Incorrect format value: '

    arr[value] = HWCValues['FormatValues']['Integer']

    for index, value in pairs(HWCValues['ArrayPlacement']) do
      if parameters[index] ~= nil then
        if index == 'Format' then
          format = HWCValues['FormatValues'][parameters['Format']]
          if format == nil then
            self:__Error(error .. parameters['Format'] .. '; using Integer')
          else
            arr[value] = HWCValues['FormatValues'][parameters['Format']]
          end
        else
          arr[value] = parameters[index]
        end
      else
        arr[value] = 'omit'
      end
    end

    return command .. '=' .. self:__BuildHWCtString(arr)
  end,


  --- Helper method for HWCx commands.
  --
  --
  -- Verifies, computes, and returns command string matching format
  -- HWCx#xx=yy.
  --
  -- https://github.com/SKAARHOJ/Support/raw/master/Manuals/DC_SKAARHOJ_RawPanel.pdf
  --
  -- @param value hwc target
  -- @param parameters table defining the text elements
  --
  -- @return string containing pipe-delimited characters
  -- @see __ToBits
  -- @see __ToDecimal
  __ComputeHWCxValue = function(self, value, parameters)
    local outputType = 0
    local outputValue = math.floor(parameters['Percent'] / 100 * 1000)
    local outputIndividual = '00' -- Unused but required per RawPanel spec
    local command = 'HWCx#' .. value
    local HWCValues = self.HWCValues

    if self:__HasValue(parameters, 'OutputType') then
      outputType = parameters['OutputType']
      if HWCValues['OutputType'][outputType] ~= nil then
        outputType = HWCValues['OutputType'][outputType]
        outputType = table.concat(self:__ToBits(outputType, 4))
        outputValue = table.concat(self:__ToBits(outputValue, 10), "")
        outputConcat = outputType .. outputIndividual .. outputValue
        command = command .. '=' .. math.floor(self:__ToDecimal(outputConcat))
        return command
      else
        self:__Error('OutputType not supported: ' .. outputType)
      end
    else
      self:__Error('Cannot execute HWCx command; no OutputType supplied')
    end
    return nil
  end,


  --- Boolean conversion method.
  --
  -- The RawPanel API, in certain cases, considers '0' to be false and '1' to be
  -- true. This method converts true to '1' or false to '0'. If the value passed
  -- into the method is neither true or false, the value is returned.
  --
  -- @param value Value that needs conversion
  --
  -- @return string 1 for true, 0 for false, or value if neither
  __ConvertValue = function(self, value)
    if value == true then
      return '1'
    elseif value == false then
      return '0'
    else
      return value
    end
  end,

  --- Documents an error.
  --
  -- Logs an error using this driver interface's Error method.
  --
  -- @param error error message
  --
  -- @return nil
  __Error = function(self, error)
    self.interface:Error(error)
  end,


  --- Checks if table has a value.
  --
  -- Iteratively checks a table to see if either index or value is a match for
  -- the supplied value.
  --
  -- @param tab table to be searched
  -- @param val value to be asserted
  --
  -- @return boolean true if found false if not
  __HasValue = function(self, tab, val)
    for index, value in pairs(tab) do
      if index == val or value == val then
        return true
      end
    end
    return false
  end,


  --- Documents a bad response.
  --
  -- Documents an error using __Error.
  --
  -- @param data the data responsible for triggering this method
  --
  -- @return nil
  -- @see __Error
  __InvalidResponse = function(self, data)
    self:__Error('Got bad response: ' .. data)
  end,


  --- Sends device commands.
  --
  -- Sends a command using this driver interface's TCP socket.
  --
  -- @param directive command string
  --
  -- @return nil
  __Send = function(self, directive)
    -- print('sending', directive)
    self.interface:Send(directive .. '\n')
  end,


  --- Slices a string value and returns the result.
  --
  -- Method used to keep the buffer from overflowing. Returns slice of string
  -- starting at first index and ending at last index.
  --
  -- @param str string that needs to be sliced
  -- @param first starting index
  -- @param last ending index
  --
  -- @return string sliced string
  __SliceString = function(self, str, first, last)
    return string.sub(str, first, last)
  end,


  --- Synchronizes ActivePanel response when list request comes in.
  --
  -- The WaveBoard, at intervals, will send a 'list' request. In response to
  -- this request, the driver must send ActivePanel=1\n. This is the callback
  -- method that fires when the list request is detected. This method also
  -- requests the Panel Topology should the Groups instance property be nil.
  --
  -- @param data the match data
  --
  -- @return nil
  __SynchronizeActivePanel = function(self, data)
    self:__Send('ActivePanel=1')
    if self.Groups == nil then
      self:__Send('PanelTopology?\n')
    end
  end,


  --- Synchronizes Topology.
  --
  -- This method clears the panel topology response of its prefix
  -- (_panelTopology_HWC=) and then calls __SortByGroup to set control
  -- group data.
  --
  -- @param data the match data
  --
  -- @return nil
  __SynchronizeTopology = function(self, data)
    data = string.gsub(data, '_panelTopology_HWC=', '')
    self.Groups = self:__SortByGroup(data)
  end,


  --- Acknowledges ping message.
  --
  -- Sometimes the Waveboard will send ping requests; this just sends ack
  -- back whenever ping is detected.
  --
  -- @param data the match data
  --
  -- @return nil
  __SynchronizePingMessage = function(self, data)
    self:__Send('ack')
  end,


  --- Detects when the device is not asleep
  --
  -- The Waveboard will periodically fall asleep; this triggers the callback on the sleep listener.
  --
  -- @param data the match data
  --
  -- @return nil
  __SynchronizeSleep = function(self, data)
    print('trying to synchronize sleep state')
    return 1
  end,


  --- Synchronize values with their watchers
  --
  -- When a value is received from the Waveboard, this function will look to
  -- see if a watcher for that value exists. When found, it will notify that watcher
  -- a change has occurred.
  --
  -- @param control the control number
  -- @param value the value to be written
  -- @param params additional parameter constraints
  --
  -- @return nil
  __Synchronize = function(self, control, value, params)
    if self.__WATCHERS['HWC'][control] ~= nil then
      local watchers = self.__WATCHERS['HWC'][control]
      for _, watcher in pairs(watchers) do
        if watcher:matches(params) then
          watcher:write(value, params)
          watcher:notify('HWC', self)
        end
      end
    end
  end,

  --- Synchronizes control messages with corresponding watchers.
  --
  -- Detects button presses and slider movements, and maps them to their
  -- respective watchers.
  --
  -- @param data the match data
  --
  -- @return nil
  __SynchronizeControl = function(self, data)
    local match = '(%d*)=(.*)'
    local _, _, control, value = string.find(data, match)
    local params = {}
    local slider = nil

    if self.__WATCHERS['HWC'] ~= nil then
      _, _, slider = string.find(value, 'Abs:(%d*)')
      if slider then
        value = slider
      end
      self:__Synchronize(control, value, params)
    end
  end,

  --- Synchronizes masked control messages with corresponding watchers.
  --
  -- Detects button presses and slider movements, and maps these movements
  -- to their respective watchers only if they have a mask property.
  --
  -- @param data the match data
  --
  -- @return nil
  __SynchronizeMasterData = function(self, data)
    local match = '(%d*)(%.(%d))=(.*)'
    local _, _, control, _, mask, value = string.find(data, match)
    self:__Synchronize(control, value, {})
  end,


  --- Sort controls by group number.
  --
  -- Raw Panel control topology assigns an ID to each control; these control ID's
  -- are target values for each Raw Panel API command. Managing these ID's
  -- manually is cumbersome, but this function makes it easier. When topology data
  -- is received, that data is broken down into groups
  -- (Group1, Group2, ...Group[n], and Master).
  --
  -- @param data topology data
  --
  -- @return table group of groups of controls
  __SortByGroup = function(self, data)
    local decoded = json.decode(data)
    local hwc = decoded['HWc']
    local groups = {}
    local text = ''
    local sub = ''
    local key = nil
    local current = nil
    local match = nil
    local number = nil

    for index, values in pairs(hwc) do
      text = values['txt']
      if string.find(text, 'Disp') then
        sub = string.gsub(text, 'Disp', '')
        group = 'Group' .. sub
        if group == 'Group' then
          group = 'Master'
        end
        groups[group] = {}
        current = groups[group]
        current['Disp'] = values['id']
      else
        if group ~= 'Master' then
          match = string.find(text, '%d')
          if match then
            number = string.sub(text, match, match)
            text = string.gsub(text, number, '')
            if string.find(text, 'Fader') then
              text = 'Fader'
            elseif string.find(text, 'MTR') then
              text = 'MTR'
            end
          end
        end
        current[text] = values['id']
      end
    end
    return groups
  end,

  --- Converts an integer to binary.
  --
  -- Only necessary for Lua < 5.3 (Lua for Windows uses 5.1).
  -- https://stackoverflow.com/questions/9079853/lua-print-integer-as-a-binary
  --
  -- @param num integer needing conversion
  -- @param bits number of bits used to represent num
  --
  -- @return table containing binary represenation OR error message
  __ToBits = function(self, num, bits)
    local t = {}
    for b = bits, 1, -1 do
      rest = math.floor(math.fmod(num, 2))
      t[b] = rest
      num = math.floor((num - rest) / 2)
    end
    if num == 0 then
      return t
    else
      return { 'Not enough bits to represent this number' }
    end
  end,


  --- Converts binary to integer.
  --
  -- Only necessary for Lua < 5.3 (Lua for Windows uses 5.1).
  -- https://stackoverflow.com/questions/37543274/how-do-i-convert-binary-to-decimal-lua
  --
  -- @param bits binary represenation of number
  --
  -- @return integer sum of the binary digits
  __ToDecimal = function(self, bits)
    bits = string.reverse(bits)
    local sum = 0
    for i = 1, string.len(bits) do
      num = string.sub(bits, i, i) == '1' and 1 or 0
      sum = sum + num * math.pow(2, i - 1)
    end
    return sum
  end,


  --- Parses the incoming data for matches.
  --
  -- Stores and manages received buffer data. Checks data for matches and
  -- calls the corresponding method.
  --
  -- @param data received data
  --
  -- @return nil
  ParseData = function(self, data)
    local matched = nil
    local count = 0
    local lastIndex = 0

    self.__BUFFER = self.__BUFFER .. data

    for __match, callback in pairs(self.__MATCHES) do
      first, last = string.find(self.__BUFFER, __match)
      if first and last then
        if last > lastIndex then
          lastIndex = last
        end
        matched = string.sub(self.__BUFFER, first, last)
        callback = self[callback]
        callback(self, matched, {})
        self.__BUFFER, count = string.gsub(self.__BUFFER, matched, '')
      end
    end
    self.__BUFFER = self.__SliceString(
        self.__BUFFER, lastIndex + 1, string.len(self.__BUFFER)
    )
    if string.len(self.__BUFFER) > self.__MAX_BUFFER then
      self.__BUFFER = ''
    end
  end,


  --- Executes a Put command.
  --
  -- Alter the state of the target device.
  --
  -- @usage Put({['directive'] = 'HWCValue', ['value'] = 2, ['parameters'] = {}})
  --
  -- @param arguments table of arguments
  --
  -- @return nil
  Put = function(self, arguments)
    if self.BLOCKING ~= true then
      local directive = arguments.directive
      if self.__VALID['Commands'][directive] then
        local value = arguments.value
        local parameters = arguments.parameters
        local fn = 'Put' .. directive
        if type(self[fn]) == 'function' then
          fn = self[fn]
          fn(self, value, parameters)
        end
      else
        self:__Error(directive .. 'is an invalid command.')
      end
    end
  end,


  --- Put method for HWCValue.
  --
  -- Sends HWC command to the device.
  --
  -- @param value hwc target
  -- @param parameters table of available parameters
  --
  -- @return nil
  -- @see __Send
  -- @see __ComputeHWCValue
  PutHWCValue = function(self, value, parameters)
    local command = self:__ComputeHWCValue(value, parameters)
    self:__Send(command)
  end,


  --- Put method for HWCcValue.
  --
  -- Sends HWCc command to device.
  --
  -- @param value hwc target
  -- @param parameters table containing rgb value
  --
  -- @return nil
  -- @see __Send
  -- @see __ComputeHWCcValue
  PutHWCcValue = function(self, value, parameters)
    local command = nil
    if self:__HasValue(parameters, 'RGB') then
      rgb = parameters['RGB']
      command = self:__ComputeHWCcValue(value, rgb)
      if command then
        self:__Send(command)
      else
        self:__Error('PutHWCcValue not sent')
      end
    else
      self:__Error('RGB value not supplied for PutHWCcValue')
    end
  end,


  --- Put method for HWCtValue.
  --
  -- Sends HWCt command to device.
  --
  -- @param value hwc target
  -- @param parameters table defining the text structure
  --
  -- @return nil
  -- @see __Send
  -- @see __ComputeHWCtValue
  PutHWCtValue = function(self, value, parameters)
    local command = self:__ComputeHWCtValue(value, parameters)
    self:__Send(command)
  end,


  --- Put method for HWCxValue.
  --
  -- Sends HWCx command to device.
  --
  -- @param value hwc target
  -- @param parameters table of available parameters
  --
  -- @return nil
  -- @see __Send
  -- @see __ComputeHWCxValue
  PutHWCxValue = function(self, value, parameters)
    local command = self:__ComputeHWCxValue(value, parameters)
    self:__Send(command)
  end,

  PutSleepTimer = function(self, value, parameters)
    if value == 'Off' then
      self:__Send('SleepTimer=0')
    else
      self:__Send('SleepTimer=' .. parameters['Milliseconds'])
    end
  end,

  --- Registers a callback function that triggers when conditions are met.
  --
  -- Looks through Watcher values if directive exists in table. Tries to find a
  -- match. If no match is found, a new Watcher is created; callback is replaced
  -- if existing Watcher is found. If the directive doesn't exist, a new Watcher
  -- is appended to the newly created table.
  --
  -- @param directive table identity
  -- @param value to watch
  -- @param params table of parameters to qualify callback
  -- @param callback method to use as a callback
  --
  -- @return nil
  Watcher = function(self, directive, value, params, callback)
    local watchers = nil
    local watcherValue = nil
    if self.__VALID['Watchers'][directive] then
      watchers = self.__WATCHERS[directive]
      if watchers then
        watcherValue = watchers[value]
      end
      if watcherValue then
        for _, watcher in pairs(watcherValue) do
          if watcher:matches(params) then
            watcher.callback = callback
            return 1
          end
        end
      else
        if watchers then
          watchers[value] = {}
          watcherValue = watchers[value]
        else
          self.__WATCHERS[directive] = {}
          self.__WATCHERS[directive][value] = {}
          watcherValue = self.__WATCHERS[directive][value]
        end
      end
      table.insert(watcherValue, Watcher:new({
        params = params,
        callback = callback
      }))
    else
      self:__Error(directive .. ' is an invalid watcher.')
    end
  end,

}

-- Waveboard Driver End -----------------------------------------------------------------------------------------------

-- Socket Setup Start -------------------------------------------------------------------------------------------------

local TcpSocketServer = require("TcpSocketServer");

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
    if self.Client.IsConnected then
      self.Client:Write(directive)
    end
  end,

  Error = function(self, error)
    self:Log(error)
  end,

  EventHandler = function(self, server, data)
    self.Client = server
    self.Driver:ParseData(data)
  end
}

-- Socket Setup End ---------------------------------------------------------------------------------------------------

-- Fader Components Start ---------------------------------------------------------------------------------------------


local FaderComponent = {
  new = function(self, object)
    object = object or {}
    setmetatable(object, self)
    self.__index = self
    return object
  end,

  convertToPercent = function(status, floor)
    local hundreds = 0
    status = status['status']
    if floor ~= true then
      hundreds = status / 100
    else
      hundreds = math.floor(status / 100)
    end
    if status - hundreds * 100 >= 50 then
      hundreds = hundreds + 1
    end
    status = hundreds * 100 * .1
    return status
  end,

  trigger = function(self)
    return 1
  end,

  send = function(self, value, ifc, metering)
    local outputType = 'Strength'
    if metering == true then
      outputType = 'VUMetering'
    end
    ifc:Put({
      ['directive'] = 'HWCxValue',
      ['value'] = self.id,
      ['parameters'] = {
        ['Percent'] = value,
        ['OutputType'] = outputType
      }
    })
  end
}

local Slider = FaderComponent:new({
  trigger = function(self, _, status, ifc)
    status = self.convertToPercent(status, false)
    self:send(status, ifc)
  end
})

local Meter = FaderComponent:new({
  trigger = function(self, _, status, ifc, metering)
    status = self.convertToPercent(status, true)
    self:send(status, ifc, metering)
  end,
})

local Fader = FaderComponent:new({
  trigger = function(self, directive, status, interface, send)
    if send ~= true then
      local meterValue = status['status'] * (MINIMUM * -1) / 100000 * 100 - (MINIMUM * -1)
      MatrixFaders[tostring(self.matrix)].Value = meterValue
    end
    self.lastStatus = status
    if not self.METERING then
      self.meter:trigger(directive, status, interface)
    end
    self.slider:trigger(directive, status, interface)
  end,

  sync = function(self, ifc)
    if self.lastStatus ~= nil then
      self.meter:trigger('HWC', self.lastStatus, ifc)
    end
  end
})

-- Fader Components End -----------------------------------------------------------------------------------------------

-- Button Components Start --------------------------------------------------------------------------------------------


local ToggleButton = {
  new = function(self, object)
    object = object or {}
    setmetatable(object, self)
    self.__index = self
    return object
  end,

  toggleOn = function(self, ifc)
    self.toggled = true
    self:send(self.on, ifc)
  end,

  toggleOff = function(self, ifc)
    self.toggled = false
    self:send(self.off, ifc)
  end,

  trigger = function(self, _, status, ifc)
    status = status['status']
    if status == 'Down' then
      if self.toggled then
        self:toggleOff(ifc)
        ControlOutputs[self.control].Value = 0.0
      else
        self:toggleOn(ifc)
        ControlOutputs[self.control].Value = 1.0
      end
    end
  end,

  send = function(self, color, ifc)
    ifc:Put({
      ['directive'] = self.command,
      ['value'] = self.hwc,
      ['parameters'] = {
        ['Color'] = color
      }
    })
  end
}

local TriggerButton = {
  new = function(self, object)
    object = object or {}
    setmetatable(object, self)
    self.__index = self
    return object
  end,

  trigger = function(self, _, status, ifc)
    status = status['status']
    if status == 'Down' then
      self:on(ifc)
    else
      self:off(ifc)
    end
  end,

  on = function(self, ifc)
    ifc:Put({
      ['directive'] = 'HWCValue',
      ['value'] = self.hwc,
      ['parameters'] = {
        ['Color'] = 'White'
      }
    })
    ifc:Put({
      ['directive'] = 'HWCcValue',
      ['value'] = self.hwc,
      ['parameters'] = {
        ['RGB'] = self.color
      }
    })
  end,

  off = function(self, ifc)
    ifc:Put({
      ['directive'] = 'HWCValue',
      ['value'] = self.hwc,
      ['parameters'] = {
        ['Color'] = 'Off'
      }
    })
    ifc:Put({
      ['directive'] = 'HWCcValue',
      ['value'] = self.hwc,
      ['parameters'] = {
        ['RGB'] = 'Default'
      }
    })
  end
}

local CueButton = TriggerButton:new({
  toggled = false,
  trigger = function(self, _, status, ifc)
    status = status['status']
    if status == 'Down' then
      if self.toggled then
        self.toggled = false
        self:off(ifc)
        self.outputs[self.output].Value = -100.0
      else
        self.toggled = true
        self:on(ifc)
        self.outputs[self.output].Value = 0.0
      end
    end
  end,
})

local VUButton = CueButton:new()

-- Button Components End ----------------------------------------------------------------------------------------------


-- Label Components Start ---------------------------------------------------------------------------------------------

local MicrophoneLabel = {
  new = function(self, object)
    object = object or {}
    setmetatable(object, self)
    self.__index = self
    return object
  end,

  send = function(self, val, ifc)
    ifc:Put({
      ['directive'] = 'HWCtValue',
      ['value'] = self.disp,
      ['parameters'] = {
        ['Label1'] = val
      }
    })
  end
}

-- Label Components End -----------------------------------------------------------------------------------------------

-- Fader Group Components Start ---------------------------------------------------------------------------------------

local FaderGroupButton = ToggleButton:new({
  trigger = function(self, _, status, ifc)
    status = status['status']
    if status == 'Down' then
      self.group:notify(self, ifc)
    end
  end
})

local FaderGroup = {
  new = function(self, object)
    object = object or {}
    setmetatable(object, self)
    self.__index = self
    return object
  end,

  notify = function(self, fgb, ifc)
    local target = nil
    local targetIndex = nil
    for index, btn in pairs(self.btns) do
      btn:toggleOff(ifc)
      if btn == fgb then
        target = fgb
        targetIndex = index
      end
    end
    target:toggleOn(ifc)
    self.controls:shift(targetIndex, ifc)
  end,

  setButtons = function(self, btns)
    self.btns = btns
  end,

  setRouterControls = function(self, controls)
    self.controls = controls
  end
}

-- Fader Group Components End -----------------------------------------------------------------------------------------

-- Router Components Start --------------------------------------------------------------------------------------------


local InputControlRouter = {
  new = function(self, object)
    object = object or {}
    setmetatable(object, self)
    self.__index = self
    return object
  end,

  shift = function(self, groupNum)
    local controlIndex = nil
    groupNum = self.values[groupNum]
    for index, control in pairs(self.controls) do
      controlIndex = string.match(index, "%d")
      control.Value = controlIndex + (groupNum * 8)
    end
  end
}

local OutputControlRouter = InputControlRouter:new({
  shift = function(self, groupNum)
    groupNum = self.values[groupNum]
    for index, _ in pairs(self.controls) do
      local target = groupNum * 8 + tonumber(index)
      self.controls[index] = Controls.Outputs[target]
    end
  end
})

local InputNamesRouter = InputControlRouter:new({
  shift = function(self, groupNum, ifc)
    local micsMap = {
      ['19'] = 'RF-1',
      ['20'] = 'RF-2',
      ['21'] = 'RF-3',
      ['22'] = 'RF-4',
      ['23'] = 'Wall',
      ['24'] = 'Floor'
    }
    local microphoneName = nil
    local microphoneNumber = nil
    groupNum = self.values[groupNum]
    for index = 1, 8 do
      microphoneNumber = index + (groupNum * 8)
      if microphoneNumber <= 18 then
        microphoneName = 'Mic ' .. tostring(microphoneNumber)
      else
        microphoneName = micsMap[tostring(microphoneNumber)]
      end
      PhysicalControls['Group' .. tostring(index)]['Label']:send(microphoneName, ifc)
    end
  end
})

local AggregateControlRouter = InputControlRouter:new({
  shift = function(self, groupNum, ifc)
    self.killVUMeters()
    self.inputs:shift(groupNum)
    self.outputs:shift(groupNum)
    self.muteInputs:shift(groupNum)
    self.muteOutputs:shift(groupNum)
    self.cueInputs:shift(groupNum)
    self.cueOutputs:shift(groupNum)
    self.vuInputs:shift(groupNum)
    self.vuOutputs:shift(groupNum)
    self.inputNames:shift(groupNum, ifc)
  end,

  killVUMeters = function()
    for _, output in pairs(VUOutputs) do
      output.Value = -100.0
    end
  end
})

-- Router Components End ----------------------------------------------------------------------------------------------


-- Basic Setup Start --------------------------------------------------------------------------------------------------

local server = TcpSocketServer.New()
local interface = DriverInterface:New()
local waveboard = Driver:new()
local registered = false
local listeners = false
local faders = {}

interface.Driver = waveboard

MatrixFaders = {
  ['1'] = Controls.Outputs[9],
  ['2'] = Controls.Outputs[10],
  ['3'] = Controls.Outputs[11],
  ['4'] = Controls.Outputs[12],
  ['5'] = Controls.Outputs[13],
  ['6'] = Controls.Outputs[14],
  ['7'] = Controls.Outputs[15],
  ['8'] = Controls.Outputs[16]
}

MatrixInputs = {
  ['1'] = Controls.Inputs[1],
  ['2'] = Controls.Inputs[2],
  ['3'] = Controls.Inputs[3],
  ['4'] = Controls.Inputs[4],
  ['5'] = Controls.Inputs[5],
  ['6'] = Controls.Inputs[6],
  ['7'] = Controls.Inputs[7],
  ['8'] = Controls.Inputs[8]
}

MatrixMutes = {
  ['1'] = Controls.Inputs[9],
  ['2'] = Controls.Inputs[10],
  ['3'] = Controls.Inputs[11],
  ['4'] = Controls.Inputs[12],
  ['5'] = Controls.Inputs[13],
  ['6'] = Controls.Inputs[14],
  ['7'] = Controls.Inputs[15],
  ['8'] = Controls.Inputs[16]
}

ControlOutputs = {
  ['1'] = Controls.Outputs[25],
  ['2'] = Controls.Outputs[26],
  ['3'] = Controls.Outputs[27],
  ['4'] = Controls.Outputs[28],
  ['5'] = Controls.Outputs[29],
  ['6'] = Controls.Outputs[30],
  ['7'] = Controls.Outputs[31],
  ['8'] = Controls.Outputs[32]
}

CueOutputs = {
  ['1'] = Controls.Outputs[49],
  ['2'] = Controls.Outputs[50],
  ['3'] = Controls.Outputs[51],
  ['4'] = Controls.Outputs[52],
  ['5'] = Controls.Outputs[53],
  ['6'] = Controls.Outputs[54],
  ['7'] = Controls.Outputs[55],
  ['8'] = Controls.Outputs[56]
}

VUOutputs = {
  ['1'] = Controls.Outputs[73],
  ['2'] = Controls.Outputs[74],
  ['3'] = Controls.Outputs[75],
  ['4'] = Controls.Outputs[76],
  ['5'] = Controls.Outputs[77],
  ['6'] = Controls.Outputs[78],
  ['7'] = Controls.Outputs[79],
  ['8'] = Controls.Outputs[80]
}

-- Basic Setup End ----------------------------------------------------------------------------------------------------


-- Build Functions Start ----------------------------------------------------------------------------------------------


function buildSlider(group)
  return Slider:new({
    id = group['Fader']
  })
end

function buildMeter(group)
  return Meter:new({
    id = group['MTR']
  })
end

function buildFaders(group, fadersIndex)
  local slider = buildSlider(group)
  local meter = buildMeter(group)
  return Fader:new({
    meter = meter,
    slider = slider,
    matrix = tostring(fadersIndex)
  })
end

function buildCueButton(hwc, color, outputIndex)
  return CueButton:new({
    hwc = hwc,
    color = color,
    output = tostring(outputIndex),
    outputs = CueOutputs
  })
end

function buildVUButton(hwc, color, outputIndex)
  return VUButton:new({
    hwc = hwc,
    color = color,
    output = tostring(outputIndex),
    outputs = VUOutputs
  })
end

function buildMicrophoneLabel(group, fadersIndex)
  return MicrophoneLabel:new({
    index = fadersIndex,
    disp = group['Disp']
  })
end

function buildTriggerButton(hwc, color)
  return TriggerButton:new({
    hwc = hwc,
    color = color
  })
end

function buildToggleButton(hwc, muteIndex)
  return ToggleButton:new({
    toggled = false,
    hwc = hwc,
    command = 'HWCValue',
    on = 'Red',
    off = 'Green',
    parameter = 'Color',
    control = tostring(muteIndex)
  })
end

function buildButtons(group, muteIndex)
  local mute = buildToggleButton(group['A'], muteIndex)
  local cue = buildCueButton(group['B'], CUE_COLOR, muteIndex)
  local vu = buildVUButton(group['D'], VU_COLOR, muteIndex)
  return { mute, cue, vu }
end

function buildControlRouter(controls)
  return InputControlRouter:new({
    controls = controls,
    values = {
      ['F1'] = 0,
      ['F2'] = 1,
      ['F3'] = 2
    }
  })
end

function buildOutputControlRouter(controls, values)
  return OutputControlRouter:new({
    controls = controls,
    values = values
  })
end

function buildRouters(routerControls, components, values)
  local inputRouter = buildControlRouter(routerControls)
  local outputRouter = buildOutputControlRouter(components, values)
  return { [1] = inputRouter, [2] = outputRouter }
end

function buildFaderRouters(faderRouterControls)
  return buildRouters(faderRouterControls, MatrixFaders, {
    ['F1'] = 0,
    ['F2'] = 1,
    ['F3'] = 2
  })
end

function buildMuteRouters(muteRouterControls)
  return buildRouters(muteRouterControls, ControlOutputs, {
    ['F1'] = 3,
    ['F2'] = 4,
    ['F3'] = 5
  })
end

function buildCueRouters(cueRouterControls)
  return buildRouters(cueRouterControls, CueOutputs, {
    ['F1'] = 6,
    ['F2'] = 7,
    ['F3'] = 8
  })
end

function buildVURouters(vuRouterControls)
  return buildRouters(vuRouterControls, VUOutputs, {
    ['F1'] = 9,
    ['F2'] = 10,
    ['F3'] = 11
  })
end

function buildFaderGroups(master, faderRouterControls, muteRouterControls, cueRouterControls, vuRouterControls)
  local faderInputRouter, faderOutputRouter = table.unpack(buildFaderRouters(faderRouterControls))
  local muteInputRouter, muteOutputRouter = table.unpack(buildMuteRouters(muteRouterControls))
  local cueInputRouter, cueOutputRouter = table.unpack(buildCueRouters(cueRouterControls))
  local vuInputRouter, vuOutputRouter = table.unpack(buildVURouters(vuRouterControls))
  local inputNamesRouter = InputNamesRouter:new({
    values = {
      ['F1'] = 0,
      ['F2'] = 1,
      ['F3'] = 2
    }
  })
  local controlRouter = AggregateControlRouter:new({
    inputs = faderInputRouter,
    muteInputs = muteInputRouter,
    muteOutputs = muteOutputRouter,
    cueInputs = cueInputRouter,
    cueOutputs = cueOutputRouter,
    vuInputs = vuInputRouter,
    vuOutputs = vuOutputRouter,
    outputs = faderOutputRouter,
    inputNames = inputNamesRouter
  })
  local faderGroup = FaderGroup:new()
  local faders = {}
  for index, control in pairs(master) do
    if index == 'F1'
        or index == 'F2'
        or index == 'F3' then
      faders[index] = FaderGroupButton:new({
        toggled = false,
        hwc = control,
        command = 'HWCValue',
        on = 'White',
        off = 'Off',
        parameter = 'Color',
        group = faderGroup
      })
    end
  end
  faderGroup:setButtons(faders)
  faderGroup:setRouterControls(controlRouter)
  return faders
end

function buildWatchers(group, fader, mute, cue, vu)
  local watchers = {
    ['A'] = mute,
    ['B'] = cue,
    ['D'] = vu,
    ['Fader'] = fader
  }
  for index, control in pairs(watchers) do
    interface.Driver:Watcher(
        'HWC',
        tostring(group[index]),
        {},
        control
    )
  end
end

function buildFaderWatchers(master, faders)
  for index, control in pairs(faders) do
    interface.Driver:Watcher(
        'HWC',
        tostring(master[index]),
        {},
        control
    )
  end
end

function buildControls()
  local fadersIndex = 1
  for index, group in pairs(interface.Driver.Groups) do
    if string.find(index, 'Group') then
      fadersIndex = string.match(index, "%d")
      local fader = buildFaders(group, fadersIndex)
      local mute, cue, vu = table.unpack(buildButtons(group, fadersIndex))
      local label = buildMicrophoneLabel(group, fadersIndex)
      label:send('Mic ' .. fadersIndex, interface.Driver)
      PhysicalControls[index] = {
        ['Fader'] = fader,
        ['Mute'] = mute,
        ['Cue'] = cue,
        ['VU'] = vu,
        ['Label'] = label
      }
      buildWatchers(group, fader, mute, cue, vu)
    end
  end
end

-- Build Functions End ------------------------------------------------------------------------------------------------

-- Main Start ---------------------------------------------------------------------------------------------------------


function establishInterface(srvr, data)
  interface.Client = srvr
  interface.Driver:SetInterface(interface)
  interface.Driver:ParseData(data)
end

function setMeterValue(index, changedControl)
  local meterValue = 0
  if changedControl.Value >= MAXIMUM then
    meterValue = 1000
  elseif changedControl.Value < MINIMUM then
    meterValue = 0
  else
    meterValue = math.floor(((MINIMUM * -1) + changedControl.Value) / (MINIMUM * -1) * 100000 / 100)
  end
  local target = PhysicalControls['Group' .. index]['Fader']
  target:trigger(
      'HWC', {
        ['status'] = meterValue
      },
      interface.Driver,
      true
  )
end

function setMeterValues()
  for index, fader in pairs(MatrixFaders) do
    setMeterValue(index, fader)
  end
end

function setCueValues()
  return 1
end

function setMuteValue(index, changedControl)
  local target = PhysicalControls['Group' .. index]
  if changedControl.Value == 1.0 then
    target['Mute']:toggleOn(interface.Driver)
  else
    target['Mute']:toggleOff(interface.Driver)
  end
end

function setMuteValues()
  for index, mute in pairs(MatrixMutes) do
    setMuteValue(index, mute)
  end
end

function determineProgramAudioStatus()
  local count = 0
  for _, __ in pairs(CUES) do
    count = count + 1
  end
  if count <= 0 then
    Controls.Outputs[97].Value = 0.0
  end
end

function setCueValue(index, changedControl)
  local target = PhysicalControls['Group' .. index]
  if changedControl.Value <= -100 then
    target['Cue'].toggled = false
    target['Cue']:off(interface.Driver)
    table.remove(CUES, target['Cue'])
    determineProgramAudioStatus()
  else
    target['Cue'].toggled = true
    target['Cue']:on(interface.Driver)
    table.insert(CUES, target['Cue'])
    Controls.Outputs[97].Value = 1.0
  end
end

function setVUValue(index, changedControl)
  local target = PhysicalControls['Group' .. index]
  local vu = target['VU']
  local fader = target['Fader']
  if changedControl.Value <= -100 then
    if VU == vu then
      VU = nil
    end
    if METER == fader then
      METER = nil
    end
    vu.toggled = false
    fader.METERING = false
    fader:sync(interface.Driver)
    vu:off(interface.Driver)
  else
    if VU ~= nil then
      vu.toggled = false
      VU:off(interface.Driver)
      VU.outputs[VU.output].Value = -100.0
    end
    if METER ~= nil then
      METER.METERING = false
      METER:sync(interface.Driver)
    end
    VU = vu
    METER = fader
    vu.toggled = true
    fader.METERING = true
    vu:on(interface.Driver)
    setPeakValue(Controls.Inputs[33])
  end
end

function setPeakValue(changedControl)
  if METER ~= nil then
    local meterValue = nil
    if changedControl.Value <= MINIMUM then
      meterValue = 0
    else
      meterValue = math.floor(((MINIMUM * -1) + changedControl.Value) / (MINIMUM * -1) * 100000 / 100)
    end
    if meterValue > 1000 then
      meterValue = 1000
    end
    METER.meter:trigger('HWC', { ['status'] = meterValue }, interface.Driver, true)
  end
end

function faderListener(index, control)
  control.EventHandler = function(changedControl)
    setMeterValue(index, changedControl)
  end
end

function muteListener(index, control)
  control.EventHandler = function(changedControl)
    setMuteValue(index, changedControl)
  end
end

function peakListener(control)
  control.EventHandler = function(changedControl)
    setPeakValue(changedControl)
  end
end

function cueListener(index, control)
  control.EventHandler = function(changedControl)
    setCueValue(index, changedControl)
  end
end

function vuListener(index, control)
  control.EventHandler = function(changedControl)
    setVUValue(index, changedControl)
  end
end

function establishListeners()
  for index, control in pairs(Controls.Inputs) do
    if index <= 8 then
      faderListener(index, control)
    elseif index > 8 and index <= 16 then
      muteListener(index - 8, control)
    elseif index > 16 and index <= 24 then
      cueListener(index - 16, control)
    elseif index > 24 and index <= 32 then
      vuListener(index - 24, control)
    else
      peakListener(control)
    end
  end
end

function setValues()
  for index, control in pairs(Controls.Inputs) do
    if index <= 8 then
      setMeterValue(index, control)
    elseif index > 8 and index <= 16 then
      setMuteValue(index - 8, control)
    elseif index > 16 and index <= 24 then
      setCueValue(index - 16, control)
    elseif index > 24 and index <= 32 then
      setVUValue(index - 24, control)
    else
      peakListener(control)
    end
  end
end

function createRouterControls(component)
  local router = Component.New(component)
  local routerControls = {}
  for index, control in pairs(router) do
    if control.Type == 'Integer' then
      routerControls[index] = control
    end
  end
  return routerControls
end

function eventHandler(srvr, data)
  if SERVER == nil then
    SERVER = srvr
  end
  establishInterface(srvr, data)
  if interface.Driver.Groups ~= nil and not registered then
    buildControls()
    if listeners ~= true then
      local faderRouterControls = createRouterControls("Fader In")
      local muteRouterControls = createRouterControls("Mute In")
      local cueRouterControls = createRouterControls("Cue In")
      local vuRouterControls = createRouterControls("VU In")
      local master = interface.Driver.Groups['Master']
      faders = buildFaderGroups(master, faderRouterControls, muteRouterControls, cueRouterControls, vuRouterControls)
      buildFaderWatchers(master, faders)
      establishListeners()
      listeners = true
    end
    faders['F1']:trigger('HWC', { ['status'] = 'Down' }, interface.Driver)
    setValues()
    interface.Driver:Put({
      ['directive'] = 'SleepTimer',
      ['value'] = 'Off',
      ['parameters'] = {}
    })
    registered = true
  elseif not registered or SERVER ~= srvr then
    removeSocket(SERVER)
    SERVER = srvr
    faders['F1']:trigger('HWC', { ['status'] = 'Down' }, interface.Driver)
    interface.Driver:Put({
      ['directive'] = 'SleepTimer',
      ['value'] = 'Off',
      ['parameters'] = {}
    })
    setValues()
    registered = true
  end
end

sockets = {}

function removeSocket(sock)
  for key, socket in pairs(sockets) do
    if socket == sock then
      table.remove(sockets, key)
    end
  end
end

function socketHandler(sock, event)
  if event == TcpSocket.Events.Data then
    eventHandler(sock, sock:Read(sock.BufferLength))
  elseif event == TcpSocket.Events.Closed
      or event == TcpSocket.Events.Error
      or event == TcpSocket.Events.Timeout then
    removeSocket(sock)
    registered = false
    server:Close()
    server:Listen(PORT)
  end
end

server.EventHandler = function(instance)
  table.insert(sockets, instance)
  instance.EventHandler = socketHandler
end

waveboard:__SynchronizeTopology('{"HWc":[{"id":1,"x":482,"y":331,"txt":"Disp1","type":30,"typeOverride":{"disp":{"w":112,"h":32}}},{"id":2,"x":432,"y":331,"txt":"DA1","type":70,"typeOverride":{"disp":{"w":56,"h":32}}},{"id":3,"x":532,"y":331,"txt":"DB1","type":70,"typeOverride":{"disp":{"w":56,"h":32}}},{"id":4,"x":427,"y":442,"txt":"A1","type":129},{"id":5,"x":537,"y":442,"txt":"B1","type":129},{"id":6,"x":427,"y":539,"txt":"C1","type":129},{"id":7,"x":537,"y":539,"txt":"D1","type":129},{"id":8,"x":482,"y":1116,"txt":"Fader 1","type":28},{"id":9,"x":355,"y":1251,"txt":"MTR 1","type":145},{"id":10,"x":743,"y":331,"txt":"Disp2","type":30,"typeOverride":{"disp":{"w":112,"h":32}}},{"id":11,"x":693,"y":331,"txt":"DA2","type":70,"typeOverride":{"disp":{"w":56,"h":32}}},{"id":12,"x":793,"y":331,"txt":"DB2","type":70,"typeOverride":{"disp":{"w":56,"h":32}}},{"id":13,"x":688,"y":442,"txt":"A2","type":129},{"id":14,"x":798,"y":442,"txt":"B2","type":129},{"id":15,"x":688,"y":539,"txt":"C2","type":129},{"id":16,"x":798,"y":539,"txt":"D2","type":129},{"id":17,"x":743,"y":1116,"txt":"Fader 2","type":28},{"id":18,"x":616,"y":1251,"txt":"MTR 2","type":145},{"id":19,"x":1003,"y":331,"txt":"Disp3","type":30,"typeOverride":{"disp":{"w":112,"h":32}}},{"id":20,"x":953,"y":331,"txt":"DA3","type":70,"typeOverride":{"disp":{"w":56,"h":32}}},{"id":21,"x":1053,"y":331,"txt":"DB3","type":70,"typeOverride":{"disp":{"w":56,"h":32}}},{"id":22,"x":948,"y":442,"txt":"A3","type":129},{"id":23,"x":1058,"y":442,"txt":"B3","type":129},{"id":24,"x":948,"y":539,"txt":"C3","type":129},{"id":25,"x":1058,"y":539,"txt":"D3","type":129},{"id":26,"x":1003,"y":1116,"txt":"Fader 3","type":28},{"id":27,"x":876,"y":1251,"txt":"MTR 3","type":145},{"id":28,"x":1264,"y":331,"txt":"Disp4","type":30,"typeOverride":{"disp":{"w":112,"h":32}}},{"id":29,"x":1214,"y":331,"txt":"DA4","type":70,"typeOverride":{"disp":{"w":56,"h":32}}},{"id":30,"x":1314,"y":331,"txt":"DB4","type":70,"typeOverride":{"disp":{"w":56,"h":32}}},{"id":31,"x":1209,"y":442,"txt":"A4","type":129},{"id":32,"x":1319,"y":442,"txt":"B4","type":129},{"id":33,"x":1209,"y":539,"txt":"C4","type":129},{"id":34,"x":1319,"y":539,"txt":"D4","type":129},{"id":35,"x":1264,"y":1116,"txt":"Fader 4","type":28},{"id":36,"x":1137,"y":1251,"txt":"MTR 4","type":145},{"id":37,"x":1524,"y":331,"txt":"Disp5","type":30,"typeOverride":{"disp":{"w":112,"h":32}}},{"id":38,"x":1474,"y":331,"txt":"DA5","type":70,"typeOverride":{"disp":{"w":56,"h":32}}},{"id":39,"x":1574,"y":331,"txt":"DB5","type":70,"typeOverride":{"disp":{"w":56,"h":32}}},{"id":40,"x":1469,"y":442,"txt":"A5","type":129},{"id":41,"x":1579,"y":442,"txt":"B5","type":129},{"id":42,"x":1469,"y":539,"txt":"C5","type":129},{"id":43,"x":1579,"y":539,"txt":"D5","type":129},{"id":44,"x":1524,"y":1116,"txt":"Fader 5","type":28},{"id":45,"x":1397,"y":1251,"txt":"MTR 5","type":145},{"id":46,"x":1785,"y":331,"txt":"Disp6","type":30,"typeOverride":{"disp":{"w":112,"h":32}}},{"id":47,"x":1735,"y":331,"txt":"DA6","type":70,"typeOverride":{"disp":{"w":56,"h":32}}},{"id":48,"x":1835,"y":331,"txt":"DB6","type":70,"typeOverride":{"disp":{"w":56,"h":32}}},{"id":49,"x":1730,"y":442,"txt":"A6","type":129},{"id":50,"x":1840,"y":442,"txt":"B6","type":129},{"id":51,"x":1730,"y":539,"txt":"C6","type":129},{"id":52,"x":1840,"y":539,"txt":"D6","type":129},{"id":53,"x":1785,"y":1116,"txt":"Fader 6","type":28},{"id":54,"x":1658,"y":1251,"txt":"MTR 6","type":145},{"id":55,"x":2045,"y":331,"txt":"Disp7","type":30,"typeOverride":{"disp":{"w":112,"h":32}}},{"id":56,"x":1995,"y":331,"txt":"DA7","type":70,"typeOverride":{"disp":{"w":56,"h":32}}},{"id":57,"x":2095,"y":331,"txt":"DB7","type":70,"typeOverride":{"disp":{"w":56,"h":32}}},{"id":58,"x":1990,"y":442,"txt":"A7","type":129},{"id":59,"x":2100,"y":442,"txt":"B7","type":129},{"id":60,"x":1990,"y":539,"txt":"C7","type":129},{"id":61,"x":2100,"y":539,"txt":"D7","type":129},{"id":62,"x":2045,"y":1116,"txt":"Fader 7","type":28},{"id":63,"x":1918,"y":1251,"txt":"MTR 7","type":145},{"id":64,"x":2306,"y":331,"txt":"Disp8","type":30,"typeOverride":{"disp":{"w":112,"h":32}}},{"id":65,"x":2256,"y":331,"txt":"DA8","type":70,"typeOverride":{"disp":{"w":56,"h":32}}},{"id":66,"x":2356,"y":331,"txt":"DB8","type":70,"typeOverride":{"disp":{"w":56,"h":32}}},{"id":67,"x":2251,"y":442,"txt":"A8","type":129},{"id":68,"x":2361,"y":442,"txt":"B8","type":129},{"id":69,"x":2251,"y":539,"txt":"C8","type":129},{"id":70,"x":2361,"y":539,"txt":"D8","type":129},{"id":71,"x":2306,"y":1116,"txt":"Fader 8","type":28},{"id":72,"x":2179,"y":1251,"txt":"MTR 8","type":145},{"id":73,"x":185,"y":331,"txt":"Disp","type":75},{"id":74,"x":185,"y":472,"txt":"F0","type":126},{"id":75,"x":185,"y":622,"txt":"F1","type":126},{"id":76,"x":185,"y":792,"txt":"F2","type":126},{"id":77,"x":185,"y":942,"txt":"F3","type":126},{"id":78,"x":185,"y":1112,"txt":"F4","type":126},{"id":79,"x":2340,"y":130,"txt":"Controller","type":250},{"id":80,"x":475,"y":269,"txt":"Section 1A","type":250},{"id":81,"x":1517,"y":269,"txt":"Section 2A","type":250},{"id":82,"x":2299,"y":269,"txt":"Section 3A","type":250},{"id":83,"x":420,"y":644,"txt":"Section 1B","type":250},{"id":84,"x":1462,"y":644,"txt":"Section 2B","type":250},{"id":85,"x":2244,"y":644,"txt":"Section 3B","type":250}],"typeIndex":{"28":{"w":30,"h":710,"in":"av","ext":"pos","subidx":0,"desc":"Motorized Fader 60mm","sub":[{"_":"r","_x":-63,"_y":53,"_w":125,"_h":250}]},"30":{"w":246,"h":78,"disp":{"w":128,"h":32},"desc":"OLED Display Tile"},"70":{"w":90,"h":60,"disp":{"w":64,"h":32},"desc":"OLED Display Tile"},"75":{"w":134,"h":76,"disp":{"w":64,"h":32},"desc":"OLED Display Tile"},"126":{"w":100,"h":120,"out":"rgb","in":"b4","desc":"Elastomer Four-Way Button"},"129":{"w":70,"h":60,"out":"rgb","in":"b","desc":"Elastomer Button"},"145":{"w":80,"h":520,"out":"rgb","ext":"steps","desc":"LED-Bar, 10 steps","sub":[{"_idx":5,"_":"r","_x":-30,"_y":-36,"_w":60,"_h":30},{"_idx":6,"_":"r","_x":-30,"_y":15,"_w":60,"_h":30},{"_idx":4,"_":"r","_x":-30,"_y":-86,"_w":60,"_h":30},{"_idx":7,"_":"r","_x":-30,"_y":65,"_w":60,"_h":30},{"_idx":3,"_":"r","_x":-30,"_y":-136,"_w":60,"_h":30},{"_idx":8,"_":"r","_x":-30,"_y":115,"_w":60,"_h":30},{"_idx":2,"_":"r","_x":-30,"_y":-186,"_w":60,"_h":30},{"_idx":9,"_":"r","_x":-30,"_y":165,"_w":60,"_h":30},{"_idx":1,"_":"r","_x":-30,"_y":-236,"_w":60,"_h":30},{"_idx":10,"_":"r","_x":-30,"_y":215,"_w":60,"_h":30}]},"250":{"w":214,"h":34,"sub":[{"_":"r","_x":-105,"_y":-15,"_w":210,"_h":30,"rx":5,"ry":5,"style":"fill:rgb(103,118,131);"}]}}}')
server:Listen(PORT)

print('Server listening on port: ', PORT)

-- Main End -----------------------------------------------------------------------------------------------------------

