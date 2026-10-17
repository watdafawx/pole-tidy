-- Powered Concrete: poles standing over a powered floor go (the floor's hidden poles power and join everything),
-- the floor's own poles are never touched, a pole joining two floors stays; then auto mode on a floor
local out, failed = {}, 0
local function log(s) out[#out + 1] = s end
local function check(ok, what)
  if not ok then failed = failed + 1 log("FAIL: " .. what) end
end

local function powered(src)
  local n, all = 0, 0
  for _, m in pairs(game.surfaces.nauvis.find_entities_filtered({ type = "assembling-machine" })) do
    all = all + 1
    if m.electric_network_id == src.electric_network_id then n = n + 1 end
  end
  return n, all
end

local function real_poles(s)
  return s.find_entities_filtered({ type = "electric-pole", name = { "small-electric-pole", "medium-electric-pole" } })
end

script.on_nth_tick(5, function(ev)
  if ev.tick ~= 5 then return end
  local s = game.surfaces.nauvis
  local f = game.forces.player
  s.always_day = true
  local area = { { -10, -10 }, { 100, 70 } }
  for _, e in pairs(s.find_entities_filtered({ area = area })) do if e.valid and e.type ~= "character" then e.destroy() end end
  local tiles = {}
  for x = -10, 100 do for y = -10, 70 do tiles[#tiles + 1] = { name = "lab-dark-1", position = { x, y } } end end
  s.set_tiles(tiles)
  -- a 60x60 floor, and a 20x20 one a tile east of it, joined only by a pole in the gap
  tiles = {}
  for x = 0, 59 do for y = 0, 59 do tiles[#tiles + 1] = { name = "powered-concrete", position = { x, y } } end end
  for x = 61, 80 do for y = 0, 19 do tiles[#tiles + 1] = { name = "powered-concrete", position = { x, y } } end end
  s.set_tiles(tiles, true, true, true, true)
  local function make(name, x, y, q)
    local e = s.create_entity({ name = name, position = { x, y }, force = f, quality = q })
    assert(e, "can't place " .. name)
    return e
  end
  local src = make("electric-energy-interface", -3, 5)
  storage.src = src
  local feeder = make("small-electric-pole", -0.5, 4.5)
  for x = 5, 59, 6 do for y = 4, 59, 12 do make("small-electric-pole", x + 0.5, y + 0.5) end end
  local bridge = make("small-electric-pole", 60.5, 10.5)
  for x = 2, 50, 12 do for y = 2, 50, 12 do make("assembling-machine-2", x + 0.5, y + 0.5).set_recipe("iron-gear-wheel") end end
  make("assembling-machine-2", 75.5, 10.5).set_recipe("iron-gear-wheel")
  local floor = s.count_entities_filtered({ name = "powered-tile" })
  log("floor poles " .. floor)
  check(floor > 0, "Powered Concrete made no floor poles")
  local on, all = powered(src)
  log("before: machines powered " .. on .. "/" .. all)
  check(on == all, "not every machine powered before the tidy")
  local poles = real_poles(s)
  local marked = remote.call("pole-tidy", "tidy", poles)
  log("tool: " .. #poles .. " poles, marked " .. tostring(marked))
  check(marked == #poles - 2, "expected all but the feeder and the bridge to go")
  check(s.count_entities_filtered({ name = "powered-tile", to_be_deconstructed = true }) == 0, "a floor pole was marked")
  check(not feeder.to_be_deconstructed(), "the feeder pole was marked")
  check(not bridge.to_be_deconstructed(), "the pole joining the floors was marked")
  for _, p in pairs(s.find_entities_filtered({ type = "electric-pole", to_be_deconstructed = true })) do p.destroy() end
  on, all = powered(src)
  log("after tool: machines powered " .. on .. "/" .. all)
  check(on == all, "a machine lost power")

  -- auto mode: poles over the floor, then one upgraded by a script among them
  for x = 11, 47, 6 do make("small-electric-pole", x + 0.5, 30.5) end
  remote.call("pole-tidy", "set_auto", true)
  storage.up = s.create_entity({ name = "medium-electric-pole", position = { 29.5, 32.5 }, force = f,
    quality = "legendary", raise_built = true })
end)

script.on_nth_tick(130, function(ev)
  if ev.tick ~= 130 then return end
  local s = game.surfaces.nauvis
  local marked = s.count_entities_filtered({ type = "electric-pole", to_be_deconstructed = true })
  log("auto mode marked " .. marked)
  check(marked > 0, "auto mode marked nothing over the floor")
  check(not storage.up.to_be_deconstructed(), "auto mode marked the upgraded pole")
  check(s.count_entities_filtered({ name = "powered-tile", to_be_deconstructed = true }) == 0, "auto mode marked a floor pole")
  for _, p in pairs(s.find_entities_filtered({ type = "electric-pole", to_be_deconstructed = true })) do p.destroy() end
  local on, all = powered(storage.src)
  log("after auto: machines powered " .. on .. "/" .. all)
  check(on == all, "a machine lost power")
  log(failed == 0 and "ALL PASS" or (failed .. " FAILED"))
  helpers.write_file("pt-floor.txt", table.concat(out, "\n") .. "\n")
end)
