-- Personal workstation overrides. Keep baseline rules for disconnected outputs
-- here; the shell writes confirmed runtime changes to hypr-monitor-generated.lua.
hl.monitor({
    output   = "DP-1",
    mode     = "3840x2160@144",
    position = "0x0",
    scale    = 1.5,
})

hl.monitor({
    output   = "DP-3",
    mode     = "3440x1440@200",
    position = "-3440x0",
    scale    = 1,
})

hl.config({
    input = {
        sensitivity = -1,
    },
    cursor = {
        hotspot_padding = 0,
    },
    xwayland = {
        force_zero_scaling = true,
    },
})
