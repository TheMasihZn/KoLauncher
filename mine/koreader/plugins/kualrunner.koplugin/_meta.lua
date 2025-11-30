local _ = require("gettext")
return {
    name = "kualrunner",
    fullname = _("KUAL Runner"),
    description = _([[Run KUAL-style search bar codes (e.g., ;un) directly from KOReader by mapping them to the underlying shell scripts.]]),
    icon = "appbar.console",
    version = "0.1.0",
    author = "Junie",
    license = "MIT",
    category = "tools",
    conflicts = {},
    requires = {},
    sorting_hint = "kualrunner",
    priority = 1,
    configurable = true,
    main = "main",
}
