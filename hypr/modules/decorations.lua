-----------------------
---- LOOK AND FEEL ----
-----------------------
local status, matugen = pcall(require, "colors.matugen")
local active1 = status and matugen.primary
local inactive = status and matugen.surface_container

hl.config({
  general = {
    gaps_in          = 5,
    gaps_out         = 10,

    border_size      = 0,

    col              = {
      active_border   = { colors = { active1 }, angle = 45 },
      inactive_border = inactive,
    },

    -- Set to true to enable resizing windows by clicking and dragging on borders and gaps
    resize_on_border = false,

    -- Please see https://wiki.hypr.land/Configuring/Advanced-and-Cool/Tearing/ before you turn this on
    allow_tearing    = false,

    layout           = "scrolling",
  },

  decoration = {
    rounding         = 20,
    rounding_power   = 2,

    -- Change transparency of focused and unfocused windows
    active_opacity   = 1.0,
    inactive_opacity = 0.9,

    shadow           = {
      enabled      = true,
      range        = 4,
      render_power = 3,
      color        = 0xee1a1a1a,
    },

    blur             = {
      enabled  = true,
      size     = 4,
      passes   = 2,
      vibrancy = 0.35,
      vibrancy_darkness = 0.35,
      brightness = 0.8,
      contrast = 2,
      special = false,
    },
  },

  animations = {
    enabled = true,
  },
})
