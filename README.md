# nvim-multipage

Multi-page vertical views for long files in Neovim.

This plugin lets you use your horizontal space to show a file as
"pages" side-by-side:

- Left pane: lines 1–40  
- Middle pane: lines 39–78 (configurable overlap)  
- Right pane: lines 77–116  
- All panes scroll together while keeping that offset.

Useful for reading / reviewing long code or prose where you want more
context than a single window can show vertically.

## Features

- 🧱 Split a file into multiple vertical "pages"
- 🔗 Synchronous scrolling via `scrollbind`
- 🧠 Per-buffer: enable/disable per file, all its panes follow
- 🎯 Only windows showing the same buffer participate
- 🔍 Configurable line overlap between pages
- 🌳 Optional `nvim-treesitter-context` integration:
  context is shown only in the left-most multipage pane

## Requirements

- Neovim 0.7+ (tested with 0.9+)
- Optional: [`nvim-treesitter-context`](https://github.com/nvim-treesitter/nvim-treesitter-context)

## Installation

### [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  'afwcxx/nvim-multipage',
  config = function()
    require('multipage').setup {
      -- number of lines of overlap between panes
      -- overlap = 1 => right starts at last line of left
      -- overlap = 2 => 2-line overlap, etc.
      overlap = 2,
    }
  end,
}
```

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  'afwcxx/nvim-multipage',
  config = function()
    require('multipage').setup {
      overlap = 2,
    }
  end,
}
```

If you don’t call `setup()`, the plugin still works with defaults
(overlap = 1).

## Commands

All commands operate on the **current buffer** and **current tabpage**.

- `:MultipageEnable`  
  Enable multipage mode for this file using all existing vertical splits
  of this buffer in the current tab.

- `:MultipageEnable {N}`  
  Ensure there are `{N}` vertical splits for this file in this tab
  (creating additional `:vsplit`s if needed), then arrange them as pages.

- `:MultipageToggle` / `:MultipageToggle {N}`  
  Toggle multipage mode for this file. If enabling and `{N}` is given,
  behaves like `:MultipageEnable {N}`.

- `:MultipageDisable`  
  Disable multipage mode for this file in this tab (turns off
  `scrollbind` for its windows).

### Examples

```vim
" Open a file and show it in 3 side-by-side pages
:edit long_file.lua
:MultipageEnable 3

" Toggle multipage mode for current file
:MultipageToggle

" Disable multipage for current file
:MultipageDisable
```

## Configuration

```lua
require('multipage').setup {
  -- Number of lines of overlap between pages.
  -- overlap = 1: right starts at last line of left
  -- overlap = 0: no overlap (pure paging)
  -- overlap = 2+: small repeated region between pages
  overlap = 2,
}
```

You can call `setup()` multiple times; later calls override previous
settings.

## Treesitter context integration

If you use [`nvim-treesitter-context`](https://github.com/nvim-treesitter/nvim-treesitter-context),
the plugin can keep the context header only on the left-most pane.

Configure `nvim-treesitter-context` like this:

```lua
require('treesitter-context').setup {
  enable = true,
  multiwindow = false, -- important: let multipage decide the window
  -- other options...
}
```

With `multiwindow = false`, only one context window is drawn.  
`nvim-multipage` then forces updates to be computed from the left-most
multipage window for that buffer, so:

- All panes scroll together
- Context is visible only on the left-most pane
- The context still follows the actual cursor position

## How it works

- It finds all windows in the current tab that show the current buffer.
- When multipage is enabled:
  - It uses the height of the left-most window as the page size.
  - It computes a "page span" as `height - overlap`.
  - Each window’s `topline` is set to:
    - `T`, `T + span`, `T + 2*span`, ...
  - `scrollbind` is enabled in those windows so that scrolling in any
    of them moves the others while preserving the offsets.
- Buffers that are not in multipage mode have `scrollbind` explicitly
  turned off when their windows are entered.

The mode is tracked per-buffer using `b:multipage_enabled`.

## Caveats

- This plugin assumes a relatively standard setup for scrolling
  (`scrollbind`, `scrolloff`) and window resizing.
- If you aggressively resize only some panes, the paging might not be
  perfectly even until the next layout refresh (triggered when switching
  windows or re-enabling).

## Contributing

Issues and pull requests are welcome!

- Ideas: custom per-file config, support for horizontal multipage,
  more explicit integration with other UI plugins, etc.
- If you hit an edge case with your setup, a minimal reproduction
  (`init.lua` + steps) helps a lot.

## License

GPL-2.0 license

