-- Pole Tidy: remove electric poles other poles make redundant. A pole may go when
--   1. everything powered it supplies is still inside another pole's supply area (power-propagation's hidden
--      poles count: they power their building), and
--   2. its grid stays in one piece: the real poles it was wired to stay joined through real poles (a copper wire
--      is added between two of them in reach when needed), and the buildings' hidden poles it was wired to still
--      reach them.
-- Poles with circuit wires are kept. Lowest quality / smallest supply area goes first.

local COPPER = defines.wire_connector_id.pole_copper
local BFS_LIMIT = 4000
local AUTO_BFS_LIMIT = 80    -- auto mode: a smaller search (a pole whose grid it can't see around is kept)
local bfs_limit = BFS_LIMIT
local HIDDEN = "power%-propagation%-invisible%-pole"

local function is_hidden(pole)
  return string.find(pole.name, HIDDEN) ~= nil
end

local max_supply
--- the largest supply distance any pole can have (bounds the search for poles covering a building)
local function get_max_supply()
  if max_supply then return max_supply end
  max_supply = 0
  for _, p in pairs(prototypes.get_entity_filtered({ { filter = "type", type = "electric-pole" } })) do
    for _, q in pairs(prototypes.quality) do
      local ok, d = pcall(p.get_supply_area_distance, q)
      if ok and d and d > max_supply then max_supply = d end
    end
  end
  max_supply = math.min(max_supply, 64)
  return max_supply
end

local function supply(pole)
  return pole.prototype.get_supply_area_distance(pole.quality)
end

local function wire_reach(pole)
  return pole.prototype.get_max_wire_distance(pole.quality)
end

local function has_circuit_wires(pole)
  for _, id in pairs({ defines.wire_connector_id.circuit_red, defines.wire_connector_id.circuit_green }) do
    local c = pole.get_wire_connector(id, false)
    if c and c.connection_count > 0 then return true end
  end
  return false
end

--- copper neighbours of a pole, plus wires the plan has added
local function neighbours(pole, plan)
  local out = {}
  local c = pole.get_wire_connector(COPPER, false)
  if c then
    for _, w in pairs(c.connections) do
      local o = w.target.owner
      if o.valid then out[#out + 1] = o end
    end
  end
  for _, o in pairs(plan.virtual[pole.unit_number] or {}) do
    if o.valid then out[#out + 1] = o end
  end
  return out
end

local function gone(pole, plan)
  return plan.removed[pole.unit_number] or pole.to_be_deconstructed()
end

--- breadth-first over copper wires from `start`, skipping removed poles (and hidden ones when real_only);
--- stops early once `stop(node)` is true. -> visited {unit = entity}, hit
local function bfs(start, plan, real_only, stop)
  local seen, todo, head = { [start.unit_number] = start }, { start }, 1
  if stop and stop(start) then return seen, true end
  local n = 1
  while todo[head] do
    local p = todo[head]
    head = head + 1
    for _, o in pairs(neighbours(p, plan)) do
      local u = o.unit_number
      if u and not seen[u] and not gone(o, plan) and not (real_only and is_hidden(o)) then
        seen[u] = o
        if stop and stop(o) then return seen, true end
        n = n + 1
        if n > bfs_limit then return seen, false end
        todo[#todo + 1] = o
      end
    end
  end
  return seen, false
end

local function overlaps(pole, d, box)
  local p = pole.position
  return box.left_top.x < p.x + d and box.right_bottom.x > p.x - d
      and box.left_top.y < p.y + d and box.right_bottom.y > p.y - d
end

--- 1. does every powered thing in the pole's supply area stay covered without it?
local function coverage_ok(pole, plan)
  local d = supply(pole)
  local p = pole.position
  local area = { { p.x - d, p.y - d }, { p.x + d, p.y + d } }
  local reach = get_max_supply()
  for _, e in pairs(pole.surface.find_entities_filtered({ area = area, force = pole.force })) do
    local proto = e.type == "entity-ghost" and e.ghost_prototype or e.prototype
    if e.type ~= "electric-pole" and proto.type ~= "electric-pole" and proto.electric_energy_source_prototype then
      local box = e.bounding_box
      -- power-propagation: a building with its own hidden pole powers itself (one look, not a wide search)
      local own = overlaps(pole, d, box) and pole.surface.find_entities_filtered({ type = "electric-pole",
        position = e.position, force = pole.force, limit = 4 })
      local self_powered = false
      for _, h in pairs(own or {}) do
        if h ~= pole and is_hidden(h) and not gone(h, plan) then self_powered = true break end
      end
      if overlaps(pole, d, box) and not self_powered then
        local covered = false
        local near = pole.surface.find_entities_filtered({ type = "electric-pole", force = pole.force,
          area = { { box.left_top.x - reach, box.left_top.y - reach }, { box.right_bottom.x + reach, box.right_bottom.y + reach } } })
        for _, q in pairs(near) do
          if q ~= pole and not gone(q, plan) and overlaps(q, supply(q), box) then
            covered = true
            break
          end
        end
        if not covered then return false end
      end
    end
  end
  return true
end

local function dist(a, b)
  local dx, dy = a.position.x - b.position.x, a.position.y - b.position.y
  return math.sqrt(dx * dx + dy * dy)
end

--- 2. does the grid stay in one piece without it? -> ok, wires to add {{a, b}}
local function grid_ok(pole, plan)
  plan.removed[pole.unit_number] = true -- tentatively
  local real, hidden = {}, {}
  for _, o in pairs(neighbours(pole, plan)) do
    if not gone(o, plan) then
      if is_hidden(o) then hidden[#hidden + 1] = o else real[#real + 1] = o end
    end
  end
  local function fail()
    plan.removed[pole.unit_number] = nil
    return false
  end
  -- the real neighbours, grouped by what they reach through real poles
  local groups, group_of = {}, {}
  for _, r in pairs(real) do
    if not group_of[r.unit_number] then
      local want = {}
      for _, o in pairs(real) do if not group_of[o.unit_number] then want[o.unit_number] = true end end
      local left = 0
      for _ in pairs(want) do left = left + 1 end
      local seen = bfs(r, plan, true, function(n)
        if want[n.unit_number] then
          left = left - 1
          return left == 0
        end
      end)
      local g = { members = {}, seen = seen }
      for _, o in pairs(real) do
        if seen[o.unit_number] and not group_of[o.unit_number] then
          group_of[o.unit_number] = g
          g.members[#g.members + 1] = o
        end
      end
      groups[#groups + 1] = g
    end
  end
  -- join the groups with new wires between neighbours in reach
  local wires = {}
  local joined = { groups[1] }
  local rest = {}
  for i = 2, #groups do rest[#rest + 1] = groups[i] end
  while #rest > 0 do
    local found
    for gi, g in pairs(rest) do
      for _, a in pairs(g.members) do
        for _, h in pairs(joined) do
          for _, b in pairs(h.members) do
            if dist(a, b) <= math.min(wire_reach(a), wire_reach(b)) then
              found = { gi, a, b }
              break
            end
          end
          if found then break end
        end
        if found then break end
      end
      if found then break end
    end
    if not found then return fail() end
    wires[#wires + 1] = { found[2], found[3] }
    joined[#joined + 1] = table.remove(rest, found[1])
  end
  -- the buildings it powered directly still reach the real grid (or each other, when it had no real neighbour)
  if #hidden > 0 then
    local target = {}
    for _, g in pairs(groups) do
      for u in pairs(g.seen) do target[u] = true end
    end
    if #real == 0 then
      local first = hidden[1]
      local seen = bfs(first, plan, false)
      for i = 2, #hidden do
        if not seen[hidden[i].unit_number] then return fail() end
      end
    else
      for _, h in pairs(hidden) do
        -- quick: still wired straight to another real pole (power-propagation wires a building to every pole whose
        -- area overlaps it, so this is the usual case); else the search through the grid
        local direct = false
        for _, o in pairs(neighbours(h, plan)) do
          if o ~= pole and not gone(o, plan) and not is_hidden(o) then direct = true break end
        end
        if not direct then
          local _, hit = bfs(h, plan, false, function(n) return target[n.unit_number] end)
          if not hit then return fail() end
        end
      end
    end
  end
  for _, w in pairs(wires) do
    local a, b = w[1], w[2]
    plan.virtual[a.unit_number] = plan.virtual[a.unit_number] or {}
    plan.virtual[b.unit_number] = plan.virtual[b.unit_number] or {}
    table.insert(plan.virtual[a.unit_number], b)
    table.insert(plan.virtual[b.unit_number], a)
    plan.wires[#plan.wires + 1] = w
  end
  return true
end

local function candidate(pole)
  return pole.valid and pole.type == "electric-pole" and not is_hidden(pole) and not pole.to_be_deconstructed()
      and not has_circuit_wires(pole)
end

--- does anything powered stand in the pole's supply area?
local function powers_anything(pole)
  local d, p = supply(pole), pole.position
  for _, e in pairs(pole.surface.find_entities_filtered({ area = { { p.x - d, p.y - d }, { p.x + d, p.y + d } }, force = pole.force })) do
    local proto = e.type == "entity-ghost" and e.ghost_prototype or e.prototype
    if proto.type ~= "electric-pole" and proto.electric_energy_source_prototype then return true end
  end
  return false
end

--- which of `poles` can go -> plan {remove = {pole}, wires = {{a, b}}}
--- auto: the pole that was just built, and line ends powering nothing (a line still being run: AI Crew, bots,
--- a script), stay
local function make_plan(poles, auto)
  local plan = { removed = {}, virtual = {}, wires = {}, remove = {} }
  local list, key = {}, {}
  for _, p in pairs(poles) do
    if candidate(p) and p ~= auto then
      -- lowest quality, smallest area, then fewest real wires (a pole hanging off the line before the line itself)
      local wires = 0
      for _, o in pairs(neighbours(p, plan)) do if not is_hidden(o) then wires = wires + 1 end end
      if not (auto and wires <= 1 and not powers_anything(p)) then
        list[#list + 1] = p
        key[p.unit_number] = { p.quality.level, supply(p), wires, p.unit_number }
      end
    end
  end
  table.sort(list, function(a, b)
    local ka, kb = key[a.unit_number], key[b.unit_number]
    for i = 1, 4 do
      if ka[i] ~= kb[i] then return ka[i] < kb[i] end
    end
    return false
  end)
  for _, p in pairs(list) do
    if coverage_ok(p, plan) and grid_ok(p, plan) then
      plan.remove[#plan.remove + 1] = p
    end
  end
  return plan
end

--- add the wires, then mark the poles; a wire that can't be made (its connector full) keeps the poles relying on it
local function apply(plan, player)
  for _, w in pairs(plan.wires) do
    local a, b = w[1], w[2]
    if a.valid and b.valid then
      local ca, cb = a.get_wire_connector(COPPER, true), b.get_wire_connector(COPPER, true)
      if not ca.is_connected_to(cb) and not ca.connect_to(cb, false) then
        return 0, "a pole has no free wire slot; nothing removed"
      end
    end
  end
  local n = 0
  for _, p in pairs(plan.remove) do
    if p.valid and p.order_deconstruction(p.force, player) then n = n + 1 end
  end
  return n
end

local function show(plan, player)
  for _, p in pairs(plan.remove) do
    rendering.draw_circle({ color = { r = 1, g = 0.3, b = 0, a = 0.6 }, radius = 0.6, width = 4, target = p,
      surface = p.surface, players = { player }, time_to_live = 600 })
  end
  for _, w in pairs(plan.wires) do
    rendering.draw_line({ color = { r = 0.2, g = 0.8, b = 1 }, width = 2, from = w[1], to = w[2],
      surface = w[1].surface, players = { player }, time_to_live = 600 })
  end
end

script.on_event(defines.events.on_player_selected_area, function(e)
  if e.item ~= "pole-tidy-tool" then return end
  local player = game.get_player(e.player_index)
  local plan = make_plan(e.entities)
  local n, problem = apply(plan, player)
  player.create_local_flying_text({ create_at_cursor = true,
    text = problem or (n == 0 and "No redundant poles here" or (n .. " redundant pole(s) marked for removal")) })
end)

script.on_event(defines.events.on_player_alt_selected_area, function(e)
  if e.item ~= "pole-tidy-tool" then return end
  local player = game.get_player(e.player_index)
  local plan = make_plan(e.entities)
  show(plan, player)
  player.create_local_flying_text({ create_at_cursor = true,
    text = #plan.remove == 0 and "No redundant poles here" or (#plan.remove .. " pole(s) would go (shown for 10 s)") })
end)

-- auto mode: poles upgraded (by Upgradeable Quality, an upgrade planner's bots, or another script) get their
-- neighbourhood tidied a moment later
-- the toggle: a button in the top-left mod button bar (mod-gui), lit while on
local mod_gui = require("mod-gui")
local BUTTON = "pole_tidy_auto"

-- (GUI Unifyer reskins the mod button bar but knows only its own list of buttons: ours take its button style, its
-- "_selected" one while on, so they match the others)
local function gu_style(button, on)
  local base
  if script.active_mods["GUI_Unifyer"] or script.active_mods["GUI_Unifyer_Unified"] then
    local ok, s = pcall(function() return game.get_player(button.player_index).mod_settings["gu_button_style_setting"] end)
    base = ok and s and s.value
  end
  local styles = prototypes.style  -- (built anew on each read)
  if not (base and styles[base]) then
    button.style = mod_gui.button_style
    button.toggled = on == true
    return
  end
  local selected = base .. "_selected"
  if on and styles[selected] then
    button.style = selected
    button.toggled = false
  else
    button.style = base
    button.toggled = on == true
  end
end

local function sync_toggle()
  for _, p in pairs(game.players) do
    local flow = mod_gui.get_button_flow(p)
    local b = flow[BUTTON] or flow.add({ type = "sprite-button", name = BUTTON, sprite = "item/medium-electric-pole",
      style = mod_gui.button_style, tooltip = { "pole-tidy.auto-tooltip" } })
    gu_style(b, storage.auto == true)
  end
end

script.on_event(defines.events.on_gui_click, function(e)
  if not (e.element.valid and e.element.name == BUTTON) then return end
  storage.auto = not storage.auto
  sync_toggle()
  game.get_player(e.player_index).print(storage.auto and "Auto pole tidy on: poles made redundant by upgraded poles are removed by bots."
    or "Auto pole tidy off.")
end)

local function on_pole_built(e)
  if not storage.auto then return end
  local pole = e.entity
  if not (pole and pole.valid and pole.type == "electric-pole") or is_hidden(pole) then return end
  storage.pending = storage.pending or {}
  if #storage.pending < 200 then storage.pending[#storage.pending + 1] = pole end
end

local filter = { { filter = "type", type = "electric-pole" } }
script.on_event(defines.events.script_raised_built, on_pole_built, filter)
script.on_event(defines.events.on_robot_built_entity, on_pole_built, filter)

-- one upgraded pole per second (Upgradeable Quality upgrades many at once: spread them out)
script.on_nth_tick(60, function()
  local pending = storage.pending
  if not pending or #pending == 0 then return end
  local pole = table.remove(pending, 1)
  if pole.valid then
    local r = math.max(wire_reach(pole), supply(pole)) + 1
    local p = pole.position
    local near = pole.surface.find_entities_filtered({ type = "electric-pole", force = pole.force,
      area = { { p.x - r, p.y - r }, { p.x + r, p.y + r } } })
    bfs_limit = AUTO_BFS_LIMIT
    apply(make_plan(near, pole))
    bfs_limit = BFS_LIMIT
  end
end)

script.on_init(function()
  storage.auto = false
  storage.pending = {}
  sync_toggle()
end)
script.on_configuration_changed(sync_toggle)
script.on_event(defines.events.on_player_created, sync_toggle)
script.on_event(defines.events.on_runtime_mod_setting_changed, function(e)
  if e.setting == "gu_button_style_setting" then sync_toggle() end
end)
script.on_event(defines.events.on_player_joined_game, sync_toggle)

-- for automated tests
remote.add_interface("pole-tidy", {
  plan = function(poles)
    local plan = make_plan(poles)
    return #plan.remove, #plan.wires
  end,
  tidy = function(poles)
    return apply(make_plan(poles))
  end,
  set_auto = function(on)
    storage.auto = on
    sync_toggle()
  end,
})
