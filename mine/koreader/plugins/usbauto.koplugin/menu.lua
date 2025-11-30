local _ = require("gettext")

local Menu = {}

local SETTING_KEY = "usbauto_enabled"

function Menu:setup_ui_integration()
    if self.ui and self.ui.menu then
        self.ui.menu:registerToMainMenu(self)
    end
end

function Menu:addToMainMenu(menu_items)
    if not menu_items or not menu_items.developer_options then return end
    if not menu_items.developer_options.sub_item_table then return end

    table.insert(menu_items.developer_options.sub_item_table, {
        text = _("USB"),
        help_text = _([[Toggle automatic USB Mass Storage when a USB cable is connected.]]),
        checked_func = function()
            return G_reader_settings:isTrue(SETTING_KEY)
        end,
        callback = function()
            G_reader_settings:flipNilOrFalse(SETTING_KEY)
        end,
    })
end

return Menu