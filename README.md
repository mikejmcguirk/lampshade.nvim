## Lampshade.nvim

VSCode-style code action lightbulb. No configuration required.

The API can be used to customize how the lamp displays and which actions trigger it.

## Installation

#### lazy.nvim:

```lua
  "mikejmcguirk/lampshade.nvim",
  lazy = false,
  init = function()
      -- Customize here
  end,
```

#### vim.pack (nightly):

```lua
    { src = "https://github.com/mikejmcguirk/nvim-qf-rancher" },
```

## Configuration

By default, ``vim.g.lampshade_default_autocmds`` will be set to true and the default autocmds
to display the lamp will be created during plugin sourcing.

Each LSP buffer will have the augroup ``lampshade-{bufnr}`` created to manage the lamp. The creation of those autocmds is is handled in the ``lampshade-init`` augroup

- The lamp will be displayed on ``BufEnter``, ``CursorMoved``, ``InsertLeave``, and ``TextChanged``.
- The lamp will be cleared on ``BufLeave`` and ``InsertEnter``

To create your own custom autocmds, disable ``vim.g.lampshade_default_autocmds`` before the plugin is sourced (in Lazy.nvim, use the init function), and then create your own autocmds utilizing the API. An example is demonstrated below:

```lua
vim.g.lampshade_default_autocmds = false

local lamp_group_root = "my-lampshade-"
local init_group_name = lamp_group_root .. "init"
local init_group = vim.api.nvim_create_augroup(init_group_name, {})

vim.api.nvim_create_autocmd("LspAttach", {
    group = init_group,
    callback = function(ev)
        local client = vim.lsp.get_client_by_id(ev.data.client_id)
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
        local buf_group = vim.api.nvim_create_augroup(buf_group_name, {})

        local opts = {} ---@type lampshade.UpdateLamp.Opts
        local ft = vim.api.nvim_get_option_value("filetype", { buf = buf }) ---@type string
        if ft == "lua" then
            opts.on_actions = function(client_id, action)
                if action.disabled then
                    return false
                end

                local title = action.title ---@type string|nil
                if not title then
                    return true
                end

                local client_name = vim.lsp.get_client_by_id(client_id).name
                if client_name ~= "lua_ls" then
                    return true
                end

                local param_change = string.find(title, "Change to parameter", 1, true)
                if param_change then
                    return false
                else
                    return true
                end
            end
        end

        local on_display = function(bufnr, lnum, hl_ns)
            vim.api.nvim_buf_set_extmark(bufnr, hl_ns, lnum, 0, {
                sign_text = "󰌶",
                sign_hl_group = "LampshadeLamp",
                priority = 1000,
                strict = false,
            })
        end

        opts.on_display = on_display

        local lamp = require("lampshade")
        -- Run manually since LspAttach occurs after BufEnter
        lamp.update_lamp(buf, opts)

        local update_events = {
            "BufEnter",
            "CursorMoved",
            "InsertLeave",
            "TextChanged",
        }

        vim.api.nvim_create_autocmd(update_events, {
            group = buf_group,
            buffer = buf,
            desc = "Show lamp",
            callback = function(iev)
                lamp.update_lamp(iev.buf, opts)
            end,
        })

        local clear_events = { "BufLeave", "InsertEnter" }
        vim.api.nvim_create_autocmd(clear_events, {
            group = buf_group,
            buffer = buf,
            desc = "Clear lamp",
            callback = function(iev)
                lamp.clear_lamp(iev.buf)
            end,
        })

        vim.api.nvim_create_autocmd("LspDetach", {
            group = buf_group,
            buffer = buf,
            desc = "Detach lamp",
            callback = function(iev)
                lamp.clear_lamp(iev.buf)
                vim.api.nvim_del_augroup_by_id(buf_group)
            end,
        })
    end,
})
```

## Alternatives

- https://github.com/kosayoda/nvim-lightbulb
- https://github.com/nvimdev/lspsaga.nvim
