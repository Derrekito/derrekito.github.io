---
title: "Building an Interactive Keybinding Cheatsheet in Neovim with Telescope"
date: 2026-02-28 10:00:00 -0700
categories: [Neovim, Plugins]
tags: [neovim, lua, telescope, keybindings, productivity]
---

A self-documenting keybinding system that lives inside the editor. This plugin enables browsing 30+ categories of shortcuts through a fuzzy-searchable Telescope picker without leaving the workflow.

## Problem Statement

Neovim configurations grow. Plugins are added, custom keymaps are written, LSP bindings are configured, DAP shortcuts are set up. Eventually there are 100+ keybindings scattered across a dozen files. Bindings mapped last month are forgotten. Opening the config and grepping around causes loss of context in the file being edited.

External cheatsheets (markdown files, printed references, browser tabs) break the workflow. The desired solution is something inside the editor that can be pulled up instantly, searched through, and dismissed just as fast.

## Proposed Approach

Build a minimal local plugin that:

1. Stores all keybindings as structured data in a single Lua table
2. Presents categories through Telescope's fuzzy picker
3. Enables drilling into a category to view its bindings
4. Supports navigating back to the category list

Three files, under 100 lines of logic. The data file is as long as the keybinding list.

## Project Structure

```text
~/.config/nvim/lua/cheatsheet/
├── init.lua    # Entry point: setup, command, keymap
├── data.lua    # Keybinding data organized by category
└── ui.lua      # Telescope picker with drill-down navigation
```

Plus a plugin spec to register it with lazy.nvim:

```text
~/.config/nvim/lua/plugins/cheatsheet.lua
```

## Implementation

### Plugin Spec

Register the local plugin with lazy.nvim using `dir` instead of a remote repo URL:

```lua
-- lua/plugins/cheatsheet.lua
return {
  {
    dir = vim.fn.stdpath("config") .. "/lua/cheatsheet",
    dependencies = { "nvim-telescope/telescope.nvim" },
    config = function()
      require("cheatsheet").setup()
    end,
  },
}
```

The `dir` field tells lazy.nvim to load from a local path. No remote repo is needed.

### Entry Point

```lua
-- lua/cheatsheet/init.lua
local M = {}

function M.open()
  require("cheatsheet.ui").open_cheatsheet()
end

function M.setup(opts)
  opts = opts or {}
  vim.api.nvim_create_user_command("Cheatsheet", M.open, {})
  vim.keymap.set("n", "<leader>cs", M.open, { desc = "Open cheatsheet" })
end

return M
```

This provides two ways to open it: the `:Cheatsheet` command or `<leader>cs`. The `setup()` function follows the standard Neovim plugin convention, so it works with any plugin manager's `config` callback.

### UI Layer

The UI module builds Telescope pickers dynamically. The key design choice is a two-level hierarchy: categories first, then items within a category, with a "Back" option to return to categories.

```lua
-- lua/cheatsheet/ui.lua
local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local data = require("cheatsheet.data")

local M = {}

function M.create_picker(title, entries, on_select)
  pickers.new({}, {
    prompt_title = title,
    finder = finders.new_table({
      results = entries,
    }),
    sorter = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        on_select(selection.value)
      end)
      return true
    end,
  }):find()
end

function M.show_categories()
  local categories = {}
  for _, section in ipairs(data.sections) do
    table.insert(categories, section.category)
  end
  table.sort(categories)
  M.create_picker("Neovim Shortcuts", categories, function(selected_category)
    M.show_items(selected_category)
  end)
end

function M.show_items(category)
  for _, section in ipairs(data.sections) do
    if section.category == category then
      local items = vim.tbl_extend("force", section.items, { "Back" })
      M.create_picker(category, items, function(selected_item)
        if selected_item == "Back" then
          M.show_categories()
        end
      end)
      return
    end
  end
end

function M.open_cheatsheet()
  M.show_categories()
end

return M
```

`create_picker` is a generic factory. It takes a title, a list of strings, and a callback for when the user selects one. Both the category view and the item view use it. This keeps the two-level navigation under 50 lines.

The "Back" entry is appended to each item list using `vim.tbl_extend`. When selected, it re-opens the category picker, creating a simple navigation loop.

### Data Layer

The data file is a flat list of sections, each with a category name and an array of formatted strings. The following shows a trimmed example of the structure:

```lua
-- lua/cheatsheet/data.lua
local M = {}

M.sections = {
  {
    category = "Leader Key",
    items = {
      "<Space>                → Leader key",
    },
  },
  {
    category = "Standard Vim Bindings",
    items = {
      "## Normal Mode",
      "h/j/k/l               → Move cursor",
      "w/b                   → Move to next/previous word",
      "0/$                   → Move to start/end of line",
      "gg/G                  → Go to first/last line",
      "u                     → Undo",
      "<C-r>                 → Redo",
      "yy                    → Yank (copy) line",
      "dd                    → Delete (cut) line",
      "## Visual Mode",
      "v                     → Enter visual mode",
      "V                     → Enter linewise visual mode",
      "<C-v>                 → Enter blockwise visual mode",
      "## Text Objects",
      "iw                    → Inner word",
      "aw                    → Around word",
      "ci\"/di\"/yi\"           → Change/delete/yank inner quotes",
    },
  },
  {
    category = "Harpoon (Normal Mode)",
    items = {
      "n: <leader>a          → Add file",
      "n: <C-e>              → Toggle menu",
      "n: <leader>1          → Jump to file 1",
      "n: <leader>2          → Jump to file 2",
      "n: <leader>3          → Jump to file 3",
      "n: <leader>4          → Jump to file 4",
    },
  },
  {
    category = "Telescope (Normal Mode)",
    items = {
      "n: <leader>ph         → Help tags",
      "n: <leader>pf         → Find files (fzf sorting)",
      "n: <leader>en         → Find files in config",
      "n: <leader>mg         → Multi grep",
    },
  },
  {
    category = "LSP (Normal Mode)",
    items = {
      "n: gr                 → Telescope lsp_references",
      "n: gd                 → Go to definition",
      "n: K                  → Hover",
      "n: <leader>vca        → Code action",
      "n: <leader>vrn        → Rename",
    },
  },
  {
    category = "DAP (Debugging, Normal Mode)",
    items = {
      "n: <leader>db         → Toggle breakpoint",
      "n: <leader>dc         → Continue",
      "n: <leader>ds         → Step over",
      "n: <leader>di         → Step into",
      "n: <leader>do         → Step out",
    },
  },
  -- ... more categories
}

return M
```

Several aspects of the format are worth noting:

- **Mode prefixes** (`n:`, `v:`, `i:`, `x:`) clarify which mode a binding applies to.
- **Section headers** (`## Normal Mode`) within a category's items work as visual dividers in the Telescope results. They are just strings—no special handling is needed.
- **Arrow separator** (`→`) provides a consistent visual rhythm. Telescope's fuzzy matching works on the full string, so searches can match by key or description.

The full data file in a typical config has 30+ categories covering everything from standard Vim bindings to plugin-specific shortcuts (Fugitive, Gitsigns, Obsidian, DAP, Zen Mode, etc.).

## Usage

Press `<leader>cs` or run `:Cheatsheet`. Telescope opens with a sorted list of categories:

```text
> Buffer Management (Normal Mode)
  Completion (nvim-cmp, Insert Mode)
  Core Neovim (Normal Mode)
  DAP (Debugging, Normal Mode)
  Fugitive (Git, Normal Mode)
  Gitsigns (Git, Normal Mode)
  Harpoon (Normal Mode)
  LSP (Normal Mode)
  Telescope (Normal Mode)
  Window Management (Normal Mode)
  Zen Mode (Normal Mode)
  ...
```

Type to fuzzy-filter. Select a category to see its bindings. Select "Back" (or press `<Esc>` and reopen) to return to categories.

Since it uses Telescope, all the usual features are available: fuzzy matching, `<C-n>`/`<C-p>` navigation, and instant filtering. Searching "harp" from the category list jumps straight to "Harpoon". Inside a category, searching "break" highlights the breakpoint binding.

## Comparison with Alternatives

**vs. `:map` / `:verbose map`** — These dump raw Vim mapping internals. Useful for debugging, not for quick reference. No descriptions, no organization.

**vs. which-key.nvim** — which-key shows available continuations after pressing a leader key. It is effective for discovery but only shows one prefix at a time. It cannot show all Git bindings across different prefixes, or enable searching "how to stage a hunk?"

**vs. a markdown file** — Requires leaving the editor (or splitting it) and manually searching. It goes stale because updating it is a separate chore from updating the config.

**vs. comments in config files** — Scattered across files. No single view. Cannot fuzzy-search across all of them.

The cheatsheet approach centralizes everything in one searchable place. The tradeoff is that the data file must be maintained alongside the keymaps. In practice this is not burdensome—when adding a new binding, a line is added to `data.lua`. It is the same file every time.

## Extension Possibilities

Several ideas for taking this further:

- **Auto-generate from keymaps**: Walk `vim.api.nvim_get_keymap()` and build sections programmatically. This sacrifices curated descriptions but gains zero-maintenance accuracy.
- **Preview window**: Show the source file and line number where each binding is defined. Telescope supports custom previewers.
- **Subcategories**: Add a third level of nesting for configs with even more bindings.
- **Export**: Generate a markdown reference from `data.lua` for documentation outside the editor.

## Source

The full implementation is three files totaling roughly 70 lines of logic plus the data. Drop the `lua/cheatsheet/` directory into the Neovim config, add the plugin spec, and populate `data.lua` with the appropriate bindings.
