local M = {}

M.check = function()
    vim.health.start("Installation")
    if vim.fn.has("nvim-0.11") then
        vim.health.ok("Neovim version is at least 0.11")
    else
        vim.health.warn("Neovim version is below 0.11")
    end

    vim.health.start("Config")
    local val = vim.g.lampshade_default_autocmds ---@type any
    local val_type = type(val)
    -- NOTE: tostring being able to handle NaN and +/-inf is LuaJIT exclusive
    local val_fmt = tostring(val)
    local var_info = "g:lampshade_default_autocmds" .. " = " .. val_fmt .. " (Allowed: boolean)"

    if "boolean" == val_type then
        vim.health.ok(var_info)
    else
        vim.health.error(var_info)
    end
end

return M

-- MID: Check if the default augroup exists
