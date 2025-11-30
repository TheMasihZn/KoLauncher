local Dispatcher = require("dispatcher")
local UIManager = require("ui/uimanager")
local Event = require("ui/event")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local Device = require("device")
-- Use this plugin's own menu module (was mistakenly pointing to replace.koplugin)
local Menu = require("plugins/usbauto.koplugin.menu")

-- USB Auto-Mount plugin implemented from the REPLACE template
local UsbAuto = WidgetContainer:extend{
    name = "usbauto",
    is_doc_only = false,
}

local SETTING_KEY = "usbauto_enabled"

function UsbAuto:isEnabled()
    return G_reader_settings:isTrue(SETTING_KEY)
end

function UsbAuto:init()
    self:registerActions()
    -- Defer all menu/toolbar integration to the separated menu module
    if self.setup_ui_integration then
        self:setup_ui_integration()
    end
end

function UsbAuto:registerActions()
    -- Optional: action to manually trigger USBMS
    Dispatcher:registerAction("usbauto_request_mass_storage", {
        category = "none",
        event = "UsbAutoRequestMassStorage",
        title = _("USB: Start mass storage"),
        general = true,
    })
end

-- Action handler: manually request USBMS
function UsbAuto:onUsbAutoRequestMassStorage()
    if Device:canToggleMassStorage() then
        local MassStorage = require("ui/elements/mass_storage")
        UIManager:flushSettings()
        MassStorage:start(false)
    else
        -- Kindle path: let the native system take over by exiting KOReader
        UIManager:flushSettings()
        UIManager:broadcastEvent(Event:new("Close"))
        UIManager:quit(86)
    end
    return true
end

-- Event handler: automatically enter USBMS when charging starts
function UsbAuto:onCharging()
    if not self:isEnabled() then return end
    if Device:canToggleMassStorage() then
        local MassStorage = require("ui/elements/mass_storage")
        MassStorage:start(false)
    else
        -- On devices like Kindle where KOReader cannot toggle USBMS,
        -- exit KOReader so the system's USBMS can take over immediately.
        UIManager:flushSettings()
        UIManager:broadcastEvent(Event:new("Close"))
        UIManager:quit(86)
    end
end

-- Mixin menu/toolbar methods from the separate module
for k, v in pairs(Menu) do
    UsbAuto[k] = v
end

return UsbAuto
