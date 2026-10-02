-- magnify.lua -- a trackpad pinch and scroll on macOS, read from the system.
--
-- LOVE 11 hears nothing of a pinch: macOS sends it to the window as a
-- "magnify" gesture, not as touches, and SDL's view ignores it. So the view
-- class is taught one more method at start-up, through LuaJIT's FFI and the
-- Objective-C runtime: magnifyWithEvent: adds the gesture's magnification to
-- `pending`, and the game takes it from there each frame. Anywhere else, or
-- if any of this is missing, `pending` simply stays 0.
local Magnify = { pending = 0, ready = false, dx = 0, dy = 0, preciseAt = -1 }

-- Whether the wheel events LOVE is reporting now come from a trackpad, whose
-- scrolling is taken here instead.
function Magnify.trackpad()
  return love.timer.getTime() - Magnify.preciseAt < 0.25
end

-- The two-finger movement since last asked, in points.
function Magnify.scroll()
  local x, y = Magnify.dx, Magnify.dy
  Magnify.dx, Magnify.dy = 0, 0
  return x, y
end

-- The gesture since last asked, as a fraction (0.1 = ten percent bigger).
function Magnify.take()
  local m = Magnify.pending
  Magnify.pending = 0
  return m
end


local okJit, ffi = pcall(require, "ffi")
if not okJit or ffi.os ~= "OSX" then return Magnify end

local ok = pcall(function()
  ffi.cdef [[
    typedef struct objc_class *Class;
    typedef struct objc_object *id;
    typedef struct objc_selector *SEL;
    typedef void (*IMP)(void);
    Class objc_getClass(const char *name);
    SEL sel_registerName(const char *name);
    bool class_addMethod(Class cls, SEL name, IMP imp, const char *types);
    void objc_msgSend(void);
  ]]
end)
if not ok then return Magnify end

local C = ffi.C
local view = C.objc_getClass("SDLView")
if view == nil then return Magnify end

-- objc_msgSend called with the exact signature, as arm64 requires.
local magnification = ffi.cast("double (*)(void *, SEL)", C.objc_msgSend)
local selMagnification = C.sel_registerName("magnification")

-- Kept in the module so the collector never frees the callback.
Magnify.handler = ffi.cast("void (*)(void *, SEL, void *)", function(_, _, event)
  if event ~= nil then
    Magnify.pending = Magnify.pending + magnification(event, selMagnification)
  end
end)

Magnify.ready = C.class_addMethod(view, C.sel_registerName("magnifyWithEvent:"),
  ffi.cast("IMP", Magnify.handler), "v@:@")

-- Two fingers on the trackpad: LOVE hears a scroll only in whole wheel
-- clicks, which pans in jumps. The view keeps the exact distance the fingers
-- moved (in points) and then passes the event on, so SDL still sees it.
local precise = ffi.cast("bool (*)(void *, SEL)", C.objc_msgSend)
local nextResponder = ffi.cast("void * (*)(void *, SEL)", C.objc_msgSend)
local forward = ffi.cast("void (*)(void *, SEL, void *)", C.objc_msgSend)
local selPrecise = C.sel_registerName("hasPreciseScrollingDeltas")
local selDX, selDY = C.sel_registerName("scrollingDeltaX"), C.sel_registerName("scrollingDeltaY")
local selNext, selScroll = C.sel_registerName("nextResponder"), C.sel_registerName("scrollWheel:")
Magnify.scroller = ffi.cast("void (*)(void *, SEL, void *)", function(self, _, event)
  if event ~= nil and precise(event, selPrecise) then
    Magnify.dx = Magnify.dx + magnification(event, selDX)
    Magnify.dy = Magnify.dy + magnification(event, selDY)
    Magnify.preciseAt = love and love.timer and love.timer.getTime() or 0
  end
  local nxt = nextResponder(self, selNext)
  if nxt ~= nil then forward(nxt, selScroll, event) end
end)
Magnify.smooth = C.class_addMethod(view, selScroll, ffi.cast("IMP", Magnify.scroller), "v@:@")

return Magnify
