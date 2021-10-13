local TestValues = {}
local json = require('lunajson')
local open = io.open('waveboard/data/topology.json', 'rb')
local data = ''
for line in io.lines('waveboard/data/topology.json') do
  data = data .. line
end
local panelData = ''
for line in io.lines('waveboard/data/panel.txt') do
  panelData = panelData .. line
end


TestValues['HWC'] = {
  ['Test1'] = {
    ['Blinking'] = 'Fast',
    ['Color'] = 'Red',
    ['Expected'] = 'HWC#2=258',
    ['Error'] = nil
  },
  ['Test2'] = {
    ['Blinking'] = 'Slow',
    ['Color'] = 'Green',
    ['Expected'] = 'HWC#2=1027',
    ['Error'] = nil
  },
  ['Test3'] = {
    ['Blinking'] = 'Medium',
    ['Color'] = 'Green',
    ['Expected'] = 'HWC#2=1027',
    ['Error'] = 'Blinking provided, but no speed defined; using slow'
  },
  ['Test4'] = {
      ['Blinking'] = nil,
      ['Color'] = 'Fuschia',
      ['Expected'] = 'HWC#2=4',
      ['Error'] = 'Color value not valid: Fuschia; using white'
  },
  ['Test5'] = {
      ['Blinking'] = nil,
      ['Color'] = 'Green',
      ['Expected'] = 'HWC#2=3',
      ['Error'] = nil
  },
  ['Test6'] = {
      ['Expected'] = 'HWC#2=0',
      ['Error'] = 'No color parameter provided'
  }
}

TestValues['HWCc'] = {
    ['Test1'] = {
      ['RGB'] = 'Amber',
      ['Expected'] = 'HWCc#2=136'
    },
    ['Test2'] = {
      ['RGB'] = 'Azure',
      ['Expected'] = nil,
      ['Error'] = 'Supplied RGB value does not exist'
    },
}

TestValues['HWCt'] = {
    ['Test1'] = {
      ['Parameters'] = {
        ['Value'] = 'Hello World!',
        ['Format'] = 'TextLine'
      },
      ['Expected'] = 'HWCt#2=Hello World!|10|||||||||||||||||'
    },
    ['Test2'] = {
      ['Parameters'] = {
        ['Value'] = 'Hello World!',
        ['Format'] = 'PNG'
      },
      ['Expected'] = 'HWCt#2=Hello World!|0|||||||||||||||||',
      ['Error'] = 'Incorrect format value: PNG; using Integer'
    }
}

TestValues['HWCx'] = {
  ['Test1'] = {
    ['Parameters'] = {
      ['Percent'] = 50,
      ['OutputType'] = 'Strength'
    },
    ['Expected'] = 'HWCx#2=4596',
  },
  ['Test2'] = {
    ['Parameters'] = {
      ['Percent'] = 50,
      ['OutputType'] = 'NotApplicable'
    },
    ['Error'] = 'OutputType not supported: NotApplicable'
  },
  ['Test3'] = {
    ['Parameters'] = {
      ['Percent'] = 50,
    },
    ['Error'] = 'Cannot execute HWCx command; no OutputType supplied'
  }
}

TestValues['__ConvertValues'] = {
  ['Test1'] = {
    ['Value'] = true,
    ['Expected'] = '1'
  },
  ['Test2'] = {
    ['Value'] = false,
    ['Expected'] = '0'
  },
  ['Test3'] = {
    ['Value'] = 'Foo',
    ['Expected'] = 'Foo'
  },
}

TestValues['__Error'] = {
  ['Test1'] = {
    ['Value'] = 'Mock Error # 1',
    ['Expected'] = 'Mock Error # 1'
  },
}

TestValues['__Send'] = {
  ['Test1'] = {
    ['Value'] = 'commandstring',
    ['Expected'] = 'commandstring\n'
  },
}

TestValues['__HasValue'] = {
  ['Test1'] = {
    ['Table'] = {
      ['Message'] = 'My cat wears a sweater for the holidays'
    },
    ['Value'] = 'Message',
    ['Expected'] = true
  },
  ['Test2'] = {
    ['Table'] = {
      ['Massage'] = 'Is message spelled wrong'
    },
    ['Value'] = 'Message',
    ['Expected'] = false
  }
}

TestValues['__SliceString'] = {
  ['Test1'] = {
    ['Value'] = 'RDYmaplistping',
    ['First'] = 11,
    ['Last'] = string.len('RDYmaplistping'),
    ['Expected'] = 'ping',
  }
}

TestValues['__ToBits'] = {
  ['Test1'] = {
    ['Integer'] = 255,
    ['Bits'] = 8,
    ['Expected'] = '11111111'
  }
}

TestValues['__ToDecimal'] = {
  ['Test1'] = {
    ['Bits'] = '11111111',
    ['Expected'] = 255
  }
}

TestValues['__SortByGroup'] = {
  ['Test1'] = {
    ['Data'] = data,
  }
}

TestValues['__SynchronizeTopology'] = {
  ['Test1'] = {
    ['Data'] = panelData
  }
}

return TestValues
