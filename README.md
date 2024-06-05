# Zap

Zap is a minimal UI framework made for [LÖVE](https://love2d.org/), heavily inspired by the other prominent UI frameworks - [Helium](https://github.com/qeffects/helium) and [Inky](https://github.com/Keyslam/Inky).  
<sub>(It doesn't use any love-specific features, so you could use it in other Lua frameworks if you wish.)</sub>

## Usage

1. Require the library.

```lua
local zap = require "zap"
```

2. Define element classes.

```lua
local button = zap.elementClass()

function button:init()
  self.count = 0
end

function button:mouseClicked(btn)
  if btn == 1 then
    self.count = self.count + 1
  end
end

function button:render(x, y, w, h)
  love.graphics.setColor(1, 1, 1)
  love.graphics.rectangle("fill", x, y, w, h)
  love.graphics.setColor(0, 0, 0)
  love.graphics.printf("I've been clicked " .. self.count .. " times!", x, y, w, "center")
end
```

3. Create instances of elements by calling the element class.

```lua
local button1 = button()
local button2 = button()
```

4. Create a Scene and hook it to the necessary callbacks.

```lua
local scene = zap.createScene()

function love.mousemoved(x, y, dx, dy)
  scene:moveMouse(x, y, dx, dy)
end

function love.mousepressed(x, y, btn)
  scene:pressMouse(btn)
end

function love.mousereleased(x, y, btn)
  scene:releaseMouse(btn)
end
```

5. Render elements in your `draw` callback.

```lua
function love.draw()
  scene:begin()

  button1:render(100, 100, 200, 16)
  button2:render(100, 200, 200, 16)

  scene:finish()
end
```

And that's the gist of it!

You can `render` elements from within other elements, so structure your UI however you see fit.