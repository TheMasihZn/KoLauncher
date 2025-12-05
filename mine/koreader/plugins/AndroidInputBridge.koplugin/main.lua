local Dispatcher = require("dispatcher")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local Menu = require("plugins/replace.koplugin.menu")

-- Minimal KOReader plugin skeleton for REPLACE
local AndroidInputBridge = WidgetContainer:extend{
    name = "AndroidInputBridge",
    is_doc_only = false,
}

function AndroidInputBridge:init()
    self:registerActions()
    -- Defer all menu/toolbar integration to the separated menu module
    if self.setup_ui_integration then
        self:setup_ui_integration()
    end
end

function AndroidInputBridge:registerActions()
    Dispatcher:registerAction("replace_show_message", {
        category = "none",
        event = "ReplaceShowMessage",
        title = _("REPLACE: Show message"),
        general = true,
    })
end

-- Action handler
function AndroidInputBridge:onReplaceShowMessage()
    UIManager:show(InfoMessage:new{ text = _("Hello from REPLACE plugin!") })
    return true
end

-- Mixin menu/toolbar methods from the separate module
for k, v in pairs(Menu) do
    AndroidInputBridge[k] = v
end

return AndroidInputBridge
