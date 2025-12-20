local cmd_parts = {
    "vimcats",
    "-l",
    '"compact"',
    "lua/lampshade/init.lua",
    "> doc/lampshade.nvim.txt",
}

local cmd = table.concat(cmd_parts, " ")
os.execute(cmd)
