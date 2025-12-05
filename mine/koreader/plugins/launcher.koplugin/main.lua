local Dispatcher = require("dispatcher")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local ConfirmBox = require("ui/widget/confirmbox")
local Menu = require("ui/widget/menu")
local FileChooser = require("ui/widget/filechooser")
local LuaSettings = require("luasettings")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local Launcher = WidgetContainer:extend{
    name = "Launcher",
    is_doc_only = false,
}

-- Utils
local function trim(s) return (s or ""):gsub("^%s+", ""):gsub("%s+$", "") end

local function path_join(a, b)
    if not a or not b then return "" end
    if a:sub(-1) == "/" then
        return a .. b
    else
        return a .. "/" .. b
    end
end

local DESKTOP_DIR = "/mnt/us/Desktop"
local SETTINGS_KEY = "launcher_saved_scripts"
local settings = LuaSettings:open("launcher_settings.lua")
local PLUGIN_DIR -- set in init() lazily

local function ensure_dir(path)
    os.execute(string.format("mkdir -p '%s' 2>/dev/null || true", path))
end

local function file_exists(path)
    local f = io.open(path, "r")
    if f then f:close() return true end
    return false
end

local function read_dir_sh(dir)
    local p = io.popen(string.format("ls -1 '%s' 2>/dev/null", dir))
    if not p then return {} end
    local files = {}
    for line in p:lines() do
        if line:match("%.sh$") then table.insert(files, line) end
    end
    p:close()
    table.sort(files)
    return files
end

local function copy_and_chmod(src, dst_dir)
    ensure_dir(dst_dir)
    local cmd = string.format("cp '%s' '%s' 2>&1 && chmod +x '%s/%s' 2>&1", src, dst_dir, dst_dir, src:match("([^/]+)$"))
    local ph = io.popen(cmd)
    local out = ph and ph:read("*a") or ""
    if ph then ph:close() end
    return out
end

local function run_script(path)
    local cmd = string.format("sh '%s' 2>&1", path)
    local h = io.popen(cmd)
    local out = h and h:read("*a") or ""
    local ok, why, code = true, "exit", 0
    if h then
        local c_ok, c_why, c_code = h:close()
        ok, why, code = c_ok, c_why, c_code
    else ok = false end
    return ok, why, code, trim(out)
end

local function is_url(s)
    return s and s:match("^https?://")
end

function Launcher:init()
    -- register actions and menu
    self:onDispatcherRegisterActions()
    -- discover plugin dir for icon lookups
    PLUGIN_DIR = (debug.getinfo(1, "S").source or ""):gsub("^@", ""):match("(.*[/\\])") or "/mnt/us/koreader/plugins/launcher.koplugin/"
    -- Register to menus (support both UIManager and self.ui paths depending on KOReader build)
    local menu_registered = false
    if UIManager and UIManager.menu and UIManager.menu.registerToMainMenu then
        UIManager.menu:registerToMainMenu(self)
        if UIManager.menu.registerToDocumentMenu then
            UIManager.menu:registerToDocumentMenu(self)
        end
        menu_registered = true
    end
    if not menu_registered and self.ui and self.ui.menu and self.ui.menu.registerToMainMenu then
        self.ui.menu:registerToMainMenu(self)
        if self.ui.menu.registerToDocumentMenu then
            self.ui.menu:registerToDocumentMenu(self)
        end
        menu_registered = true
    end
    if not menu_registered then
        print("Launcher: menu API not found; falling back to toolbar only (if available).")
    end

    -- Try registering to toolbars if available in this KOReader build (support both UIManager and self.ui)
    local toolbar_registered = false
    if UIManager and UIManager.toolbar and UIManager.toolbar.registerToMainToolbar then
        UIManager.toolbar:registerToMainToolbar(self)
        if UIManager.toolbar.registerToDocumentToolbar then
            UIManager.toolbar:registerToDocumentToolbar(self)
        end
        toolbar_registered = true
    end
    if not toolbar_registered and self.ui and self.ui.toolbar and self.ui.toolbar.registerToMainToolbar then
        self.ui.toolbar:registerToMainToolbar(self)
        if self.ui.toolbar.registerToDocumentToolbar then
            self.ui.toolbar:registerToDocumentToolbar(self)
        end
        toolbar_registered = true
    end
    if not toolbar_registered then
        print("Launcher: toolbar API not found; access via Tools → Launcher menu if available.")
    end
    ensure_dir(DESKTOP_DIR)
end

function Launcher:onDispatcherRegisterActions()
    Dispatcher:registerAction("launcher_create", { category = "tools", event = "LauncherCreate", title = _("Create launcher"), general = true })
    Dispatcher:registerAction("launcher_run_from_desktop", { category = "tools", event = "LauncherRunFromDesktop", title = _("Run from Desktop"), general = true })
end

function Launcher:addToMainMenu(menu_items)
    if menu_items.tools and type(menu_items.tools.sub_item_table) == "table" then
        table.insert(menu_items.tools.sub_item_table, {
            text = _("Launcher"),
            sub_item_table = self:getLauncherMenuTable(),
        })
    else
        -- Fallback: add as a top-level menu if Tools is not present
        menu_items.launcher = {
            text = _("Launcher"),
            sub_item_table = self:getLauncherMenuTable(),
        }
    end
end

function Launcher:addToDocumentMenu(menu_items)
    self:addToMainMenu(menu_items)
end

-- Toolbar integration
-- We aim to place a dedicated button next to the search field in the top bar.
-- We add to both the home (main) toolbar and the document (reading) toolbar.

local function get_icon_path()
    -- The user can drop a custom icon into plugins/Launcher.koplugin/icons/
    -- We will try several common filenames; fallback to a built-in appbar icon.
    local candidates = {
        "icons/launcher.png",
        "icons/launcher.svg",
        "icons/launcher.jpg",
    }
    for _, rel in ipairs(candidates) do
        local p = (PLUGIN_DIR or "") .. rel
        local f = io.open(p, "rb")
        if f then f:close(); return p end
    end
    return "appbar.toolbox"
end

function Launcher:_toolbarItem()
    return {
        id = "launcher_button",
        icon = get_icon_path(),
        -- Some skins show text on long-press/tooltip
        text = _("Launcher"),
        callback = function() self:showQuickMenu() end,
    }
end

local function insert_next_to_search(container, item)
    -- container may be a plain array, or a table with keys {left=..., right=...}
    local function try_list(list)
        if type(list) ~= "table" then return false end
        local idx_search
        for i, it in ipairs(list) do
            if it and (it.id == "search" or it.text == _("Search")) then
                idx_search = i; break
            end
        end
        if idx_search then
            table.insert(list, idx_search + 1, item)
            return true
        end
        return false
    end
    if container.right and try_list(container.right) then return true end
    if try_list(container) then return true end
    if container.right and type(container.right) == "table" then
        table.insert(container.right, item); return true
    end
    if container.left and type(container.left) == "table" then
        table.insert(container.left, item); return true
    end
    table.insert(container, item); return true
end

function Launcher:addToMainToolbar(toolbar_items)
    -- Defensive: toolbar_items is provided by KOReader; we'll insert our button near Search if possible.
    local item = self:_toolbarItem()
    insert_next_to_search(toolbar_items, item)
end

function Launcher:addToDocumentToolbar(toolbar_items)
    local item = self:_toolbarItem()
    insert_next_to_search(toolbar_items, item)
end

function Launcher:showQuickMenu()
    -- Quick access menu opened from the toolbar button
    local menu = Menu:new{
        title = _("Launcher"),
        item_table = self:getLauncherMenuTable(),
        is_borderless = true,
        is_popout = false,
    }
    UIManager:show(menu)
end

function Launcher:getSaved()
    return settings:readSetting(SETTINGS_KEY) or {}
end

function Launcher:saveSaved(t)
    settings:saveSetting(SETTINGS_KEY, t)
    settings:flush()
end

function Launcher:getLauncherMenuTable()
    local t = {
        {
            text = _("Create launcher"),
            icon = "appbar.add",
            keep_menu_open = false,
            enabled_func = function() return true end,
            callback = function() self:showCreateDialog() end,
        },
        { text = _("—"), separator = true },
    }
    -- list .sh scripts on Desktop
    local scripts = read_dir_sh(DESKTOP_DIR)
    if #scripts == 0 then
        table.insert(t, { text = _("No scripts found in /mnt/us/Desktop"), enabled = false })
    else
        for _, fname in ipairs(scripts) do
            local fpath = path_join(DESKTOP_DIR, fname)
            table.insert(t, {
                text = fname,
                keep_menu_open = false,
                callback = function()
                    self:executeAndDisplay(fpath)
                end,
            })
        end
    end
    return t
end

function Launcher:showCreateDialog()
    local dlg
    dlg = MultiInputDialog:new{
        title = _("Create new script"),
        fields = {
            {
                text = "",
                hint = _("Script name (without .sh)"),
            },
            {
                text = DESKTOP_DIR,
                hint = _("Destination folder"),
            },
        },
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dlg)
                    end,
                },
                {
                    text = _("Create"),
                    is_enter_default = true,
                    callback = function()
                        local fields = dlg:getFields()
                        local name = trim(fields[1] or "")
                        local dest_dir = trim(fields[2] or DESKTOP_DIR)
                        UIManager:close(dlg)

                        if name == "" then
                            UIManager:show(InfoMessage:new{ text = _("Please provide a script name.") })
                            return
                        end

                        -- Remove .sh if user added it
                        name = name:gsub("%.sh$", "")

                        -- Create the file path
                        ensure_dir(dest_dir)
                        local script_path = path_join(dest_dir, name .. ".sh")

                        -- Check if file already exists
                        if file_exists(script_path) then
                            UIManager:show(InfoMessage:new{ text = _("File already exists: ") .. script_path })
                            return
                        end

                        -- Create new script with template
                        local f = io.open(script_path, "w")
                        if not f then
                            UIManager:show(InfoMessage:new{ text = _("Failed to create file: ") .. script_path })
                            return
                        end

                        -- Write template content
                        f:write("#!/bin/sh\n")
                        f:write("# " .. name .. "\n")
                        f:write("# Created: " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n\n")
                        f:write("# Add your shell commands here\n\n")
                        f:close()

                        -- Make executable
                        os.execute(string.format("chmod +x '%s'", script_path))

                        -- Save to settings
                        local saved = self:getSaved()
                        saved[#saved + 1] = { name = name, source = script_path, desktop = script_path, time = os.time() }
                        self:saveSaved(saved)

                        -- Show success message
                        UIManager:show(InfoMessage:new{ 
                            text = _("Script created!\n\nReopen the Launcher menu to see it in the list.\n\nOpening editor..."),
                            timeout = 3,
                        })

                        -- Open in editor after a short delay
                        UIManager:scheduleIn(1, function()
                            self:openScriptInEditor(script_path)
                        end)
                    end,
                },
            },
        },
    }
    UIManager:show(dlg)
end



function Launcher:openScriptInEditor(script_path)
    -- Read current file content
    local file = io.open(script_path, "r")
    if not file then
        UIManager:show(InfoMessage:new{ text = _("Failed to open file: ") .. script_path })
        return
    end
    local content = file:read("*a")
    file:close()

    -- Create custom editor dialog
    local editor_dialog
    editor_dialog = InputDialog:new{
        title = script_path:match("([^/]+)$"),
        input = content,
        input_type = "text",
        text_type = "code",
        para_direction_rtl = false,
        fullscreen = true,
        condensed = false,
        allow_newline = true,
        cursor_at_end = false,
        buttons = {
            {
                {
                    text = _("Close"),
                    id = "close",
                    callback = function()
                        UIManager:close(editor_dialog)
                    end,
                },
                {
                    text = _("Save"),
                    callback = function()
                        local edited_content = editor_dialog:getInputText()
                        local f = io.open(script_path, "w")
                        if f then
                            f:write(edited_content)
                            f:close()
                            UIManager:show(InfoMessage:new{ 
                                text = _("Script saved successfully!"),
                                timeout = 2,
                            })
                        else
                            UIManager:show(InfoMessage:new{ text = _("Failed to save file") })
                        end
                    end,
                },
                {
                    text = _("Save & Run"),
                    is_enter_default = true,
                    callback = function()
                        local edited_content = editor_dialog:getInputText()
                        local f = io.open(script_path, "w")
                        if f then
                            f:write(edited_content)
                            f:close()
                            UIManager:close(editor_dialog)
                            UIManager:show(InfoMessage:new{ 
                                text = _("Running script..."),
                                timeout = 1,
                            })
                            UIManager:scheduleIn(0.5, function()
                                self:executeAndDisplay(script_path)
                            end)
                        else
                            UIManager:show(InfoMessage:new{ text = _("Failed to save file") })
                        end
                    end,
                },
            },
        },
    }
    UIManager:show(editor_dialog)
end



function Launcher:executeAndDisplay(path)
    local ok, why, code, output = run_script(path)
    if ok and is_url(output) then
        -- open browser if possible
        local opened = pcall(function()
            local Browser = require("apps/browser/browser")
            if Browser and Browser.openURL then Browser.openURL(output) end
        end)
        if opened then return end
    end

    -- [optional] Try render image if output points to an image file
    if ok and output:match("%.(png|jpg|jpeg|bmp)$") and file_exists(output) then
        pcall(function()
            local ImageViewer = require("apps/imageviewer/main")
            if ImageViewer and ImageViewer.openFile then
                ImageViewer.openFile(output)
                return
            end
        end)
    end

    local text = ok and output ~= "" and output or (ok and _("Command finished with no output.") or string.format(_("Failed (%s %s)\n%s"), tostring(why), tostring(code), output))

    -- Use InputDialog as a fullscreen editor with built-in Save/Close buttons.
    local outdlg
    outdlg = InputDialog:new{
        title = _("Script output"),
        input = text,
        allow_newline = true,
        fullscreen = true,
        condensed = true,
        close_button_text = _("Exit"),
        save_button_text = _("Save"),
        save_callback = function(content, closing)
            -- content is the possibly edited text
            local fname = os.date("%Y%m%d-%H%M%S") .. ".txt"
            local base = path:match("([^/]+)%.sh$") or "output"
            local dir = path_join(DESKTOP_DIR, base)
            ensure_dir(dir)
            local fp = path_join(dir, fname)
            local f = io.open(fp, "w")
            if not f then
                return false, _("Could not save output.")
            end
            f:write(content or "")
            f:close()
            return true, _("Saved to ") .. fp
        end,
    }
    UIManager:show(outdlg)
end

return Launcher
