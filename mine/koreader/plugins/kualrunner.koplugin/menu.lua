local _ = require("gettext")

local Menu = {}

function Menu:setup_ui_integration()
    if self.ui and self.ui.menu then
        self.ui.menu:registerToMainMenu(self)
    end
end

local function make_run_item(self, code, cmd)
    return {
        text = string.format("%s → %s", code, cmd),
        callback = function()
            self:runCode(code)
        end,
    }
end

function Menu:addToMainMenu(menu_items)
    if not menu_items  then return end

    -- Build dynamic list of mapped codes
    local mapped_list = { }
    if self.mappings then
        for code, cmd in pairs(self.mappings) do
            table.insert(mapped_list, make_run_item(self, code, cmd))
        end
        table.sort(mapped_list, function(a, b) return a.text < b.text end)
    end

    table.insert(menu_items.sub_item_table, {
        text = _("KUAL Runner"),
        help_text = _([[Run KUAL-style codes and manage their mappings.]]),
        sub_item_table = {
            {
                text = _("Run code…"),
                callback = function() self:promptRunCode() end,
            },
            {
                text = _("Mapped codes"),
                enabled_func = function() return self.mappings and next(self.mappings) ~= nil end,
                sub_item_table = mapped_list,
            },
            {
                text = _("Add mapping…"),
                callback = function() self:promptAddMapping() end,
            },
            {
                text = _("Remove mapping…"),
                callback = function() self:promptRemoveMapping() end,
            },
        }
    })
end

return Menu
