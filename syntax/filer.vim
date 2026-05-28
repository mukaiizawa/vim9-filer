vim9script

if exists('b:current_syntax')
  finish
endif

syntax match FilerHeader /\%1l.*$/
syntax match FilerParent /^\.\.\/\%(\s\{2,}.\+\)\?$/
syntax match FilerMarked /^\s*\zs\*\ze/
syntax match FilerTreeIcon /^\s*[* ]\zs[|+-]\ze /
syntax match FilerDirectory /^\s*[* ][+-] .\{-}\/\ze\%(\s\{2,}.\+\)\?$/
syntax match FilerFile /^\s*[* ]|.\{-}\ze\%(\s\{2,}.\+\)\?$/
syntax match FilerSize /\s\zs\d\+\%(\.\d\+\)\?[BKMGTP]\ze\%(\s\+\d\{4}-\d\{2}-\d\{2} \d\{2}:\d\{2}\)\?$/
syntax match FilerTimestamp /\d\{4}-\d\{2}-\d\{2} \d\{2}:\d\{2}$/
syntax match FilerMarkedLine /^\s*\*.*/
syntax match FilerEmpty /^(empty)$/

highlight default link FilerHeader Keyword
highlight default link FilerParent Keyword
highlight default link FilerMarked Special
highlight default link FilerMarkedLine Special
highlight default link FilerTreeIcon Comment
highlight default link FilerDirectory Keyword
highlight default link FilerFile Normal
highlight default link FilerSize Number
highlight default link FilerTimestamp Number
highlight default link FilerEmpty Comment

b:current_syntax = 'filer'
