local api = vim.api
local lsp = vim.lsp
local util = lsp.util
local uv = vim.uv

local lamp_hl_hs = api.nvim_create_namespace("mjm/lightbulb")
local timer = uv.new_timer()
assert(timer, "Action lamp timer was not initialized")

---@param bufnr integer
---@param lnum integer
---@param hl_ns integer
---@return nil
local function default_display(bufnr, lnum, hl_ns)
    api.nvim_buf_set_extmark(bufnr, hl_ns, lnum, 0, {
        virt_text = { { "󰌶", "LampshadeLamp" } },
        priority = 1000,
        strict = false,
    })
end

---@param _ integer
---@param action (lsp.Command|lsp.CodeAction)
---@return boolean
local function default_action_filter(_, action)
    if action.disabled then
        return false
    else
        return true
    end
end

---@param buf integer
---@return nil
local function clear_buf_lamp_state(buf)
    if vim.b[buf].action_lamp_cancel then
        pcall(vim.b[buf].action_lamp_cancel)
        vim.b[buf].action_lamp_cancel = nil
    end

    api.nvim_buf_clear_namespace(buf, lamp_hl_hs, 0, -1)
end

---@param results table<integer, vim.lsp.CodeActionResultEntry>
---@param buf integer
---@param lnum integer 0-indexed
---@param opts lampshade.UpdateLamp.Opts
---@return nil
local function on_results(results, buf, lnum, opts)
    local loaded = api.nvim_buf_is_loaded(buf)
    if not loaded then
        return
    end

    clear_buf_lamp_state(buf)
    local cur_buf = api.nvim_get_current_buf()
    if cur_buf ~= buf then
        return
    end

    local cur_lines = api.nvim_buf_line_count(buf)
    if lnum >= cur_lines then
        return
    end

    local client_actions = {} ---@type table<integer, (lsp.Command|lsp.CodeAction)[]>
    for client_id, result in pairs(results) do
        local actions = result.result
        if actions then
            client_actions[client_id] = actions
        end
    end

    if vim.tbl_isempty(client_actions) then
        return
    end

    local action_filter = opts.on_actions or default_action_filter
    local filtered_actions = {} ---@type (lsp.Command|lsp.CodeAction)[]
    for client_id, actions in pairs(client_actions) do
        for _, action in ipairs(actions) do
            local is_valid = action_filter(client_id, action)
            if is_valid then
                filtered_actions[#filtered_actions + 1] = action
            end
        end
    end

    if #filtered_actions == 0 then
        return
    end

    ---@type fun(bufnr: integer, lnum: integer, hl_ns: integer)
    local display = opts.on_display or default_display
    display(buf, lnum, lamp_hl_hs)
end

---@param method vim.lsp.protocol.Method.ClientToServer.Request
---@param clients vim.lsp.Client[]
---@return boolean
local function has_supporting_client(method, clients)
    for _, client in ipairs(clients) do
        local supports_method = client:supports_method(method)
        if supports_method then
            return true
        end
    end

    return false
end

---@param buf integer
---@param opts lampshade.UpdateLamp.Opts
---@return nil
local function on_timer(buf, opts)
    local loaded = api.nvim_buf_is_loaded(buf)
    if not loaded then
        return
    end

    clear_buf_lamp_state(buf)
    local cur_buf = api.nvim_get_current_buf()
    if buf ~= cur_buf then
        return
    end

    ---@type vim.lsp.protocol.Method.ClientToServer.Request
    local method = "textDocument/codeAction"
    local clients = lsp.get_clients({ bufnr = buf })
    local supporting_client = has_supporting_client(method, clients)
    if not supporting_client then
        return
    end

    local win = api.nvim_get_current_win()
    local lnum = api.nvim_win_get_cursor(win)[1] - 1

    ---@type fun(client: vim.lsp.Client, bufnr: integer): lsp.CodeActionParams
    local params = function(client, _)
        local offset_encoding = client.offset_encoding or "utf-16"
        local ret = util.make_range_params(win, offset_encoding) ---@type lsp.CodeActionParams
        local diagnostics = lsp.diagnostic.from(vim.diagnostic.get(buf, { lnum = lnum }))
        ret.context = {
            diagnostics = diagnostics,
            triggerKind = lsp.protocol.CodeActionTriggerKind.Automatic,
        }

        return ret
    end

    vim.b[buf].action_lamp_cancel = lsp.buf_request_all(buf, method, params, function(results)
        on_results(results, buf, lnum, opts)
    end)
end

local function validate_update_opts(opts)
    vim.validate("opts", opts, "table")
    vim.validate("opts.debounce", opts.debounce, "number", true)
    vim.validate("opts.on_dispay", opts.on_dispay, "callable", true)
    vim.validate("opts.on_action", opts.on_action, "callable", true)
end

---@mod lampshade.nvim Illuminate code actions
---@brief [[
---VSCode-style code action lightbulb. No configuration required.
---
---The API can be used to customize how the lamp displays and which actions
---trigger it.
---@brief ]]

---@mod lampshade-installation Installation
---@brief [[
---Neovim 0.11+ is supported
---
---Lazy.nvim:
--->
---    "mikejmcguirk/lampshade.nvim",
---    lazy = false,
---    init = function()
---        -- Customize here
---    end,
---<
---vim.pack spec (v0.12+):
--->
---    { src = "https://github.com/mikejmcguirk/lampshade.nvim" },
---<
---Verify installation and settings with ":checkhealth lampshade"
---@brief ]]

---@mod lampshade-config Configuration

---(Default true) This g:variable is checked during plugin sourcing. If it is
---true or nil, the default auto commands to display and clear the lamp will
---be created.
---
---Each LSP buffer will have the augroup "lampshade-"{bufnr} created to
---manage the lamp. The creation of those autocmds is is handled in the
---"lampshade-init" augroup.
---
---The lamp will be displayed on BufEnter, CursorMoved, DiagnosticChanged,
---InsertLeave, and TextChanged.
---
---The lamp will be cleared on BufLeave and InsertEnter
---@alias lampshade_default_autocmds boolean
---
---@brief [[
---By default, the lamp is displayed using the "LampshadeLamp" highlight group.
---It links to |hl-DiagnosticInfo|.
---@brief ]]

--- @class Lampshade
local M = {}

---@mod lampshade-api API

---@class lampshade.UpdateLamp.Opts
---
---
---( Default: 200ms ) How long to hold codeAction
---requests before sending them to the server.
---If another local function call is made before
---the timer expires, the timer will be stopped
---without sending a request to the server, and
---restarted at its full duration.
---
---@field debounce? integer
---
---
---Custom function to display the lamp. The calling
---function will clear the namespace beforehand. By
---default, the lamp will be displayed as virtual
---text using the DiagnosticInfo highlight group.
---
---The namespace will be cleared before the function
---is called.
---
---By default, the lamp will be displayed as virtual text.
---
---@field on_display? fun(bufnr: integer, lnum: integer, hl_ns: integer)
---
---
---Function to filter out actions that should not be
---considered toward showing the lightbulb. By default,
---any action with a disabled flag is filtered.
---
---@field on_actions? fun(client_id: integer, action: lsp.Command|lsp.CodeAction):boolean

---Update a buffer's lamp display. All other lamps will be cleared
---
---@param buf integer Buffer to show the lamp in
---@param opts? lampshade.UpdateLamp.Opts See |lampshade.UpdateLamp.Opts|
---@return nil
function M.update_lamp(buf, opts)
    vim.validate("buf", buf, "number")
    opts = opts or {}
    validate_update_opts(opts)

    local loaded = api.nvim_buf_is_loaded(buf)
    if not loaded then
        return
    end

    clear_buf_lamp_state(buf)
    local cur_buf = api.nvim_get_current_buf()
    if cur_buf ~= buf then
        return
    end

    if timer:is_active() then
        timer:stop()
    end

    local debounce = opts.debounce or 200
    timer:start(
        debounce,
        0,
        vim.schedule_wrap(function()
            on_timer(buf, opts)
        end)
    )
end

---Stop showing the lamp in a buffer. This will also cancel any pending LSP
---requests
---
---@param buf integer Buffer to clear the lamp in
---@return nil
function M.clear_lamp(buf)
    vim.validate("buf", buf, "number")

    local loaded = api.nvim_buf_is_loaded(buf) ---@type boolean
    if not loaded then
        return
    end

    clear_buf_lamp_state(buf)
end

---@return integer The lamp extmark namespace
function M.get_hl_ns()
    return lamp_hl_hs
end

return M
