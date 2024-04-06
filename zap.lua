local function aabsIntersect(x1, y1, w1, h1, x2, y2, w2, h2)
  return x1 < x2 + w2 and
      x2 < x1 + w1 and
      y1 < y2 + h2 and
      y2 < y1 + h1
end

-- A stack of scenes that are currently being drawn into.
---@type Zap.Scene[]
local sceneStack = {}

local function getActiveScene()
  return sceneStack[#sceneStack]
end

---An instance of an element which can be rendered and interacted with.
---@class Zap.Element
---@field class Zap.ElementClass The class that this element is based on.
---@field package _scene Zap.Scene
---@field package _x number
---@field package _y number
---@field package _w number
---@field package _h number
---@field package _hovered boolean
---@field package _prevHovered boolean
---@field package _pressed table<any, true>
---@field package _parent? Zap.Element
---@field package _contained boolean
local Element = {}
Element.__index = Element

---Render the element, and set its position & size.
---@param x number
---@param y number
---@param width number
---@param height number
function Element:render(x, y, width, height)
  if not self._scene then
    self._scene = getActiveScene()
  end

  if #self._scene._parentStack > 0 then
    self._parent = self._scene._parentStack[#self._scene._parentStack]
  end
  table.insert(self._scene._parentStack, self)

  table.insert(self._scene._renderedElements, self)

  self._x = x
  self._y = y
  self._w = width
  self._h = height

  self.class.render(self, x, y, width, height)

  table.remove(self._scene._parentStack)
end

---Returns the view that this element was last rendered in.
---@return number x
---@return number y
---@return number width
---@return number height
function Element:getView()
  return self._x, self._y, self._w, self._h
end

---Returns the parent element that rendered this element, or `nil` if this is a root element.
---@return Zap.Element?
function Element:getParent()
  return self._parent
end

---Returns whether this element is currently hovered by the mouse.
---@return boolean hovered
function Element:isHovered()
  return self._hovered
end

---Returns whether `button` is currently pressed on this element.<br>
---If `button` is not given, returns whether _any_ mouse button is currently pressed on this element.
---@param button any?
---@return boolean pressed
function Element:isPressed(button)
  if button then
    return self._pressed[button]
  else
    return not not next(self._pressed)
  end
end

---Returns the position of the mouse relative to this element's position.
---@return number x
---@return number y
function Element:getRelativeMouse()
  return self._scene._mouseX - self._x, self._scene._mouseY - self._y
end

---Returns whether `other` is inside of `self`'s hierarchy - that is, if `self` or any of its children contain `other`.
---@param other Zap.Element
function Element:isInHierarchy(other)
  ---@type Zap.Element?
  local parent = other
  while parent do
    if parent == self then
      return true
    end
    parent = parent:getParent()
  end
  return false
end

---Set whether an element considers itself hovered only if its parent is hovered as well.
---@param contained boolean
function Element:setContained(contained)
  self._contained = contained
end

---@param class Zap.ElementClass
local function createElement(class)
  local self = setmetatable({}, Element)
  self.class = class
  self._pressed = {}
  if self.class.init then
    self.class.init(self)
  end
  return self
end

local elementClassMetatable = {
  ---@param class Zap.ElementClass
  __call = function(class)
    return createElement(class)
  end
}

---An ElementClass contains methods for rendering the element and interacting with it.<br>
---You can call an ElementClass to create a new Element with it.
---@class Zap.ElementClass: Zap.Element
---@field init fun(self: Zap.Element) Called when the element is created.
---@field render fun(self: Zap.Element, x: number, y: number, width: number, height: number) Called when the element needs to render its contents to the screen. Additional elements may be rendered here.
---@field mouseEntered fun(self: Zap.Element) Called when the mouse enters this element.
---@field mouseExited fun(self: Zap.Element) Called when the mouse exits this element.
---@field mousePressed fun(self: Zap.Element, button: any) Called when a mouse button is pressed over this element.
---@field mouseReleased fun(self: Zap.Element, button: any) Called when a mouse button is released over this element.
---@field mouseClicked fun(self: Zap.Element, button: any) Called when a mouse button is clicked (pressed & released) over this element.
---@operator call:Zap.Element

---Creates a new `ElementClass`.
---@return Zap.ElementClass
local function elementClass()
  return setmetatable({}, elementClassMetatable)
end

---A scene keeps track of the elements rendered inside it, and dispatches mouse events to them.
---@class Zap.Scene
---@field package _mouseX number
---@field package _mouseY number
---@field package _parentStack Zap.Element[]
---@field package _began boolean
---@field package _renderedElements Zap.Element[]
---@field package _overlappingElements Zap.Element[]
---@field package _pressedElement Zap.Element
---@field package _releaseHandle boolean
local Scene = {}
Scene.__index = Scene

---Sets the position of the mouse in this scene.
---@param x number
---@param y number
function Scene:setMousePosition(x, y)
  self._mouseX = x
  self._mouseY = y
  self:resolveOverlappingElements()
end

---Call when a mouse button has been pressed.
---@param button any
function Scene:mousePressed(button)
  for i, e in ipairs(self._overlappingElements) do
    e._pressed[button] = true
    if e.class.mousePressed then
      e.class.mousePressed(e, button)
    end
    self._pressedElement = e
  end
end

---Call when a mouse button has been released.
---@param button any
function Scene:mouseReleased(button)
  local pressedElement
  if self._pressedElement then
    pressedElement = self._pressedElement
    local e = self._pressedElement
    local prevPressed = e._pressed[button]
    e._pressed[button] = nil
    if e.class.mouseReleased then
      e.class.mouseReleased(e, button)
    end
    if prevPressed and e._hovered and e.class.mouseClicked then
      e.class.mouseClicked(e, button)
    end
    if not next(e._pressed) then
      self._pressedElement = nil
    end
  end
  for i, e in ipairs(self._overlappingElements) do
    if e ~= pressedElement and e.class.mouseReleased then
      e.class.mouseReleased(e, button)
    end
  end
end

---Begins a frame where elements can be drawn.
function Scene:begin()
  assert(not self._began, "attempt to begin a Scene more than once")
  self._began = true
  self._renderedElements = {}
  table.insert(sceneStack, self)
end

---Finishes a scene's frame after drawing elements.
function Scene:finish()
  assert(self._began and sceneStack[#sceneStack] == self, "attempt to finish a Scene that did not begin")
  self._began = false
  table.remove(sceneStack)
end

---Does the mouse overlap this element's AABB?
---@param e Zap.Element
---@package
function Scene:doesMouseOverlapElement(e)
  return self._mouseX >= e._x and self._mouseY >= e._y and self._mouseX < e._x + e._w and self._mouseY < e._y + e._h
end

---@package
function Scene:resolveOverlappingElements()
  local prevOverlapping = self._overlappingElements

  self._overlappingElements = {}

  -- TODO implement spatial hashing here if needed
  for _, e in ipairs(self._renderedElements) do
    e._prevHovered = e._hovered
    e._hovered = false
    local hovered = self:doesMouseOverlapElement(e) and (not e._contained or e._parent._hovered)
    if hovered then
      for i = #self._overlappingElements, 1, -1 do
        local other = self._overlappingElements[i]
        if aabsIntersect(e._x, e._y, e._w, e._h, other._x, other._y, other._w, other._h) and not other:isInHierarchy(e) then
          other._hovered = false
          table.remove(self._overlappingElements, i)
        end
      end
      e._hovered = true
      table.insert(self._overlappingElements, e)
    end
  end

  for _, e in ipairs(prevOverlapping) do
    if not e._hovered and e.class.mouseExited then
      e.class.mouseExited(e)
    end
  end

  for _, e in ipairs(self._overlappingElements) do
    if not e._prevHovered and e.class.mouseEntered then
      e.class.mouseEntered(e)
    end
  end
end

---Creates a new scene.
---@return Zap.Scene scene
local function createScene()
  local self = setmetatable({}, Scene)
  self._parentStack = {}
  self._began = false
  self._renderedElements = {}
  self._pressedElements = {}
  self._overlappingElements = {}
  return self
end

return {
  createScene = createScene,
  elementClass = elementClass
}
