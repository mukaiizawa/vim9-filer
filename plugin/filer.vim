vim9script

if exists('g:loaded_filer')
  finish
endif
g:loaded_filer = true
g:loaded_netrwPlugin = true

command! -nargs=? -complete=dir Filer call filer#Open(<q-args>)
command! -nargs=* FilerBufferDir call filer#OpenBufferDir()

augroup filer_default_explorer
  autocmd!
  autocmd BufEnter * call filer#MaybeOpenDir(expand('<amatch>'))
augroup END
