local Dispatcher = require("dispatcher")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

-- Extend WidgetContainer like Calibre does
local Estekhareh = WidgetContainer:extend {
    name = "Estekhareh.",
    is_doc_only = false,
}

-- Dynamically get the path where this plugin is located
local function current_plugin_dir()
    -- debug.getinfo(1, "S").source returns "@path/to/file"
    -- sub(2) removes the '@'
    return debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])")
end

local KINDLE_PLUGIN_DIR = current_plugin_dir()
-- Fallback if dynamic path fails
if not KINDLE_PLUGIN_DIR then
    KINDLE_PLUGIN_DIR = "/mnt/us/koreader/plugins/estekhareh.koplugin/"
end

local SCRIPT_PATH = KINDLE_PLUGIN_DIR .. "rand.sh"

local function file_exists(path)
    local f = io.open(path, "r")
    if f then
        f:close()
        return true
    end
    return false
end

function Estekhareh:init()
    self:onDispatcherRegisterActions()

    -- FIX: Use UIManager directly. 'self.ui' might be nil at this stage.
    if UIManager.menu then
        UIManager.menu:registerToMainMenu(self)
        -- Also register to the reading screen (document) menu
        if UIManager.menu.registerToDocumentMenu then
            UIManager.menu:registerToDocumentMenu(self)
        end
    else
        print("Estekhareh: UIManager.menu is not available.")
    end
end

function Estekhareh:onDispatcherRegisterActions()
    Dispatcher:registerAction("estekhareh_run_script", {
        category = "none",
        event = "EstekharehRunScript",
        title = _("Ask Estekhareh."),
        general = true,
    })
    --Dispatcher:registerAction("run_sh_script", {
    --	category = "none",
    --	event = "RunCustomScript",
    --	title = _("Run Any script"),
    --	general = true,
    --})
end

-- Handler for the legacy event (backward compatibility)
function Estekhareh:onEstRunScript()
    self:runScript()
    return true
end

-- Handler for the event registered above (new name)
function Estekhareh:onEstekharehRunScript()
    self:runScript()
    return true
end

-- Handler for the event registered above
function Estekhareh:onRunCustomScript()
    self:runScript()
    return true
end

function Estekhareh:runScript()
    if not file_exists(SCRIPT_PATH) then
        UIManager:show(InfoMessage:new { text = _("rand.sh not found at: ") .. (SCRIPT_PATH or "unknown") })
        return
    end

    -- Run the script synchronously and capture its output
    local cmd = string.format("sh '%s' 2>&1", SCRIPT_PATH)
    local handle = io.popen(cmd)
    local output = handle and handle:read("*a") or ""
    local success, reason, code = true, "exit", 0
    if handle then
        local ok, why, status = handle:close()
        success, reason, code = ok, why, status
    else
        success = false
    end

    local function trim(s)
        return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
    end
    output = trim(output)

    local msg
    if not success then
        msg = string.format(_("rand.sh failed (%s %s). Output:\n%s"), tostring(reason), tostring(code),
            output ~= "" and output or _("(no output)"))
    else
        msg = output ~= "" and output or _("rand.sh finished with no output.")
    end

    UIManager:show(InfoMessage:new { text = msg })
end

-- Called by KOReader when constructing the menu
function Estekhareh:addToMainMenu(menu_items)
    menu_items.estekhareh = {
        text = _("Estekhareh."),
        -- Show an icon in the main menu
        icon = "appbar.menu",
        sub_item_table = {
            {
                text = _("Run rand.sh"),
                callback = function()
                    self:runScript()
                end,
            },
        },
    }
end

-- Called by KOReader when constructing the reader (document) menu
function Estekhareh:addToDocumentMenu(menu_items)
    -- Reuse the same structure as in the main menu
    menu_items.Estekhareh = {
        text = _("Estekhareh"),
        -- Show an icon in the reader/document menu
        icon = "appbar.menu",
        sub_item_table = {
            {
                text = _("Run rand.sh"),
                callback = function()
                    self:runScript()
                end,
            },
        },
    }
end

-- search options available from UI
--function Estekhareh:getSearchMenuTable()
--	return {
--		{
--			text = _("Manage Scripts"),
--			separator = true,
--			keep_menu_open = true,
--			sub_item_table_func = function()
--				local result = {}
--				-- append previous scanned dirs to the list.
--
--				--for path, _ in pairs(cache.data) do
--				--	table.insert(result, {
--				--		text = path,
--				--		keep_menu_open = true,
--				--		checked_func = function()
--				--			return cache:isTrue(path)
--				--		end,
--				--		callback = function()
--				--			cache:toggle(path)
--				--			cache:flush()
--				--			CalibreSearch:invalidateCache()
--				--		end,
--				--	})
--				--end
--
--				-- if there's no result then no libraries are stored
--				if #result == 0 then
--					table.insert(result, {
--						text = _("No scripts yet"),
--						enabled = false
--					})
--				end
--
--				table.insert(result, 1, {
--					text = _("create a new script"),
--					separator = true,
--					callback = function()
--						CalibreSearch:prompt()
--					end,
--				})
--				return result
--			end,
--		},
--		{
--			text = _("Enable searches in the reader"),
--			checked_func = function()
--				return G_reader_settings:isTrue("calibre_search_from_reader")
--			end,
--			callback = function()
--				G_reader_settings:toggle("calibre_search_from_reader")
--				UIManager:show(InfoMessage:new{
--					text = _("This will take effect on next restart."),
--				})
--			end,
--		},
--		{
--			text = _("Store metadata in cache"),
--			checked_func = function()
--				return G_reader_settings:nilOrTrue("calibre_search_cache_metadata")
--			end,
--			callback = function()
--				G_reader_settings:flipNilOrTrue("calibre_search_cache_metadata")
--			end,
--		},
--		{
--			text = _("Case sensitive search"),
--			checked_func = function()
--				return not G_reader_settings:nilOrTrue("calibre_search_case_insensitive")
--			end,
--			callback = function()
--				G_reader_settings:flipNilOrTrue("calibre_search_case_insensitive")
--			end,
--		},
--		{
--			text = _("Search by title"),
--			checked_func = function()
--				return G_reader_settings:nilOrTrue("calibre_search_find_by_title")
--			end,
--			callback = function()
--				G_reader_settings:flipNilOrTrue("calibre_search_find_by_title")
--			end,
--		},
--		{
--			text = _("Search by authors"),
--			checked_func = function()
--				return G_reader_settings:nilOrTrue("calibre_search_find_by_authors")
--			end,
--			callback = function()
--				G_reader_settings:flipNilOrTrue("calibre_search_find_by_authors")
--			end,
--		},
--		{
--			text = _("Search by series"),
--			checked_func = function()
--				return G_reader_settings:isTrue("calibre_search_find_by_series")
--			end,
--			callback = function()
--				G_reader_settings:toggle("calibre_search_find_by_series")
--			end,
--		},
--		{
--			text = _("Search by tag"),
--			checked_func = function()
--				return G_reader_settings:isTrue("calibre_search_find_by_tag")
--			end,
--			callback = function()
--				G_reader_settings:toggle("calibre_search_find_by_tag")
--			end,
--		},
--		{
--			text = _("Search by path"),
--			checked_func = function()
--				return G_reader_settings:isTrue("calibre_search_find_by_path")
--			end,
--			callback = function()
--				G_reader_settings:toggle("calibre_search_find_by_path")
--			end,
--		},
--	}
--end

return Estekhareh
