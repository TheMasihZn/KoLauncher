local Dispatcher = require("dispatcher")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

-- Minimal KOReader plugin skeleton for CheetSheet
local CheetSheet = WidgetContainer:extend{
    name = "CheetSheet",
    is_doc_only = false,
}

function CheetSheet:init()
    self:registerActions()
    -- Register to menus (support both UIManager and self.ui depending on KOReader build)
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
        print("CheetSheet: menu API not found; falling back to toolbar only (if available).")
    end
    -- Also register to toolbars (top bar) if available (support both UIManager and self.ui)
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
        print("CheetSheet: toolbar API not found; access via Tools → CheetSheet menu if available.")
    end
end

function CheetSheet:registerActions()
    Dispatcher:registerAction("replace_show_message", {
        category = "none",
        event = "ReplaceShowMessage",
        title = _("CheetSheet: Show message"),
        general = true,
    })
end

-- Action handler
function CheetSheet:onReplaceShowMessage()
    UIManager:show(InfoMessage:new{ text = _("Hello from CheetSheet plugin!") })
    return true
end

-- Main menu integration
function CheetSheet:addToMainMenu(menu_items)
    -- Prefer adding inside the standard Tools menu when available
    if menu_items.tools and type(menu_items.tools.sub_item_table) == "table" then
        table.insert(menu_items.tools.sub_item_table, {
            text = _("CheetSheet"),
            icon = "appbar.menu",
            sub_item_table = {
                {
                    text = _("Show welcome message"),
                    callback = function()
                        self:onReplaceShowMessage()
                    end,
                },
            },
        })
    else
        -- Fallback: add as a top-level entry if Tools menu is not present
        menu_items.replace = {
            text = _("CheetSheet"),
            icon = "appbar.menu",
            sub_item_table = {
                {
                    text = _("Show welcome message"),
                    callback = function()
                        self:onReplaceShowMessage()
                    end,
                },
            },
        }
    end
end

-- Document (reader) menu integration
function CheetSheet:addToDocumentMenu(menu_items)
    menu_items.replace = {
        text = _("CheetSheet"),
        icon = "appbar.menu",
        sub_item_table = {
            {
                text = _("Show welcome message"),
                callback = function()
                    self:onReplaceShowMessage()
                end,
            },
        },
    }
end

-- Toolbar integration (add a button in the top bar near the wrench menu)
local function insert_toolbar_item(container, item)
    -- container might be a flat list or a table with left/right arrays depending on KOReader version/skin
    if type(container) ~= "table" then return end
    if container.right and type(container.right) == "table" then
        table.insert(container.right, item)
        return
    end
    if container.left and type(container.left) == "table" then
        table.insert(container.left, item)
        return
    end
    table.insert(container, item)
end

function CheetSheet:_toolbarItem()
    return {
        id = "replace_button",
        icon = "appbar.menu",
        text = _("CheetSheet"),
        callback = function()
            -- Keep it simple: show the same welcome message as the menu action
            self:onReplaceShowMessage()
        end,
    }
end

function CheetSheet:addToMainToolbar(toolbar_items)
    insert_toolbar_item(toolbar_items, self:_toolbarItem())
end

function CheetSheet:addToDocumentToolbar(toolbar_items)
    insert_toolbar_item(toolbar_items, self:_toolbarItem())
end

return CheetSheet
