-- 11. Render: lpp-vita's basic 3D pipeline.
local S = {
  title = "3D Render", modules = { "Render", "Graphics" },
  desc = "Builds a textured pyramid vertex by vertex (Render.createVertex + loadModel) and loads a torus "
      .. "from a Wavefront .obj (loadObject). Draws both with drawModel, moves the camera with "
      .. "setCamera, swaps textures at runtime with useTexture, and frees everything with unloadModel "
      .. "and destroyVertex. drawModel's 8th argument draws without the camera, for HUD-fixed models.",
  hints = { { "lstick", "Orbit" }, { "rstick", "Move cam" }, { "square", "Swap texture" }, { "cross", "Spin" } },
}

local tex_a, tex_b, use_b = nil, nil, false
local pyramid, verts, torus = nil, {}, nil
local cam = { x = 0, y = 0, z = 0, rx = 0, ry = 0 }
local a, spin = 0, true

-- createVertex(x, y, z, u, v, nx, ny, nz)
local function V(x, y, z, u, v, nx, ny, nz)
  local h = Render.createVertex(x, y, z, u, v, nx, ny, nz)
  verts[#verts + 1] = h
  return h
end

local function build_pyramid()
  local apex, b = { 0, 0.9, 0 }, 0.7
  local base = { { -b, -0.5, b }, { b, -0.5, b }, { b, -0.5, -b }, { -b, -0.5, -b } }
  local list = {}
  for i = 1, 4 do
    local p, q = base[i], base[i % 4 + 1]
    list[#list + 1] = V(p[1], p[2], p[3], 0, 0, 0, 0.5, 1)
    list[#list + 1] = V(q[1], q[2], q[3], 1, 0, 0, 0.5, 1)
    list[#list + 1] = V(apex[1], apex[2], apex[3], 0.5, 1, 0, 0.5, 1)
  end
  for _, tri in ipairs({ { 1, 3, 2 }, { 1, 4, 3 } }) do
    for _, k in ipairs(tri) do
      local p = base[k]
      list[#list + 1] = V(p[1], p[2], p[3], (p[1] + b) / (2 * b), (p[3] + b) / (2 * b), 0, -1, 0)
    end
  end
  return Render.loadModel(list, tex_a)
end

function S.enter()
  tex_a = Graphics.loadImage(asset_path("img/texture.png"))
  tex_b = Graphics.loadImage(asset_path("img/checker.bmp"))
  local ok, m = Try("Render.loadModel(18 vertices)", build_pyramid)
  pyramid = ok and m or nil
  ok, m = Try("Render.loadObject(torus.obj)", Render.loadObject, asset_path("model/torus.obj"), tex_a)
  torus = ok and m or nil
  Render.setCamera(0, 0, 0, 0, 0, 0)
end

function S.leave()
  Defer.free(Render.unloadModel, pyramid)
  Defer.free(Render.unloadModel, torus)
  for _, v in ipairs(verts) do Defer.free(Render.destroyVertex, v) end
  verts, pyramid, torus = {}, nil, nil
  Defer.free(Graphics.freeImage, tex_a)
  Defer.free(Graphics.freeImage, tex_b)
end

function S.update()
  if spin then a = a + 1.2 end
  if Input.pressed("cross") then spin = not spin end
  cam.ry = cam.ry + Input.axis(Input.lx) * 0.03
  cam.rx = math.max(-0.8, math.min(0.8, cam.rx + Input.axis(Input.ly) * 0.03))
  cam.x = cam.x + Input.axis(Input.rx) * 0.05
  cam.z = cam.z + Input.axis(Input.ry) * 0.05
  Render.setCamera(cam.x, cam.y, cam.z, cam.rx, cam.ry, 0)
  if Input.pressed("square") then
    use_b = not use_b
    local t = use_b and tex_b or tex_a
    if pyramid then Try("Render.useTexture(pyramid)", Render.useTexture, pyramid, t) end
    if torus then Try("Render.useTexture(torus)", Render.useTexture, torus, t) end
  end
end

function S.draw()
  -- drawModel(model, x, y, z, angleX, angleY, angleZ [, no_camera]) ; angles in degrees
  if torus then Render.drawModel(torus, -1.4, 0, -6, a * 0.7, a, 0) end
  if pyramid then Render.drawModel(pyramid, 1.6, 0, -6, 15, -a * 1.5, 0) end
  if pyramid then Render.drawModel(pyramid, 2.5, -1.35, -5, 0, a * 3, 0, true) end
  UI.text(16, 470, string.format("camera  pos %.1f %.1f %.1f   rot %.2f %.2f", cam.x, cam.y, cam.z, cam.rx, cam.ry), C.text, 15)
  UI.text(16, 444, "small pyramid bottom-right: drawModel(..., true) ignores the camera", C.dim, 14)
  Log.draw(620, 56, 324, 120)
end

return S
