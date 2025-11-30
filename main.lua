    function Launcher:showQuickMenu()
        -- Quick access menu opened from the toolbar button
        local ok, menu = pcall(function()
            return Menu:new{
                title = _("Launcher"),
                item_table = self:getLauncherMenuTable(),
                is_borderless = true,
                is_popout = false,
                onMenuSelect = function(item)
                    if item.callback then
                        item.callback()
                    end
                end,
            }
        end)
        if ok and menu then
            UIManager:show(menu)
        else
            UIManager:show(InfoMessage:new{ text = _("Failed to open launcher menu") })
        end
    end
