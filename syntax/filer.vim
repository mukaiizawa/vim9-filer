vim9script

if exists('b:current_syntax')
  finish
endif

syntax match FilerHeader /\%1l.*$/
syntax match FilerParent /^\.\.\/$/
syntax match FilerMarked /^\s*\zs\*\ze/
syntax match FilerMarkedLine /^\s*\*.*/
syntax match FilerTreeIcon /^\s*[* ]\zs[|+-]\ze /
syntax match FilerDirectory /^\s*[* ][+-] .\+\/$/
syntax match FilerFile /^\s*[* ]|.\+$/
syntax match FilerEmpty /^(empty)$/

highlight default link FilerHeader Title
highlight default link FilerParent Directory
highlight default link FilerMarked Identifier
highlight default link FilerTreeIcon Comment
highlight default link FilerDirectory Directory
highlight default link FilerFile Normal
highlight default link FilerEmpty Comment

b:current_syntax = 'filer'
