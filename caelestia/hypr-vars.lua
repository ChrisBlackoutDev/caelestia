local config_home = os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")
local scheme = require("scheme.current")

return {
    editor            = "code",
    hyprScripts       = config_home .. "/hypr/scripts",
    blurPopups        = false,
    blurInputMethods  = false,
    blurSize          = 4,
    blurPasses        = 1,
    shadowRange       = 8,
    shadowRenderPower = 2,
    shadowColour      = "rgba(" .. scheme.surface .. "d4)",
    windowOpacity     = 1.0,
}
