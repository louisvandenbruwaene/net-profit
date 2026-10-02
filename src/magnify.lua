-- magnify.lua -- a trackpad pinch on macOS, read straight from the system.
--
-- LOVE 11 hears nothing of a pinch: macOS sends it to the window as a
-- "magnify" gesture, not as touches, and SDL's view ignores it. So the view
-- class is taught one more method at start-up, through LuaJIT's FFI and the
-- Objective-C runtime: magnifyWithEvent: adds the gesture's magnification to
-- `pending`, and the game takes it from there each frame. Anywhere else, or
-- if any of this is missing, `pending` simply stays 0.
local Magnify = { pending = 0, ready = false }

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

-- The gesture since last asked, as a fraction (0.1 = ten percent bigger).
function Magnify.take()
  local m = Magnify.pending
  Magnify.pending = 0
  return m
end

return Magnify
