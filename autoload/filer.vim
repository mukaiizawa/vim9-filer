vim9script

var state_by_bufnr: dict<any> = {}
var rename_state_by_bufnr: dict<any> = {}
var copy_state_by_bufnr: dict<any> = {}
var last_open_error = ''
var active_jobs: list<job> = []

const SEARCH_HIGHLIGHT_PROP = 'FilerSearchMatch'
const DEFAULT_TREE_INDENTATION = 2
const DEFAULT_TREE_ICONS = {
  leaf: '|',
  opened: '-',
  closed: '+',
  file: ' ',
  marked: '*',
}
const SORT_MODES = ['name', 'size', 'time']
const TIMESTAMP_FORMAT = '%Y-%m-%d %H:%M'
const SECONDS_PER_DAY = 24 * 60 * 60
const TIMESTAMP_PLACEHOLDER = '-'
const META_RESERVED_WIDTH = 5 + 1 + 16
const TIMESTAMP_HIGHLIGHT_GROUPS = [
  'FilerTimestampVeryFresh',
  'FilerTimestampFresh',
  'FilerTimestampRecent',
  'FilerTimestampNeutral',
  'FilerTimestampOld',
  'FilerTimestampVeryOld',
  'FilerTimestampUnknown',
]
const ENTRY_DIR = 'dir'
const ENTRY_FILE = 'file'
const HEADER_LINE = 1
const FIRST_ENTRY_LINE = HEADER_LINE + 1
const FILE_OPEN_COMMANDS = ['edit', 'split', 'vsplit', 'tabedit', 'drop']
const FILER_OPEN_COMMANDS = ['edit', 'split', 'vsplit', 'tabedit']
const FILER_MAPPING_SPECS = [
  {action: 'close', lhs: 'q', plug: '<Plug>(filer-close)', nowait: false},
  {action: 'open', lhs: ['<CR>', 'l'], plug: '<Plug>(filer-open)', nowait: false},
  {action: 'open_split', lhs: 's', plug: '<Plug>(filer-open-split)', nowait: false},
  {action: 'open_vsplit', lhs: 'v', plug: '<Plug>(filer-open-vsplit)', nowait: false},
  {action: 'open_tab', lhs: 't', plug: '<Plug>(filer-open-tab)', nowait: false},
  {action: 'open_drop', lhs: 'o', plug: '<Plug>(filer-open-drop)', nowait: false},
  {action: 'duplicate', lhs: '<Tab>', plug: '<Plug>(filer-duplicate)', nowait: false},
  {action: 'toggle_tree', lhs: 'za', plug: '<Plug>(filer-toggle-tree)', nowait: false},
  {action: 'toggle_tree_recursive', lhs: 'zA', plug: '<Plug>(filer-toggle-tree-recursive)', nowait: false},
  {action: 'home', lhs: '~', plug: '<Plug>(filer-go-home)', nowait: false},
  {action: 'root', lhs: "\\", plug: '<Plug>(filer-go-root)', nowait: false},
  {action: 'parent', lhs: 'h', plug: '<Plug>(filer-go-parent)', nowait: false},
  {action: 'refresh', lhs: '.', plug: '<Plug>(filer-refresh)', nowait: false},
  {action: 'toggle_mark', lhs: '<Space>', plug: '<Plug>(filer-toggle-mark)', nowait: true},
  {action: 'toggle_all_marks', lhs: '*', plug: '<Plug>(filer-toggle-all-marks)', nowait: false},
  {action: 'create', lhs: 'a', plug: '<Plug>(filer-create)', nowait: false},
  {action: 'copy_or_mark', lhs: 'c', plug: '<Plug>(filer-copy-or-mark)', nowait: false},
  {action: 'delete_or_mark', lhs: 'd', plug: '<Plug>(filer-delete-or-mark)', nowait: true},
  {action: 'first_entry', lhs: 'gg', plug: '<Plug>(filer-jump-first-entry)', nowait: false},
  {action: 'rename_or_mark', lhs: 'r', plug: '<Plug>(filer-rename-or-mark)', nowait: false},
  {action: 'open_external', lhs: 'x', plug: '<Plug>(filer-open-external)', nowait: false},
  {action: 'yank_path', lhs: 'yy', plug: '<Plug>(filer-yank-path)', nowait: false},
  {action: 'search', lhs: '/', plug: '<Plug>(filer-search)', nowait: true},
  {action: 'next_search_result', lhs: 'n', plug: '<Plug>(filer-next-search-result)', nowait: true},
  {action: 'previous_search_result', lhs: 'N', plug: '<Plug>(filer-previous-search-result)', nowait: true},
  {action: 'cycle_sort', lhs: 'S', plug: '<Plug>(filer-cycle-sort)', nowait: true},
]
const BATCH_MAPPING_SPECS = [
  {action: 'close', lhs: 'q', plug: '<Plug>(filer-batch-close)', nowait: false},
]

# config

def NoDefaultMappings(): bool
  return get(g:, 'filer_no_default_mappings', false) ? true : false
enddef

def MappingConfig(var_name: string): dict<any>
  var config = get(g:, var_name, {})
  return type(config) == v:t_dict ? config : {}
enddef

def HasMappingConfig(var_name: string): bool
  return type(get(g:, var_name, 0)) == v:t_dict
enddef

def ViewConfig(): dict<any>
  var config = get(g:, 'filer_view', {})
  return type(config) == v:t_dict ? config : {}
enddef

def ViewIndent(): number
  var value = get(ViewConfig(), 'indent', DEFAULT_TREE_INDENTATION)
  return type(value) == v:t_number && value >= 0 ? value : DEFAULT_TREE_INDENTATION
enddef

def ViewIcons(): dict<any>
  var icons = copy(DEFAULT_TREE_ICONS)
  var configured_icons = get(ViewConfig(), 'icons', {})
  if type(configured_icons) != v:t_dict
    return icons
  endif
  for key in keys(icons)
    var value = get(configured_icons, key, icons[key])
    if type(value) == v:t_string && !empty(value)
      icons[key] = value
    endif
  endfor
  return icons
enddef

def MappingList(value: any): list<string>
  if type(value) == v:t_string
    return empty(value) ? [] : [value]
  endif
  if type(value) != v:t_list
    return []
  endif
  var mappings: list<string> = []
  for item in value
    if type(item) == v:t_string && !empty(item)
      add(mappings, item)
    endif
  endfor
  return mappings
enddef

def HasBufferLocalNormalMapping(lhs: string): bool
  var info = maparg(lhs, 'n', false, true)
  return !empty(info) && get(info, 'buffer', 0) != 0
enddef

def MapKeyToPlug(lhs: string, plug: string, nowait: bool)
  if HasBufferLocalNormalMapping(lhs)
    return
  endif
  var flags = '<silent><buffer>'
  if nowait
    flags ..= '<nowait>'
  endif
  execute 'nmap ' .. flags .. ' ' .. lhs .. ' ' .. plug
enddef

def ApplyMappingSpecs(specs: list<dict<any>>, config_var_name: string)
  var no_default = NoDefaultMappings()
  var has_config = HasMappingConfig(config_var_name)
  if no_default && !has_config
    return
  endif
  var config = MappingConfig(config_var_name)
  for spec in specs
    var action: string = spec.action
    if no_default && !has_key(config, action)
      continue
    endif
    var plug: string = spec.plug
    var lhs = get(config, action, spec.lhs)
    var nowait: bool = spec.nowait
    for key in MappingList(lhs)
      MapKeyToPlug(key, plug, nowait)
    endfor
  endfor
enddef

def ConfigString(var_name: string, default_value: string): string
  var value = get(g:, var_name, default_value)
  return type(value) == v:t_string ? value : default_value
enddef

def ResolveOpenCommand(command: string, config_var_name: string, default_command: string, allowed_commands: list<string>): string
  var resolved = empty(command) ? ConfigString(config_var_name, default_command) : command
  if index(allowed_commands, resolved) >= 0
    return resolved
  endif
  echoerr $'Invalid g:{config_var_name}: {resolved}. Expected one of: {join(allowed_commands, ", ")}'
  return default_command
enddef

def ResolveFileOpenCommand(command: string = ''): string
  return ResolveOpenCommand(command, 'filer_file_open_command', 'edit', FILE_OPEN_COMMANDS)
enddef

def ResolveDirectoryOpenCommand(command: string = ''): string
  if command ==# 'drop'
    return 'edit'
  endif
  return ResolveOpenCommand(command, 'filer_directory_open_command', 'edit', FILER_OPEN_COMMANDS)
enddef

def ResolveLaunchCommand(command: string = ''): string
  return ResolveOpenCommand(command, 'filer_launch_command', 'edit', FILER_OPEN_COMMANDS)
enddef

def ResolveBufferDirCommand(command: string = ''): string
  return ResolveOpenCommand(command, 'filer_buffer_dir_command', 'vsplit', FILER_OPEN_COMMANDS)
enddef

def ResolveDuplicateCommand(command: string = ''): string
  return ResolveOpenCommand(command, 'filer_duplicate_command', 'vsplit', FILER_OPEN_COMMANDS)
enddef

def DisplayDir(path: string): string
  if empty(path) || IsRootPath(path)
    return path
  endif
  return path .. '/'
enddef

def SetLastOpenError(message: string)
  last_open_error = message
enddef

def ClearLastOpenError()
  last_open_error = ''
enddef

def GetLastOpenError(): string
  return last_open_error
enddef

def Prompt(prompt: string, default_value: string = ''): string
  return input(prompt, default_value)
enddef

def Confirm(message: string): bool
  return confirm(message, "&Yes\n&No", 2) == 1
enddef

def IsWindows(): bool
  return has('win32') || has('win64')
enddef

def IsMac(): bool
  return has('mac') || has('macunix')
enddef

def DoVisitDirAutocmd()
  if empty(BufferDir())
    return
  endif
  doautocmd <nomodeline> User FilerVisitDir
enddef

# path and files

def WarnBrokenLink(path: string)
  echohl WarningMsg
  echomsg $'Broken symbolic link: {path}'
  echohl None
enddef

def WarnUnreadableDir(path: string)
  echohl WarningMsg
  echomsg $'Cannot read directory: {path}'
  echohl None
enddef

def PathKey(path: string): string
  var normalized = NormalizePath(path)
  return IsWindows() ? tolower(normalized) : normalized
enddef

def PathExists(path: string): bool
  return filereadable(path) || isdirectory(path) || getftype(path) ==# 'link'
enddef

def IsBrokenLink(path: string): bool
  return getftype(path) ==# 'link' && !filereadable(path) && !isdirectory(path)
enddef

def IsDirectory(path: string): bool
  return isdirectory(path)
enddef

def IsRootPath(path: string): bool
  return path ==# '/'
    || path =~? '^[A-Z]:/$'
    || path =~? '^//[^/]\+/\?[^/]\+/$'
enddef

def IsAbsolutePath(path: string): bool
  var normalized = NormalizeSeparators(ExpandHomePath(path))
  return normalized =~# '^/'
    || normalized =~? '^[A-Z]:/'
    || normalized =~# '^//'
enddef

def NativePath(path: string): string
  return IsWindows() ? substitute(path, '/', '\\', 'g') : path
enddef

def Basename(path: string): string
  return fnamemodify(path, ':t')
enddef

def NormalizeSeparators(path: string): string
  return substitute(path, '\\', '/', 'g')
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
  var normalized_base = TrimTrailingSeparators(base)
  if IsRootPath(normalized_base)
    return NormalizePath(normalized_base .. child)
  endif
  return NormalizePath(normalized_base .. '/' .. child)
enddef

def ResolvePath(base: string, path: string): string
  var expanded = ExpandHomePath(path)
  return IsAbsolutePath(expanded) ? NormalizePath(expanded) : JoinPath(base, expanded)
enddef

def EntryDepthPrefix(depth: number): string
  return repeat(' ', depth * ResolvedViewIndent())
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

def IsSameOrChildPath(parent: string, child: string): bool
  var normalized_parent = PathKey(parent)
  var normalized_child = PathKey(child)
  if normalized_parent ==# normalized_child
    return true
  endif
  var prefix = IsRootPath(normalized_parent) ? normalized_parent : normalized_parent .. '/'
  return stridx(normalized_child, prefix) == 0
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

def SafeReadDir(dir: string): list<string>
  try
    return readdir(dir)
  catch
    WarnUnreadableDir(dir)
    return []
  endtry
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
  var names = SafeReadDir(dir)
  sort(names, (left, right) => CompareItems(dir, sort_mode, left, right))
  return names
enddef

def EnsureParentDir(path: string)
  var parent = ParentDir(path)
  if !isdirectory(parent)
    mkdir(parent, 'p')
  endif
enddef

def DeletePath(path: string)
  if IsDirectory(path)
    delete(path, 'rf')
  else
    delete(path)
  endif
enddef

def MovePath(source: string, destination: string)
  if rename(source, destination) != 0
    throw $'Failed to move {source} to {destination}'
  endif
enddef

# job

def TrackJob(current_job: job)
  CleanupFinishedJobs()
  add(active_jobs, current_job)
enddef

def CleanupFinishedJobs()
  var jobs: list<job> = []
  for current_job in active_jobs
    if job_status(current_job) ==# 'run'
      add(jobs, current_job)
    endif
  endfor
  active_jobs = jobs
enddef

def StartJob(cmd: list<string>): bool
  if !exists('*job_start')
    SetLastOpenError('job_start() is unavailable')
    return false
  endif
  try
    var current_job = job_start(cmd)
    if type(current_job) == v:t_job
      if job_status(current_job) ==# 'fail'
        SetLastOpenError($'job_start() failed for {string(cmd)}')
        return false
      endif
      TrackJob(current_job)
      ClearLastOpenError()
      return true
    endif
    SetLastOpenError($'job_start() did not return a job: {string(current_job)} for {string(cmd)}')
    return false
  catch
    SetLastOpenError($'{v:exception} for {string(cmd)}')
    return false
  endtry
enddef

# entry

def MakeEntry(kind: string, name: string, path: string, depth: number): dict<any>
  return {
    kind: kind,
    name: name,
    path: path,
    depth: depth,
  }
enddef

def MakeFilesystemEntry(name: string, path: string, depth: number): dict<any>
  return MakeEntry(IsDirectory(path) ? ENTRY_DIR : ENTRY_FILE, name, path, depth)
enddef

def EntryMtime(entry: dict<any>): number
  return getftime(entry.path)
enddef

def EntryTimestamp(entry: dict<any>): string
  var mtime = EntryMtime(entry)
  return mtime < 0 ? TIMESTAMP_PLACEHOLDER : strftime(TIMESTAMP_FORMAT, mtime)
enddef

def EntrySize(entry: dict<any>): string
  if entry.kind !=# ENTRY_FILE
    return '     '
  endif
  var size = getfsize(entry.path)
  if size < 0
    return printf('%5s', TIMESTAMP_PLACEHOLDER)
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

def EntryUnderCursor(state: dict<any>): dict<any>
  var index = line('.') - FIRST_ENTRY_LINE
  if index < 0 || index >= len(state.entries)
    return {}
  endif
  return state.entries[index]
enddef

# state

def MakeState(dir: string): dict<any>
  return {
    cwd: dir,
    entries: [],
    expanded_dirs: {dir: true},
    marked_paths: {},
    file_search_query: '',
    search_matches: [],
    sort_mode: 'name',
  }
enddef

def MissingStateError(bufnr: number): string
  return $'filer state is missing for buffer {bufnr} ({bufname(bufnr)}); filetype={&filetype}; cwd={getcwd()}; close and reopen the filer buffer'
enddef

def EnsureState(): dict<any>
  var bufnr = bufnr('%')
  if !has_key(state_by_bufnr, bufnr)
    throw MissingStateError(bufnr)
  endif
  return state_by_bufnr[bufnr]
enddef

def AddTreeEntries(entries: list<dict<any>>, dir: string, depth: number, state: dict<any>)
  for name in SortedChildren(dir, state.sort_mode)
    var path = JoinPath(dir, name)
    var entry = MakeFilesystemEntry(name, path, depth)
    add(entries, entry)
    if entry.kind ==# ENTRY_DIR && get(state.expanded_dirs, path, false)
      AddTreeEntries(entries, path, depth + 1, state)
    endif
  endfor
enddef

def ExpandSubtreeRecursive(state: dict<any>, dir: string, visited: dict<bool>)
  var dir_key = PathKey(dir)
  if has_key(visited, dir_key)
    return
  endif
  visited[dir_key] = true
  state.expanded_dirs[dir] = true
  for name in SafeReadDir(dir)
    var path = JoinPath(dir, name)
    if IsDirectory(path)
      ExpandSubtreeRecursive(state, path, visited)
    endif
  endfor
enddef

def CollapseSubtreeRecursive(state: dict<any>, dir: string)
  for path in copy(keys(state.expanded_dirs))
    if path !=# state.cwd && IsSameOrChildPath(dir, path)
      remove(state.expanded_dirs, path)
    endif
  endfor
enddef

def SearchCasePrefix(query: string): string
  if &ignorecase && (!&smartcase || query !~# '\u')
    return '\c'
  endif
  return '\C'
enddef

def SearchPattern(query: string): string
  return empty(query) ? '' : SearchCasePrefix(query) .. query
enddef

def SearchPatternError(query: string): string
  if empty(query)
    return ''
  endif
  try
    match('', SearchPattern(query))
  catch
    return v:exception
  endtry
  return ''
enddef

def SearchNameMatches(name: string, pattern: string): bool
  try
    return name =~ pattern
  catch
    return false
  endtry
enddef

def SearchTree(dir: string, root: string, state: dict<any>, pattern: string, entries: list<dict<any>>)
  for name in SortedChildren(dir, state.sort_mode)
    var path = JoinPath(dir, name)
    if SearchNameMatches(name, pattern)
      add(entries, MakeFilesystemEntry(RelativePath(root, path), path, 0))
    endif
    if IsDirectory(path)
      SearchTree(path, root, state, pattern, entries)
    endif
  endfor
enddef

def BuildEntries(state: dict<any>): list<dict<any>>
  var entries: list<dict<any>> = []
  if empty(state.file_search_query)
    AddTreeEntries(entries, state.cwd, 0, state)
  else
    SearchTree(state.cwd, state.cwd, state, SearchPattern(state.file_search_query), entries)
  endif
  return entries
enddef

# Jump

def JumpToPath(target_path: string)
  var bufnr = bufnr('%')
  if !has_key(state_by_bufnr, bufnr)
    return
  endif
  var target = NormalizePath(target_path)
  var state = state_by_bufnr[bufnr]
  for index in range(len(state.entries))
    if state.entries[index].path ==# target
      cursor(FIRST_ENTRY_LINE + index, 1)
      return
    endif
  endfor
  JumpToFirstEntry()
enddef

# Mark

def MarkEntry(state: dict<any>, entry: dict<any>)
  if empty(entry)
    return
  endif
  state.marked_paths[entry.path] = true
enddef

def IsMarked(state: dict<any>, entry: dict<any>): bool
  if empty(entry)
    return false
  endif
  return get(state.marked_paths, entry.path, false)
enddef

def HasMarks(state: dict<any>): bool
  return !empty(state.marked_paths)
enddef

def MarkedPaths(state: dict<any>): list<string>
  return sort(keys(state.marked_paths))
enddef

def ClearInvalidMarks(state: dict<any>)
  for path in copy(keys(state.marked_paths))
    if !PathExists(path)
      remove(state.marked_paths, path)
    endif
  endfor
enddef

def ClearAllMarks(state: dict<any>)
  state.marked_paths = {}
enddef

def ClearAllMarksForBuffer(bufnr: number)
  if has_key(state_by_bufnr, bufnr)
    ClearAllMarks(state_by_bufnr[bufnr])
  endif
enddef

def RemoveMark(state: dict<any>, entry: dict<any>)
  if IsMarked(state, entry)
    remove(state.marked_paths, entry.path)
  endif
enddef

def DisplayName(state: dict<any>, entry: dict<any>): string
  var icons = ResolvedViewIcons()
  var mark = IsMarked(state, entry)
    ? icons.marked
    : repeat(' ', strdisplaywidth(icons.marked))
  var prefix = EntryDepthPrefix(entry.depth)
  if entry.kind ==# ENTRY_DIR
    var icon = get(state.expanded_dirs, entry.path, false) && empty(state.file_search_query)
      ? icons.opened
      : icons.closed
    return prefix .. mark .. icon .. ' ' .. entry.name .. '/'
  endif
  return prefix .. mark .. icons.leaf .. icons.file .. entry.name
enddef

def TruncateDisplayMarker(marker: string, max_width: number): string
  var head = ''
  for char in split(marker, '\zs')
    if strdisplaywidth(head .. char) > max_width
      break
    endif
    head ..= char
  endfor
  return head
enddef

def TruncateDisplayText(text: string, max_width: number, marker: string = '...'): string
  if max_width <= 0
    return ''
  endif
  if strdisplaywidth(text) <= max_width
    return text
  endif
  var marker_width = strdisplaywidth(marker)
  if max_width <= marker_width
    return TruncateDisplayMarker(marker, max_width)
  endif
  var head = ''
  for char in split(text, '\zs')
    if strdisplaywidth(head .. char .. marker) > max_width
      break
    endif
    head ..= char
  endfor
  return head .. marker
enddef

def TimestampHighlightGroup(mtime: number): string
  if mtime < 0
    return 'FilerTimestampUnknown'
  endif
  var age = max([0, localtime() - mtime])
  if age <= SECONDS_PER_DAY
    return 'FilerTimestampVeryFresh'
  elseif age <= 3 * SECONDS_PER_DAY
    return 'FilerTimestampFresh'
  elseif age <= 7 * SECONDS_PER_DAY
    return 'FilerTimestampRecent'
  elseif age <= 30 * SECONDS_PER_DAY
    return 'FilerTimestampNeutral'
  elseif age <= 180 * SECONDS_PER_DAY
    return 'FilerTimestampOld'
  endif
  return 'FilerTimestampVeryOld'
enddef

def TimestampColumn(line: string, timestamp: string): number
  var start_char = strchars(line) - strchars(timestamp)
  return byteidx(line, start_char) + 1
enddef

def HasVisibleTimestamp(line: string, timestamp: string): bool
  var line_chars = strchars(line)
  var timestamp_chars = strchars(timestamp)
  if timestamp_chars > line_chars
    return false
  endif
  return strcharpart(line, line_chars - timestamp_chars) ==# timestamp
enddef

def ClearTimestampProps(bufnr: number, last_lnum: number)
  if !exists('*prop_clear') || last_lnum < 1
    return
  endif
  try
    prop_clear(1, last_lnum, {bufnr: bufnr, all: true})
  catch
  endtry
enddef

def EnsureTimestampPropTypes(bufnr: number)
  if !exists('*prop_type_add')
    return
  endif
  for group in TIMESTAMP_HIGHLIGHT_GROUPS
    if hlexists(group) == 0
      continue
    endif
    try
      prop_type_add(group, {bufnr: bufnr, highlight: group})
    catch
    endtry
  endfor
enddef

def AddTimestampHighlight(bufnr: number, spec: dict<any>)
  if !exists('*prop_add') || hlexists(spec.group) == 0
    return
  endif
  try
    prop_add(spec.lnum, spec.col, {
      bufnr: bufnr,
      length: spec.len,
      type: spec.group,
    })
  catch
  endtry
enddef

def ApplyTimestampHighlights(bufnr: number, specs: list<dict<any>>, last_lnum: number)
  ClearTimestampProps(bufnr, last_lnum)
  EnsureTimestampPropTypes(bufnr)
  for spec in specs
    AddTimestampHighlight(bufnr, spec)
  endfor
enddef

def EnsureSearchHighlightPropType(bufnr: number)
  if !exists('*prop_type_add') || hlexists('Search') == 0
    return
  endif
  try
    prop_type_add(SEARCH_HIGHLIGHT_PROP, {bufnr: bufnr, highlight: 'Search'})
  catch
  endtry
enddef

def SearchHighlightSpecs(line: string, pattern: string, lnum: number): list<dict<any>>
  var specs: list<dict<any>> = []
  if empty(pattern)
    return specs
  endif
  var start = 0
  while true
    var found = matchstrpos(line, pattern, start)
    var start_index: number = found[1]
    var end_index: number = found[2]
    if start_index < 0
      break
    endif
    if end_index > start_index
      add(specs, {lnum: lnum, col: start_index + 1, len: end_index - start_index})
      start = end_index
    else
      start = start_index + 1
    endif
  endwhile
  return specs
enddef

def AddSearchHighlight(bufnr: number, spec: dict<any>)
  if !exists('*prop_add') || hlexists('Search') == 0
    return
  endif
  try
    prop_add(spec.lnum, spec.col, {
      bufnr: bufnr,
      length: spec.len,
      type: SEARCH_HIGHLIGHT_PROP,
    })
  catch
  endtry
enddef

def ApplySearchHighlights(bufnr: number, specs: list<dict<any>>)
  EnsureSearchHighlightPropType(bufnr)
  for spec in specs
    AddSearchHighlight(bufnr, spec)
  endfor
enddef

def EntryTruncationMarker(entry: dict<any>): string
  return entry.kind ==# ENTRY_DIR ? '.../' : '...'
enddef

def FormatEntryLineParts(state: dict<any>, entry: dict<any>, width: number): dict<any>
  var name = DisplayName(state, entry)
  var size = EntrySize(entry)
  var timestamp = EntryTimestamp(entry)
  var meta = size .. ' ' .. timestamp
  if width <= META_RESERVED_WIDTH + 1
    var text = TruncateDisplayText(name, width, EntryTruncationMarker(entry))
    return {line: text, searchable_text: text}
  endif
  var name_width = width - META_RESERVED_WIDTH - 1
  var left = TruncateDisplayText(name, name_width, EntryTruncationMarker(entry))
  return {
    line: left .. repeat(' ', width - strdisplaywidth(left) - META_RESERVED_WIDTH) .. meta,
    searchable_text: left,
  }
enddef

def FormatEntryLine(state: dict<any>, entry: dict<any>, width: number): string
  return FormatEntryLineParts(state, entry, width).line
enddef

def StatuslineText(state: dict<any>): string
  var items: list<string> = []
  if !empty(state.file_search_query)
    add(items, $'search:{substitute(state.file_search_query, "%", "%%", "g")}')
  endif
  var count_label = empty(state.file_search_query) ? 'entries' : 'results'
  add(items, $'sort:{state.sort_mode}')
  add(items, $'{count_label}:{len(state.entries)}')
  var mark_count = len(MarkedPaths(state))
  if mark_count > 0
    add(items, $'marks:{mark_count}')
  endif
  return '%=' .. join(items, ' ')
enddef

def PathUnderCursor(state: dict<any>): string
  var entry = EntryUnderCursor(state)
  return empty(entry) ? '' : entry.path
enddef

def PathUnderCursorOrCwd(state: dict<any>): string
  return line('.') == HEADER_LINE ? state.cwd : PathUnderCursor(state)
enddef

def SingleQuoteForPowerShell(path: string): string
  return "'" .. substitute(path, "'", "''", 'g') .. "'"
enddef

def PowerShellCommand(script: string): list<string>
  return ['powershell', '-NoProfile', '-Command', script]
enddef

def WindowsOpenDirectoryCommand(normalized: string): list<string>
  var native = NativePath(normalized)
  var argument = '/n,"' .. native .. '"'
  var ps = '$ErrorActionPreference = ''Stop''; Start-Process -FilePath explorer.exe -ArgumentList ' .. SingleQuoteForPowerShell(argument)
  return PowerShellCommand(ps)
enddef

def WindowsOpenFileCommand(normalized: string): list<string>
  var native = NativePath(normalized)
  var ps = '$ErrorActionPreference = ''Stop''; Start-Process -FilePath ' .. SingleQuoteForPowerShell(native)
  return PowerShellCommand(ps)
enddef

def OpenCommandForDefaultApplication(normalized: string): list<string>
  if IsWindows()
    return IsDirectory(normalized) ? WindowsOpenDirectoryCommand(normalized) : WindowsOpenFileCommand(normalized)
  endif
  if IsMac()
    return ['open', normalized]
  endif
  if executable('xdg-open') != 1
    SetLastOpenError('xdg-open is unavailable')
    return []
  endif
  return ['xdg-open', normalized]
enddef

def OpenPathWithDefaultApplication(target: string): bool
  var normalized = NormalizePath(target)
  if empty(normalized)
    SetLastOpenError('empty target path')
    return false
  endif
  if !PathExists(normalized)
    SetLastOpenError($'target path does not exist: {normalized}')
    return false
  endif
  var cmd = OpenCommandForDefaultApplication(normalized)
  return len(cmd) > 0 && StartJob(cmd)
enddef

def Render()
  var bufnr = bufnr('%')
  if !has_key(state_by_bufnr, bufnr)
    return
  endif
  var state = state_by_bufnr[bufnr]
  var previous_last_lnum = line('$')
  state.entries = BuildEntries(state)
  var width = max([1, winwidth(0)])
  var timestamp_highlights: list<dict<any>> = []
  var search_highlights: list<dict<any>> = []
  var search_pattern = SearchPattern(state.file_search_query)
  var lines = [TruncateDisplayText(DisplayDir(state.cwd), width)]
  for index in range(len(state.entries))
    var entry = state.entries[index]
    var line_parts = FormatEntryLineParts(state, entry, width)
    var line: string = line_parts.line
    add(lines, line)
    extend(search_highlights, SearchHighlightSpecs(line_parts.searchable_text, search_pattern, FIRST_ENTRY_LINE + index))
    var timestamp = EntryTimestamp(entry)
    if !HasVisibleTimestamp(line, timestamp)
      continue
    endif
    add(timestamp_highlights, {
      lnum: FIRST_ENTRY_LINE + index,
      col: TimestampColumn(line, timestamp),
      len: strlen(timestamp),
      group: TimestampHighlightGroup(EntryMtime(entry)),
    })
  endfor
  &l:modifiable = true
  setbufline(bufnr, 1, lines)
  if line('$') > len(lines)
    deletebufline(bufnr, len(lines) + 1, line('$'))
  endif
  &l:modifiable = false
  state.search_matches = search_highlights
  ApplyTimestampHighlights(bufnr, timestamp_highlights, max([previous_last_lnum, len(lines)]))
  ApplySearchHighlights(bufnr, search_highlights)
  &l:statusline = StatuslineText(state)
enddef

def DefineFilerPlugMappings()
  nnoremap <silent><buffer> <Plug>(filer-close) <Cmd>close<CR>
  nnoremap <silent><buffer> <Plug>(filer-open) <Cmd>call filer#OpenEntryUnderCursor()<CR>
  nnoremap <silent><buffer> <Plug>(filer-open-split) <Cmd>call filer#OpenEntryUnderCursor('split')<CR>
  nnoremap <silent><buffer> <Plug>(filer-open-vsplit) <Cmd>call filer#OpenEntryUnderCursor('vsplit')<CR>
  nnoremap <silent><buffer> <Plug>(filer-open-tab) <Cmd>call filer#OpenEntryUnderCursor('tabedit')<CR>
  nnoremap <silent><buffer> <Plug>(filer-open-drop) <Cmd>call filer#OpenEntryUnderCursor('drop')<CR>
  nnoremap <silent><buffer> <Plug>(filer-duplicate) <Cmd>call filer#DuplicateBuffer()<CR>
  nnoremap <silent><buffer> <Plug>(filer-toggle-tree) <Cmd>call filer#ToggleTree()<CR>
  nnoremap <silent><buffer> <Plug>(filer-toggle-tree-recursive) <Cmd>call filer#ExpandTreeRecursive()<CR>
  nnoremap <silent><buffer> <Plug>(filer-go-home) <Cmd>call filer#GoHome()<CR>
  nnoremap <silent><buffer> <Plug>(filer-go-root) <Cmd>call filer#GoRoot()<CR>
  nnoremap <silent><buffer> <Plug>(filer-go-parent) <Cmd>call filer#GoParent()<CR>
  nnoremap <silent><buffer> <Plug>(filer-refresh) <Cmd>call filer#ReopenCurrentDir()<CR>
  nnoremap <silent><buffer> <Plug>(filer-toggle-mark) <Cmd>call filer#ToggleMark()<CR>
  nnoremap <silent><buffer> <Plug>(filer-toggle-all-marks) <Cmd>call filer#ToggleAllMarks()<CR>
  nnoremap <silent><buffer> <Plug>(filer-create) <Cmd>call filer#Create()<CR>
  nnoremap <silent><buffer> <Plug>(filer-copy-or-mark) <Cmd>call filer#CopyOrMark()<CR>
  nnoremap <silent><buffer> <Plug>(filer-delete-or-mark) <Cmd>call filer#DeleteOrMark()<CR>
  nnoremap <silent><buffer> <Plug>(filer-jump-first-entry) <Cmd>call filer#JumpToFirstEntry()<CR>
  nnoremap <silent><buffer> <Plug>(filer-rename-or-mark) <Cmd>call filer#RenameOrMark()<CR>
  nnoremap <silent><buffer> <Plug>(filer-open-external) <Cmd>call filer#OpenWithDefaultApplication()<CR>
  nnoremap <silent><buffer> <Plug>(filer-yank-path) <Cmd>call filer#YankPathUnderCursorToClipboard()<CR>
  nnoremap <silent><buffer> <Plug>(filer-search) <Cmd>call filer#SearchFiles()<CR>
  nnoremap <silent><buffer> <Plug>(filer-next-search-result) <Cmd>call filer#JumpSearchResult(1, v:count1)<CR>
  nnoremap <silent><buffer> <Plug>(filer-previous-search-result) <Cmd>call filer#JumpSearchResult(-1, v:count1)<CR>
  nnoremap <silent><buffer> <Plug>(filer-cycle-sort) <Cmd>call filer#CycleSort()<CR>
enddef

def ApplyFilerDefaultMappings()
  ApplyMappingSpecs(FILER_MAPPING_SPECS, 'filer_mappings')
enddef

def DefineBatchPlugMappings()
  nnoremap <silent><buffer> <Plug>(filer-batch-close) <Cmd>bwipeout<CR>
enddef

def ApplyBatchDefaultMappings()
  ApplyMappingSpecs(BATCH_MAPPING_SPECS, 'filer_batch_mappings')
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
    execute 'autocmd BufEnter <buffer=' .. current_bufnr .. '> doautocmd <nomodeline> User FilerVisitDir'
    execute 'autocmd BufHidden <buffer=' .. current_bufnr .. '> call ' .. expand('<SID>') .. 'ClearAllMarksForBuffer(' .. current_bufnr .. ')'
    execute 'autocmd BufWipeout <buffer=' .. current_bufnr .. '> call filer#CleanupStateForCurrentBuffer()'
  augroup END
  DefineFilerPlugMappings()
  ApplyFilerDefaultMappings()
enddef

def SetCwd(state: dict<any>, dir: string, reset_tree: bool = false)
  var previous_dir = state.cwd
  state.cwd = NormalizeDir(dir)
  if !empty(previous_dir) && previous_dir !=# state.cwd
    state.file_search_query = ''
    ClearAllMarks(state)
  endif
  if reset_tree
    state.expanded_dirs = {}
    state.expanded_dirs[state.cwd] = true
  else
    state.expanded_dirs[state.cwd] = true
  endif
  DoVisitDirAutocmd()
enddef

def OpenFile(path: string, command: string = ''): bool
  if IsBrokenLink(path)
    WarnBrokenLink(path)
    return false
  endif
  execute ResolveFileOpenCommand(command) .. ' ' .. fnameescape(path)
  return true
enddef

def CanonicalizeBufferName(name: string): string
  var canonical = NormalizeSeparators(name)
  return IsWindows() ? tolower(canonical) : canonical
enddef

def BufferNameInUse(name: string, current_bufnr: number): bool
  var target = CanonicalizeBufferName(name)
  for info in getbufinfo()
    if info.bufnr != current_bufnr && CanonicalizeBufferName(bufname(info.bufnr)) ==# target
      return true
    endif
  endfor
  return false
enddef

def MakeUniqueBufferName(base: string, current_bufnr: number): string
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

def MakeBufferName(dir: string, current_bufnr: number): string
  return MakeUniqueBufferName('[filer] ' .. dir, current_bufnr)
enddef

def MakeRenameBufferName(cwd: string, current_bufnr: number): string
  return MakeUniqueBufferName('[filer-rename] ' .. cwd, current_bufnr)
enddef

def MakeCopyBufferName(cwd: string, current_bufnr: number): string
  return MakeUniqueBufferName('[filer-copy] ' .. cwd, current_bufnr)
enddef

def MakeTemporaryMovePath(path: string): string
  var candidate = path .. '.filer-tmp'
  var suffix = 2
  while PathExists(candidate)
    candidate = $'{path}.filer-tmp.{suffix}'
    suffix += 1
  endwhile
  return candidate
enddef

def ValidateRenameSources(paths: list<string>)
  for i in range(len(paths))
    for j in range(i + 1, len(paths) - 1)
      if IsSameOrChildPath(paths[i], paths[j]) || IsSameOrChildPath(paths[j], paths[i])
        throw $'Cannot batch rename nested paths at the same time: {paths[i]} / {paths[j]}'
      endif
    endfor
  endfor
enddef

def SetupRenameBuffer(context: dict<any>)
  var current_bufnr = bufnr('%')
  rename_state_by_bufnr[current_bufnr] = context
  setlocal buftype=acwrite
  setlocal bufhidden=hide
  setlocal noswapfile
  setlocal nowrap
  setlocal filetype=filer_rename
  setlocal syntax=
  augroup filer_rename_buffer_lifecycle
    execute 'autocmd! * <buffer=' .. current_bufnr .. '>'
    execute 'autocmd BufWriteCmd <buffer=' .. current_bufnr .. '> call filer#ApplyRenameBuffer()'
    execute 'autocmd BufWipeout <buffer=' .. current_bufnr .. '> call filer#CleanupRenameBufferForCurrentBuffer()'
  augroup END
  DefineBatchPlugMappings()
  ApplyBatchDefaultMappings()
enddef

def SetupCopyBuffer(context: dict<any>)
  var current_bufnr = bufnr('%')
  copy_state_by_bufnr[current_bufnr] = context
  setlocal buftype=acwrite
  setlocal bufhidden=hide
  setlocal noswapfile
  setlocal nowrap
  setlocal filetype=filer_copy
  setlocal syntax=
  augroup filer_copy_buffer_lifecycle
    execute 'autocmd! * <buffer=' .. current_bufnr .. '>'
    execute 'autocmd BufWriteCmd <buffer=' .. current_bufnr .. '> call filer#ApplyCopyBuffer()'
    execute 'autocmd BufWipeout <buffer=' .. current_bufnr .. '> call filer#CleanupCopyBufferForCurrentBuffer()'
  augroup END
  DefineBatchPlugMappings()
  ApplyBatchDefaultMappings()
enddef

def OpenRenameBuffer(state: dict<any>, paths: list<string>)
  ValidateRenameSources(paths)
  var filer_bufnr = bufnr('%')
  enew
  var rename_bufnr = bufnr('%')
  execute 'file ' .. fnameescape(MakeRenameBufferName(state.cwd, rename_bufnr))
  SetupRenameBuffer({
    filer_bufnr: filer_bufnr,
    cwd: state.cwd,
    source_paths: copy(paths),
  })
  setline(1, paths)
  if line('$') > len(paths)
    deletebufline(rename_bufnr, len(paths) + 1, line('$'))
  endif
  setlocal nomodified
  cursor(1, 1)
enddef

def OpenCopyBuffer(state: dict<any>, paths: list<string>)
  var filer_bufnr = bufnr('%')
  enew
  var copy_bufnr = bufnr('%')
  execute 'file ' .. fnameescape(MakeCopyBufferName(state.cwd, copy_bufnr))
  SetupCopyBuffer({
    filer_bufnr: filer_bufnr,
    cwd: state.cwd,
    source_paths: copy(paths),
  })
  setline(1, paths)
  if line('$') > len(paths)
    deletebufline(copy_bufnr, len(paths) + 1, line('$'))
  endif
  setlocal nomodified
  cursor(1, 1)
enddef

def CollectRenameDestinations(context: dict<any>): list<string>
  var source_paths = context.source_paths
  var lines = getline(1, '$')
  if len(lines) != len(source_paths)
    throw $'Expected {len(source_paths)} lines, got {len(lines)}'
  endif
  var destinations: list<string> = []
  for line_text in lines
    if empty(line_text)
      throw 'Rename destination cannot be empty'
    endif
    add(destinations, ResolvePath(context.cwd, line_text))
  endfor
  return destinations
enddef

def CollectCopyDestinations(context: dict<any>): list<string>
  var source_paths = context.source_paths
  var lines = getline(1, '$')
  if len(lines) != len(source_paths)
    throw $'Expected {len(source_paths)} lines, got {len(lines)}'
  endif
  var destinations: list<string> = []
  for line_text in lines
    if empty(line_text)
      throw 'Copy destination cannot be empty'
    endif
    add(destinations, ResolvePath(context.cwd, line_text))
  endfor
  return destinations
enddef

def CopyFile(source: string, destination: string)
  writefile(readfile(source, 'b'), destination, 'b')
enddef

def CopyDirectory(source: string, destination: string)
  mkdir(destination, 'p')
  for name in SafeReadDir(source)
    var child_source = JoinPath(source, name)
    var child_destination = JoinPath(destination, name)
    CopyPath(child_source, child_destination)
  endfor
enddef

def CopyPath(source: string, destination: string)
  if PathExists(destination)
    DeletePath(destination)
  endif
  EnsureParentDir(destination)
  if IsDirectory(source)
    CopyDirectory(source, destination)
    return
  endif
  CopyFile(source, destination)
enddef

def ApplyBulkCopy(source_paths: list<string>, destination_paths: list<string>): list<string>
  var copied_paths: list<string> = []
  for index in range(len(source_paths))
    var source = source_paths[index]
    var destination = destination_paths[index]
    if PathKey(source) ==# PathKey(destination) && source ==# destination
      continue
    endif
    if !PathExists(source)
      throw $'Source does not exist: {source}'
    endif
    if IsSameOrChildPath(destination, source)
      throw $'Copy destination overlaps source and would remove it: {destination}'
    endif
    if IsDirectory(source) && IsSameOrChildPath(source, destination)
      throw $'Cannot copy a directory into itself: {source} -> {destination}'
    endif
    CopyPath(source, destination)
    add(copied_paths, destination)
  endfor
  return copied_paths
enddef

def ApplyBulkRename(source_paths: list<string>, destination_paths: list<string>): list<string>
  var source_set: dict<bool> = {}
  var destination_set: dict<bool> = {}
  var staged_moves: list<dict<any>> = []
  var final_moves: list<dict<any>> = []
  var renamed_paths: list<string> = []
  for path in source_paths
    source_set[PathKey(path)] = true
  endfor
  for index in range(len(source_paths))
    var source = source_paths[index]
    var destination = destination_paths[index]
    var source_key = PathKey(source)
    var destination_key = PathKey(destination)
    if has_key(destination_set, destination_key)
      throw $'Duplicate destination: {destination}'
    endif
    destination_set[destination_key] = true
    if source_key ==# destination_key && source ==# destination
      add(renamed_paths, source)
      continue
    endif
    if PathExists(destination) && !has_key(source_set, destination_key)
      throw $'Destination already exists: {destination}'
    endif
  endfor
  for index in range(len(source_paths))
    var source = source_paths[index]
    var destination = destination_paths[index]
    var source_key = PathKey(source)
    var destination_key = PathKey(destination)
    if source_key ==# destination_key && source ==# destination
      continue
    endif
    if source_key ==# destination_key || has_key(source_set, destination_key)
      var temp_path = MakeTemporaryMovePath(source)
      MovePath(source, temp_path)
      add(staged_moves, {
        temp_path: temp_path,
        destination: destination,
      })
      add(renamed_paths, destination)
      continue
    endif
    add(final_moves, {
      source: source,
      destination: destination,
    })
    add(renamed_paths, destination)
  endfor
  for move in final_moves
    EnsureParentDir(move.destination)
    MovePath(move.source, move.destination)
  endfor
  for move in staged_moves
    EnsureParentDir(move.destination)
    MovePath(move.temp_path, move.destination)
  endfor
  return renamed_paths
enddef

def OpenInCurrentBuffer(dir: string, reset_tree: bool = true)
  var current_bufnr = bufnr('%')
  execute 'file ' .. fnameescape(MakeBufferName(dir, current_bufnr))
  SetupBuffer()
  var bufnr = bufnr('%')
  var prev = has_key(state_by_bufnr, bufnr) ? state_by_bufnr[bufnr] : MakeState(dir)
  state_by_bufnr[bufnr] = prev
  SetCwd(prev, dir, reset_tree)
  ClearInvalidMarks(prev)
  Render()
  JumpToFirstEntry()
enddef

def OpenOrReuse(dir: string, reset_tree: bool = true)
  var current_bufnr = bufnr('%')
  if &filetype !=# 'filer' || !has_key(state_by_bufnr, current_bufnr)
    enew
  endif
  OpenInCurrentBuffer(dir, reset_tree)
enddef

def OpenEmptyWindow(command: string)
  if command ==# 'split'
    new
  elseif command ==# 'vsplit'
    vnew
  elseif command ==# 'tabedit'
    tabnew
  endif
enddef

def OpenFilerWithCommand(dir: string, command: string, reset_tree: bool = true)
  if command ==# 'edit'
    OpenOrReuse(dir, reset_tree)
    return
  endif
  OpenEmptyWindow(command)
  OpenInCurrentBuffer(dir, reset_tree)
enddef

# API

export def JumpToFirstEntry()
  cursor(min([FIRST_ENTRY_LINE, line('$')]), 1)
enddef

export def ResolvedViewIndent(): number
  return ViewIndent()
enddef

export def ResolvedViewIcons(): dict<any>
  return ViewIcons()
enddef

export def BufferDir(bufnr: number = bufnr('%')): string
  if !has_key(state_by_bufnr, bufnr)
    return ''
  endif
  return get(state_by_bufnr[bufnr], 'cwd', '')
enddef

export def Refresh()
  var state = EnsureState()
  ClearInvalidMarks(state)
  Render()
enddef

export def RefreshCurrentWindow()
  var bufnr = bufnr('%')
  if &filetype !=# 'filer' || !has_key(state_by_bufnr, bufnr)
    return
  endif
  Render()
enddef

export def RefreshResizedWindows()
  if empty(state_by_bufnr)
    return
  endif
  for winid in get(v:event, 'windows', [])
    win_execute(winid, 'silent call filer#RefreshCurrentWindow()')
  endfor
enddef

export def Open(dir_arg: string = '', command: string = '', reset_tree: bool = true)
  var dir = NormalizeDir(dir_arg)
  if !isdirectory(dir)
    echoerr $'Not a directory: {dir}'
    return
  endif
  OpenFilerWithCommand(dir, ResolveLaunchCommand(command), reset_tree)
enddef

export def OpenBufferDir(command: string = '')
  var open_command = ResolveBufferDirCommand(command)
  if &filetype ==# 'filer'
    var state = EnsureState()
    OpenFilerWithCommand(state.cwd, open_command, false)
    return
  endif
  var target = expand('%:p')
  var dir = expand('%:p:h')
  if empty(dir)
    dir = getcwd()
  endif
  OpenFilerWithCommand(dir, open_command)
  if !empty(target)
    JumpToPath(target)
  endif
enddef

export def DuplicateBuffer(command: string = '')
  var state = EnsureState()
  OpenFilerWithCommand(state.cwd, ResolveDuplicateCommand(command), false)
enddef

export def OpenEntryUnderCursor(command: string = '')
  var state = EnsureState()
  var entry = EntryUnderCursor(state)
  if line('.') == HEADER_LINE
    entry = MakeEntry(ENTRY_DIR, state.cwd, state.cwd, 0)
  endif
  if empty(entry)
    return
  endif
  if entry.kind ==# ENTRY_FILE
    OpenFile(entry.path, command)
    return
  endif
  if entry.kind ==# ENTRY_DIR
    OpenFilerWithCommand(entry.path, ResolveDirectoryOpenCommand(command))
  endif
enddef

export def ToggleMark()
  var state = EnsureState()
  var entry = EntryUnderCursor(state)
  if empty(entry)
    return
  endif
  if IsMarked(state, entry)
    RemoveMark(state, entry)
  else
    MarkEntry(state, entry)
  endif
  Render()
  var next_line = line('.') + 1
  var target_line = next_line > line('$') ? FIRST_ENTRY_LINE : next_line
  cursor(target_line, 1)
enddef

export def ToggleAllMarks()
  var state = EnsureState()
  var all_marked = true
  for entry in state.entries
    if !IsMarked(state, entry)
      all_marked = false
      break
    endif
  endfor
  ClearAllMarks(state)
  if !all_marked
    for entry in state.entries
      MarkEntry(state, entry)
    endfor
  endif
  Render()
enddef

export def ToggleTree()
  var state = EnsureState()
  if !empty(state.file_search_query)
    return
  endif
  var entry = EntryUnderCursor(state)
  if empty(entry) || entry.kind !=# ENTRY_DIR
    return
  endif
  state.expanded_dirs[entry.path] = !get(state.expanded_dirs, entry.path, false)
  Render()
enddef

export def ExpandTreeRecursive()
  var state = EnsureState()
  if !empty(state.file_search_query)
    return
  endif
  var entry = EntryUnderCursor(state)
  if empty(entry) || entry.kind !=# ENTRY_DIR
    return
  endif
  if get(state.expanded_dirs, entry.path, false)
    CollapseSubtreeRecursive(state, entry.path)
  else
    ExpandSubtreeRecursive(state, entry.path, {})
  endif
  Render()
enddef

export def GoParent()
  var state = EnsureState()
  var current_dir = state.cwd
  OpenFilerWithCommand(ParentDir(current_dir), 'edit')
  JumpToPath(current_dir)
enddef

export def GoHome()
  OpenFilerWithCommand(NormalizeDir('~'), 'edit')
enddef

export def GoRoot()
  var state = EnsureState()
  OpenFilerWithCommand(FilesystemRoot(state.cwd), 'edit')
enddef

export def ReopenCurrentDir()
  var state = EnsureState()
  OpenFilerWithCommand(state.cwd, 'edit')
enddef

export def CleanupStateForCurrentBuffer()
  var bufnr = bufnr('%')
  if has_key(state_by_bufnr, bufnr)
    ClearTimestampProps(bufnr, line('$'))
    remove(state_by_bufnr, bufnr)
  endif
enddef

export def CleanupRenameBufferForCurrentBuffer()
  var bufnr = bufnr('%')
  if has_key(rename_state_by_bufnr, bufnr)
    remove(rename_state_by_bufnr, bufnr)
  endif
enddef

export def CleanupCopyBufferForCurrentBuffer()
  var bufnr = bufnr('%')
  if has_key(copy_state_by_bufnr, bufnr)
    remove(copy_state_by_bufnr, bufnr)
  endif
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
  Render()
  JumpToPath(path)
enddef

export def DeleteOrMark()
  var state = EnsureState()
  if HasMarks(state)
    DeleteMarked()
    return
  endif
  MarkEntry(state, EntryUnderCursor(state))
  Render()
enddef

export def DeleteMarked()
  var state = EnsureState()
  if !HasMarks(state)
    echo 'No marked paths'
    return
  endif
  var paths = MarkedPaths(state)
  if !Confirm($'Delete {len(paths)} marked paths?')
    return
  endif
  for path in paths
    if PathExists(path)
      DeletePath(path)
    endif
  endfor
  ClearAllMarks(state)
  Render()
enddef

export def RenameOrMark()
  var state = EnsureState()
  if HasMarks(state)
    OpenRenameBuffer(state, MarkedPaths(state))
    return
  endif
  MarkEntry(state, EntryUnderCursor(state))
  Render()
enddef

export def CopyOrMark()
  var state = EnsureState()
  if HasMarks(state)
    OpenCopyBuffer(state, MarkedPaths(state))
    return
  endif
  MarkEntry(state, EntryUnderCursor(state))
  Render()
enddef

export def ApplyRenameBuffer()
  var rename_bufnr = bufnr('%')
  if !has_key(rename_state_by_bufnr, rename_bufnr)
    return
  endif
  var context = rename_state_by_bufnr[rename_bufnr]
  var destination_paths = CollectRenameDestinations(context)
  var renamed_paths = ApplyBulkRename(context.source_paths, destination_paths)
  setlocal nomodified
  var filer_bufnr = context.filer_bufnr
  if !bufexists(filer_bufnr) || !has_key(state_by_bufnr, filer_bufnr)
    echo $'Renamed {len(renamed_paths)} entries'
    return
  endif
  execute 'buffer ' .. filer_bufnr
  var state = state_by_bufnr[filer_bufnr]
  ClearAllMarks(state)
  Render()
  JumpToFirstEntry()
  execute 'bwipeout ' .. rename_bufnr
enddef

export def ApplyCopyBuffer()
  var copy_bufnr = bufnr('%')
  if !has_key(copy_state_by_bufnr, copy_bufnr)
    return
  endif
  var context = copy_state_by_bufnr[copy_bufnr]
  var destination_paths = CollectCopyDestinations(context)
  var copied_paths = ApplyBulkCopy(context.source_paths, destination_paths)
  setlocal nomodified
  var filer_bufnr = context.filer_bufnr
  if !bufexists(filer_bufnr) || !has_key(state_by_bufnr, filer_bufnr)
    echo $'Copied {len(copied_paths)} entries'
    return
  endif
  execute 'buffer ' .. filer_bufnr
  var state = state_by_bufnr[filer_bufnr]
  ClearAllMarks(state)
  Render()
  JumpToFirstEntry()
  execute 'bwipeout ' .. copy_bufnr
enddef

export def YankPathUnderCursorToClipboard()
  var state = EnsureState()
  var path = PathUnderCursorOrCwd(state)
  if empty(path)
    return
  endif
  setreg('+', path)
  echo $'Copied to clipboard: {path}'
enddef

export def SearchFiles()
  var state = EnsureState()
  var query = Prompt('Search filename: ')
  var pattern_error = SearchPatternError(query)
  if !empty(pattern_error)
    echohl ErrorMsg
    echomsg $'Invalid search pattern: {query} ({pattern_error})'
    echohl None
    return
  endif
  state.file_search_query = query
  ClearAllMarks(state)
  Render()
  JumpToFirstEntry()
enddef

def JumpSearchEntry(state: dict<any>, direction: number, count: number)
  var total = len(state.entries)
  if total == 0
    return
  endif
  var target = line('.') - FIRST_ENTRY_LINE
  if target < 0 || target >= total
    target = direction > 0 ? -1 : 0
  endif
  var remaining = max([1, count])
  while remaining > 0
    target += direction > 0 ? 1 : -1
    if target >= total
      target = 0
    elseif target < 0
      target = total - 1
    endif
    remaining -= 1
  endwhile
  cursor(FIRST_ENTRY_LINE + target, 1)
enddef

def NextSearchMatchIndex(matches: list<dict<any>>, lnum: number, col: number): number
  var index = 0
  while index < len(matches)
    var match = matches[index]
    if match.lnum > lnum || (match.lnum == lnum && match.col > col)
      return index
    endif
    index += 1
  endwhile
  return 0
enddef

def PreviousSearchMatchIndex(matches: list<dict<any>>, lnum: number, col: number): number
  var index = len(matches) - 1
  while index >= 0
    var match = matches[index]
    if match.lnum < lnum || (match.lnum == lnum && match.col < col)
      return index
    endif
    index -= 1
  endwhile
  return len(matches) - 1
enddef

def JumpSearchMatch(state: dict<any>, direction: number, count: number)
  var matches: list<dict<any>> = state.search_matches
  if empty(matches)
    JumpSearchEntry(state, direction, count)
    return
  endif
  var target = direction > 0
    ? NextSearchMatchIndex(matches, line('.'), col('.'))
    : PreviousSearchMatchIndex(matches, line('.'), col('.'))
  var remaining = max([1, count]) - 1
  while remaining > 0
    target += direction > 0 ? 1 : -1
    if target >= len(matches)
      target = 0
    elseif target < 0
      target = len(matches) - 1
    endif
    remaining -= 1
  endwhile
  cursor(matches[target].lnum, matches[target].col)
enddef

export def JumpSearchResult(direction: number, count: number = 1)
  var state = EnsureState()
  var key = direction > 0 ? 'n' : 'N'
  var step_count = max([1, count])
  if empty(state.file_search_query)
    execute 'normal! ' .. step_count .. key
    return
  endif
  JumpSearchMatch(state, direction, step_count)
enddef

export def CycleSort()
  var state = EnsureState()
  var current_index = index(SORT_MODES, state.sort_mode)
  state.sort_mode = SORT_MODES[(current_index + 1) % len(SORT_MODES)]
  Render()
  JumpToFirstEntry()
enddef

export def OpenWithDefaultApplication()
  var state = EnsureState()
  var path = PathUnderCursorOrCwd(state)
  if empty(path)
    return
  endif
  if IsBrokenLink(path)
    WarnBrokenLink(path)
    return
  endif
  if OpenPathWithDefaultApplication(path)
    echo $'Opening with default application: {path}'
    return
  endif
  var reason = GetLastOpenError()
  echoerr empty(reason)
    ? $'Failed to open with default application: {path}'
    : $'Failed to open with default application: {path} ({reason})'
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
