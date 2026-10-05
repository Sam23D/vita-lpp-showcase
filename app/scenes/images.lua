-- 3. Images: loading, every draw variant, pixel access, saving, GIFs, async loading.
local S = {
  title = "Images", modules = { "Graphics" },
  desc = "Loads PNG, JPG and BMP, then uses every image call: drawImage, drawScaleImage, "
      .. "drawRotateImage, drawPartialImage and drawImageExtended, setImageFilters, createImage, "
      .. "drawPixel and getPixel on an image, overloadImage, saveImage, animated GIFs "
      .. "(loadAnimatedImage, setImageFrame) and loadImageAsync. Three pages; use L and R to switch.",
  hints = { { "l", "" }, { "r", "Page" }, { "square", "Action" } },
}

local page, t = 1, 0
local img = {}
local filter_linear = false
local canvas, cur = nil, { x = 32, y = 32 }
local async_img = nil
local PAGES = { "Draw calls", "Pixels", "GIF + async" }

function S.enter()
  img.png = Graphics.loadImage(asset_path("img/hello.png"))
  img.jpg = Graphics.loadImage(asset_path("img/photo.jpg"))
  img.bmp = Graphics.loadImage(asset_path("img/checker.bmp"))
  img.sheet = Graphics.loadImage(asset_path("img/sprites.png"))
  img.gif = Graphics.loadAnimatedImage(asset_path("img/spinner.gif"))
  img.frames = Graphics.getImageFramesNum(img.gif)
  Log.info(string.format("hello.png %dx%d, photo.jpg %dx%d, gif frames %d",
    Graphics.getImageWidth(img.png), Graphics.getImageHeight(img.png),
    Graphics.getImageWidth(img.jpg), Graphics.getImageHeight(img.jpg), img.frames))
  -- createImage(w, h, color, memtype). Quirk: the fill is a memset, so only the low byte
  -- of `color` (red) is replicated into every channel -> pass white or black, not a colour.
  canvas = Graphics.createImage(64, 64, Color.new(255, 255, 255), MEM_VRAM)
  Graphics.setImageFilters(canvas, FILTER_POINT, FILTER_POINT)
end

function S.leave()
  for _, h in pairs({ img.png, img.jpg, img.bmp, img.sheet, img.gif, canvas, async_img }) do
    Defer.free(Graphics.freeImage, h)
  end
  img, canvas, async_img = {}, nil, nil
end

local function action()
  if page == 1 then
    filter_linear = not filter_linear
    local f = filter_linear and FILTER_LINEAR or FILTER_POINT
    Try("setImageFilters " .. (filter_linear and "LINEAR" or "POINT"), Graphics.setImageFilters, img.bmp, f, f)
  elseif page == 2 then
    -- overloadImage: raw memcpy into the texture. 64px wide -> 256 bytes per row (RGBA).
    local row = {}
    for x = 0, 63 do row[#row + 1] = string.char(x * 4, 255 - x * 4, 200, 255) end
    local bytes = table.concat(row)
    for y = 28, 35 do Graphics.overloadImage(canvas, y * 256, #bytes, bytes) end
    Log.ok("overloadImage: wrote 8 gradient rows")
    local path = data_path("canvas.png")
    if Try("saveImage -> " .. path, Graphics.saveImage, canvas, path, FORMAT_PNG) then
      -- reload what we just saved; the 2-arg form loadImage(path, MEM_RAM) hits an lpp bug
      -- (it reads argument #4), so this shows the error and then uses the 1-arg form
      Try("loadImage(path, MEM_RAM)", Graphics.loadImage, path, MEM_RAM)
      local ok, h = Try("loadImage(path)", Graphics.loadImage, path)
      if ok then
        Log.info(string.format("reloaded %dx%d", Graphics.getImageWidth(h), Graphics.getImageHeight(h)))
        Graphics.freeImage(h)
      end
    end
  else
    Defer.free(Graphics.freeImage, async_img); async_img = nil
    Async.start("loadImageAsync(photo.jpg)", function()
      Graphics.loadImageAsync(asset_path("img/photo.jpg"))
    end, function(res)
      async_img = tonumber(res) -- the async result is the image handle as a string
    end)
  end
end

function S.update()
  t = t + 1
  if Input.pressed("r") then page = page % #PAGES + 1 end
  if Input.pressed("l") then page = (page - 2) % #PAGES + 1 end
  if Input.pressed("square") then action() end
  if page == 2 then
    -- paint into the canvas with the d-pad / left stick / touch
    if Input.rep("left") then cur.x = cur.x - 1 end
    if Input.rep("right") then cur.x = cur.x + 1 end
    if Input.rep("up") then cur.y = cur.y - 1 end
    if Input.rep("down") then cur.y = cur.y + 1 end
    cur.x = cur.x + Input.axis(Input.lx) * 1.5
    cur.y = cur.y + Input.axis(Input.ly) * 1.5
    local p = Input.touch[1]
    if p and Input.in_rect(p, 60, 90, 384, 384) then
      cur.x, cur.y = (p.x - 60) / 6, (p.y - 90) / 6
    end
    cur.x = math.max(0, math.min(63, cur.x))
    cur.y = math.max(0, math.min(63, cur.y))
    if Input.held("cross") or p then
      local h = (t * 4) % 360
      local r = math.floor(127 + 127 * math.sin(math.rad(h)))
      local g = math.floor(127 + 127 * math.sin(math.rad(h + 120)))
      local b = math.floor(127 + 127 * math.sin(math.rad(h + 240)))
      Graphics.drawPixel(math.floor(cur.x), math.floor(cur.y), Color.new(r, g, b), canvas)
    end
  end
end

local function caption(x, y, s) UI.mono(x, y, s, C.accent2, 13) end

local function draw_page1()
  Graphics.drawImage(30, 70, img.png)
  caption(30, 172, "drawImage(x, y, img)")
  Graphics.drawImage(30, 196, img.png, Color.new(120, 255, 160))
  caption(30, 298, "drawImage(x, y, img, tint)")
  Graphics.drawScaleImage(310, 70, img.jpg, 0.75, 0.75)
  caption(310, 196, "drawScaleImage(x,y,img,.75,.75)")
  -- rotation functions draw around the image centre
  Graphics.drawRotateImage(420, 340, img.png, t / 50)
  caption(310, 410, "drawRotateImage(cx,cy,img,rad)")
  local frame = math.floor(t / 10) % 4
  Graphics.drawPartialImage(620, 70, img.sheet, frame * 64, 0, 64, 64)
  caption(600, 140, "drawPartialImage(.., 64*f,0,64,64)")
  Graphics.drawImageExtended(800, 112, img.sheet, frame * 64, 0, 64, 64,
    -t / 30, 1.4 + 0.4 * math.sin(t / 20), 1.4, Color.new(255, 255, 255, 220))
  caption(720, 160, "drawImageExtended(...)")
  Graphics.drawScaleImage(620, 196, img.bmp, 4, 4)
  caption(620, 458, "checker.bmp x4, filter: " .. (filter_linear and "LINEAR" or "POINT") .. "  [square]")
end

local function draw_page2()
  UI.panel(50, 60, 404, 424, "createImage(64,64) canvas  x6")
  Graphics.drawScaleImage(60, 90, canvas, 6, 6)
  UI.frame(60 + math.floor(cur.x) * 6, 90 + math.floor(cur.y) * 6, 6, 6, C.white)
  local px = Graphics.getPixel(math.floor(cur.x), math.floor(cur.y), canvas)
  UI.panel(480, 60, 450, 424, "Pixel access")
  UI.kv(500, 96, {
    { "cursor", string.format("%d, %d", cur.x, cur.y) },
    { "getPixel", UI.hex(px) },
    { "R G B A", string.format("%d %d %d %d", Color.getR(px), Color.getG(px), Color.getB(px), Color.getA(px)) },
  }, 110, 16, 24)
  UI.rect(860, 96, 50, 50, px)
  UI.frame(860, 96, 50, 50, C.line)
  UI.paragraph(500, 180, "Hold CROSS (or touch the canvas) to paint with drawPixel(x, y, color, image). "
    .. "SQUARE writes gradient rows with overloadImage, saves the canvas with saveImage(..., FORMAT_PNG) "
    .. "to ux0:/data/lpp-showcase/canvas.png and loads it back.", 410, C.dim, 15)
  Log.draw(500, 320, 410, 150, "Log")
end

local function draw_page3()
  Graphics.setImageFrame(img.gif, math.floor(t / 6) % img.frames)
  Graphics.drawScaleImage(80, 90, img.gif, 3, 3)
  caption(60, 300, "loadAnimatedImage + setImageFrame")
  caption(60, 320, "frame " .. (math.floor(t / 6) % img.frames + 1) .. " / " .. img.frames)
  UI.panel(420, 70, 510, 230, "loadImageAsync  [square]")
  if async_img then
    Graphics.drawImage(440, 104, async_img)
  else
    UI.text(440, 110, Async.busy() and "loading..." or "press SQUARE", C.dim, 16)
  end
  Async.draw_badge(440, 270)
  Log.draw(420, 316, 510, 168, "Log")
end

function S.draw()
  S.subtitle = "Graphics  -  page " .. page .. "/3: " .. PAGES[page]
  if page == 1 then draw_page1() elseif page == 2 then draw_page2() else draw_page3() end
end

return S
