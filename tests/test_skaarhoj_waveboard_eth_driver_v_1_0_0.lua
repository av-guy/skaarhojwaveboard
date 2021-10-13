lu = require('luaunit')
local TestValues = require('tests/skaarhoj_waveboard_eth_driver_test_values')
local WaveBoard = require('waveboard/skaarhoj_waveboard_eth_driver_v_1_0_0')
local waveboard = WaveBoard:new()
local interface = {
    directive = nil,
    error = nil,
    Send = function(self, directive)
      self.directive = directive
    end,
    Error = function(self, error)
      self.error = error
    end
}

waveboard:SetInterface(interface)
TestWaveBoard = {}

-- Start Test Helpers ---------------------------------------------------------


function testHelper(testNumber, actual, expected)
  if expected ~= actual then
    print('Failed at test number ' .. testNumber)
  end
end


function testExpected(test, command, value)
  testHelper(test, command, value)
  assertEquals(command, value)
end


function testError(test, iError, value)
  testHelper(test, iError, value)
  assertEquals(iError, value)
end

-- End Test Helpers -----------------------------------------------------------

-- __BuildHWCtString Tests

function TestWaveBoard:testBuildHWCtString()
  local arr = {[1] = 'Hello', [2] = 'World'}
  for i = 3, 16, 1 do arr[i] = 'omit' end
  local text = waveboard:__BuildHWCtString(arr)
  assertEquals(text, 'Hello|World|||||||||||||||')
end


-- __ComputeHWCValue Tests

function TestWaveBoard:testComputeHWCValue()
  local params = TestValues['HWC']
  local command = ''
  local __params = {}
  for test, values in pairs(params) do
    __params = {}
    if values['Blinking'] ~= nil then
      __params['Blinking'] = values['Blinking']
    end
    if values['Color'] ~= nil then
      __params['Color'] = values['Color']
    end
    command = waveboard:__ComputeHWCValue(2, __params)
    testExpected(test, command, values['Expected'])
    if values['Error'] ~= nil then
      testError(test, interface.error, values['Error'])
    end
  end
end


-- __ComputeHWCcValue Tests

function TestWaveBoard:testComputeHWCcValue()
  local params = TestValues['HWCc']
  local command = ''
  local __params = {}
  for test, values in pairs(params) do
    __params = {}
    if values['RGB'] ~= nil then
      __params['RGB'] = values['RGB']
    end
    command = waveboard:__ComputeHWCcValue(2, __params['RGB'])
    testExpected(test, command, values['Expected'])
    if values['Error'] ~= nil then
      testError(test, interface.error, values['Error'])
    end
  end
end


-- __ComputeHWCtValue Tests

function TestWaveBoard:testComputeHWCtValue()
  local params = TestValues['HWCt']
  local command = ''
  local __params = {}
  for test, values in pairs(params) do
    __params = {}
    __params = values['Parameters']
    command = waveboard:__ComputeHWCtValue(2, __params)
    testExpected(test, command, values['Expected'])
    if values['Error'] ~= nil then
      testError(test, interface.error, values['Error'])
    end
  end
end


-- __ComputeHWCxValue Tests

function TestWaveBoard:testHWCxValues()
  local params = TestValues['HWCx']
  local command = ''
  local __params = {}
  for test, values in pairs(params) do
    __params = {}
    __params = values['Parameters']
    command = waveboard:__ComputeHWCxValue(2, __params)
    testExpected(test, command, values['Expected'])
    if values['Error'] ~= nil then
      testError(test, interface.error, values['Error'])
    end
  end
end


-- __ConvertValue Tests

function TestWaveBoard:testConvertValue()
  local params = TestValues['__ConvertValues']
  for test, values in pairs(params) do
    value = waveboard:__ConvertValue(values['Value'])
    testExpected(test, value, values['Expected'])
  end
end


-- __Error Tests

function TestWaveBoard:testError()
  local params = TestValues['__Error']
  for test, values in pairs(params) do
    value = waveboard:__Error(values['Value'])
    testExpected(test, interface.error, values['Expected'])
  end
end


-- __HasValue Tests

function TestWaveBoard:testHasValue()
  local params = TestValues['__HasValue']
  for test, values in pairs(params) do
    value = waveboard:__HasValue(values['Table'], values['Value'])
    testExpected(test, value, values['Expected'])
  end
end


-- __InvalidResponse Tests [OMITTED]


-- __Send Tests

function TestWaveBoard:testSend()
  local params = TestValues['__Send']
  for test, values in pairs(params) do
    value = waveboard:__Send(values['Value'])
    testExpected(test, interface.directive, values['Expected'])
  end
end


-- __SliceString Tests

function TestWaveBoard:testSliceString()
  local params = TestValues['__SliceString']
  for test, values in pairs(params) do
    local value = values['Value']
    local first = values['First']
    local last = values['Last']
    value = waveboard:__SliceString(value, first, last)
    testExpected(test, value, values['Expected'])
  end
end


-- __SortByGroup Tests

function TestWaveBoard:testSortByGroups()
  local params = TestValues['__SortByGroup']
  for test, values in pairs(params) do
    local data = values['Data']
    local groups = waveboard:__SortByGroup(data)
    local group = nil
    for index=1, 8, 1 do
      group = groups['Group' .. index]
      assertEquals(group ~= nil, true)
    end
    assertEquals(groups['Master'] ~= nil, true)
  end
end


-- __SynchronizeTopology Tests

function TestWaveBoard:testSynchronizeTopology()
  local params = TestValues['__SynchronizeTopology']
  local group = ''
  for test, values in pairs(params) do
    local data = values['Data']
    waveboard:__SynchronizeTopology(data)
    assertEquals(waveboard.Groups ~= nil, true)
    for index=1, 8, 1 do
      group = waveboard.Groups['Group' .. index]
      assertEquals(group ~= nil, true)
    end
  end
end


-- __ToBits Tests

function TestWaveBoard:testToBits()
  local params = TestValues['__ToBits']
  for test, values in pairs(params) do
    local value = values['Integer']
    local bits = values['Bits']
    value = waveboard:__ToBits(value, bits)
    testExpected(test, table.concat(value), values['Expected'])
  end
end


-- __ToDecimal Tests

function TestWaveBoard:testToDecimal()
  local params = TestValues['__ToDecimal']
  for test, values in pairs(params) do
    local bits = values['Bits']
    value = waveboard:__ToDecimal(bits)
    testExpected(test, value, values['Expected'])
  end
end


-- ParseData Tests

function TestWaveBoard:testParseData()
  local data = 'RDYmaplistRDYpingmaplistRDY'
  waveboard:ParseData(data)
  assertEquals(waveboard.__BUFFER, '')
end

function callback(status, params)
  print(status, params)
end

function TestWaveBoard:testWatchers()
  local directive = 'HWC'
  local value = 2
  local params = {}
  local last = 0
  waveboard:Watcher(directive, value, params, callback)
  waveboard:Watcher(directive, value, {
    ['Blinking'] = 1,
    ['Color'] = 1
  }, callback)
  waveboard:Watcher(directive, value, params, callback)
  for index, watcher in pairs(waveboard.__WATCHERS[directive][value]) do
    if last < index then
      last = index
    end
  end
  assertEquals(last, 2)
end

results = lu.run()

os.exit(results)
