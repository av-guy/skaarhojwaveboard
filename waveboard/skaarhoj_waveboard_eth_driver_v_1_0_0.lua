local bit = require("bit")
local json = require('lunajson')

--- WaveBoard Ethernet Driver
module('WaveBoard', package.seeall)

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
      ['HWCtValue'] = 1
    },
    ['Watchers'] = {
      ['HWC'] = 1
    }
  },
  __MATCHES = {
    ['list'] = '__SynchronizeActivePanel',
    ['ping'] = '__SynchronizePingMessage',
    ['nack'] = '__InvalidResponse',
    ['_panelTopology_HWC=.*'] = '__SynchronizeTopology',
    ['HWC#(%d*)=(.*)'] = '__SynchronizeControl',
    ['HWC#(%d*)(%.)(%d)=(.*)'] = '__SynchronizeMasterData'
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
      computed = bit.bor(7, color) -- Per the demo scripts provided on GitHub
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
    local hundreds = 0
    local outputValue = parameters['Percent'] / 100 * 1000
    local outputIndividual = '00' -- Unused but required per RawPanel spec
    local command = 'HWCx#' .. value
    local HWCValues = self.HWCValues

    if self:__HasValue(parameters, 'OutputType') then
      outputType = parameters['OutputType']
      if HWCValues['OutputType'][outputType] ~= nil then
        outputType = HWCValues['OutputType'][outputType]
        outputType = table.concat(self:__ToBits(outputType, 4))
        outputValue = table.concat(self:__ToBits(outputValue, 10))
        outputConcat = outputType .. outputIndividual .. outputValue
        command = command .. '=' .. self:__ToDecimal(outputConcat)
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

  __Synchronize = function(self, control, value, params)
    if self.__WATCHERS['HWC'][control] ~= nil then
      watchers = self.__WATCHERS['HWC'][control]
      for index, watcher in pairs(watchers) do
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
        print(value, 'IS VALUE')
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
    local match = '(%d*)(%.)(%d)=(.*)'
    local _, _, control, _, mask, value = string.find(data, match)
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
    for b = bits, 1, - 1 do
      rest = math.fmod(num, 2)
      t[b] = rest
      num = (num - rest) / 2
    end
    if num == 0 then
      return t
    else
      return {'Not enough bits to represent this number'}
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

  Get = function(self, arguments)
    return 1
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
    local callback = nil
    local sub = nil
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
        for index, watcher in pairs(watcherValue) do
          if watcher:matches(params) then
            print('it matches')
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

return Driver
