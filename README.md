# filer

A minimal file explorer implemented in Vim9 script.

## Usage

Open the explorer with:

```vim
:Filer
```

You can also pass a directory:

```vim
:Filer path/to/dir
```

This plugin also replaces Vim's default directory buffer behavior and opens `filer` automatically when entering a directory.

## Key Bindings

- `<CR>`: Open the item under the cursor. Files are edited, directories are entered.
- `<Tab>` / `t`: Toggle directory expansion.
- `~`: Redraw with the home directory as the root.
- `h`: Redraw with the parent directory as the root.
- `l`: Open a file, or redraw with the directory under the cursor as the root.
- `r`: Redraw.
- `q`: Close the explorer.
- `<Space>`: Toggle multi-selection.
- `*`: Clear the current selection.
- `a`: Create a file or directory. Enter a trailing `/` to create a directory.
- `d`: Delete the item on the current line.
- `D`: Delete all selected items.
- `R`: Rename the item on the current line.
- `B`: Batch rename selected items one by one.
- `m`: Move the item on the current line.
- `y`: Mark the current item or selected items for copy.
- `yy`: Copy the full path of the current line to the clipboard register. On the first line, copy the current directory.
- `x`: Mark the current item or selected items for cut.
- `p`: Paste into the current directory or the directory under the cursor.
- `/`: Run a normal buffer search.
- `<C-F>`: Recursively search for file names under the current directory.
- `s`: Cycle sort mode: `name` -> `size` -> `time`.

## Notes

- Symbolic links are shown as directories when their targets are directories.
- Selected items are marked with `*`.
- The statusline shows the sort mode, item count, search query, and clipboard state.
- When `:syntax on` is enabled, the `filer` syntax file is loaded and uses standard colorscheme highlight groups.
- In a `filer` buffer, `~` is mapped to jump to the home directory, and `~` is also expanded in path input prompts.
- Basic operation on Windows is supported within the same drive.
- Home directory resolution on Windows prefers `expand('~')`, then falls back to `HOME`, `USERPROFILE`, or `HOMEDRIVE` + `HOMEPATH`.
- Moving or renaming across drives on Windows is not supported.
