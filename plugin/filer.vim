vim9script

if exists('g:loaded_filer')
  finish
endif
g:loaded_filer = true
g:loaded_netrwPlugin = true

command! -nargs=? -complete=dir Filer call filer#Open(<q-args>)
command! -nargs=? -complete=dir FilerSplit call filer#Open(<q-args>, 'split')
command! -nargs=? -complete=dir FilerVsplit call filer#Open(<q-args>, 'vsplit')
command! -nargs=? -complete=dir FilerTab call filer#Open(<q-args>, 'tabedit')
command! -nargs=? FilerBufferDir call filer#OpenBufferDir(<q-args>)

augroup filer_default_explorer
  autocmd!
  autocmd BufEnter * call filer#MaybeOpenDir(expand('<amatch>'))
augroup END

augroup filer_resize
  autocmd!
  autocmd WinResized * call filer#RefreshResizedWindows()
augroup END
