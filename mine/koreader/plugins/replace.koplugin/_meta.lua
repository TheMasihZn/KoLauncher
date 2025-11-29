local _ = require("gettext")
return {
    name = "REPLACE",             -- Internal plugin identifier used in code (e.g., "dictionary", "clock", "wifi")
    fullname = _("REPLACE"),      -- Display name shown in UI (translatable) (e.g., "Dictionary", "Clock Widget", "WiFi Manager")
    description = _([[REPLACE]]), -- Plugin description shown in manager (translatable) (e.g., "Provides dictionary lookup functionality")
    icon = "appbar.menu",         -- Use a built-in KOReader icon to avoid external assets
    version = "1.0.0",            -- Plugin version for updates (e.g., "1.2.3", "0.9.0")
    author = "REPLACE",           -- Plugin creator/maintainer (e.g., "John Doe", "KOReader Team")
    license = "REPLACE",          -- Software license (e.g., "AGPL", "MIT", "GPL-3.0")
    category = "tools",           -- Show this plugin under the Tools menu
    conflicts = {},               -- List of incompatible plugins (e.g., {"old_dictionary", "legacy_widget"})
    requires = {},                -- List of required plugins (e.g., {"base_widget", "settings"})
    sorting_hint = "replace",     -- Hint for menu sorting (e.g., "dictionary", "zzz_last")
    priority = 1,                 -- Plugin loading order priority (e.g., 1 for highest, 100 for lowest)
    configurable = true,          -- Whether plugin has settings (true/false)
    main = "main",                -- Entry point module name (e.g., "main", "init")
}
