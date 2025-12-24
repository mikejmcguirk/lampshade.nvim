local api = vim.api
local lsp = vim.lsp

api.nvim_set_hl(0, "LampshadeLamp", { link = "DiagnosticInfo" })

local is_nil = type(vim.g.lampshade_default_autocmds) == "nil"
if is_nil == "nil" then
    vim.g.lampshade_default_autocmds = true
end

if not vim.g.lampshade_default_autocmds then
    return
end

local lamp_group_root = "lampshade-"
local init_group_name = lamp_group_root .. "init"
local init_group = api.nvim_create_augroup(init_group_name, {})

api.nvim_create_autocmd("LspAttach", {
    group = init_group,
    callback = function(ev)
        local client = lsp.get_client_by_id(ev.data.client_id)
        if not client then
            return
        end

        if not client:supports_method("textDocument/codeAction") then
            return
        end

        -- Because multiple LSPs can attach to a buffer, use an augroup to de-duplicate autocmds
        local buf = ev.buf
        local buf_str = tostring(buf)
        local buf_group_name = lamp_group_root .. buf_str
        local buf_group = api.nvim_create_augroup(buf_group_name, {})

        local lamp = require("lampshade")
        -- Run manually since LspAttach occurs after BufEnter
        lamp.update_lamp(buf)

        local update_events = {
            "BufEnter",
            "CursorMoved",
            "DiagnosticChanged",
            "InsertLeave",
            "TextChanged",
        }

        api.nvim_create_autocmd(update_events, {
            group = buf_group,
            buffer = buf,
            desc = "Show lamp",
            callback = function(iev)
                if iev.event == "DiagnosticChanged" then
                    local mode = api.nvim_get_mode().mode
                    local short_mode = string.sub(mode, 1)
                    local bad_mode = string.match(short_mode, "[csS\19irR]")
                    if bad_mode then
                        return
                    end
                end

                lamp.update_lamp(iev.buf)
            end,
        })

        local clear_events = { "BufLeave", "InsertEnter" }
        api.nvim_create_autocmd(clear_events, {
            group = buf_group,
            buffer = buf,
            desc = "Clear lamp",
            callback = function(iev)
                lamp.clear_lamp(iev.buf)
            end,
        })

        api.nvim_create_autocmd("LspDetach", {
            group = buf_group,
            buffer = buf,
            desc = "Detach lamp",
            callback = function(iev)
                lamp.clear_lamp(iev.buf)
                api.nvim_del_augroup_by_id(buf_group)
            end,
        })
    end,
})

-- LOW: Would be cool to track context.version
-- - Starts at 0, which is easy enough
-- - Tougher: It doesn't seem to track undos/saves one-to-one. Unsure why

-- MAYBE: Would be interesting to cache results, but unsure how I can do so in a useful way. The
-- code builds the position based on the exact cursor position, and this can be relevant
-- such as with Lua function args. If we can't even cache by line, and cache is irrelevant on
-- each document change, then what's the point?
