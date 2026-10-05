--[[
  lpp_mock.lua — a desktop stand-in for the lpp-vita interpreter, for LuaJIT.

  It installs the same 18 global modules and 128+ constants that lpp-vita registers,
  and every function is validated against tools/mock/lpp_api.lua, which is GENERATED
  from lpp-vita's C sources (tools/gen_api.py):
    * argument count       - the exact `if (argc ...) luaL_error` predicate from C
    * argument types       - luaL_checkinteger/number/string and table reads
    * unsafe-only calls    - raise "this function requires unsafe mode" in safe mode
    * state guards         - blend phase, Network/Camera/Video/sensor init, async limit,
                             one message dialog at a time, ...
  Rendering goes to a 960x544 cairo surface (FFI), so frames can be saved as PNG.
  Files map app0:/ -> the app folder and ux0:/ etc. -> a sandbox directory.

  Real behaviour that needs hardware (camera frames, audio, network) is simulated
  with plausible values; the point is to execute every code path of the app with
  the real calling conventions, not to emulate the Vita.
]]

local ffi = require("ffi")
local M = { log = {}, errors = {}, frame = 0, script = nil }
local API = dofile(MOCK_DIR .. "lpp_api.lua")
M.API = API

---------------------------------------------------------------- configuration
M.cfg = {
  safe = true,                          -- emulate eboot_safe.bin
  app_dir = "./app/",
  sandbox = "./build/sandbox/",
  wifi = true,
  shots_dir = nil,                      -- if set, Screen.flip saves PNGs on request
}

---------------------------------------------------------------- cairo via FFI
ffi.cdef [[
typedef struct _cairo_surface cairo_surface_t;
typedef struct _cairo cairo_t;
typedef struct _cairo_font_face cairo_font_face_t;
typedef struct { double x_bearing, y_bearing, width, height, x_advance, y_advance; } cairo_text_extents_t;
cairo_surface_t *cairo_image_surface_create(int format, int width, int height);
cairo_surface_t *cairo_image_surface_create_from_png(const char *filename);
int cairo_surface_status(cairo_surface_t *s);
int cairo_image_surface_get_width(cairo_surface_t *s);
int cairo_image_surface_get_height(cairo_surface_t *s);
unsigned char *cairo_image_surface_get_data(cairo_surface_t *s);
int cairo_image_surface_get_stride(cairo_surface_t *s);
void cairo_surface_flush(cairo_surface_t *s);
void cairo_surface_mark_dirty(cairo_surface_t *s);
int cairo_surface_write_to_png(cairo_surface_t *s, const char *filename);
void cairo_surface_destroy(cairo_surface_t *s);
cairo_t *cairo_create(cairo_surface_t *target);
void cairo_destroy(cairo_t *cr);
void cairo_save(cairo_t *cr);
void cairo_restore(cairo_t *cr);
void cairo_set_source_rgba(cairo_t *cr, double r, double g, double b, double a);
void cairo_set_source_surface(cairo_t *cr, cairo_surface_t *s, double x, double y);
void cairo_paint(cairo_t *cr);
void cairo_paint_with_alpha(cairo_t *cr, double a);
void cairo_rectangle(cairo_t *cr, double x, double y, double w, double h);
void cairo_arc(cairo_t *cr, double xc, double yc, double r, double a1, double a2);
void cairo_move_to(cairo_t *cr, double x, double y);
void cairo_line_to(cairo_t *cr, double x, double y);
void cairo_new_path(cairo_t *cr);
void cairo_fill(cairo_t *cr);
void cairo_stroke(cairo_t *cr);
void cairo_clip(cairo_t *cr);
void cairo_set_line_width(cairo_t *cr, double w);
void cairo_translate(cairo_t *cr, double x, double y);
void cairo_scale(cairo_t *cr, double x, double y);
void cairo_rotate(cairo_t *cr, double a);
void cairo_select_font_face(cairo_t *cr, const char *family, int slant, int weight);
void cairo_set_font_size(cairo_t *cr, double size);
void cairo_show_text(cairo_t *cr, const char *utf8);
void cairo_text_extents(cairo_t *cr, const char *utf8, cairo_text_extents_t *ext);
int cairo_status(cairo_t *cr);
const char *cairo_status_to_string(int status);
void cairo_set_operator(cairo_t *cr, int op);
typedef struct _cairo_pattern cairo_pattern_t;
cairo_pattern_t *cairo_get_source(cairo_t *cr);
void cairo_pattern_set_filter(cairo_pattern_t *p, int filter);
void cairo_push_group(cairo_t *cr);
void cairo_pop_group_to_source(cairo_t *cr);
void cairo_mask_surface(cairo_t *cr, cairo_surface_t *s, double x, double y);
]]
local cairo = ffi.load("cairo")
local FMT_ARGB32, OP_SOURCE, OP_OVER, OP_MULTIPLY = 0, 1, 2, 14
local FILTER_NEAREST, FILTER_BILINEAR = 3, 4

local W, H = 960, 544
local screen = cairo.cairo_image_surface_create(FMT_ARGB32, W, H)
local front = cairo.cairo_image_surface_create(FMT_ARGB32, W, H) -- "displayed" frame
local cr = cairo.cairo_create(screen)
M.screen, M.front = screen, front

local function rgba(c)
  c = c % 4294967296
  local r, g, b, a = c % 256, math.floor(c / 256) % 256, math.floor(c / 65536) % 256, math.floor(c / 16777216) % 256
  return r / 255, g / 255, b / 255, a / 255
end
local function set_color(ctx, c) local r, g, b, a = rgba(c); cairo.cairo_set_source_rgba(ctx, r, g, b, a) end

---------------------------------------------------------------- handles
-- lpp returns raw C pointers as integers. We hand out large distinct integers and
-- keep the object behind them, checking the "magic" like the C code does.
local objects, next_handle = {}, 0x81000000
local function new_handle(kind, obj)
  next_handle = next_handle + 0x40
  obj.kind = kind
  objects[next_handle] = obj
  return next_handle
end
local function get(h, kind, fname)
  local o = objects[h]
  if not o or (kind and o.kind ~= kind) then
    error(fname .. ": attempt to access wrong memory block type (" .. tostring(h) .. ")", 3)
  end
  return o
end
local function free(h) objects[h] = nil end

---------------------------------------------------------------- argument checking
local function check_predicate(pred, argc)
  -- predicates come straight from C, e.g. "argc != 3 && argc != 4", "argc < 2 || argc > 6"
  local expr = pred:gsub("!=", "~="):gsub("&&", " and "):gsub("||", " or ")
  local f = assert(loadstring("local argc = ...; return " .. expr))
  return f(argc)
end

local TYPE_OK = {
  int = function(v) return type(v) == "number" or (type(v) == "string" and tonumber(v) ~= nil) end,
  num = function(v) return type(v) == "number" or (type(v) == "string" and tonumber(v) ~= nil) end,
  str = function(v) return type(v) == "string" or type(v) == "number" end,
  bool = function() return true end,
  table = function(v) return type(v) == "table" end,
}
local TYPE_NAME = { int = "number", num = "number", str = "string", table = "table", bool = "any" }

M.stats = { calls = 0, by_fn = {}, arg_errors = 0 }

local function wrap(modname, fname, impl)
  local spec = API.modules[modname] and API.modules[modname][fname]
  assert(spec, "mock implements " .. modname .. "." .. fname .. " which lpp-vita does not export")
  local full = modname .. "." .. fname
  return function(...)
    local argc = select("#", ...)
    -- trailing nils are real arguments in Lua's C API too (lua_gettop counts them)
    M.stats.calls = M.stats.calls + 1
    M.stats.by_fn[full] = (M.stats.by_fn[full] or 0) + 1
    -- every native call costs 10 us of simulated time, so busy-wait loops terminate
    M.advance(0.01)
    M.since_flip = M.since_flip + 1
    if M.since_flip > 2000000 then
      error("watchdog: 2M native calls without Screen.flip (busy loop?) at " .. full, 2)
    end
    if spec.argc and check_predicate(spec.argc, argc) then
      M.stats.arg_errors = M.stats.arg_errors + 1
      error(full .. ": wrong number of arguments (" .. argc .. ", C requires not: " .. spec.argc .. ")", 2)
    end
    local args = { ... }
    for i, t in pairs(spec.args) do
      if i <= argc and t ~= "bool" then
        local v = args[i]
        if not TYPE_OK[t](v) then
          M.stats.arg_errors = M.stats.arg_errors + 1
          error(string.format("bad argument #%d to '%s' (%s expected, got %s)", i, fname, TYPE_NAME[t], type(v)), 2)
        end
      end
    end
    if spec.unsafe and M.cfg.safe then error("this function requires unsafe mode", 2) end
    return impl(...)
  end
end

---------------------------------------------------------------- virtual filesystem
local function sh(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end
local function host_path(p, fname)
  p = tostring(p)
  local dev, rest = p:match("^(%w+):/?(.*)$")
  if not dev then error((fname or "io") .. ": not an absolute Vita path: " .. p, 3) end
  if dev == "app0" then return M.cfg.app_dir .. rest, true end
  return M.cfg.sandbox .. dev .. "/" .. rest, false
end
M.host_path = host_path

-- safe eboot: only ux0:/data and app0:/ may be opened
local function io_allowed(p)
  if not M.cfg.safe then return true end
  return p:match("^app0:") or p:match("^ux0:/?data")
end

local function exists(hp) local f = io.open(hp, "rb") if f then f:close() return true end return false end
local function isdir(hp) return os.execute("test -d " .. sh(hp)) == 0 end
local function mkdir_p(hp) os.execute("mkdir -p " .. sh(hp)) end
local function dirname(hp) return hp:match("^(.*)/[^/]*$") or "." end
local function readall(hp) local f = io.open(hp, "rb") if not f then return nil end local s = f:read("*a") f:close() return s end

---------------------------------------------------------------- image loading
local function surface_from_file(path)
  local hp = host_path(path, "loadImage")
  local data = readall(hp)
  if not data then return nil, "file" end
  local magic = data:byte(1) + data:byte(2) * 256
  local png = hp
  if magic ~= 0x5089 then
    if magic ~= 0x4D42 and magic ~= 0xD8FF and magic ~= 0x4947 then return nil, "magic" end
    png = M.cfg.sandbox .. ".tmp_convert.png"
    os.execute("magick " .. sh(hp .. "[0]") .. " PNG32:" .. sh(png) .. " 2>/dev/null")
  end
  local s = cairo.cairo_image_surface_create_from_png(png)
  if cairo.cairo_surface_status(s) ~= 0 then return nil, "decode" end
  return s
end

local function new_image(surface, extra)
  local o = extra or {}
  o.s = surface
  o.w = cairo.cairo_image_surface_get_width(surface)
  o.h = cairo.cairo_image_surface_get_height(surface)
  o.filter = FILTER_NEAREST
  return new_handle("image", o)
end

local function color_surface(w, h, c)
  local s = cairo.cairo_image_surface_create(FMT_ARGB32, w, h)
  local ctx = cairo.cairo_create(s)
  set_color(ctx, c)
  cairo.cairo_paint(ctx)
  cairo.cairo_destroy(ctx)
  return s
end

---------------------------------------------------------------- state
local st = {
  blend = false, rescaler = nil, net = false, async_n = 0, async_state = 1, async_res = nil,
  async_until = 0, async_fin = nil, msg = nil, kb = nil, sensors = false, cam = nil,
  video = { ready = false }, gui = false, sound_init = false, mic = nil, clear = 0xFF000000,
  ftp = false, files = {}, fd_next = 0x40010000, timers_wall = 0,
}
M.state = st

-- simulated clocks: the mock advances 1/60 s per Screen.flip so runs are deterministic
local now_ms = 0
M.since_flip = 0
function M.now() return now_ms end
function M.advance(ms) now_ms = now_ms + ms end

---------------------------------------------------------------- input injection
M.input = { buttons = 0, lx = 128, ly = 128, rx = 128, ry = 128, touch = {}, rear = {} }
function M.press(mask) M.input.buttons = mask end

local function bit_or(a, b) return bit.bor(a, b) end

---------------------------------------------------------------- drawing helpers
local function ensure_blend(fname)
  if not st.blend then error(fname .. " can't be called outside a blending phase.", 3) end
end

local function draw_target() return st.rescaler and st.rescaler.ctx or cr end

local function draw_surface(ctx, img, x, y, sx, sy, rot, part, tint, centered)
  cairo.cairo_save(ctx)
  cairo.cairo_translate(ctx, x, y)
  if rot and rot ~= 0 then cairo.cairo_rotate(ctx, rot) end
  cairo.cairo_scale(ctx, sx or 1, sy or 1)
  local px, py, pw, ph = 0, 0, img.w, img.h
  if part then px, py, pw, ph = part[1], part[2], part[3], part[4] end
  if centered then cairo.cairo_translate(ctx, -pw / 2, -ph / 2) end
  cairo.cairo_rectangle(ctx, 0, 0, pw, ph)
  cairo.cairo_clip(ctx)
  cairo.cairo_set_source_surface(ctx, img.s, -px, -py)
  cairo.cairo_pattern_set_filter(cairo.cairo_get_source(ctx), img.filter or FILTER_NEAREST)
  if tint then
    local r, g, b, a = rgba(tint)
    cairo.cairo_paint_with_alpha(ctx, a)
    if r < 0.99 or g < 0.99 or b < 0.99 then
      cairo.cairo_set_operator(ctx, OP_MULTIPLY)
      cairo.cairo_set_source_rgba(ctx, r, g, b, 1)
      cairo.cairo_mask_surface(ctx, img.s, -px, -py)
      cairo.cairo_set_operator(ctx, OP_OVER)
    end
  else
    cairo.cairo_paint(ctx)
  end
  cairo.cairo_restore(ctx)
end

---------------------------------------------------------------- fonts (cairo toy API)
-- cairo_show_text requires valid UTF-8 and puts the context in an error state otherwise
-- (after which NOTHING draws). vita2d would just print junk glyphs, so emulate that.
local function utf8_clean(s)
  s = tostring(s)
  if not s:find("[\128-\255%z]") then return s end
  local out, i, n = {}, 1, #s
  while i <= n do
    local c = s:byte(i)
    local len = (c < 0x80 and 1) or (c >= 0xC2 and c <= 0xDF and 2) or (c >= 0xE0 and c <= 0xEF and 3) or (c >= 0xF0 and c <= 0xF4 and 4) or 0
    local ok = len > 0 and c ~= 0
    for k = 1, len - 1 do
      local cc = s:byte(i + k)
      if not cc or cc < 0x80 or cc > 0xBF then ok = false end
    end
    if ok then out[#out + 1] = s:sub(i, i + len - 1); i = i + len
    else out[#out + 1] = "?"; i = i + 1 end
  end
  return table.concat(out)
end
M.utf8_clean = utf8_clean
local function font_draw(ctx, font, x, y, text, c, size)
  cairo.cairo_save(ctx)
  cairo.cairo_select_font_face(ctx, font.family, 0, font.bold and 1 or 0)
  cairo.cairo_set_font_size(ctx, size)
  set_color(ctx, c)
  cairo.cairo_move_to(ctx, x, y + size * 0.92)
  cairo.cairo_show_text(ctx, utf8_clean(text))
  cairo.cairo_restore(ctx)
end
local ext = ffi.new("cairo_text_extents_t")
local measure_ctx = cairo.cairo_create(cairo.cairo_image_surface_create(FMT_ARGB32, 4, 4))
local function font_width(font, text, size)
  cairo.cairo_select_font_face(measure_ctx, font.family, 0, font.bold and 1 or 0)
  cairo.cairo_set_font_size(measure_ctx, size)
  cairo.cairo_text_extents(measure_ctx, utf8_clean(text), ext)
  return math.floor(ext.x_advance + 0.5)
end
local debug_font = { family = "Liberation Sans", bold = false }

---------------------------------------------------------------- modules
local impl = {}
local function mod(name) impl[name] = impl[name] or {} return impl[name] end

-- Color --------------------------------------------------------------------
local Color = mod("Color")
function Color.new(r, g, b, a)
  a = a or 255
  local v = (r % 256) + (g % 256) * 256 + (b % 256) * 65536 + (a % 256) * 16777216
  if v >= 2147483648 then v = v - 4294967296 end -- C int
  return v
end
function Color.getR(c) return (c % 4294967296) % 256 end
function Color.getG(c) return math.floor((c % 4294967296) / 256) % 256 end
function Color.getB(c) return math.floor((c % 4294967296) / 65536) % 256 end
function Color.getA(c) return math.floor((c % 4294967296) / 16777216) % 256 end

-- Screen -------------------------------------------------------------------
local Screen = mod("Screen")
function Screen.clear(c)
  if c then st.clear = c end
  local ctx = draw_target()
  cairo.cairo_save(ctx)
  cairo.cairo_set_operator(ctx, OP_SOURCE)
  set_color(ctx, st.clear)
  cairo.cairo_paint(ctx)
  cairo.cairo_restore(ctx)
end
function Screen.flip()
  -- a cairo context in error state silently stops drawing: fail loudly instead
  local status = cairo.cairo_status(cr)
  if status ~= 0 then
    error("mock renderer broke (cairo: " .. ffi.string(cairo.cairo_status_to_string(status)) .. ")", 2)
  end
  -- copy back buffer to the "front" buffer
  local fctx = cairo.cairo_create(front)
  cairo.cairo_set_operator(fctx, OP_SOURCE)
  cairo.cairo_set_source_surface(fctx, screen, 0, 0)
  cairo.cairo_paint(fctx)
  cairo.cairo_destroy(fctx)
  M.frame = M.frame + 1
  M.since_flip = 0
  now_ms = now_ms + 1000 / 60
  if M.on_flip then M.on_flip(M.frame) end
end
function Screen.waitVblankStart() end
function Screen.getPixel(x, y)
  cairo.cairo_surface_flush(front)
  local data = cairo.cairo_image_surface_get_data(front)
  local stride = cairo.cairo_image_surface_get_stride(front)
  local p = ffi.cast("uint32_t*", data + y * stride)[x]
  local a, r, g, b = bit.rshift(p, 24), bit.band(bit.rshift(p, 16), 255), bit.band(bit.rshift(p, 8), 255), bit.band(p, 255)
  return Color.new(r, g, b, a)
end

-- Graphics -----------------------------------------------------------------
local Graphics = mod("Graphics")
function Graphics.initBlend()
  if st.blend then error("initBlend can't be called inside a blending phase.", 2) end
  st.blend = true
end
function Graphics.termBlend()
  if not st.blend then error("termBlend can't be called outside a blending phase.", 2) end
  st.blend = false
  if st.rescaler then
    local r = st.rescaler
    cairo.cairo_save(cr)
    cairo.cairo_set_operator(cr, OP_SOURCE)
    cairo.cairo_set_source_rgba(cr, 0, 0, 0, 1)
    cairo.cairo_paint(cr)
    cairo.cairo_restore(cr)
    draw_surface(cr, { s = r.s, w = W, h = H, filter = FILTER_NEAREST }, r.x, r.y, r.sx, r.sy)
  end
  -- system dialogs are composited here on the real console
  if st.msg or st.kb then M.draw_dialog_overlay(cr) end
end
function Graphics.debugPrint(x, y, text, c, scale)
  ensure_blend("debugPrint")
  font_draw(draw_target(), debug_font, x, y, text, c, 17.4 * (scale or 1))
end
function Graphics.fillRect(x1, x2, y1, y2, c)
  ensure_blend("drawRect")
  if x2 < x1 then x1, x2 = x2, x1 end
  if y2 < y1 then y1, y2 = y2, y1 end
  local ctx = draw_target()
  set_color(ctx, c)
  cairo.cairo_rectangle(ctx, x1, y1, x2 - x1, y2 - y1)
  cairo.cairo_fill(ctx)
end
local function line(ctx, x1, y1, x2, y2, c)
  set_color(ctx, c)
  cairo.cairo_set_line_width(ctx, 1)
  cairo.cairo_move_to(ctx, x1 + 0.5, y1 + 0.5)
  cairo.cairo_line_to(ctx, x2 + 0.5, y2 + 0.5)
  cairo.cairo_stroke(ctx)
end
function Graphics.fillEmptyRect(x1, x2, y1, y2, c)
  ensure_blend("drawEmptyRect")
  local ctx = draw_target()
  line(ctx, x1, y1, x2, y1, c); line(ctx, x1, y2, x2, y2, c)
  line(ctx, x1, y1, x1, y2, c); line(ctx, x2, y1, x2, y2, c)
end
function Graphics.drawLine(x1, x2, y1, y2, c)
  ensure_blend("drawLine")
  line(draw_target(), x1, y1, x2, y2, c)
end
function Graphics.fillCircle(x, y, r, c)
  ensure_blend("drawCircle")
  local ctx = draw_target()
  set_color(ctx, c)
  cairo.cairo_new_path(ctx)
  cairo.cairo_arc(ctx, x, y, r, 0, 2 * math.pi)
  cairo.cairo_fill(ctx)
end
function Graphics.drawPixel(x, y, c, img)
  if img then
    local o = get(img, "image", "drawPixel")
    local ctx = cairo.cairo_create(o.s)
    cairo.cairo_set_operator(ctx, OP_SOURCE)
    set_color(ctx, c)
    cairo.cairo_rectangle(ctx, math.floor(x), math.floor(y), 1, 1)
    cairo.cairo_fill(ctx)
    cairo.cairo_destroy(ctx)
    return
  end
  ensure_blend("drawPixel")
  local ctx = draw_target()
  set_color(ctx, c)
  cairo.cairo_rectangle(ctx, x, y, 1, 1)
  cairo.cairo_fill(ctx)
end
function Graphics.loadImage(path, memtype)
  if memtype ~= nil then
    -- real lpp reads luaL_checkinteger(L, 4) here: with 2 args that is "number expected, got no value"
    error("bad argument #4 to 'loadImage' (number expected, got no value)", 2)
  end
  local s, why = surface_from_file(path)
  if not s then
    error(why == "magic" and "Error loading image (invalid magic)." or "Error loading image.", 2)
  end
  return new_image(s)
end
function Graphics.loadImageAsync(path)
  if st.async_n >= 1 then error("cannot start more async tasks.", 2) end
  M.start_async(function()
    local s = surface_from_file(path)
    return s and tostring(new_image(s)) or nil
  end)
end
function Graphics.loadAnimatedImage(path)
  local hp = host_path(path, "loadAnimatedImage")
  local data = readall(hp)
  if not data or data:sub(1, 2) ~= "GI" then error("Error loading image (invalid magic).", 2) end
  local n = tonumber(io.popen("magick identify " .. sh(hp) .. " | wc -l"):read("*a")) or 1
  local frames = {}
  for i = 0, n - 1 do
    local png = M.cfg.sandbox .. ".gif_" .. i .. ".png"
    os.execute("magick " .. sh(hp .. "[" .. i .. "]") .. " -coalesce PNG32:" .. sh(png) .. " 2>/dev/null")
    frames[#frames + 1] = cairo.cairo_image_surface_create_from_png(png)
  end
  return new_image(frames[1], { frames = frames, cur = 0 })
end
function Graphics.getImageFramesNum(img)
  local o = get(img, "image", "getImageFramesNum")
  if not o.frames then error("attempt to access a static image.", 2) end
  return #o.frames
end
function Graphics.setImageFrame(img, idx)
  local o = get(img, "image", "setImageFrame")
  if not o.frames then error("attempt to access a static image.", 2) end
  if idx >= #o.frames then idx = #o.frames - 1 end
  o.s = o.frames[idx + 1]
end
function Graphics.createImage(w, h, c, memtype)
  -- lpp does memset(data, color, ...) : only the low byte (red) is replicated
  local byte = (c or 0xFFFFFFFF) % 256
  local v = byte + byte * 256 + byte * 65536 + byte * 16777216
  return new_image(color_surface(w, h, v), { rendertarget = true })
end
function Graphics.freeImage(img) get(img, "image", "freeImage"); free(img) end
function Graphics.getImageWidth(img) return get(img, "image", "getImageWidth").w end
function Graphics.getImageHeight(img) return get(img, "image", "getImageHeight").h end
function Graphics.setImageFilters(img, minf, magf)
  get(img, "image", "setImageFilters").filter = (magf == 1) and FILTER_BILINEAR or FILTER_NEAREST
end
function Graphics.drawImage(x, y, img, tint)
  ensure_blend("drawImage")
  draw_surface(draw_target(), get(img, "image", "drawImage"), x, y, 1, 1, 0, nil, tint)
end
function Graphics.drawScaleImage(x, y, img, sx, sy, tint)
  ensure_blend("drawScaleImage")
  draw_surface(draw_target(), get(img, "image", "drawScaleImage"), x, y, sx, sy, 0, nil, tint)
end
function Graphics.drawRotateImage(x, y, img, rad, tint)
  ensure_blend("drawRotateImage")
  draw_surface(draw_target(), get(img, "image", "drawRotateImage"), x, y, 1, 1, rad, nil, tint, true)
end
function Graphics.drawPartialImage(x, y, img, px, py, pw, ph, tint)
  ensure_blend("drawPartialImage")
  draw_surface(draw_target(), get(img, "image", "drawPartialImage"), x, y, 1, 1, 0, { px, py, pw, ph }, tint)
end
function Graphics.drawImageExtended(x, y, img, px, py, pw, ph, rad, sx, sy, tint)
  ensure_blend("drawImageExtended")
  draw_surface(draw_target(), get(img, "image", "drawImageExtended"), x, y, sx, sy, rad, { px, py, pw, ph }, tint, true)
end
local function img_pixel_ptr(o, x, y)
  cairo.cairo_surface_flush(o.s)
  local data = cairo.cairo_image_surface_get_data(o.s)
  local stride = cairo.cairo_image_surface_get_stride(o.s)
  return ffi.cast("uint32_t*", data + y * stride) + x
end
function Graphics.getPixel(x, y, img)
  local o = get(img, "image", "getPixel")
  local p = img_pixel_ptr(o, x, y)[0]
  local a, r, g, b = bit.rshift(p, 24), bit.band(bit.rshift(p, 16), 255), bit.band(bit.rshift(p, 8), 255), bit.band(p, 255)
  return Color.new(r, g, b, a)
end
function Graphics.overloadImage(img, offset, size, data)
  local o = get(img, "image", "overloadImage")
  cairo.cairo_surface_flush(o.s)
  local stride = cairo.cairo_image_surface_get_stride(o.s)
  local base = cairo.cairo_image_surface_get_data(o.s)
  -- lpp textures are RGBA bytes with a stride of width*4 (64-aligned); remap into cairo's ARGB
  local row_bytes = o.w * 4
  for i = 0, math.floor(math.min(size, #data) / 4) - 1 do
    local off = offset + i * 4
    local y, x = math.floor(off / row_bytes), (off % row_bytes) / 4
    if y < o.h then
      local r, g, b, a = data:byte(i * 4 + 1, i * 4 + 4)
      ffi.cast("uint32_t*", base + y * stride)[x] = bit.bor(bit.lshift(a, 24), bit.lshift(r, 16), bit.lshift(g, 8), b)
    end
  end
  cairo.cairo_surface_mark_dirty(o.s)
end
function Graphics.saveImage(img, path, fmt)
  local o = get(img, "image", "saveImage")
  local hp = host_path(path, "saveImage")
  mkdir_p(dirname(hp))
  if (fmt or 0) == 1 then
    cairo.cairo_surface_write_to_png(o.s, hp)
  else
    local tmp = hp .. ".tmp.png"
    cairo.cairo_surface_write_to_png(o.s, tmp)
    os.execute("magick " .. sh(tmp) .. " BMP3:" .. sh(hp) .. " && rm -f " .. sh(tmp))
  end
end
function Graphics.initRescaler(x, y, sx, sy)
  if st.rescaler then error("cannot start two different rescalers together", 2) end
  local s = cairo.cairo_image_surface_create(FMT_ARGB32, W, H)
  st.rescaler = { s = s, ctx = cairo.cairo_create(s), x = x, y = y, sx = sx, sy = sy }
end
function Graphics.termRescaler()
  if not st.rescaler then error("no rescaler available", 2) end
  cairo.cairo_destroy(st.rescaler.ctx)
  st.rescaler = nil
end

-- Font ---------------------------------------------------------------------
local Font = mod("Font")
function Font.load(path)
  local hp = host_path(path, "Font.load")
  if not exists(hp) then error("cannot load font file", 2) end
  local name = hp:match("([^/]+)$")
  local family = name:match("Mono") and "Liberation Mono" or (name:match("Serif") and "Liberation Serif" or "Liberation Sans")
  return new_handle("font", { family = family, bold = name:match("Bold") ~= nil, size = 16 })
end
function Font.unload(f) get(f, "font", "Font.unload"); free(f) end
function Font.setPixelSizes(f, size) get(f, "font", "setPixelSizes").size = size end
function Font.getTextWidth(f, text) local o = get(f, "font", "getTextWidth"); return font_width(o, text, o.size) end
function Font.getTextHeight(f, text) return math.floor(get(f, "font", "getTextHeight").size * 1.15 + 0.5) end
function Font.print(f, x, y, text, c)
  ensure_blend("print")
  local o = get(f, "font", "Font.print")
  font_draw(draw_target(), o, x, y, text, c, o.size)
end

-- Controls -----------------------------------------------------------------
local Controls = mod("Controls")
function Controls.read(port)
  if port and port > 5 then error("wrong port number.", 2) end
  local b = M.input.buttons
  if M.cfg.safe then  -- VOL/POWER only visible in unsafe mode
    b = bit.band(b, bit.bnot(bit.bor(SCE_CTRL_VOLUP_V, SCE_CTRL_VOLDOWN_V, SCE_CTRL_POWER_V)))
  end
  return b
end
function Controls.readLeftAnalog(port) if port and port > 5 then error("wrong port number.", 2) end return M.input.lx, M.input.ly end
function Controls.readRightAnalog(port) if port and port > 5 then error("wrong port number.", 2) end return M.input.rx, M.input.ry end
function Controls.check(pad, b) return bit.band(pad, b) ~= 0 end
local function touch_ret(list, max)
  local out = {}
  for i = 1, math.min(#list, max) do out[#out + 1] = list[i].x; out[#out + 1] = list[i].y end
  return unpack(out)
end
function Controls.readTouch() return touch_ret(M.input.touch, 6) end
function Controls.readRetroTouch() return touch_ret(M.input.rear, 4) end
function Controls.rumble(port, s, l) if port > 5 then error("wrong port number.", 2) end end
function Controls.setLightbar(port, c) if port > 5 then error("wrong port number.", 2) end end
function Controls.lockHomeButton() st.home_locked = true end
function Controls.unlockHomeButton() st.home_locked = false end
function Controls.getDeviceInfo()
  local t = {}
  for i = 1, 5 do t[i] = { type = (i == 1) and 1 or 0 } end
  return t
end
function Controls.headsetStatus() return false end
function Controls.enableGyro() st.sensors = true end
function Controls.enableAccel() st.sensors = true end
function Controls.disableGyro() st.sensors = false end
function Controls.disableAccel() st.sensors = false end
local function need_sensors() if not st.sensors then error("you must enable sensors reading to use this function.", 3) end end
function Controls.readGyro() need_sensors(); local t = M.frame / 30; return 0.1 * math.sin(t), 0.05 * math.cos(t), 0.02 end
function Controls.readAccel() need_sensors(); local t = M.frame / 50; return 0.3 * math.sin(t), 0.2 * math.cos(t), -0.95 end
function Controls.getEnterButton() return SCE_CTRL_CROSS_V end

-- Timer --------------------------------------------------------------------
-- Mirrors luaTimer.cpp exactly, including the setTime-while-running quirk.
local Timer = mod("Timer")
local function T(h, fname) return get(h, "timer", fname) end
function Timer.new() return new_handle("timer", { playing = true, tick = now_ms }) end
function Timer.getTime(h) local t = T(h, "Timer.getTime"); return math.floor(t.playing and (now_ms - t.tick) or t.tick) end
function Timer.setTime(h, v)
  local t = T(h, "Timer.setTime")
  v = v % 4294967296 -- (uint32_t) cast in C
  if v >= 2147483648 then v = v - 4294967296 end
  if t.playing then t.tick = now_ms + v else t.tick = v end
end
function Timer.pause(h) local t = T(h, "Timer.pause"); if t.playing then t.playing = false; t.tick = now_ms - t.tick end end
function Timer.resume(h) local t = T(h, "Timer.resume"); if not t.playing then t.playing = true; t.tick = now_ms - t.tick end end
function Timer.reset(h) local t = T(h, "Timer.reset"); t.tick = t.playing and now_ms or 0 end
function Timer.isPlaying(h) return T(h, "Timer.isPlaying").playing end
function Timer.destroy(h) T(h, "Timer.destroy"); free(h) end

-- System -------------------------------------------------------------------
local System = mod("System")
local function fs_check(p, fname)
  if not io_allowed(p) then error(fname .. ": safe eboot cannot access " .. p, 3) end
  return host_path(p, fname)
end
function System.openFile(p, flags)
  local hp = host_path(p)
  if not io_allowed(p) then error("cannot open requested file.", 2) end
  local mode
  if flags == FREAD_V then mode = "rb"
  elseif flags == FRDWR_V then mode = "r+b"
  else mode = exists(hp) and "r+b" or "w+b" end  -- FCREATE/FWRITE: O_CREAT, no O_TRUNC
  if flags == FWRITE_V and not exists(hp) then error("cannot open requested file.", 2) end
  local f = io.open(hp, mode)
  if not f then error("cannot open requested file.", 2) end
  st.fd_next = st.fd_next + 1
  st.files[st.fd_next] = { f = f, path = p, hp = hp }
  return st.fd_next
end
local function FH(h) local o = st.files[h]; if not o then error("bad file handle " .. tostring(h), 3) end return o end
function System.readFile(h, n) return FH(h).f:read(n) or "" end
function System.writeFile(h, s, n) FH(h).f:write(s:sub(1, n)) end
function System.seekFile(h, pos, whence)
  local w = ({ [0] = "set", [1] = "cur", [2] = "end" })[whence] or "set"
  FH(h).f:seek(w, pos)
end
function System.sizeFile(h) local f = FH(h).f; local cur = f:seek(); local n = f:seek("end"); f:seek("set", cur); return n end
function System.closeFile(h) FH(h).f:close(); st.files[h] = nil end
local function stat_table(hp)
  local out = io.popen("stat -c '%s %F %Y' " .. sh(hp) .. " 2>/dev/null"):read("*l")
  if not out then return nil end
  local size, kind, mtime = out:match("^(%d+) (.-) (%d+)$")
  local d = os.date("*t", tonumber(mtime))
  local dt = { year = d.year, month = d.month, day = d.day, hour = d.hour, minute = d.min, second = d.sec }
  return { size = tonumber(size), directory = kind == "directory", mod_time = dt, access_time = dt, creation_time = dt }
end
function System.statFile(p) return stat_table(fs_check(p, "statFile")) end
function System.statOpenedFile(h) local o = FH(h); o.f:flush(); return stat_table(o.hp) end
function System.doesFileExist(p) return io_allowed(p) and exists(host_path(p)) and not isdir(host_path(p)) or false end
function System.doesDirExist(p) local hp = host_path(p); return (not M.cfg.safe or io_allowed(p) or p:match("^%w+:/?$") ~= nil) and isdir(hp) end
function System.listDirectory(p)
  local hp = host_path(p)
  if (M.cfg.safe and not io_allowed(p)) or not isdir(hp) then return nil end
  local t = {}
  for name in io.popen("ls -A " .. sh(hp)):lines() do
    local full = hp:gsub("/?$", "/") .. name
    local s = stat_table(full) or { size = 0 }
    t[#t + 1] = { name = name, size = s.size, directory = isdir(full) }
  end
  return t
end
function System.createDirectory(p) mkdir_p(fs_check(p, "createDirectory")) end
function System.deleteDirectory(p) os.execute("rmdir " .. sh(fs_check(p, "deleteDirectory")) .. " 2>/dev/null") end
function System.deleteFile(p) os.remove(fs_check(p, "deleteFile")) end
function System.rename(a, b) os.rename(fs_check(a, "rename"), fs_check(b, "rename")) end
function System.copyFile(a, b)
  local ha, hb = host_path(a), fs_check(b, "copyFile")
  if not exists(ha) then error("the file doesn't exist", 2) end
  os.execute("cp " .. sh(ha) .. " " .. sh(hb))
end
function System.exit() error({ mock_exit = true }, 0) end
function System.wait(us) now_ms = now_ms + us / 1000 end
local battery = { pct = 87, charging = false }
function System.isBatteryCharging() return battery.charging end
function System.getBatteryPercentage() return battery.pct end
function System.getBatteryLife() return 214 end
function System.getBatteryCapacity() return 1870 end
function System.getBatteryFullCapacity() return 2150 end
function System.getBatteryTemp() return 31 end
function System.getBatteryVolt() return 4012 end
function System.getBatteryHealth() return 94 end
function System.getBatteryCycles() return 132 end
local timers_disabled = {}
function System.disableTimer(t) timers_disabled[t] = true end
function System.enableTimer(t) timers_disabled[t] = nil end
function System.resetTimer(t) end
local clocks = { cpu = 333, bus = 111, gpu = 111, xbar = 111 }
function System.setCpuSpeed(v) clocks.cpu = v end
function System.getCpuSpeed() return clocks.cpu end
function System.setBusSpeed(v) clocks.bus = v end
function System.getBusSpeed() return clocks.bus end
function System.setGpuSpeed(v) clocks.gpu = v end
function System.getGpuSpeed() return clocks.gpu end
function System.setGpuXbarSpeed(v) clocks.xbar = v end
function System.getGpuXbarSpeed() return clocks.xbar end
function System.launchEboot(p) if not exists(host_path(p)) then error("error opening file.", 2) end M.event("launchEboot " .. p) end
function System.launchApp(tid) M.event("launchApp " .. tid) end
function System.getTime() local d = os.date("*t"); return d.hour, d.min, d.sec end
function System.getDate() local d = os.date("*t"); return d.wday - 1, d.day, d.month, d.year end
function System.getUsername() return "VitaUser" end
function System.getLanguage() return 1 end
function System.getModel() return 0x10000 end
function System.getTitle() return "Hello Vita (lpp showcase)" end
function System.getTitleID() return "LPPS00001" end
function System.getPsId() return "00:00:00:01:01:03:00:10:0C:00:A1:B2:C3:D4:E5:F6" end
function System.getFirmware() return "3.60" end
function System.getSpoofedFirmware() return "3.73" end
function System.getFactoryFirmware() return "3.01" end
function System.isSafeMode() return M.cfg.safe end
function System.getFreeSpace(dev) return 12.4 * 2 ^ 30 end
function System.getTotalSpace(dev) return 29.7 * 2 ^ 30 end
function System.getBootParams() return "" end
function System.consolePrint(s) M.log[#M.log + 1] = s; if M.cfg.log_console and s:find("^AUTOTEST") then print(s) end end
function System.takeScreenshot(p, fmt, ratio)
  local hp = host_path(p)
  mkdir_p(dirname(hp))
  local tmp = hp .. ".tmp.png"
  cairo.cairo_surface_write_to_png(front, tmp)
  local fmtname = ({ [0] = "BMP3:", [1] = "PNG:", [2] = "JPG:" })[fmt or 0]
  os.execute("magick " .. sh(tmp) .. " " .. fmtname .. sh(hp) .. " && rm -f " .. sh(tmp))
end
function System.executeUri(uri) M.event("executeUri " .. uri) end
function System.reboot() M.event("reboot") return 0 end
function System.shutdown() M.event("shutdown") return 0 end
function System.standby() M.event("standby") return 0 end
function System.setMessage(text, progress, buttons)
  if st.msg then error("cannot start multiple message instances.", 2) end
  if buttons and (buttons > 4 or buttons < 0) then error("invalid buttons type argument.", 2) end
  st.msg = { text = text, progress = progress and 0 or nil, buttons = buttons or 0, opened = M.frame, prog_msg = "" }
end
function System.getMessageState()
  if not st.msg then return 1 end           -- FINISHED
  if st.msg.result then
    local r = st.msg.result
    st.msg = nil
    return r
  end
  return 2                                  -- RUNNING
end
function System.setMessageProgress(p) if not st.msg then error("no message instances available.", 2) end st.msg.progress = p end
function System.setMessageProgMsg(s) if not st.msg then error("no message instances available.", 2) end st.msg.prog_msg = s end
function System.closeMessage() if not st.msg then error("no message instances available.", 2) end st.msg.result = 1 end
function System.extractSfo(p)
  local hp = host_path(p)
  local data = readall(hp)
  if not data then error("error opening SFO file.", 2) end
  local off = 0
  local u32 = function(o) local a, b, c, d = data:byte(o + 1, o + 4); return a + b * 256 + c * 65536 + d * 16777216 end
  if u32(0) ~= 0x46535000 then
    if u32(0) ~= 0x50425000 then error("SFO file is corrupted.", 2) end
    off = 0x28
  end
  local key_ofs, val_ofs, count = u32(off + 8), u32(off + 12), u32(off + 16)
  local map = { APP_VER = "version", TITLE = "title", STITLE = "short_title", CATEGORY = "category", TITLE_ID = "titleid" }
  local t, n = {}, 0
  for i = 0, count - 1 do
    local e = off + 20 + i * 16
    local nofs = data:byte(e + 1) + data:byte(e + 2) * 256
    local len, dofs = u32(e + 4), u32(e + 12)
    local name = data:match("^[^%z]*", off + key_ofs + nofs + 1)
    if map[name] then
      t[map[name]] = data:sub(off + val_ofs + dofs + 1, off + val_ofs + dofs + len):gsub("%z.*", "")
      n = n + 1
    end
  end
  if n == 0 then error("SFO file is corrupted.", 2) end
  return t
end
function System.extractPbp(p, dir)
  local data = readall(host_path(p))
  if not data then error("error opening PBP file.", 2) end
  if data:sub(1, 4) ~= "\0PBP" then error("PBP file is corrupted.", 2) end
  local names = { "PARAM.SFO", "ICON0.PNG", "ICON1.PMF", "PIC0.PNG", "PIC1.PNG", "SND0.AT3", "DATA.PSP", "DATA.PSAR" }
  local u32 = function(o) local a, b, c, d = data:byte(o + 1, o + 4); return a + b * 256 + c * 65536 + d * 16777216 end
  local hd = fs_check(dir, "extractPbp")
  mkdir_p(hd)
  for i = 1, 8 do
    local s = u32(8 + 4 * (i - 1))
    local e = (i < 8) and u32(8 + 4 * i) or #data
    if e > s then
      local f = io.open(hd .. "/" .. names[i], "wb"); f:write(data:sub(s + 1, e)); f:close()
    end
  end
end
local function unzip(zip, args, dest)
  os.execute("unzip -o -q " .. sh(host_path(zip)) .. " " .. args .. " -d " .. sh(dest) .. " 2>/dev/null")
end
function System.extractZip(z, dir) local hd = fs_check(dir, "extractZip"); mkdir_p(hd); unzip(z, "", hd) end
function System.extractFromZip(z, name, dst)
  local hd = fs_check(dst, "extractFromZip")
  mkdir_p(dirname(hd))
  os.execute("unzip -p " .. sh(host_path(z)) .. " " .. sh(name) .. " > " .. sh(hd) .. " 2>/dev/null")
end
function System.extractZipAsync(z, dir)
  if st.async_n >= 1 then error("cannot start more async tasks.", 2) end
  M.start_async(function() System.extractZip(z, dir) end)
end
function System.extractFromZipAsync(z, name, dst)
  if st.async_n >= 1 then error("cannot start more async tasks.", 2) end
  M.start_async(function() System.extractFromZip(z, name, dst) end)
end
local function zip_add(path, zipfile, parent, level, create)
  local hp, hz = host_path(path), fs_check(zipfile, "zip")
  mkdir_p(dirname(hz))
  local abs_zip = io.popen("realpath -m " .. sh(hz)):read("*l")
  local stage = M.cfg.sandbox .. ".zipstage"
  os.execute("rm -rf " .. sh(stage) .. " && mkdir -p " .. sh(stage .. "/" .. (parent or "")))
  os.execute("cp -r " .. sh(hp) .. " " .. sh(stage .. "/" .. (parent or "") .. "/"))
  if create then os.remove(hz) end
  os.execute("cd " .. sh(stage) .. " && zip -q -r -" .. math.max(0, math.min(9, level or 6)) .. " " .. sh(abs_zip) .. " .")
end
function System.compressZip(path, zipfile, level) zip_add(path, zipfile, nil, level, true) end
function System.addToZip(path, zipfile, parent, level) zip_add(path, zipfile, parent, level, false) end
function System.getAsyncState() return st.async_state end
function System.getAsyncResult()
  local r = st.async_res
  st.async_res = nil
  return r
end
function System.unmountPartition(i) M.event(string.format("unmountPartition 0x%X", i)) end
function System.mountPartition(i, perm) M.event(string.format("mountPartition 0x%X %d", i, perm)) end
function System.installApp(d) M.event("installApp " .. d) end
function System.uninstallApp(t) M.event("uninstallApp " .. t) end
function System.doesAppExist(t) return t == "LPPS00001" or t:match("^NPXS") ~= nil end
function System.loadUserPlugin(p) return exists(host_path(p)) and 0x40010003 or -2147418110 end
function System.loadKernelPlugin(p) return exists(host_path(p)) and 0x00410005 or -2147418110 end
function System.unloadUserPlugin(id) end
function System.unloadKernelPlugin(id) end
function System.unmountMountpoint(m) M.event("unmountMountpoint " .. m) end

-- async engine: one task, finishes after a few frames ------------------------
function M.start_async(fn)
  st.async_n = 1
  st.async_state = 0
  st.async_until = M.frame + 20
  st.async_fn = fn
end
function M.tick_async()
  if st.async_n == 1 and M.frame >= st.async_until then
    local ok, r = pcall(st.async_fn)
    st.async_res = ok and r or nil
    st.async_state = 1
    st.async_n = 0
  end
end

-- Sound ---------------------------------------------------------------------
local Sound = mod("Sound")
local MAGIC_OK = { [0x03334449] = "mp3", [0x6468544D] = "midi", [0x5367674F] = "ogg", [0x46464952] = "wav",
                   [0x4D524F46] = "aif", [0x56485350] = "pshv" }
function Sound.init() st.sound_init = true end
function Sound.term() st.sound_init = false end
function Sound.open(p)
  local data = readall(host_path(p))
  if not data then error("file doesn't exist.", 2) end
  local a, b, c, d = data:byte(1, 4)
  local magic = a + b * 256 + c * 65536 + d * 16777216
  if not MAGIC_OK[magic] then error("unknown audio file format.", 2) end
  local title, author = "", ""
  if MAGIC_OK[magic] ~= "midi" and MAGIC_OK[magic] ~= "aif" then
    local meta = io.popen("ffprobe -v error -show_entries format_tags=title,artist -of default=nw=1 " .. sh(host_path(p))):read("*a")
    title = meta:match("TAG:title=([^\n]*)") or ""
    author = meta:match("TAG:artist=([^\n]*)") or ""
  end
  return new_handle("music", { playing = false, volume = 32767, title = title, author = author, fmt = MAGIC_OK[magic] })
end
function Sound.play(h, loop) local o = get(h, "music", "Sound.play"); o.playing, o.loop = true, loop end
function Sound.pause(h) get(h, "music", "Sound.pause").playing = false end
function Sound.resume(h) get(h, "music", "Sound.resume").playing = true end
function Sound.isPlaying(h) return get(h, "music", "Sound.isPlaying").playing end
function Sound.close(h) get(h, "music", "Sound.close"); free(h) end
function Sound.setVolume(h, v) get(h, "music", "Sound.setVolume").volume = math.max(0, math.min(32767, v)) end
function Sound.getVolume(h) return get(h, "music", "Sound.getVolume").volume end
function Sound.getTitle(h) return get(h, "music", "Sound.getTitle").title end
function Sound.getAuthor(h) return get(h, "music", "Sound.getAuthor").author end
function Sound.playShutter(id) if id > 2 or id < 0 then error("invalid shutter sound id.", 2) end end

-- Mic -----------------------------------------------------------------------
local Mic = mod("Mic")
function Mic.start(secs, rate)
  if rate % 16000 ~= 0 then error("samplerate must be a multiple of 16000", 2) end
  if rate > 48000 then error("too high samplerate", 2) end
  st.mic = { secs = secs, rate = rate, rec = true, start = M.frame, frames = 0 }
end
function Mic.isRecording()
  local m = st.mic
  if not m or not m.rec then return false end
  m.frames = m.frames + 1
  if (M.frame - m.start) >= m.secs * 60 then m.rec = false end
  return m.rec
end
function Mic.pause() if st.mic then st.mic.rec = false end end
function Mic.resume() if st.mic then st.mic.rec = true end end
function Mic.stop(p)
  local m = st.mic or { rate = 16000, secs = 1 }
  local hp = host_path(p)
  mkdir_p(dirname(hp))
  os.execute(string.format("ffmpeg -y -loglevel error -f lavfi -i sine=frequency=440:duration=%d -ar %d -ac 1 -c:a pcm_s16le %s",
    m.secs, m.rate, sh(hp)))
  st.mic = nil
end

-- Video ---------------------------------------------------------------------
local Video = mod("Video")
local function vready(fname) if not st.video.ready then error("you must init the player first.", 3) end end
function Video.init() if st.video.ready then return end st.video = { ready = true, vol = 32767, mode = 100, t = 0 } end
function Video.term() vready(); st.video = { ready = false } end
function Video.open(p, loop)
  vready()
  local hp = host_path(p)
  if not exists(hp) then error("file doesn't exist.", 2) end
  local v = st.video
  v.file, v.loop, v.playing, v.t, v.frames = hp, loop, true, 0, {}
  v.dur = tonumber(io.popen("ffprobe -v error -show_entries format=duration -of csv=p=0 " .. sh(hp)):read("*l")) or 10
end
function Video.close() vready(); st.video.file = nil; st.video.playing = false end
function Video.getOutput()
  vready()
  local v = st.video
  if not v.file then return 0 end
  -- one frame per simulated second, extracted lazily with ffmpeg
  local sec = math.floor(v.t / 1000) % math.max(1, math.floor(v.dur))
  if not v.frames[sec] then
    local png = M.cfg.sandbox .. string.format(".vid_%d.png", sec)
    os.execute(string.format("ffmpeg -y -loglevel error -ss %d -i %s -frames:v 1 %s", sec, sh(v.file), sh(png)))
    v.frames[sec] = new_image(cairo.cairo_image_surface_create_from_png(png))
  end
  return v.frames[sec]
end
function Video.pause() vready(); st.video.playing = false end
function Video.resume() vready(); st.video.playing = true end
function Video.isPlaying() vready(); return st.video.playing and st.video.file ~= nil end
function Video.getTime() vready(); return st.video.t end
function Video.jumpToTime(ms) st.video.t = math.max(0, ms) end
function Video.setPlayMode(m) st.video.mode = m end
function Video.setVolume(v) st.video.vol = math.max(0, math.min(32767, v)) end
function Video.getVolume() return st.video.vol or 32767 end
function Video.openSubs(p)
  local data = readall(host_path(p))
  if not data then error("file doesn't exist.", 2) end
  local cues = {}
  for a1, a2, a3, b1, b2, b3, text in data:gmatch("(%d+):(%d+):(%d+)[.,]%d+ %-%-> (%d+):(%d+):(%d+)[.,]%d+\r?\n([^\r\n]+)") do
    cues[#cues + 1] = { s = (a1 * 3600 + a2 * 60 + a3) * 1000, e = (b1 * 3600 + b2 * 60 + b3) * 1000, text = text }
  end
  st.video.subs = cues
end
function Video.closeSubs() st.video.subs = nil end
function Video.getSubs()
  local v = st.video
  for _, c in ipairs(v.subs or {}) do if v.t >= c.s and v.t < c.e then return c.text end end
  return ""
end
function M.tick_video()
  local v = st.video
  if v.ready and v.file and v.playing then
    v.t = v.t + (1000 / 60) * (v.mode or 100) / 100
    if v.loop and v.t > v.dur * 1000 then v.t = 0 end
  end
end

-- Camera --------------------------------------------------------------------
local Camera = mod("Camera")
local function cam_on(fname) if not st.cam then error("camera has not been initialized.", 3) end return st.cam end
function Camera.init(dev, res, fps)
  if st.cam then error("cannot start two camera instances together", 2) end
  st.cam = { dev = dev, vals = {} }
  st.cam.img = new_image(color_surface(640, 480, Color.new(40, 60, 90)))
end
function Camera.term() cam_on(); free(st.cam.img); st.cam = nil end
function Camera.getOutput()
  local c = cam_on()
  -- synthetic "viewfinder": moving gradient bars + crosshair
  local o = get(c.img, "image")
  local ctx = cairo.cairo_create(o.s)
  for i = 0, 15 do
    local k = (i * 40 + M.frame * 3) % 640
    cairo.cairo_set_source_rgba(ctx, 0.2 + i / 30, 0.3, 0.6 - i / 40, 1)
    cairo.cairo_rectangle(ctx, k, 0, 40, 480)
    cairo.cairo_fill(ctx)
  end
  cairo.cairo_set_source_rgba(ctx, 1, 1, 1, 0.9)
  cairo.cairo_set_line_width(ctx, 3)
  cairo.cairo_arc(ctx, 320, 240, 60, 0, 2 * math.pi)
  cairo.cairo_stroke(ctx)
  cairo.cairo_select_font_face(ctx, "Liberation Sans", 0, 1)
  cairo.cairo_set_font_size(ctx, 28)
  cairo.cairo_move_to(ctx, 20, 460)
  cairo.cairo_show_text(ctx, (c.dev == 0 and "FRONT" or "REAR") .. " CAMERA (mock)")
  cairo.cairo_destroy(ctx)
  return c.img
end
for _, name in ipairs({ "Brightness", "Saturation", "Sharpness", "Contrast", "Reverse", "Effect", "Exposure",
                         "Zoom", "AntiFlicker", "ISO", "Gain", "WhiteBalance", "Backlight", "Nightmode" }) do
  Camera["set" .. name] = function(v) cam_on().vals[name] = v end
  Camera["get" .. name] = function()
    local v = cam_on().vals[name] or 0
    if name == "Saturation" or name == "Exposure" then v = math.floor(v * 10) end -- C stores *10
    if name == "Sharpness" then v = math.floor(v / 100) end
    return v
  end
end

-- Render --------------------------------------------------------------------
-- Software rasteriser: projects triangles (perspective 45deg like lpp) and fills
-- them flat-shaded with the texture's average colour. Good enough for screenshots.
local Render = mod("Render")
local cam3 = { x = 0, y = 0, z = 0, rx = 0, ry = 0, rz = 0 }
function Render.createVertex(x, y, z, u, v, n1, n2, n3)
  return new_handle("vertex", { x = x, y = y, z = z, u = u, v = v, n = { n1, n2, n3 } })
end
function Render.destroyVertex(h) get(h, "vertex", "destroyVertex"); free(h) end
local function avg_color(img)
  local o = get(img, "image")
  local sum = { 0, 0, 0 }
  local n = 0
  for y = 0, o.h - 1, math.max(1, math.floor(o.h / 8)) do
    for x = 0, o.w - 1, math.max(1, math.floor(o.w / 8)) do
      local p = img_pixel_ptr(o, x, y)[0]
      sum[1] = sum[1] + bit.band(bit.rshift(p, 16), 255)
      sum[2] = sum[2] + bit.band(bit.rshift(p, 8), 255)
      sum[3] = sum[3] + bit.band(p, 255)
      n = n + 1
    end
  end
  return { sum[1] / n / 255, sum[2] / n / 255, sum[3] / n / 255 }
end
function Render.loadModel(list, tex)
  if type(list) ~= "table" or #list % 3 ~= 0 or #list == 0 then error("invalid vertex list.", 2) end
  local tris = {}
  for i = 1, #list, 3 do
    local a, b, c = get(list[i], "vertex"), get(list[i + 1], "vertex"), get(list[i + 2], "vertex")
    tris[#tris + 1] = { { a.x, a.y, a.z }, { b.x, b.y, b.z }, { c.x, c.y, c.z }, n = a.n }
  end
  return new_handle("model", { tris = tris, tex = tex, col = avg_color(tex) })
end
function Render.loadObject(path, tex)
  local data = readall(host_path(path))
  if not data then error("invalid model file.", 2) end
  local v, vn, tris = {}, {}, {}
  for x, y, z in data:gmatch("\nv ([%-%d%.e]+) ([%-%d%.e]+) ([%-%d%.e]+)") do v[#v + 1] = { tonumber(x), tonumber(y), tonumber(z) } end
  local first = data:match("^v ([%-%d%.e]+ [%-%d%.e]+ [%-%d%.e]+)")
  if first then local x, y, z = first:match("(%S+) (%S+) (%S+)"); table.insert(v, 1, { tonumber(x), tonumber(y), tonumber(z) }) end
  for x, y, z in data:gmatch("\nvn ([%-%d%.e]+) ([%-%d%.e]+) ([%-%d%.e]+)") do vn[#vn + 1] = { tonumber(x), tonumber(y), tonumber(z) } end
  for a, an, b, c in data:gmatch("\nf (%d+)/%d*/(%d+) (%d+)/%d*/%d+ (%d+)/%d*/%d+") do
    tris[#tris + 1] = { v[tonumber(a)], v[tonumber(b)], v[tonumber(c)], n = vn[tonumber(an)] }
  end
  if #tris == 0 then error("invalid model file.", 2) end
  return new_handle("model", { tris = tris, tex = tex, col = avg_color(tex) })
end
function Render.unloadModel(h) get(h, "model", "unloadModel"); free(h) end
function Render.useTexture(h, tex) local m = get(h, "model", "useTexture"); m.tex = tex; m.col = avg_color(tex) end
function Render.setCamera(x, y, z, rx, ry, rz) cam3 = { x = x, y = y, z = z, rx = rx, ry = ry, rz = rz } end
local function rot(p, ax, ay, az)
  local x, y, z = p[1], p[2], p[3]
  local c, s = math.cos(ax), math.sin(ax); y, z = y * c - z * s, y * s + z * c
  c, s = math.cos(ay), math.sin(ay); x, z = x * c + z * s, -x * s + z * c
  c, s = math.cos(az), math.sin(az); x, y = x * c - y * s, x * s + y * c
  return { x, y, z }
end
function Render.drawModel(h, x, y, z, ax, ay, az, no_cam)
  local m = get(h, "model", "drawModel")
  local ctx = draw_target()
  local f = (H / 2) / math.tan(math.rad(22.5))
  local out = {}
  for _, t in ipairs(m.tris) do
    local pts = {}
    for k = 1, 3 do
      local p = rot(t[k], math.rad(ax), math.rad(ay), math.rad(az))
      p = { p[1] + x, p[2] + y, p[3] + z }
      if not no_cam then
        p = { p[1] - cam3.x, p[2] - cam3.y, p[3] - cam3.z }
        p = rot(p, -cam3.rx, -cam3.ry, -cam3.rz)
      end
      pts[k] = p
    end
    local nz = (pts[2][1] - pts[1][1]) * (pts[3][2] - pts[1][2]) - (pts[2][2] - pts[1][2]) * (pts[3][1] - pts[1][1])
    local depth = (pts[1][3] + pts[2][3] + pts[3][3]) / 3
    if depth < -0.1 then
      local n = t.n and rot(t.n, math.rad(ax), math.rad(ay), math.rad(az)) or { 0, 0, 1 }
      local light = math.max(0.25, (n[1] * 0.4 + n[2] * 0.6 + n[3] * 0.7) / 1.0)
      out[#out + 1] = { pts = pts, depth = depth, light = math.min(1, light) }
    end
  end
  table.sort(out, function(a, b) return a.depth < b.depth end)
  for _, t in ipairs(out) do
    cairo.cairo_new_path(ctx)
    for k = 1, 3 do
      local p = t.pts[k]
      local sx, sy = W / 2 + f * p[1] / -p[3], H / 2 - f * p[2] / -p[3]
      if k == 1 then cairo.cairo_move_to(ctx, sx, sy) else cairo.cairo_line_to(ctx, sx, sy) end
    end
    cairo.cairo_set_source_rgba(ctx, m.col[1] * t.light, m.col[2] * t.light, m.col[3] * t.light, 1)
    cairo.cairo_fill(ctx)
  end
end

-- Keyboard ------------------------------------------------------------------
local Keyboard = mod("Keyboard")
function Keyboard.start(title, text, length, ktype, kmode, opt)
  if ktype and ktype > 3 then error("invalid keyboard type", 2) end
  if kmode and kmode > 1 then error("invalid keyboard mode", 2) end
  if #title > 64 then error("title is too long", 2) end
  st.kb = { title = title, text = text, state = 2, opened = M.frame }
end
function Keyboard.getState()
  if not st.kb then return 0 end
  return st.kb.state
end
function Keyboard.getInput() return st.kb and st.kb.result or "" end
function Keyboard.clear() st.kb = nil end

-- Network / Socket ----------------------------------------------------------
local Network = mod("Network")
local function net(fname) if not st.net then error("Network is not inited", 3) end end
function Network.init() if st.net then error("Network is already inited", 2) end st.net = true end
function Network.term() net(); st.net = false end
function Network.initFTP()
  net()
  if not M.cfg.wifi then error("cannot start FTP server (WiFi off?)", 2) end
  st.ftp = true
  return "192.168.1.42", 1337
end
function Network.termFTP() net(); st.ftp = false end
function Network.getIPAddress() net(); return "192.168.1.42" end
function Network.getMacAddress() net(); return "00:1F:A7:12:34:56" end
function Network.isWifiEnabled() net(); return M.cfg.wifi end
function Network.getWifiLevel() net(); return 78 end
local FAKE_BODIES = {
  ["httpbin.org/get"] = '{"args":{"from":"vita"},"headers":{"User-Agent":"lpp-vita-showcase/1.0"},"origin":"203.0.113.7"}',
  ["httpbin.org/post"] = '{"data":"{\\"console\\":\\"PS Vita\\",\\"api\\":\\"lpp\\"}","json":{"api":"lpp"}}',
  ["worldtimeapi.org"] = '{"datetime":"2026-10-04T23:59:00.000000+00:00","timezone":"Etc/UTC"}',
}
local function fake_body(url, method)
  if method == 2 then return "" end -- HEAD
  for k, v in pairs(FAKE_BODIES) do if url:find(k, 1, true) then return v end end
  return "<html><head><title>Example Domain</title></head><body>mock</body></html>"
end
M.fake_body = fake_body
function Network.requestString(url, ua, method, post)
  net()
  if st.async_n > 0 then error("cannot download file when async download is active", 2) end
  return fake_body(url, method)
end
function Network.downloadFile(url, path, ua, method, post)
  net()
  if st.async_n > 0 then error("cannot download file when async download is active", 2) end
  local hp = host_path(path)
  mkdir_p(dirname(hp))
  if url:match("%.png$") then
    os.execute("cp " .. sh(M.cfg.app_dir .. "assets/img/hello.png") .. " " .. sh(hp))
  else
    local f = io.open(hp, "wb"); f:write("# Lua Player Plus Vita (mock download)\n" .. url .. "\n"); f:close()
  end
end
function Network.requestStringAsync(url, ua, method, post)
  net()
  if st.async_n >= 1 then error("cannot start more async tasks.", 2) end
  M.start_async(function() return fake_body(url, method) end)
end
function Network.downloadFileAsync(url, path, ua, method, post)
  net()
  if st.async_n >= 1 then error("cannot start more async tasks.", 2) end
  M.start_async(function() st.async_n = 0; Network.downloadFile(url, path) end)
end

local Socket = mod("Socket")
function Socket.createServerSocket(port, proto)
  net()
  return new_handle("socket", { server = true, port = port, pending = {} })
end
function Socket.connect(host, port, proto)
  net()
  if host == "127.0.0.1" and port == 9 then error("Failed connecting to the server.", 2) end
  local s = { server = false, inbox = {} }
  if port == 80 then
    s.inbox = { "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n\r\n", "<html><head><title>Example Domain</title></head></html>" }
  end
  return new_handle("socket", s)
end
function Socket.send(h, data)
  net()
  local s = get(h, "socket", "Socket.send")
  if s.server then error("send not allowed for server sockets.", 2) end
  if s.peer then s.peer.sent = (s.peer.sent or "") .. data end
  return #data
end
function Socket.receive(h, size)
  net()
  local s = get(h, "socket", "Socket.receive")
  if s.server then error("recv not allowed for server sockets.", 2) end
  return table.remove(s.inbox, 1) or ""
end
function Socket.accept(h)
  net()
  local s = get(h, "socket", "Socket.accept")
  if not s.server then error("accept allowed for server sockets only.", 2) end
  local c = table.remove(s.pending, 1)
  if not c then return nil end
  return new_handle("socket", { server = false, inbox = { c.msg }, peer = c })
end
function Socket.close(h) net(); get(h, "socket", "Socket.close"); free(h) end
function M.socket_client(msg)
  for _, o in pairs(objects) do
    if o.kind == "socket" and o.server then
      local c = { msg = msg }
      table.insert(o.pending, c)
      return c
    end
  end
end

-- Database (real SQLite through the sqlite3 CLI) -------------------------------
local Database = mod("Database")
function Database.open(path)
  local hp = host_path(path)
  if path:match("^ur0:") then
    -- emulate the system app database
    mkdir_p(dirname(hp))
    os.execute("sqlite3 " .. sh(hp) .. " \"CREATE TABLE IF NOT EXISTS tbl_appinfo_icon(titleId TEXT);" ..
      " INSERT INTO tbl_appinfo_icon SELECT 'NPXS1000' || value FROM json_each('[1,2,3,4,5,6,7,8,9]')" ..
      " WHERE (SELECT COUNT(*) FROM tbl_appinfo_icon) = 0;\" 2>/dev/null")
  end
  mkdir_p(dirname(hp))
  return new_handle("db", { hp = hp })
end
function Database.close(h) get(h, "db", "Database.close"); free(h) end
function Database.execQuery(h, sql)
  local d = get(h, "db", "Database.execQuery")
  local tmp = M.cfg.sandbox .. ".sql"
  local f = io.open(tmp, "w"); f:write(sql); f:close()
  local p = io.popen("sqlite3 -json " .. sh(d.hp) .. " < " .. sh(tmp) .. " 2>&1; echo \"__RC=$?\"")
  local out = p:read("*a"); p:close()
  local rc = tonumber(out:match("__RC=(%d+)%s*$"))
  out = out:gsub("__RC=%d+%s*$", "")
  if rc ~= 0 then error((out:gsub("^Parse error near line %d+: ", ""):gsub("\n.*", "")), 2) end
  -- tiny JSON array-of-objects reader; values become strings like sqlite3_exec gives
  local rows = {}
  for obj in out:gmatch("%b{}") do
    local row = {}
    for k, v in obj:gmatch('"([^"]+)":(%b"")') do row[k] = v:sub(2, -2):gsub('\\"', '"') end
    for k, v in obj:gmatch('"([^"]+)":([%-%d%.eE]+)') do row[k] = v end
    rows[#rows + 1] = row
  end
  return rows
end

-- Registry ------------------------------------------------------------------
local Registry = mod("Registry")
local reg = { ["/CONFIG/SYSTEM/username"] = "VitaUser", ["/CONFIG/SYSTEM/language"] = 1,
  ["/CONFIG/SYSTEM/button_assign"] = 1, ["/CONFIG/SYSTEM/flight_mode"] = 0, ["/CONFIG/DISPLAY/brightness"] = 65536,
  ["/CONFIG/SOUND/main_volume"] = 22, ["/CONFIG/DATE/time_format"] = 1, ["/CONFIG/NP/account_id"] = string.rep("\171", 8) }
function Registry.getKey(cat, name, t)
  local v = reg[cat .. name]
  if t == 1 then return (v or ""):sub(1, 256) .. string.rep("\0", 256 - #(v or "")) end
  if t == 0 then return tostring(v or "") end
  return tonumber(v) or 0
end
function Registry.setKey(cat, name, t, v, size) reg[cat .. name] = v end
function Registry.getSysKey(id, t) return t == 0 and "" or id * 3 end

-- Gui (Dear ImGui) — immediate-mode stand-in that lays widgets out and draws simple boxes
local Gui = mod("Gui")
local G = { theme = 0, cursor = nil, win = nil, menubar = false, menus = 0, ww = nil, nextpos = nil, nextsize = nil }
local function gctx() return draw_target() end
local function gtext(x, y, s, c, size) font_draw(gctx(), { family = "Liberation Sans" }, x, y, s, c or 0xFFE6E6E6, size or 15) end
local function grow(h) local c = G.cursor; local y = c.y; c.y = c.y + (h or 22) + 4; c.lastx = c.x; return y end
local function gwidget(label, h, drawfn)
  local c = G.cursor
  if not c then return end
  local x, y = c.same and c.samex or c.x, c.same and c.samey or c.y
  if not c.same then grow(h) end
  local w = drawfn(x, y)
  c.same = false
  c.samex, c.samey = x + (w or 120) + 8, y
end
function Gui.init() st.gui = true end
function Gui.initBlend() G.frame_begun = true end
function Gui.termBlend() G.frame_begun = false end
function Gui.setTheme(t) G.theme = t end
function Gui.setInputMode(a, b, c, d) end
function Gui.initMainMenubar()
  local ctx = gctx()
  cairo.cairo_set_source_rgba(ctx, 0.15, 0.18, 0.25, 1)
  cairo.cairo_rectangle(ctx, 0, 0, W, 22); cairo.cairo_fill(ctx)
  G.menubar, G.menux = true, 8
  return true
end
function Gui.termMainMenubar() G.menubar = false end
function Gui.initMenu(label, enabled)
  if G.menubar then
    gtext(G.menux, 3, label, enabled == false and 0xFF808080 or nil)
    G.menux = G.menux + font_width({ family = "Liberation Sans" }, label, 15) + 18
  end
  -- the driver opens one menu at a time through M.gui_open, like tapping it
  return enabled ~= false and M.gui_open == label
end
function Gui.termMenu() end
function Gui.drawMenuItem(label, sel, en) return false end
function Gui.setWindowPos(x, y, mode) G.nextpos = { x, y } end
function Gui.setWindowSize(w, h, mode) G.nextsize = { w, h } end
function Gui.initWindow(label, flags)
  local p, s = G.nextpos or { 60, 60 }, G.nextsize or { 400, 300 }
  local ctx = gctx()
  cairo.cairo_set_source_rgba(ctx, 0.06, 0.06, 0.08, 0.94); cairo.cairo_rectangle(ctx, p[1], p[2], s[1], s[2]); cairo.cairo_fill(ctx)
  cairo.cairo_set_source_rgba(ctx, 0.16, 0.29, 0.48, 1); cairo.cairo_rectangle(ctx, p[1], p[2], s[1], 22); cairo.cairo_fill(ctx)
  gtext(p[1] + 8, p[2] + 3, label)
  G.cursor = { x = p[1] + 10, y = p[2] + 30, w = s[1] - 20, bottom = p[2] + s[2] }
  cairo.cairo_save(ctx); cairo.cairo_rectangle(ctx, p[1], p[2], s[1], s[2]); cairo.cairo_clip(ctx)
  G.nextpos, G.nextsize = nil, nil
end
function Gui.termWindow() cairo.cairo_restore(gctx()); G.cursor = nil end
function Gui.drawText(label, c) gwidget(label, 16, function(x, y) gtext(x, y, label, c); return font_width({ family = "Liberation Sans" }, label, 15) end) end
function Gui.drawDisabledText(label) Gui.drawText(label, 0xFF808080) end
function Gui.drawWrappedText(label) Gui.drawText(label:sub(1, 60) .. (#label > 60 and "..." or "")) end
local function box(x, y, w, h, r, g, b)
  local ctx = gctx(); cairo.cairo_set_source_rgba(ctx, r, g, b, 1); cairo.cairo_rectangle(ctx, x, y, w, h); cairo.cairo_fill(ctx)
end
function Gui.drawButton(label, w, h)
  gwidget(label, h or 20, function(x, y)
    local bw = (w and w > 0) and w or font_width({ family = "Liberation Sans" }, label, 15) + 16
    box(x, y, bw, h or 20, 0.26, 0.59, 0.98); gtext(x + 8, y + 2, label, 0xFFFFFFFF); return bw
  end)
  return false
end
function Gui.drawSmallButton(label) return Gui.drawButton(label) end
function Gui.drawCheckbox(label, v)
  gwidget(label, 18, function(x, y) box(x, y, 18, 18, 0.16, 0.29, 0.48); if v then box(x + 4, y + 4, 10, 10, 0.26, 0.59, 0.98) end gtext(x + 26, y + 1, label); return 200 end)
  return v
end
function Gui.drawRadioButton(label, v)
  gwidget(label, 18, function(x, y)
    local ctx = gctx(); cairo.cairo_set_source_rgba(ctx, 0.16, 0.29, 0.48, 1); cairo.cairo_new_path(ctx); cairo.cairo_arc(ctx, x + 9, y + 9, 9, 0, 6.3); cairo.cairo_fill(ctx)
    if v then cairo.cairo_set_source_rgba(ctx, 0.26, 0.59, 0.98, 1); cairo.cairo_new_path(ctx); cairo.cairo_arc(ctx, x + 9, y + 9, 4, 0, 6.3); cairo.cairo_fill(ctx) end
    gtext(x + 24, y + 1, label); return font_width({ family = "Liberation Sans" }, label, 15) + 30
  end)
  return false
end
function Gui.resetLine() if G.cursor then G.cursor.same = true end end
function Gui.drawSeparator() gwidget("", 2, function(x, y) box(x, y, G.cursor.w, 1, 0.4, 0.4, 0.5); return G.cursor.w end) end
local function slider(label, vmin, vmax, ...)
  local vals = { ... }
  gwidget(label, 20, function(x, y)
    local w = (G.ww or 300) / #vals - 4
    for i, v in ipairs(vals) do
      box(x + (i - 1) * (w + 4), y, w, 20, 0.16, 0.29, 0.48)
      local f = (v - vmin) / math.max(1e-9, vmax - vmin)
      box(x + (i - 1) * (w + 4) + f * (w - 10), y + 2, 10, 16, 0.26, 0.59, 0.98)
      gtext(x + (i - 1) * (w + 4) + w / 2 - 12, y + 2, string.format(math.floor(v) == v and "%d" or "%.2f", v))
    end
    gtext(x + (G.ww or 300) + 6, y + 2, label); return 400
  end)
  return ...
end
function Gui.drawSlider(label, vmin, vmax, ...) return slider(label, vmin, vmax, ...) end
function Gui.drawIntSlider(label, vmin, vmax, ...) return slider(label, vmin, vmax, ...) end
function Gui.drawTooltip(label) end
function Gui.drawComboBox(label, idx, items)
  gwidget(label, 20, function(x, y) box(x, y, G.ww or 220, 20, 0.16, 0.29, 0.48); gtext(x + 6, y + 2, tostring(items[idx])); gtext(x + (G.ww or 220) + 8, y + 2, label); return 380 end)
  return idx
end
function Gui.drawListBox(label, idx, items)
  gwidget(label, #items * 18 + 4, function(x, y)
    box(x, y, G.ww or 220, #items * 18 + 4, 0.1, 0.12, 0.18)
    for i, it in ipairs(items) do
      if i == idx then box(x, y + 2 + (i - 1) * 18, G.ww or 220, 18, 0.26, 0.59, 0.98) end
      gtext(x + 6, y + 3 + (i - 1) * 18, it)
    end
    gtext(x + (G.ww or 220) + 8, y + 2, label); return 380
  end)
  return idx
end
function Gui.drawColorPicker(label, c, alpha)
  gwidget(label, 120, function(x, y)
    for i = 0, 19 do
      local r, g, b = rgba(Color.new(i * 12, 255 - i * 12, 180))
      box(x + i * 8, y, 8, 100, r, g, b)
    end
    local r, g, b = rgba(c); box(x + 170, y, 30, 30, r, g, b); gtext(x + 210, y + 6, label); return 300
  end)
  -- reproduce the C bug: alpha byte is garbage when `alpha` is not set
  return Color.new(Color.getR(c), Color.getG(c), Color.getB(c), alpha and Color.getA(c) or 0)
end
function Gui.drawProgressbar(f, w, h)
  gwidget("", h or 18, function(x, y) local bw = (w and w > 0) and w or G.cursor.w; box(x, y, bw, h or 18, 0.16, 0.29, 0.48); box(x, y, bw * f, h or 18, 0.9, 0.7, 0.0); return bw end)
end
function Gui.drawImage(img, w, h, tx, ty, tw, th, c)
  local o = get(img, "image", "Gui.drawImage")
  gwidget("", h or o.h, function(x, y)
    local sx, sy = (w or o.w) / (tw or o.w), (h or o.h) / (th or o.h)
    draw_surface(gctx(), o, x, y, sx, sy, 0, tx and { tx, ty, tw, th } or nil, c)
    return w or o.w
  end)
end
function Gui.setWidgetPos(x, y) if G.cursor then G.cursor.x0 = G.cursor.x0 or G.cursor.x; G.cursor.y = G.cursor.y end end
function Gui.getTextSize(s) return font_width({ family = "Liberation Sans" }, s, 15), 15 end
function Gui.setWidgetWidth(w) G.ww = w end
function Gui.resetWidgetWidth() G.ww = nil end

---------------------------------------------------------------- dialogs overlay
function M.draw_dialog_overlay(ctx)
  cairo.cairo_set_source_rgba(ctx, 0, 0, 0, 0.55)
  cairo.cairo_rectangle(ctx, 0, 0, W, H); cairo.cairo_fill(ctx)
  local x, y, w, h = 180, 150, 600, 220
  cairo.cairo_set_source_rgba(ctx, 0.93, 0.94, 0.96, 1)
  cairo.cairo_rectangle(ctx, x, y, w, h); cairo.cairo_fill(ctx)
  local text = st.msg and st.msg.text or ("[Keyboard] " .. st.kb.title)
  local yy = y + 30
  for line in (tostring(text) .. "\n"):gmatch("([^\n]*)\n") do
    font_draw(ctx, { family = "Liberation Sans" }, x + 30, yy, line, Color.new(30, 30, 40), 20)
    yy = yy + 28
  end
  if st.msg and st.msg.progress then
    cairo.cairo_set_source_rgba(ctx, 0.8, 0.8, 0.85, 1); cairo.cairo_rectangle(ctx, x + 30, y + 150, w - 60, 14); cairo.cairo_fill(ctx)
    cairo.cairo_set_source_rgba(ctx, 0.2, 0.45, 0.95, 1); cairo.cairo_rectangle(ctx, x + 30, y + 150, (w - 60) * st.msg.progress / 100, 14); cairo.cairo_fill(ctx)
    font_draw(ctx, { family = "Liberation Sans" }, x + 30, y + 172, st.msg.prog_msg or "", Color.new(30, 30, 40), 16)
  elseif st.kb then
    cairo.cairo_set_source_rgba(ctx, 1, 1, 1, 1); cairo.cairo_rectangle(ctx, x + 30, y + 80, w - 60, 40); cairo.cairo_fill(ctx)
    font_draw(ctx, { family = "Liberation Sans" }, x + 40, y + 88, st.kb.text or "", Color.new(30, 30, 40), 20)
  else
    local labels = ({ [0] = { "OK" }, { "Yes", "No" }, {}, { "OK", "Cancel" }, { "Cancel" } })[st.msg.buttons] or {}
    for i, l in ipairs(labels) do
      local bx = x + w - 30 - (#labels - i + 1) * 130
      cairo.cairo_set_source_rgba(ctx, 0.2, 0.45, 0.95, 1); cairo.cairo_rectangle(ctx, bx, y + h - 56, 120, 36); cairo.cairo_fill(ctx)
      font_draw(ctx, { family = "Liberation Sans" }, bx + 40, y + h - 48, l, Color.new(255, 255, 255), 18)
    end
  end
end

-- scripted answers for dialogs (the test driver sets these)
function M.answer_message(result) if st.msg then st.msg.result = result end end -- 1 FINISHED/yes, 3 CANCELED
function M.answer_keyboard(text)
  if st.kb then
    if text then st.kb.result, st.kb.state = text, 1 else st.kb.state = 3 end
  end
end

M.events = {}
function M.event(s) M.events[#M.events + 1] = s end

---------------------------------------------------------------- install globals
local CONST = {
  -- Controls (vitasdk SceCtrlButtons)
  SCE_CTRL_SELECT = 0x1, SCE_CTRL_START = 0x8, SCE_CTRL_UP = 0x10, SCE_CTRL_RIGHT = 0x20, SCE_CTRL_DOWN = 0x40,
  SCE_CTRL_LEFT = 0x80, SCE_CTRL_LTRIGGER = 0x100, SCE_CTRL_RTRIGGER = 0x200, SCE_CTRL_TRIANGLE = 0x1000,
  SCE_CTRL_CIRCLE = 0x2000, SCE_CTRL_CROSS = 0x4000, SCE_CTRL_SQUARE = 0x8000, SCE_CTRL_PSBUTTON = 0x10000,
  SCE_CTRL_POWER = 0x40000000, SCE_CTRL_VOLUP = 0x400000, SCE_CTRL_VOLDOWN = 0x800000,
  UNPAIRED_DEV = 0, VITA_DEV = 1, VIRTUAL_DEV = 2, DS3_DEV = 4, DS4_DEV = 8,
  -- Graphics
  FILTER_POINT = 0, FILTER_LINEAR = 1, MEM_VRAM = 0x09408060, MEM_PHYCONT_RAM = 0x0C80D060, MEM_RAM = 0x0C20D060,
  -- System
  FREAD = 1, FWRITE = 2, FCREATE = 0x0202, FRDWR = 3, SET = 0, CUR = 1, END = 2,
  AUTO_SUSPEND_TIMER = 1, SCREEN_OFF_TIMER = 4, SCREEN_DIMMING_TIMER = 6,
  FORMAT_BMP = 0, FORMAT_PNG = 1, FORMAT_JPG = 2,
  BUTTON_OK = 0, BUTTON_YES_NO = 1, BUTTON_NONE = 2, BUTTON_OK_CANCEL = 3, BUTTON_CANCEL = 4,
  READ_ONLY = 1, READ_WRITE = 2,
  -- Common dialog status (Keyboard registers them, System reuses them)
  RUNNING = 2, FINISHED = 1, CANCELED = 3,
  -- Keyboard
  MODE_TEXT = 0, MODE_PASSWORD = 1, TYPE_DEFAULT = 0, TYPE_LATIN = 1, TYPE_NUMBER = 2, TYPE_EXT_NUMBER = 3,
  OPT_MULTILINE = 1, OPT_NO_AUTOCAP = 2, OPT_NO_ASSISTANCE = 4,
  -- Registry (registered after Keyboard: TYPE_NUMBER is overwritten with the same value 2)
  TYPE_STRING = 0, TYPE_BINARY = 1,
  -- Network
  GET_METHOD = 1, POST_METHOD = 2, HEAD_METHOD = 3, OPTIONS_METHOD = 4, PUT_METHOD = 5, DELETE_METHOD = 6,
  TRACE_METHOD = 7, CONNECT_METHOD = 8, UDP_SOCKET = 17, TCP_SOCKET = 6,
  -- Sound
  IMAGE_CAPTURE = 0, VIDEO_CAPTURE_START = 1, VIDEO_CAPTURE_END = 2,
  -- Video
  NORMAL_MODE = 100, FAST_FORWARD_2X_MODE = 200, FAST_FORWARD_4X_MODE = 400, FAST_FORWARD_8X_MODE = 800,
  FAST_FORWARD_16X_MODE = 1600, FAST_FORWARD_32X_MODE = 3200,
  -- Camera
  INNER_CAM = 0, OUTER_CAM = 1, VGA_RES = 1, QVGA_RES = 2, QQVGA_RES = 3, CIF_RES = 4, QCIF_RES = 5, PSP_RES = 6, NGP_RES = 7,
  ANTIFLICKER_AUTO = 1, ANTIFLICKER_50HZ = 2, ANTIFLICKER_60HZ = 3, ISO_AUTO = 1, ISO_100 = 100, ISO_200 = 200, ISO_400 = 400,
  WB_AUTO = 0, WB_DAYLIGHT = 1, WB_CWF = 2, WB_SLSA = 4, BACKLIGHT_OFF = 0, BACKLIGHT_ON = 1,
  NIGHTMODE_OFF = 0, NIGHTMODE_LOW = 1, NIGHTMODE_MED = 2, NIGHTMODE_HIGH = 128,
  REVERSE_OFF = 0, REVERSE_MIRROR = 1, REVERSE_FLIP = 2, REVERSE_BOTH = 3,
  EFFECT_NONE = 0, EFFECT_NEGATIVE = 1, EFFECT_BLACKWHITE = 2, EFFECT_SEPIA = 3, EFFECT_BLUE = 4, EFFECT_RED = 5, EFFECT_GREEN = 6,
  -- Gui
  DARK_THEME = 0, LIGHT_THEME = 1, CLASSIC_THEME = 2, SET_ONCE = 0, SET_ALWAYS = 1,
  FLAG_NONE = 0, FLAG_NO_TITLEBAR = 1, FLAG_NO_RESIZE = 2, FLAG_NO_MOVE = 4, FLAG_NO_SCROLLBAR = 8,
  FLAG_NO_COLLAPSE = 32, FLAG_HORIZONTAL_SCROLLBAR = 2048,
}
SCE_CTRL_VOLUP_V, SCE_CTRL_VOLDOWN_V, SCE_CTRL_POWER_V = CONST.SCE_CTRL_VOLUP, CONST.SCE_CTRL_VOLDOWN, CONST.SCE_CTRL_POWER
SCE_CTRL_CROSS_V = CONST.SCE_CTRL_CROSS
FREAD_V, FWRITE_V, FRDWR_V = CONST.FREAD, CONST.FWRITE, CONST.FRDWR

function M.install()
  -- constants: every name the real interpreter registers must exist here, and nothing extra
  local want = {}
  for _, c in ipairs(API.constants) do want[c] = true end
  for name, v in pairs(CONST) do
    assert(want[name], "mock constant " .. name .. " is not registered by lpp-vita")
    _G[name] = v
  end
  for name in pairs(want) do assert(CONST[name] ~= nil, "mock is missing constant " .. name) end
  -- modules: wrap each implemented function with the C-derived checks
  local missing = {}
  for modname, fns in pairs(API.modules) do
    local t = {}
    for fname in pairs(fns) do
      local f = impl[modname] and impl[modname][fname]
      if f then t[fname] = wrap(modname, fname, f) else missing[#missing + 1] = modname .. "." .. fname end
    end
    _G[modname] = t
  end
  assert(#missing == 0, "mock is missing: " .. table.concat(missing, ", "))
  for modname, fns in pairs(impl) do
    for fname in pairs(fns) do assert(API.modules[modname][fname], "extra mock fn " .. modname .. "." .. fname) end
  end
  -- lpp-vita's Lua: LuaJIT 2.1 + bit32 from 5.2
  bit32 = bit32 or { band = bit.band, bor = bit.bor, bxor = bit.bxor, bnot = bit.bnot, lshift = bit.lshift, rshift = bit.rshift }
  -- dofile must understand app0:/ paths
  local real_dofile = dofile
  dofile = function(p) return real_dofile(host_path(p)) end
end

function M.save_png(path) cairo.cairo_surface_write_to_png(front, path) end
function M.save_back(path) cairo.cairo_surface_write_to_png(screen, path) end

return M
