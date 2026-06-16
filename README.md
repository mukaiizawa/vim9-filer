# filer

A minimal file explorer implemented in Vim9 script.

This plugin intentionally disables netrw by setting `g:loaded_netrwPlugin`.
It replaces Vim's default directory buffer handling with `filer`.

## Usage

Open the explorer with:

```vim
:Filer
```

You can also pass a directory:

```vim
:Filer path/to/dir
```

Open the explorer directly in another window or tab with:

```vim
:FilerSplit path/to/dir
:FilerVsplit path/to/dir
:FilerTab path/to/dir
```

Open the directory of the current buffer and jump to the current file with:

```vim
:FilerBufferDir
:FilerBufferDir split
```

When Vim enters a directory buffer, `filer` opens automatically instead of
netrw.

## Key Bindings

- `<CR>` / `l`: Open the item under the cursor. Files use `g:filer_file_open_command`; directories use `g:filer_directory_open_command`.
- `s`: Open the item under the cursor in a horizontal split.
- `v`: Open the item under the cursor in a vertical split.
- `t`: Open the item under the cursor in a new tab.
- `o`: Open the file under the cursor with `:drop`. Directories are entered in the current window.
- `za`: Toggle directory expansion for the directory under the cursor.
- `zA`: Recursively toggle expansion for the directory under the cursor.
- `~`: Redraw with the home directory as the root.
- `\`: Redraw with the filesystem root as the root.
- `h`: Redraw with the parent directory as the root.
- `.`: Re-open the current directory and redraw the view.
- `gg`: Jump to the first entry.
- `<Tab>`: Duplicate the current filer buffer with `g:filer_duplicate_command`.
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
- `S`: Cycle sort mode: `name` -> `size` -> `time`.

## Opening Customization

The same command names are used for file opens and filer windows:

```vim
g:filer_file_open_command = 'edit'
g:filer_directory_open_command = 'edit'
g:filer_launch_command = 'edit'
g:filer_buffer_dir_command = 'vsplit'
g:filer_duplicate_command = 'vsplit'
```

File opens accept `edit`, `split`, `vsplit`, `tabedit`, and `drop`. Filer
windows accept `edit`, `split`, `vsplit`, and `tabedit`.

## API

Use `filer#BufferDir()` to get the directory shown by the current filer buffer.
Pass a buffer number to inspect another filer buffer. It returns an empty string
when the buffer is not a live filer buffer.

`User FilerVisitDir` is triggered when a filer buffer visits a directory,
including opening a filer buffer, changing the filer root, reopening the current
root, or entering an existing filer buffer.

```vim
autocmd User FilerVisitDir echomsg filer#BufferDir()
```

## Key Mapping Customization

Default mappings can be disabled:

```vim
g:filer_no_default_mappings = true

autocmd FileType filer nmap <buffer> o <Plug>(filer-open)
autocmd FileType filer nmap <buffer> q <Plug>(filer-close)
autocmd FileType filer_rename nmap <buffer> q <Plug>(filer-batch-close)
autocmd FileType filer_copy nmap <buffer> q <Plug>(filer-batch-close)
```

Custom buffer-local mappings can also be defined directly with `<Plug>`
mappings:

```vim
autocmd FileType filer nmap <buffer> <C-B> <Plug>(filer-search)
```

Individual default mappings can also be changed with `g:filer_mappings`:

```vim
g:filer_mappings = {
      'open': '<CR>',
      'open_split': 's',
      'open_vsplit': 'v',
      'parent': 'H',
      'search': '/',
      }
```

Use an empty string to disable one action, or a list to assign multiple keys:

```vim
g:filer_mappings = {
      'open_external': '',
      'open': ['<CR>', 'l'],
      }
```

When `g:filer_no_default_mappings` is enabled, only explicitly configured
actions in `g:filer_mappings` are mapped.

Batch rename and copy buffers use `g:filer_batch_mappings`:

```vim
g:filer_batch_mappings = {
      'close': 'q',
      }
```

Available `g:filer_mappings` actions are `close`, `open`, `open_split`,
`open_vsplit`, `open_tab`, `open_drop`, `duplicate`, `toggle_tree`,
`toggle_tree_recursive`, `home`, `root`, `parent`, `refresh`, `toggle_mark`,
`mark_all`, `create`, `copy_or_mark`, `delete_or_mark`, `first_entry`,
`rename_or_mark`, `open_external`, `yank_path`, `search`, and `cycle_sort`.

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
