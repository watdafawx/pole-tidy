local icon = "__base__/graphics/icons/medium-electric-pole.png"

data:extend({
  {
    type = "selection-tool",
    name = "pole-tidy-tool",
    icon = icon,
    icon_size = 64,
    flags = { "only-in-cursor", "not-stackable", "spawnable" },
    subgroup = "tool",
    order = "z[pole-tidy]",
    stack_size = 1,
    draw_label_for_cursor_render = true,
    select = {
      border_color = { r = 1, g = 0.5, b = 0 },
      cursor_box_type = "not-allowed",
      mode = { "same-force", "any-entity" },
      entity_type_filters = { "electric-pole" },
    },
    alt_select = {
      border_color = { r = 0.2, g = 0.8, b = 1 },
      cursor_box_type = "entity",
      mode = { "same-force", "any-entity" },
      entity_type_filters = { "electric-pole" },
    },
  },
  {
    type = "shortcut",
    name = "pole-tidy-tool",
    order = "b[blueprints]-p[pole-tidy]",
    action = "spawn-item",
    item_to_spawn = "pole-tidy-tool",
    icon = icon,
    icon_size = 64,
    small_icon = icon,
    small_icon_size = 64,
  },
})
