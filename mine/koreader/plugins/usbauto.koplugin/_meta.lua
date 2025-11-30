local _ = require("gettext")
return {
    name = "usbauto",
    fullname = _("USB Auto-Mount"),
    description = _([[Automatically enter USB Mass Storage when a USB cable is connected. Adds a Debug/Developer menu toggle to enable or disable this behavior.]]),
    icon = "appbar.usb",
    version = "1.0.0",
    author = "KoLauncher",
    license = "MIT",
    category = "tools",
    conflicts = {},
    requires = {},
    sorting_hint = "usb",
    priority = 50,
    configurable = true,
    main = "main",
}
