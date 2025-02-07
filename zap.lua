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
---@field package _prevW number
---@field package _prevH number
---@field package _hovered boolean
---@field package _prevHovered boolean
---@field package _pressed table<any, true>
---@field package _parent? Zap.Element
---@field package _container boolean
---@field package _ignoreContainer boolean
---@field package _mouseTransforms Zap.MouseTransform[]
---@field package _nextRenderCallbacks Zap.BeforeRenderCallback[]
---@field package _providedValues table<any, any>
local Element = {}
Element.__index = function(t, i)
  return Element[i] or t.class[i]
end

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
  self._scene._renderedElementsLookup[self] = true
  self._scene._renderedElementsHash = self._scene._renderedElementsHash .. tostring(self)

  for i = 1, math.max(#self._mouseTransforms, #self._scene._mouseTransformStack) do
    self._mouseTransforms[i] = self._scene._mouseTransformStack[i]
  end

  self._x = x
  self._y = y
  self._w = width
  self._h = height

  while #self._nextRenderCallbacks > 0 do
    self._nextRenderCallbacks[1](self)
    table.remove(self._nextRenderCallbacks, 1)
  end

  if self.class.resized and self._prevW and (self._prevW ~= self._w or self._prevH ~= self._h) then
    self.class.resized(self, width, height, self._prevW, self._prevH)
  end

  if self.class.render then
    self.class.render(self, x, y, width, height)
  end

  self._prevW, self._prevH = self._w, self._h

  table.remove(self._scene._parentStack)
end

---Returns the scene this element was rendered in.
---@return Zap.Scene
function Element:getScene()
  return self._scene
end

---By default, an element associates itself with a scene when it's first rendered.
---If you need it to happen before it's rendered, you can call this method.
---@param scene Zap.Scene
function Element:setScene(scene)
  self._scene = scene
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

---Returns the root element that this element is contained within.
---@return Zap.Element
function Element:getRoot()
  if self._parent then
    return self._parent:getRoot()
  end
  return self
end

---Returns whether this element is currently hovered by the mouse.
---@return boolean hovered
function Element:isHovered()
  return self._hovered
end

---Returns whether the mouse is anywhere over this element's rectangle, regardless of whether other elements appear in front of it.
---@return boolean over
function Element:isMouseOver()
  return self._scene:doesMouseOverlapElement(self)
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

---Returns the position of the mouse in the scene.
---@return number x
---@return number y
function Element:getAbsoluteMouse()
  return self._scene._mouseX, self._scene._mouseY
end

---Returns the position of the mouse relative to this element's position.
---@return number x
---@return number y
function Element:getRelativeMouse()
  local mouseX, mouseY = self._scene._mouseX, self._scene._mouseY
  for _, f in ipairs(self._mouseTransforms) do
    mouseX, mouseY = f(mouseX, mouseY)
  end
  return mouseX - self._x, mouseY - self._y
end

---Returns the width that this element desires to be rendered with.
---@return number width
function Element:desiredWidth()
  return self.class.desiredWidth(self)
end

---Returns the height that this element desires to be rendered with.
---@return number height
function Element:desiredHeight()
  return self.class.desiredHeight(self)
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

---Set whether this element is a "container" - the children of container elements will be considered hovered only if the container element is hovered as well.
---@param container boolean
function Element:setContainer(container)
  self._container = container
end

---Set whether this element should ignore any parent container elements, to be able to be considered hovered even if a container parent isn't hovered.
---@param ignoreContainer boolean
function Element:setIgnoreContainer(ignoreContainer)
  self._ignoreContainer = ignoreContainer
end

---Queues a function to run the next time the element is rendered - right after its view is set, but just before the element's `render` method is called.
---@param func Zap.BeforeRenderCallback
function Element:nextRender(func)
  table.insert(self._nextRenderCallbacks, func)
end

---Provides a value that children of this element can `inject`.
---@param key any
---@param value any
function Element:provide(key, value)
  self._providedValues[key] = value
end

---Returns the value that was `provide`d with the same key by a parent.
---
---Note that this may only be used during or after the element's first render.
---@param key any
---@return any
function Element:inject(key)
  return self._providedValues[key] or (self._parent and self._parent:inject(key))
end

---@param class Zap.ElementClass
local function createElement(class, ...)
  ---@type Zap.Element
  local self = setmetatable({}, Element)
  self.class = class
  self._pressed = {}
  self._mouseTransforms = {}
  self._nextRenderCallbacks = {}
  self._providedValues = {}
  if self.class.init then
    self.class.init(self, ...)
  end
  return self
end

local elementClassMetatable = {
  ---@param class Zap.ElementClass
  __call = function(class, ...)
    return createElement(class, ...)
  end
}

---An ElementClass contains methods for rendering the element and interacting with it.<br>
---You can call an ElementClass to create a new Element with it.
---@class Zap.ElementClass: Zap.Element
---@field init fun(self: Zap.Element, ...) Called when the element is created.
---@field render fun(self: Zap.Element, x: number, y: number, width: number, height: number) Called when the element needs to render its contents to the screen. Additional elements may be rendered here.
---@field mouseEntered fun(self: Zap.Element) Called when the mouse enters this element.
---@field mouseExited fun(self: Zap.Element) Called when the mouse exits this element.
---@field mousePressed fun(self: Zap.Element, button: any): boolean? Called when a mouse button is pressed over this element.<br>May optionally return a boolean that says whether this event was "consumed" - if false, the event will be propagated to the element's parent. `true` by default.
---@field mouseReleased fun(self: Zap.Element, button: any) Called when a mouse button is released over this element.
---@field mouseClicked fun(self: Zap.Element, button: any) Called when a mouse button is clicked (pressed & released) over this element.
---@field mouseMoved fun(self: Zap.Element, x: number, y: number, dx: number, dy: number) Called when the mouse is moved over the element. `x` and `y` are absolute coordinates.
---@field resized fun(self: Zap.Element, w: number, h: number, prevW: number, prevH: number) Called when the element has been rendered with a different size.
---@field desiredWidth fun(self: Zap.Element): number Returns the width that this element desires to be rendered with.
---@field desiredHeight fun(self: Zap.Element): number Returns the height that this element desires to be rendered with.
---@operator call:Zap.Element

---Creates a new `ElementClass`.
---@return Zap.ElementClass
local function elementClass()
  return setmetatable({}, elementClassMetatable)
end

---@alias Zap.MouseTransform fun(x: number, y: number): number, number
---@alias Zap.BeforeRenderCallback fun(e: Zap.Element)

---A scene keeps track of the elements rendered inside it, and dispatches mouse events to them.
---@class Zap.Scene
---@field package _mouseX number
---@field package _mouseY number
---@field package _parentStack Zap.Element[]
---@field package _began boolean
---@field package _renderedElements Zap.Element[]
---@field package _renderedElementsLookup table<Zap.Element, true>
---@field package _renderedElementsHash string
---@field package _prevRenderedElements Zap.Element[]
---@field package _prevRenderedElementsHash string
---@field package _overlappingElements Zap.Element[]
---@field package _pressedElement Zap.Element?
---@field package _mouseTransformStack Zap.MouseTransform[]
local Scene = {}
Scene.__index = Scene

---Call when the mouse has moved.
---@param x number The current X of the mouse.
---@param y number The current Y of the mouse.
---@param dx number How much the mouse has moved on the X axis.
---@param dy number How much the mouse has moved on the Y axis.
function Scene:moveMouse(x, y, dx, dy)
  self._mouseX = x
  self._mouseY = y
  self:resolveOverlappingElements()
  if self._pressedElement then
    if self._pressedElement.class.mouseMoved and self:isElementRendered(self._pressedElement) then
      -- TODO - transform the `dx` and `dy` parameters if mouseTransforms exist
      local rx, ry = self._pressedElement:getRelativeMouse()
      self._pressedElement.class.mouseMoved(self._pressedElement, rx, ry, dx, dy)
    end
  else
    for _, e in ipairs(self._overlappingElements) do
      if e.class.mouseMoved then
        local rx, ry = e:getRelativeMouse()
        e.class.mouseMoved(e, rx, ry, dx, dy)
      end
    end
  end
end

---Call when a mouse button has been pressed.
---@param button any
---@param runBefore? fun(element: Zap.Element?) A function that will be called with the pressed element, just before its `mousePressed` event will be fired.
function Scene:pressMouse(button, runBefore)
  self:resolveOverlappingElements()
  local last = self._overlappingElements[#self._overlappingElements]
  if runBefore then
    runBefore(last)
  end
  if last then
    repeat
      ---@type boolean?
      local consumed = false
      last._pressed[button] = true
      if last.class.mousePressed then
        consumed = last.class.mousePressed(last, button)
        if consumed == nil then
          consumed = true
        end
      elseif last.class.mouseClicked then
        consumed = true
      end
      if not consumed then
        last._pressed[button] = nil
        last = last._parent
      end
    until consumed or not last
  end
  self._pressedElement = last
end

---Call when a mouse button has been released.
---@param button any
function Scene:releaseMouse(button)
  self:resolveOverlappingElements()
  local pressedElement = self._pressedElement
  if pressedElement then
    local prevPressed = pressedElement._pressed[button]
    pressedElement._pressed[button] = nil
    if pressedElement.class.mouseReleased then
      pressedElement.class.mouseReleased(pressedElement, button)
    end
    if prevPressed and pressedElement._hovered and pressedElement.class.mouseClicked then
      pressedElement.class.mouseClicked(pressedElement, button)
    end
    if not next(pressedElement._pressed) then
      self._pressedElement = nil
    end
  end
  for _, e in ipairs(self._overlappingElements) do
    if e ~= pressedElement and e.class.mouseReleased then
      e.class.mouseReleased(e, button)
    end
  end
end

---Raises a custom event that will be fired for the topmost element under the mouse that implements it.<br>
---Will be bubbled up similarly to `mousePressed`.
---@param event string
---@param ... any
function Scene:raiseMouseEvent(event, ...)
  self:resolveOverlappingElements()
  local last = self._overlappingElements[#self._overlappingElements]
  if last then
    repeat
      local consumed = false
      if last.class[event] then
        consumed = last.class[event](last, ...)
        if consumed == nil then
          consumed = true
        end
      end
      if not consumed then
        last = last._parent
      end
    until consumed or not last
  end
end

---Raise an event to all rendered elements.<br>
---If any element's class has a method with the same name as the event, it will be called with the given parameters.
---@param event string
---@param ... any
function Scene:raiseEvent(event, ...)
  for _, e in ipairs(self._renderedElements) do
    if e.class[event] then
      e.class[event](e, ...)
    end
  end
end

---Begins a frame where elements can be drawn.
function Scene:begin()
  assert(not self._began, "attempt to begin a Scene more than once")
  self._began = true
  self._prevRenderedElements = self._renderedElements
  self._prevRenderedElementsHash = self._renderedElementsHash
  self._renderedElements = {}
  self._renderedElementsLookup = {}
  self._renderedElementsHash = ""
  table.insert(sceneStack, self)
end

---Finishes a scene's frame after drawing elements.
function Scene:finish()
  assert(self._began and sceneStack[#sceneStack] == self, "attempt to finish a Scene that did not begin")
  assert(#self._mouseTransformStack == 0,
    "not all mouse transforms were popped\nverify that all calls to `pushMouseTransform` have a matching `popMouseTransform`")

  self._began = false
  table.remove(sceneStack)

  if self._prevRenderedElements then
    for _, e in ipairs(self._prevRenderedElements) do
      if not self._renderedElementsLookup[e] then
        e._hovered = false
      end
    end
  end

  if self._renderedElementsHash ~= self._prevRenderedElementsHash and self._mouseX then
    self:resolveOverlappingElements()
  end
end

---Does the mouse overlap this element's AABB?
---@param e Zap.Element
---@package
function Scene:doesMouseOverlapElement(e)
  local mouseX, mouseY = self._mouseX, self._mouseY
  for _, f in ipairs(e._mouseTransforms) do
    mouseX, mouseY = f(mouseX, mouseY)
  end
  return mouseX >= e._x and mouseY >= e._y and mouseX < e._x + e._w and mouseY < e._y + e._h
end

---@package
function Scene:resolveOverlappingElements()
  local prevOverlapping = self._overlappingElements

  self._overlappingElements = {}

  -- If a container element is not hovered, it will be stored in this variable
  -- until the next element won't be in the container's hierarchy.
  ---@type Zap.Element?
  local unhoveredContainer

  -- TODO implement spatial hashing here if needed
  for _, e in ipairs(self._renderedElements) do
    e._prevHovered = e._hovered
    e._hovered = false
    if unhoveredContainer and not unhoveredContainer:isInHierarchy(e) then
      unhoveredContainer = nil
    end
    local hovered = (e._ignoreContainer or not unhoveredContainer) and self:doesMouseOverlapElement(e)
    if hovered then
      for i = #self._overlappingElements, 1, -1 do
        local other = self._overlappingElements[i]
        if not other:isInHierarchy(e) then
          other._hovered = false
          table.remove(self._overlappingElements, i)
        end
      end
      e._hovered = true
      table.insert(self._overlappingElements, e)
    elseif e._container and not unhoveredContainer then
      unhoveredContainer = e
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

---Returns the element currently pressed by the mouse.
---@return Zap.Element
function Scene:getPressedElement()
  return self._pressedElement
end

---Returns a list of elements the mouse is currently hovering over.<br>
---(This is also the table used internally by the scene, so please don't modify it.)
---@return Zap.Element[]
function Scene:getHoveredElements()
  return self._overlappingElements
end

---Returns whether `e` has been rendered in the last frame.
---@param e Zap.Element
---@return boolean
function Scene:isElementRendered(e)
  return not not self._renderedElementsLookup[e]
end

---Emulates a mouse press on the element.
---@param e Zap.Element
---@param button any
function Scene:setPressedElement(e, button)
  e._pressed[button] = true
  self._pressedElement = e
end

---Pushes a function that will transform the mouse's position for all elements rendered after this call.
---@param func Zap.MouseTransform
function Scene:pushMouseTransform(func)
  table.insert(self._mouseTransformStack, func)
end

---Pops the last mouse transform that was pushed with `pushMouseTransform`.
function Scene:popMouseTransform()
  table.remove(self._mouseTransformStack)
end

---Creates a new scene.
---@return Zap.Scene scene
local function createScene()
  local self = setmetatable({}, Scene)
  self._mouseX = 0
  self._mouseY = 0
  self._parentStack = {}
  self._began = false
  self._renderedElements = {}
  self._overlappingElements = {}
  self._mouseTransformStack = {}
  return self
end

return {
  createScene = createScene,
  elementClass = elementClass
}
