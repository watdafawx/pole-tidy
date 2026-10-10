-- builds a small grid, tidies it, removes the marked poles like bots would, and checks nothing lost power
local out = {}
local function log(s) out[#out + 1] = s end

script.on_nth_tick(5, function(ev)
  if ev.tick ~= 5 then return end
  local s = game.surfaces.nauvis
  local f = game.forces.player
  s.always_day = true
  local area = { { -30, -30 }, { 70, 30 } }
  for _, e in pairs(s.find_entities_filtered({ area = area })) do if e.valid and e.type ~= "character" then e.destroy() end end
  local tiles = {}
  for x = -30, 70 do for y = -30, 30 do tiles[#tiles + 1] = { name = "lab-dark-1", position = { x, y } } end end
  s.set_tiles(tiles)
  local function make(name, x, y, q)
    local e = s.create_entity({ name = name, position = { x, y }, force = f, quality = q })
    assert(e, "can't place " .. name)
    return e
  end
  local src = make("electric-energy-interface", -1, 1)
  local poles = {}
  for x = 0, 40, 5 do poles[#poles + 1] = make("small-electric-pole", x + 0.5, 0.5) end
  local machines = {}
  for x = 2, 38, 6 do
    local m = make("assembling-machine-2", x + 0.5, 3.5)
    m.set_recipe("iron-gear-wheel")
    machines[#machines + 1] = m
  end
  -- a far machine powered only through the end of the line
  local far = make("small-electric-pole", 46.5, 0.5)
  machines[#machines + 1] = make("assembling-machine-2", 48.5, 3.5)
  -- an upgraded pole covering the middle
  local big = make("medium-electric-pole", 20.5, 2.5, "legendary")
  -- a pole with a circuit wire: kept
  local red = make("small-electric-pole", 10.5, -3.5)
  red.get_wire_connector(defines.wire_connector_id.circuit_red, true).connect_to(
    poles[3].get_wire_connector(defines.wire_connector_id.circuit_red, true), false)
  -- wire the line explicitly (script-built poles may not auto-wire)
  local function cu(a, b) a.get_wire_connector(defines.wire_connector_id.pole_copper, true).connect_to(
    b.get_wire_connector(defines.wire_connector_id.pole_copper, true), false) end
  local line = { poles[1] }
  for i = 2, #poles do line[#line + 1] = poles[i] end
  line[#line + 1] = far
  for i = 2, #line do cu(line[i - 1], line[i]) end
  cu(big, poles[5])
  cu(red, poles[3])
  -- a duplicate next to a line pole, covering nothing new: goes
  local dup = make("small-electric-pole", 30.5, -1.5)
  cu(dup, poles[7])
  -- power: the interface touches the first pole's supply area
  local all = s.find_entities_filtered({ type = "electric-pole", area = area })
  local real = 0
  for _, p in pairs(all) do if not string.find(p.name, "invisible") then real = real + 1 end end
  local function powered()
    local n = 0
    for _, m in pairs(machines) do if m.valid and m.is_connected_to_electric_network() then n = n + 1 end end
    return n
  end
  log("before: real poles " .. real .. ", machines powered " .. powered() .. "/" .. #machines)
  local would, wires = remote.call("pole-tidy", "plan", all)
  log("plan: remove " .. would .. ", new wires " .. wires)
  local marked = remote.call("pole-tidy", "tidy", all)
  log("marked " .. tostring(marked))
  local names = {}
  for _, p in pairs(s.find_entities_filtered({ type = "electric-pole", area = area, to_be_deconstructed = true })) do
    names[#names + 1] = p.name .. "@" .. p.position.x .. "," .. p.position.y
    p.destroy({ raise_destroy = true })
  end
  log("removed: " .. table.concat(names, " "))
  log("kept circuit pole: " .. tostring(red.valid) .. ", kept big pole: " .. tostring(big.valid) .. ", kept far: " .. tostring(far.valid))
  -- networks: every remaining real pole on the source's network
  local nets, n = {}, 0
  for _, p in pairs(s.find_entities_filtered({ type = "electric-pole", area = area })) do
    if not string.find(p.name, "invisible") and not nets[p.electric_network_id] then
      nets[p.electric_network_id] = true
      n = n + 1
    end
  end
  log("after: machines powered " .. powered() .. "/" .. #machines .. ", separate grids " .. n)
  log("duplicate removed: " .. tostring(not dup.valid))
  -- auto mode: a pole upgraded by a script (as Upgradeable Quality does) gets its neighbourhood tidied
  remote.call("pole-tidy", "set_auto", true)
  local up = s.create_entity({ name = "medium-electric-pole", position = { 36.5, 2.5 }, force = f,
    quality = "legendary", raise_built = true })
  cu(up, poles[8])
  -- AI Crew running poles to a dark machine: a fresh line end powering nothing yet stays
  local run = s.create_entity({ name = "small-electric-pole", position = { 46.5, -6.5 }, force = f, raise_built = true })
  cu(run, far)
  storage.run = run
end)

script.on_nth_tick(130, function(ev)
  if ev.tick ~= 130 then return end
  local s = game.surfaces.nauvis
  local names = {}
  for _, p in pairs(s.find_entities_filtered({ type = "electric-pole", to_be_deconstructed = true })) do
    names[#names + 1] = p.name .. "@" .. p.position.x .. "," .. p.position.y
  end
  log("auto mode marked " .. #names .. ": " .. table.concat(names, " "))
  if storage.run.to_be_deconstructed() then log("FAIL: auto mode removed a line still being run") end
  for _, p in pairs(s.find_entities_filtered({ type = "electric-pole", to_be_deconstructed = true })) do p.destroy() end
  local on, all, nets, n = 0, 0, {}, 0
  for _, m in pairs(s.find_entities_filtered({ type = "assembling-machine" })) do
    all = all + 1
    if m.is_connected_to_electric_network() then on = on + 1 else
      log("  unpowered: " .. m.name .. "@" .. m.position.x .. "," .. m.position.y) end
  end
  for _, p in pairs(s.find_entities_filtered({ type = "electric-pole" })) do
    if not string.find(p.name, "invisible") and not nets[p.electric_network_id] then
      nets[p.electric_network_id] = true
      n = n + 1
    end
  end
  log("after auto: machines powered " .. on .. "/" .. all .. ", separate grids " .. n)
  helpers.write_file("pt-test.txt", table.concat(out, "\n") .. "\n")
end)
