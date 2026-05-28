vim9script

var state_by_bufnr: dict<any> = {}

const TREE_INDENTATION = 1
const TREE_LEAF_ICON = '|'
const TREE_OPENED_ICON = '-'
const TREE_CLOSED_ICON = '+'
const FILE_ICON = ' '
const MARKED_FILE_ICON = '*'
const SORT_MODES = ['name', 'size', 'time']
const TIMESTAMP_FORMAT = '%Y-%m-%d %H:%M'

def EscapeStatusline(text: string): string
  return substitute(substitute(text, '%', '%%', 'g'), ' ', '\\ ', 'g')
enddef

def Notify(message: string)
  echo message
enddef

def NormalizeSeparators(path: string): string
  return substitute(path, '\\', '/', 'g')
enddef

def GetHomeDir(): string
  var expanded = expand('~')
  if !empty(expanded) && expanded !=# '~'
    return TrimTrailingSeparators(fnamemodify(expanded, ':p'))
  endif

  if !empty($HOME)
    return TrimTrailingSeparators(fnamemodify($HOME, ':p'))
  endif

  if !empty($USERPROFILE)
    return TrimTrailingSeparators(fnamemodify($USERPROFILE, ':p'))
  endif

  if !empty($HOMEDRIVE) && !empty($HOMEPATH)
    return TrimTrailingSeparators(fnamemodify($HOMEDRIVE .. $HOMEPATH, ':p'))
  endif

  return ''
enddef

def ExpandHomePath(path: string): string
  if empty(path) || path[0] !=# '~'
    return path
  endif

  if len(path) > 1 && path[1] !=# '/' && path[1] !=# '\'
    return path
  endif

  var home = GetHomeDir()
  if empty(home)
    return path
  endif

  if path ==# '~'
    return home
  endif

  return home .. '/' .. path[2 :]
enddef

def IsRootPath(path: string): bool
  return path ==# '/'
    || path =~? '^[A-Z]:/$'
    || path =~? '^//[^/]\+/\?[^/]\+/$'
enddef

def TrimTrailingSeparators(path: string): string
  var normalized = NormalizeSeparators(path)
  if empty(normalized)
    return ''
  endif

  if IsRootPath(normalized)
    return normalized
  endif

  return substitute(normalized, '/\+$', '', '')
enddef

def JoinPath(base: string, child: string): string
  if empty(base)
    return NormalizePath(child)
  endif

  if empty(child)
    return NormalizePath(base)
  endif

  return NormalizePath(TrimTrailingSeparators(base) .. '/' .. child)
enddef

def IsAbsolutePath(path: string): bool
  var normalized = NormalizeSeparators(ExpandHomePath(path))
  return normalized =~# '^/'
    || normalized =~? '^[A-Z]:/'
    || normalized =~# '^//'
enddef

def ResolvePath(base: string, path: string): string
  var expanded = ExpandHomePath(path)
  return IsAbsolutePath(expanded) ? NormalizePath(expanded) : JoinPath(base, expanded)
enddef

def NormalizeDir(dir_arg: string): string
  if empty(dir_arg)
    return NormalizePath(getcwd())
  endif

  return NormalizePath(dir_arg)
enddef

def NormalizePath(path: string): string
  if empty(path)
    return ''
  endif

  return TrimTrailingSeparators(fnamemodify(ExpandHomePath(path), ':p'))
enddef

def PathExists(path: string): bool
  return filereadable(path) || isdirectory(path) || getftype(path) ==# 'link'
enddef

def IsDirectory(path: string): bool
  return isdirectory(path)
enddef

def Basename(path: string): string
  return fnamemodify(path, ':t')
enddef

def ParentDir(path: string): string
  var normalized = NormalizePath(path)
  if empty(normalized)
    return ''
  endif

  if IsRootPath(normalized)
    return normalized
  endif

  return NormalizePath(fnamemodify(normalized, ':h'))
enddef

def FilesystemRoot(path: string): string
  var normalized = NormalizePath(path)
  if empty(normalized)
    return NormalizeDir(getcwd())
  endif

  if normalized =~? '^[A-Z]:/'
    return normalized[0 : 2]
  endif

  if normalized =~# '^//'
    var match = matchstr(normalized, '^//[^/]\+/\?[^/]\+')
    return empty(match) ? '/' : match
  endif

  return '/'
enddef

def RelativePath(root: string, path: string): string
  var normalized_root = NormalizeDir(root)
  var normalized_path = NormalizePath(path)
  if normalized_path ==# normalized_root
    return ''
  endif

  var prefix = IsRootPath(normalized_root) ? normalized_root : normalized_root .. '/'
  return stridx(normalized_path, prefix) == 0 ? strpart(normalized_path, len(prefix)) : normalized_path
enddef

def EntryDepthPrefix(depth: number): string
  return repeat(' ', depth * TREE_INDENTATION)
enddef

def MakeState(dir: string): dict<any>
  return {
    cwd: dir,
    entries: [],
    expanded_dirs: {dir: true},
    marked_paths: {},
    clipboard_paths: [],
    clipboard_mode: '',
    file_search_query: '',
    sort_mode: 'name',
  }
enddef

def EnsureState(): dict<any>
  var bufnr = bufnr('%')
  if !has_key(state_by_bufnr, bufnr)
    state_by_bufnr[bufnr] = MakeState(getcwd())
  endif
  return state_by_bufnr[bufnr]
enddef

def CompareItems(dir: string, sort_mode: string, left_name: string, right_name: string): number
  var left_path = JoinPath(dir, left_name)
  var right_path = JoinPath(dir, right_name)
  var left_dir = IsDirectory(left_path)
  var right_dir = IsDirectory(right_path)

  if left_dir != right_dir
    return left_dir ? -1 : 1
  endif

  if sort_mode ==# 'size'
    var left_size = left_dir ? 0 : getfsize(left_path)
    var right_size = right_dir ? 0 : getfsize(right_path)
    if left_size != right_size
      return left_size > right_size ? -1 : 1
    endif
  elseif sort_mode ==# 'time'
    var left_time = getftime(left_path)
    var right_time = getftime(right_path)
    if left_time != right_time
      return left_time > right_time ? -1 : 1
    endif
  endif

  return left_name ==# right_name ? 0 : (left_name <# right_name ? -1 : 1)
enddef

def SortedChildren(dir: string, sort_mode: string): list<string>
  var names = readdir(dir)
  sort(names, (left, right) => CompareItems(dir, sort_mode, left, right))
  return names
enddef

def AddTreeEntries(entries: list<dict<any>>, dir: string, depth: number, state: dict<any>)
  for name in SortedChildren(dir, state.sort_mode)
    var path = JoinPath(dir, name)
    if IsDirectory(path)
      add(entries, {
        kind: 'dir',
        name: name,
        path: path,
        depth: depth,
      })
      if get(state.expanded_dirs, path, false)
        AddTreeEntries(entries, path, depth + 1, state)
      endif
    else
      add(entries, {
        kind: 'file',
        name: name,
        path: path,
        depth: depth,
      })
    endif
  endfor
enddef

def SearchTree(dir: string, root: string, state: dict<any>, entries: list<dict<any>>)
  for name in SortedChildren(dir, state.sort_mode)
    var path = JoinPath(dir, name)
    if stridx(tolower(name), tolower(state.file_search_query)) >= 0
      add(entries, {
        kind: IsDirectory(path) ? 'dir' : 'file',
        name: RelativePath(root, path),
        path: path,
        depth: 0,
      })
    endif

    if IsDirectory(path)
      SearchTree(path, root, state, entries)
    endif
  endfor
enddef

def BuildEntries(state: dict<any>): list<dict<any>>
  var entries: list<dict<any>> = []
  var parent = ParentDir(state.cwd)

  if parent !=# state.cwd
    add(entries, {
      kind: 'parent',
      name: '..',
      path: parent,
      depth: 0,
    })
  endif

  if empty(state.file_search_query)
    AddTreeEntries(entries, state.cwd, 0, state)
  else
    SearchTree(state.cwd, state.cwd, state, entries)
  endif

  return entries
enddef

def IsMarked(state: dict<any>, path: string): bool
  return get(state.marked_paths, path, false)
enddef

def DisplayName(state: dict<any>, entry: dict<any>): string
  if entry.kind ==# 'parent'
    return '../'
  endif

  var mark = IsMarked(state, entry.path) ? MARKED_FILE_ICON : ' '
  var prefix = EntryDepthPrefix(entry.depth)

  if entry.kind ==# 'dir'
    var icon = get(state.expanded_dirs, entry.path, false) && empty(state.file_search_query)
      ? TREE_OPENED_ICON
      : TREE_CLOSED_ICON
    return prefix .. mark .. icon .. ' ' .. entry.name .. '/'
  endif

  return prefix .. mark .. TREE_LEAF_ICON .. FILE_ICON .. entry.name
enddef

def TruncateDisplayText(text: string, max_width: number): string
  if max_width <= 0
    return ''
  endif

  if strdisplaywidth(text) <= max_width
    return text
  endif

  if max_width <= 3
    return repeat('.', max_width)
  endif

  var head = ''
  for char in split(text, '\zs')
    if strdisplaywidth(head .. char .. '...') > max_width
      break
    endif
    head ..= char
  endfor
  return head .. '...'
enddef

def EntryTimestamp(entry: dict<any>): string
  if entry.kind ==# 'parent'
    return ''
  endif

  var mtime = getftime(entry.path)
  return mtime < 0 ? '' : strftime(TIMESTAMP_FORMAT, mtime)
enddef

def HumanFileSize(path: string): string
  var size = getfsize(path)
  if size < 0
    return '     '
  endif

  var units = ['B', 'K', 'M', 'G', 'T', 'P']
  var value = str2float(string(size))
  var unit_index = 0
  while value >= 1024.0 && unit_index < len(units) - 1
    value /= 1024.0
    unit_index += 1
  endwhile

  var text = ''
  if unit_index == 0
    text = printf('%dB', float2nr(value))
  elseif value < 10.0
    text = printf('%.1f%s', value, units[unit_index])
  else
    text = printf('%.0f%s', value, units[unit_index])
  endif
  return printf('%5s', text)
enddef

def EntrySize(entry: dict<any>): string
  if entry.kind !=# 'file'
    return '     '
  endif

  return HumanFileSize(entry.path)
enddef

def FormatEntryLine(state: dict<any>, entry: dict<any>, width: number): string
  var name = DisplayName(state, entry)
  if entry.kind ==# 'parent'
    return TruncateDisplayText(name, width)
  endif

  var size = EntrySize(entry)
  var timestamp = EntryTimestamp(entry)
  var meta = empty(timestamp) ? size : size .. ' ' .. timestamp
  if empty(meta)
    return TruncateDisplayText(name, width)
  endif

  var meta_width = strdisplaywidth(meta)
  if width <= meta_width
    return TruncateDisplayText(meta, width)
  endif

  var name_width = width - meta_width - 1
  var left = TruncateDisplayText(name, name_width)
  return left .. repeat(' ', width - strdisplaywidth(left) - meta_width) .. meta
enddef

def MarkCount(state: dict<any>): number
  return len(keys(state.marked_paths))
enddef

def UpdateStatusline(state: dict<any>)
  var dir_count = 0
  var file_count = 0

  for entry in state.entries
    if entry.kind ==# 'dir'
      dir_count += 1
    elseif entry.kind ==# 'file'
      file_count += 1
    endif
  endfor

  var search = empty(state.file_search_query) ? '' : $' search:{state.file_search_query}'
  var clip = empty(state.clipboard_mode) ? '' : $' clip:{state.clipboard_mode}({len(state.clipboard_paths)})'
  &l:statusline = EscapeStatusline(
    $' filer {state.cwd}  sort:{state.sort_mode} dirs:{dir_count} files:{file_count} marks:{MarkCount(state)}{search}{clip} '
  )
enddef

def CurrentEntryIndex(state: dict<any>): number
  return line('.') - 2
enddef

def CurrentEntry(state: dict<any>): dict<any>
  var index = CurrentEntryIndex(state)
  if index < 0 || index >= len(state.entries)
    return {}
  endif
  return state.entries[index]
enddef

def CurrentPath(state: dict<any>): string
  var entry = CurrentEntry(state)
  return empty(entry) ? '' : entry.path
enddef

def JumpToPath(target_path: string)
  var bufnr = bufnr('%')
  if !has_key(state_by_bufnr, bufnr)
    return
  endif

  var target = NormalizePath(target_path)
  var state = state_by_bufnr[bufnr]
  for index in range(len(state.entries))
    if state.entries[index].path ==# target
      cursor(index + 2, 1)
      return
    endif
  endfor

  cursor(2, 1)
enddef

export def JumpToTop()
  cursor(min([3, line('$')]), 1)
enddef

def Render()
  var bufnr = bufnr('%')
  if !has_key(state_by_bufnr, bufnr)
    return
  endif

  var state = state_by_bufnr[bufnr]
  state.entries = BuildEntries(state)
  var width = max([1, winwidth(0)])

  var lines = [TruncateDisplayText(state.cwd, width)]
  for entry in state.entries
    add(lines, FormatEntryLine(state, entry, width))
  endfor
  if len(state.entries) == 0
    add(lines, TruncateDisplayText('(empty)', width))
  endif

  &l:modifiable = true
  setbufline(bufnr, 1, lines)
  if line('$') > len(lines)
    deletebufline(bufnr, len(lines) + 1, line('$'))
  endif
  &l:modifiable = false
  UpdateStatusline(state)
enddef

def SetupBuffer()
  var current_bufnr = bufnr('%')
  setlocal buftype=nofile
  setlocal bufhidden=hide
  setlocal noswapfile
  setlocal nowrap
  setlocal nonumber
  setlocal norelativenumber
  setlocal foldcolumn=0
  setlocal signcolumn=no
  setlocal nomodifiable
  setlocal filetype=filer
  setlocal syntax=filer
  setlocal laststatus=2

  augroup filer_buffer_lifecycle
    execute 'autocmd! * <buffer=' .. current_bufnr .. '>'
    execute 'autocmd BufHidden <buffer=' .. current_bufnr .. '> call filer#ClearMarksForCurrentBuffer()'
    execute 'autocmd BufWipeout <buffer=' .. current_bufnr .. '> call filer#CleanupStateForCurrentBuffer()'
  augroup END

  nnoremap <silent><buffer> q <Cmd>close<CR>
  nnoremap <silent><buffer> <CR> <Cmd>call filer#Enter()<CR>
  nnoremap <silent><buffer> t <Cmd>call filer#ToggleTree()<CR>
  nnoremap <silent><buffer> ~ <Cmd>call filer#GoHome()<CR>
  nnoremap <silent><buffer> \ <Cmd>call filer#GoRoot()<CR>
  nnoremap <silent><buffer> h <Cmd>call filer#GoParent()<CR>
  nnoremap <silent><buffer> l <Cmd>call filer#GoChild()<CR>
  nnoremap <silent><buffer><nowait> <Space> <Cmd>call filer#ToggleMark()<CR>
  nnoremap <silent><buffer> * <Cmd>call filer#MarkAll()<CR>
  nnoremap <silent><buffer> a <Cmd>call filer#Create()<CR>
  nnoremap <silent><buffer> dd <Cmd>call filer#DeleteCurrent()<CR>
  nnoremap <silent><buffer> gg <Cmd>call filer#JumpToTop()<CR>
  nnoremap <silent><buffer> r <Cmd>call filer#RenameCurrent()<CR>
  nnoremap <silent><buffer> m <Cmd>call filer#MoveCurrent()<CR>
  nnoremap <silent><buffer> yy <Cmd>call filer#YankCurrentPathToClipboard()<CR>
  nnoremap <silent><buffer> y <Cmd>call filer#Yank()<CR>
  nnoremap <silent><buffer> x <Cmd>call filer#Cut()<CR>
  nnoremap <silent><buffer> p <Cmd>call filer#Paste()<CR>
  nnoremap <silent><buffer> <C-F> <Cmd>call filer#SearchFiles()<CR>
  nnoremap <silent><buffer> s <Cmd>call filer#CycleSort()<CR>
enddef

def SetCwd(state: dict<any>, dir: string, reset_tree: bool = false)
  var previous_dir = state.cwd
  state.cwd = NormalizeDir(dir)
  if !empty(previous_dir) && previous_dir !=# state.cwd
    state.marked_paths = {}
  endif
  if reset_tree
    state.expanded_dirs = {}
    state.expanded_dirs[state.cwd] = true
  else
    state.expanded_dirs[state.cwd] = true
  endif
  execute 'lcd ' .. fnameescape(state.cwd)
  if exists('*unite#repo#Append')
    try
      unite#repo#Append(state.cwd)
    catch
    endtry
  endif
enddef

def RefreshState(state: dict<any>, cursor_path: string = '')
  Render()
  JumpToPath(cursor_path)
enddef

def SelectedPaths(state: dict<any>): list<string>
  if MarkCount(state) > 0
    return sort(keys(state.marked_paths))
  endif

  var current_path = CurrentPath(state)
  return empty(current_path) ? [] : [current_path]
enddef

def RemoveMark(state: dict<any>, path: string)
  if has_key(state.marked_paths, path)
    remove(state.marked_paths, path)
  endif
enddef

def ClearInvalidMarks(state: dict<any>)
  for path in copy(keys(state.marked_paths))
    if !PathExists(path)
      remove(state.marked_paths, path)
    endif
  endfor
enddef

def CurrentTargetDirectory(state: dict<any>): string
  var entry = CurrentEntry(state)
  if !empty(entry) && entry.kind ==# 'dir'
    return entry.path
  endif
  return state.cwd
enddef

def EnsureParentDir(path: string)
  var parent = ParentDir(path)
  if !isdirectory(parent)
    mkdir(parent, 'p')
  endif
enddef

def CopyFile(src: string, dest: string)
  EnsureParentDir(dest)
  writefile(readfile(src, 'b'), dest, 'b')
enddef

def CopyPath(src: string, dest: string)
  if PathExists(dest)
    throw $'Destination already exists: {dest}'
  endif

  if IsDirectory(src)
    mkdir(dest, 'p')
    for name in readdir(src)
      CopyPath(JoinPath(src, name), JoinPath(dest, name))
    endfor
    return
  endif

  CopyFile(src, dest)
enddef

def DeletePath(path: string)
  if IsDirectory(path)
    delete(path, 'rf')
  else
    delete(path)
  endif
enddef

def Prompt(prompt: string, default_value: string = ''): string
  return input(prompt, default_value)
enddef

def Confirm(message: string): bool
  return confirm(message, "&Yes\n&No", 2) == 1
enddef

def BufferNameInUse(name: string, current_bufnr: number): bool
  for info in getbufinfo()
    if info.bufnr != current_bufnr && bufname(info.bufnr) ==# name
      return true
    endif
  endfor

  return false
enddef

def MakeBufferName(dir: string, current_bufnr: number): string
  var base = '[filer] ' .. dir
  if !BufferNameInUse(base, current_bufnr)
    return base
  endif

  var suffix = 2
  var candidate = $'{base} ({suffix})'
  while BufferNameInUse(candidate, current_bufnr)
    suffix += 1
    candidate = $'{base} ({suffix})'
  endwhile
  return candidate
enddef

def OpenOrReuse(dir: string, reset_tree: bool = true)
  var current_bufnr = bufnr('%')
  if &filetype !=# 'filer' || !has_key(state_by_bufnr, current_bufnr)
    enew
  endif
  current_bufnr = bufnr('%')
  execute 'file ' .. fnameescape(MakeBufferName(dir, current_bufnr))
  SetupBuffer()

  var bufnr = bufnr('%')
  var prev = has_key(state_by_bufnr, bufnr) ? state_by_bufnr[bufnr] : MakeState(dir)
  state_by_bufnr[bufnr] = prev
  SetCwd(prev, dir, reset_tree)
  ClearInvalidMarks(prev)
  Render()
  cursor(2, 1)
enddef

export def Open(dir_arg: string = '', reset_tree: bool = true)
  var dir = NormalizeDir(dir_arg)
  if !isdirectory(dir)
    echoerr $'Not a directory: {dir}'
    return
  endif

  OpenOrReuse(dir, reset_tree)
enddef

export def OpenBufferDir()
  if &filetype ==# 'filer'
    var state = EnsureState()
    Open(state.cwd, false)
    return
  endif

  var target = expand('%:p')
  var dir = expand('%:p:h')
  if empty(dir)
    dir = getcwd()
  endif
  Open(dir)
  if !empty(target)
    JumpToPath(target)
  endif
enddef

export def Refresh()
  var state = EnsureState()
  var current_path = CurrentPath(state)
  ClearInvalidMarks(state)
  RefreshState(state, current_path)
enddef

export def Enter()
  var state = EnsureState()
  var entry = CurrentEntry(state)
  if empty(entry)
    return
  endif

  if entry.kind ==# 'file'
    execute 'edit ' .. fnameescape(entry.path)
    return
  endif

  if entry.kind ==# 'parent'
    Open(entry.path)
    return
  endif

  Open(entry.path)
  JumpToTop()
enddef

export def ToggleTree()
  var state = EnsureState()
  if !empty(state.file_search_query)
    return
  endif

  var entry = CurrentEntry(state)
  if empty(entry) || entry.kind !=# 'dir'
    return
  endif

  state.expanded_dirs[entry.path] = !get(state.expanded_dirs, entry.path, false)
  RefreshState(state, entry.path)
enddef

export def GoParent()
  var state = EnsureState()
  var current_dir = state.cwd
  Open(ParentDir(current_dir))
  JumpToPath(current_dir)
enddef

export def GoHome()
  Open('~')
enddef

export def GoRoot()
  var state = EnsureState()
  Open(FilesystemRoot(state.cwd))
enddef

export def GoChild()
  var state = EnsureState()
  var entry = CurrentEntry(state)
  if empty(entry)
    return
  endif

  if entry.kind ==# 'file'
    execute 'edit ' .. fnameescape(entry.path)
    return
  endif

  if entry.kind !=# 'dir'
    return
  endif

  Open(entry.path)
enddef

export def ToggleMark()
  var state = EnsureState()
  var path = CurrentPath(state)
  var current_index = CurrentEntryIndex(state)
  if empty(path)
    return
  endif

  if IsMarked(state, path)
    RemoveMark(state, path)
  else
    state.marked_paths[path] = true
  endif
  RefreshState(state, path)
  var target_line = current_index + 3 > line('$') ? 3 : current_index + 3
  if target_line >= 3
    cursor(target_line, 1)
  endif
enddef

export def ClearMarks()
  var state = EnsureState()
  state.marked_paths = {}
  RefreshState(state, CurrentPath(state))
enddef

export def ClearMarksForCurrentBuffer()
  var bufnr = bufnr('%')
  if !has_key(state_by_bufnr, bufnr)
    return
  endif

  state_by_bufnr[bufnr].marked_paths = {}
enddef

export def CleanupStateForCurrentBuffer()
  var bufnr = bufnr('%')
  if has_key(state_by_bufnr, bufnr)
    remove(state_by_bufnr, bufnr)
  endif
enddef

export def MarkAll()
  var state = EnsureState()
  var all_marked = true
  var has_markable_entry = false

  for entry in state.entries
    if entry.kind !=# 'parent'
      has_markable_entry = true
      if !IsMarked(state, entry.path)
        all_marked = false
        break
      endif
    endif
  endfor

  if all_marked && has_markable_entry
    state.marked_paths = {}
    RefreshState(state, CurrentPath(state))
    return
  endif

  state.marked_paths = {}
  for entry in state.entries
    if entry.kind !=# 'parent'
      state.marked_paths[entry.path] = true
    endif
  endfor
  RefreshState(state, CurrentPath(state))
enddef

export def Create()
  var state = EnsureState()
  var raw = Prompt('Create file or dir: ')
  if empty(raw)
    return
  endif

  var path = ResolvePath(state.cwd, raw)
  if PathExists(path)
    echoerr $'Already exists: {path}'
    return
  endif

  if raw =~ '[\/]$'
    mkdir(path, 'p')
  else
    EnsureParentDir(path)
    writefile([], path)
  endif

  RefreshState(state, path)
enddef

export def DeleteCurrent()
  var state = EnsureState()
  var path = CurrentPath(state)
  if empty(path)
    return
  endif

  if !Confirm($'Delete {path}?')
    return
  endif

  DeletePath(path)
  RemoveMark(state, path)
  RefreshState(state, ParentDir(path))
enddef

export def DeleteMarked()
  var state = EnsureState()
  var paths = sort(keys(state.marked_paths))
  if len(paths) == 0
    Notify('No marked paths')
    return
  endif

  if !Confirm($'Delete {len(paths)} marked paths?')
    return
  endif

  for path in paths
    if PathExists(path)
      DeletePath(path)
    endif
  endfor

  state.marked_paths = {}
  RefreshState(state, state.cwd)
enddef

export def RenameCurrent()
  var state = EnsureState()
  var path = CurrentPath(state)
  if empty(path)
    return
  endif

  var new_name = Prompt('Rename to: ', Basename(path))
  if empty(new_name) || new_name ==# Basename(path)
    return
  endif

  var dest = JoinPath(ParentDir(path), new_name)
  if PathExists(dest)
    echoerr $'Already exists: {dest}'
    return
  endif

  rename(path, dest)
  if IsMarked(state, path)
    RemoveMark(state, path)
    state.marked_paths[dest] = true
  endif
  RefreshState(state, dest)
enddef

export def RenameMarked()
  var state = EnsureState()
  var paths = sort(keys(state.marked_paths))
  if len(paths) == 0
    Notify('No marked paths')
    return
  endif

  var renamed: list<string> = []
  for path in paths
    if !PathExists(path)
      continue
    endif

    var new_name = Prompt($'Rename {Basename(path)} to: ', Basename(path))
    if empty(new_name) || new_name ==# Basename(path)
      add(renamed, path)
      continue
    endif

    var dest = JoinPath(ParentDir(path), new_name)
    if PathExists(dest)
      echoerr $'Already exists: {dest}'
      continue
    endif

    rename(path, dest)
    add(renamed, dest)
  endfor

  state.marked_paths = {}
  for path in renamed
    state.marked_paths[path] = true
  endfor
  RefreshState(state, len(renamed) > 0 ? renamed[0] : state.cwd)
enddef

export def MoveCurrent()
  var state = EnsureState()
  var path = CurrentPath(state)
  if empty(path)
    return
  endif

  var dest = Prompt('Move to: ', JoinPath(state.cwd, Basename(path)))
  if empty(dest)
    return
  endif
  dest = ResolvePath(state.cwd, dest)

  if PathExists(dest)
    echoerr $'Already exists: {dest}'
    return
  endif

  EnsureParentDir(dest)
  rename(path, dest)
  if IsMarked(state, path)
    RemoveMark(state, path)
    state.marked_paths[dest] = true
  endif
  RefreshState(state, dest)
enddef

export def Yank()
  var state = EnsureState()
  var paths = SelectedPaths(state)
  if len(paths) == 0
    return
  endif

  state.clipboard_paths = paths
  state.clipboard_mode = 'copy'
  Notify($'Yanked {len(paths)} path(s)')
  RefreshState(state, paths[0])
enddef

export def YankCurrentPathToClipboard()
  var state = EnsureState()
  var path = line('.') == 1 ? state.cwd : CurrentPath(state)
  if empty(path)
    return
  endif

  setreg('+', path)
  Notify($'Copied to clipboard: {path}')
  RefreshState(state, path)
enddef

export def Cut()
  var state = EnsureState()
  var paths = SelectedPaths(state)
  if len(paths) == 0
    return
  endif

  state.clipboard_paths = paths
  state.clipboard_mode = 'cut'
  Notify($'Cut {len(paths)} path(s)')
  RefreshState(state, paths[0])
enddef

export def Paste()
  var state = EnsureState()
  if empty(state.clipboard_mode) || len(state.clipboard_paths) == 0
    Notify('Clipboard is empty')
    return
  endif

  var target_dir = CurrentTargetDirectory(state)
  var pasted: list<string> = []

  try
    for src in state.clipboard_paths
      if !PathExists(src)
        continue
      endif

      var dest = JoinPath(target_dir, Basename(src))
      if state.clipboard_mode ==# 'copy'
        CopyPath(src, dest)
      else
        if PathExists(dest)
          throw $'Destination already exists: {dest}'
        endif
        rename(src, dest)
      endif
      add(pasted, dest)
    endfor
  catch
    echoerr v:exception
    return
  endtry

  if state.clipboard_mode ==# 'cut'
    state.clipboard_mode = ''
    state.clipboard_paths = []
    state.marked_paths = {}
  endif

  RefreshState(state, len(pasted) > 0 ? pasted[0] : target_dir)
enddef

export def SearchFiles()
  var state = EnsureState()
  var query = Prompt('Search filename: ', state.file_search_query)
  state.file_search_query = query
  RefreshState(state, state.cwd)
enddef

export def CycleSort()
  var state = EnsureState()
  var current_index = index(SORT_MODES, state.sort_mode)
  state.sort_mode = SORT_MODES[(current_index + 1) % len(SORT_MODES)]
  RefreshState(state, CurrentPath(state))
enddef

export def MaybeOpenDir(path: string)
  if &buftype !=# '' || &filetype ==# 'filer'
    return
  endif

  var dir = NormalizeDir(path)
  if empty(path) || !isdirectory(dir)
    return
  endif

  Open(dir)
enddef
