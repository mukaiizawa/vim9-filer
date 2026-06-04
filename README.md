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

Open the directory of the current buffer in a vertical split and jump to the current file with:

```vim
:FilerBufferDir
```

This plugin disables netrw and replaces Vim's default directory buffer behavior by opening `filer` automatically when entering a directory.

## Key Bindings

- `<CR>`: Open the item under the cursor. Files are edited, directories are entered.
- `t`: Toggle directory expansion for the directory under the cursor.
- `T`: Recursively toggle expansion for the directory under the cursor.
- `~`: Redraw with the home directory as the root.
- `\`: Redraw with the filesystem root as the root.
- `h`: Redraw with the parent directory as the root.
- `l`: Open a file, or redraw with the directory under the cursor as the root.
- `.`: Re-open the current directory and redraw the view.
- `gg`: Jump to the first entry.
- `q`: Close the explorer.
- `<Space>`: Toggle multi-selection.
- `*`: Toggle marking of all items in the current view.
- `a`: Create a file or directory. Enter a trailing `/` to create a directory.
- `c`: Mark the item on the current line when nothing is marked; otherwise open a batch copy buffer for all marked items.
- `d`: Mark the item on the current line when nothing is marked; otherwise confirm and delete all marked items.
- `r`: Mark the item on the current line when nothing is marked; otherwise open a batch rename buffer for all marked items.
- `x`: Open the item on the current line with the OS default associated application. On the first line, open the current directory.
- `yy`: Copy the full path of the current line to the clipboard register. On the first line, copy the current directory.
- `<C-F>`: Recursively search for file names under the current directory. Submit an empty query to clear the search.
- `s`: Cycle sort mode: `name` -> `size` -> `time`.

## Notes

- The first line shows the current directory with a trailing `/`. Entries start on the second line when present.
- Directory entries are shown before files for every sort mode.
- Each entry shows name, file size, and modification time. When either value is unavailable, `-` is shown instead. Directories do not show a size.
- When the window is too narrow to fit the metadata area, the entry falls back to showing only the name.
- Symbolic links are shown as directories when their targets are directories.
- Selected items are marked with `*`.
- Marks are cleared when changing directories or when the `filer` buffer is closed.
- Batch rename opens a temporary buffer listing the marked paths. Edit the lines and write the buffer to apply the rename.
- Batch copy opens a temporary buffer listing the marked paths. Edit the lines and write the buffer to copy only the changed entries.
- The statusline shows the current directory on the left, and the sort mode plus `[current/total]` position on the right.
- When `:syntax on` is enabled, the `filer` syntax file is loaded. Timestamps are color-coded by recency, from cool tones for newer entries to warm tones for older entries.
- In a `filer` buffer, `~` is mapped to jump to the home directory, and `~` is also expanded in path input prompts.
- Basic operation on Windows is supported within the same drive.
- `x` on WSL is currently unsupported.
- Home directory resolution on Windows prefers `expand('~')`, then falls back to `HOME`, `USERPROFILE`, or `HOMEDRIVE` + `HOMEPATH`.
- Renaming across drives on Windows is not supported.
