local Dispatcher = require("dispatcher")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local Menu = require("menu")

local SETTINGS_KEY = "kualrunner_mappings"

local KualRunner = WidgetContainer:extend{
    name = "kualrunner",
    is_doc_only = false,
}

function KualRunner:init()
    self:_loadMappings()
    if self.setup_ui_integration then
        self:setup_ui_integration()
    end
end

function KualRunner:_defaultMappings()
    return {
        [";un"] = "sh /mnt/us/extensions/usbnet/bin/usbnetwork toggle",
        [";mrpi"] = "sh /mnt/us/extensions/MRInstaller/bin/mrpi.sh",
        [";alpine"] = "sh /mnt/us/Desktop/alpine/scripts/start_gui.sh",
    }
end

function KualRunner:_loadMappings()
    local saved = G_reader_settings:readSetting(SETTINGS_KEY)
    if type(saved) ~= "table" then
        self.mappings = self:_defaultMappings()
        G_reader_settings:saveSetting(SETTINGS_KEY, self.mappings)
    else
        -- ensure defaults are present but don't overwrite user values
        self.mappings = saved
        for k, v in pairs(self:_defaultMappings()) do
            if self.mappings[k] == nil then
                self.mappings[k] = v
            end
        end
        G_reader_settings:saveSetting(SETTINGS_KEY, self.mappings)
    end
end

function KualRunner:_saveMappings()
    G_reader_settings:saveSetting(SETTINGS_KEY, self.mappings)
end

local function trim(s)
    return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

function KualRunner:_runCommand(cmd)
    -- Try to capture output; fallback to plain execute
    local output = ""
    local ok = false
    local handle = io.popen(cmd .. " 2>&1")
    if handle then
        output = handle:read("*a") or ""
        ok = handle:close() and true or false
    else
        ok = os.execute(cmd) == 0
    end
    return ok, output
end

function KualRunner:runCode(code)
    code = trim(code)
    if code == "" then
        UIManager:show(InfoMessage:new{ text = _("Empty code."), timeout = 2 })
        return
    end
    if not code:match("^;") then
        code = ";" .. code
    end
    local cmd = self.mappings[code]
    if not cmd then
        UIManager:show(InfoMessage:new{ text = string.format(_("No mapping for %s"), code), timeout = 3 })
        return
    end

    UIManager:show(InfoMessage:new{ text = string.format(_("Running %s..."), code), timeout = 1 })
    UIManager:scheduleIn(0, function()
        local ok, out = self:_runCommand(cmd)
        if ok then
            local msg = out ~= "" and out or _("Done.")
            UIManager:show(InfoMessage:new{ text = msg, timeout = 3 })
        else
            local msg = out ~= "" and out or _("Failed.")
            UIManager:show(InfoMessage:new{ text = msg, timeout = 4 })
        end
    end)
end

function KualRunner:promptRunCode()
    local dlg
    dlg = InputDialog:new{
        title = _("Run KUAL code"),
        input = ";un",
        input_hint = _("Enter code like ;un, ;mrpi, ;711"),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function() UIManager:close(dlg) end,
                },
                {
                    text = _("Run"),
                    is_enter_default = true,
                    callback = function()
                        local code = dlg:getInputText()
                        UIManager:close(dlg)
                        self:runCode(code)
                    end,
                },
            },
        },
    }
    UIManager:show(dlg)
end

function KualRunner:promptAddMapping()
    local dlg
    local default_text = ";code => sh /path/to/script arg"
    dlg = InputDialog:new{
        title = _("Add mapping"),
        input = default_text,
        input_hint = _("Format: ;code => command"),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function() UIManager:close(dlg) end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local line = dlg:getInputText() or ""
                        UIManager:close(dlg)
                        local code, cmd = line:match("^%s*(;[^%s=]+)%s*=>%s*(.+)%s*$")
                        if not code or not cmd then
                            UIManager:show(InfoMessage:new{ text = _("Invalid format. Use: ;code => command") })
                            return
                        end
                        self.mappings[code] = cmd
                        self:_saveMappings()
                        UIManager:show(InfoMessage:new{ text = string.format(_("Saved mapping for %s"), code), timeout = 2 })
                    end,
                },
            },
        },
    }
    UIManager:show(dlg)
end

function KualRunner:promptRemoveMapping()
    local dlg
    dlg = InputDialog:new{
        title = _("Remove mapping"),
        input = ";un",
        input_hint = _("Enter code to remove (e.g., ;un)"),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function() UIManager:close(dlg) end,
                },
                {
                    text = _("Remove"),
                    is_enter_default = true,
                    callback = function()
                        local code = trim(dlg:getInputText())
                        UIManager:close(dlg)
                        if code ~= "" and not code:match("^;") then code = ";" .. code end
                        if self.mappings[code] then
                            self.mappings[code] = nil
                            self:_saveMappings()
                            UIManager:show(InfoMessage:new{ text = string.format(_("Removed %s"), code), timeout = 2 })
                        else
                            UIManager:show(InfoMessage:new{ text = _("No such mapping."), timeout = 2 })
                        end
                    end,
                },
            },
        },
    }
    UIManager:show(dlg)
end

-- Mixin menu methods
for k, v in pairs(Menu) do
    KualRunner[k] = v
end

return KualRunner
