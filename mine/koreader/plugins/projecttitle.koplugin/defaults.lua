-- Default settings and migrations for Project Title (CoverBrowser) plugin
-- This file allows configuring defaults without editing main.lua

return {
    -- Flag in global reader settings to mark that initial defaults have been applied
    initial_setup_flag = "aaaProjectTitle_initial_default_setup_done2",

    -- Initial defaults applied on first run
    initial = {
        -- Display modes
        filemanager_display_mode = "list_image_meta",
        history_display_mode = "list_image_meta",
        collection_display_mode = "list_image_meta",

        -- Config versioning
        config_version = "1",

        -- Plugin specific settings
        series_mode = "series_in_separate_line",
        hide_file_info = true,
        unified_display_mode = true,
        show_progress_in_mosaic = true,
        autoscan_on_eject = false,
    },

    -- Versioned migrations. Each step runs when current version == from.
    migrations = {
        {
            from = "1",
            to = "2",
            settings = {
                disable_auto_foldercovers = false,
                force_max_progressbars = false,
                opened_at_top_of_library = true,
                reverse_footer = false,
                use_custom_bookstatus = true,
                replace_footer_text = true,
                show_name_grid_folders = false,
                config_version = "2",
            },
            restart = true,
        },
        {
            from = "2",
            to = "3",
            settings = {
                force_no_progressbars = false,
                config_version = "3",
            },
        },
        {
            from = "3",
            to = "4",
            settings = {
                force_focus_indicator = false,
                use_stacked_foldercovers = true,
                config_version = "4",
            },
        },
        {
            from = "4",
            to = "5",
            settings = {
                show_tags = false,
                config_version = "5",
            },
        },
    },
}
