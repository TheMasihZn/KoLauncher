local Dispatcher = require("dispatcher")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
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
    if not a or a == "" then return b end
    if a:sub(-1) == "/" then return a .. b end
    return a .. "/" .. b
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
    PLUGIN_DIR = (debug.getinfo(1, "S").source or ""):gsub("^@", ""):match("(.*[/\\])") or "/mnt/us/koreader/plugins/Launcher.koplugin/"
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
        on_select = function() end,
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
    dlg = InputDialog:new{
        title = _("Create launcher"),
        fields = {
            { id = "name", label = _("Name"), text = "My Script" },
            { id = "path", label = _("Absolute path to .sh"), text = "/mnt/us/" },
        },
        buttons = {
            {
                { text = _("Browse"), icon = "appbar.folder.open", callback = function()
                    self:openFileChooser(function(chosen)
                        if chosen then dlg:setValue("path", chosen) end
                    end)
                end },
                { text = _("Save"), callback = function()
                    self:saveFromDialog(dlg, false)
                end },
                { text = _("Run and save"), icon = "appbar.player.play", callback = function()
                    self:saveFromDialog(dlg, true)
                end },
                { id = "close", text = _("Cancel") },
            }
        },
    }
    UIManager:show(dlg)
end

function Launcher:openFileChooser(on_done)
    local chooser = FileChooser:new{
        title = _("Choose .sh file"),
        path = "/mnt/us",
        select_file = true,
        file_filter = function(name) return name:match("%.sh$") end,
        on_apply = function(path)
            UIManager:close(chooser)
            if on_done then on_done(path) end
        end,
        on_cancel = function()
            UIManager:close(chooser)
            if on_done then on_done(nil) end
        end,
    }
    UIManager:show(chooser)
end

function Launcher:saveFromDialog(dlg, do_run)
    local name = trim(dlg:getValue("name"))
    local path = trim(dlg:getValue("path"))
    if name == "" or path == "" then
        UIManager:show(InfoMessage:new{ text = _("Please provide both name and path.") })
        return
    end
    if not file_exists(path) then
        UIManager:show(InfoMessage:new{ text = _("File not found: ") .. path })
        return
    end

    -- copy to Desktop and chmod
    local copy_out = copy_and_chmod(path, DESKTOP_DIR)
    -- persist
    local saved = self:getSaved()
    saved[#saved + 1] = { name = name, source = path, desktop = path_join(DESKTOP_DIR, path:match("([^/]+)$")), time = os.time() }
    self:saveSaved(saved)

    -- add alias to terminal emulator (best-effort; feature marker [optional])
    -- [optional] This requires KOReader terminal emulator alias API, if present.
    pcall(function()
        local TermAliases = require("apps/terminal/aliases")
        if TermAliases and TermAliases.addAlias then
            TermAliases.addAlias(name, string.format("sh '%s'", saved[#saved].desktop))
        end
    end)

    UIManager:show(InfoMessage:new{ text = _("Saved to Desktop. ") .. copy_out })
    UIManager:close(dlg)

    if do_run then
        self:executeAndDisplay(saved[#saved].desktop)
    end
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
