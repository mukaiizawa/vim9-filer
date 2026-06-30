vim9script

if exists('b:current_syntax')
  finish
endif

def LiteralPattern(text: string): string
  return '\V' .. escape(text, '\') .. '\m'
enddef

def PatternAlternatives(items: list<string>): string
  var patterns: list<string> = []
  for item in items
    add(patterns, LiteralPattern(item))
  endfor
  return join(patterns, '\|')
enddef

def SyntaxMatch(group: string, pattern: string)
  execute 'syntax match ' .. group .. ' ' .. string(pattern)
enddef

var icons = filer#ResolvedViewIcons()
var leaf_icon: string = icons.leaf
var opened_icon: string = icons.opened
var closed_icon: string = icons.closed
var file_icon: string = icons.file
var marked_icon: string = icons.marked
var mark_pattern = LiteralPattern(marked_icon)
var row_mark_pattern = PatternAlternatives([
  marked_icon,
  repeat(' ', strdisplaywidth(marked_icon)),
])
var row_mark_prefix = '\%(' .. row_mark_pattern .. '\)'
var tree_icon_pattern = PatternAlternatives([leaf_icon, opened_icon, closed_icon])
var dir_icon_pattern = PatternAlternatives([opened_icon, closed_icon])
var metadata_tail_pattern = '\ze\%(\s\{2,}.\+\)\?$'

SyntaxMatch('FilerHeader', '\%1l.*$')
SyntaxMatch('FilerMarked', '^\s*\zs' .. mark_pattern .. '\ze')
var tree_pattern = '^\s*' .. row_mark_prefix .. '\zs\%(' .. tree_icon_pattern .. '\)'
SyntaxMatch('FilerTreeIcon', tree_pattern)
var dir_pattern = '^\s*' .. row_mark_prefix .. '\%(' .. dir_icon_pattern .. '\) .\{-}\%(/\)\?' .. metadata_tail_pattern
SyntaxMatch('FilerDirectory', dir_pattern)
var file_pattern = '^\s*' .. row_mark_prefix .. LiteralPattern(leaf_icon) .. LiteralPattern(file_icon) .. '.\{-}' .. metadata_tail_pattern
SyntaxMatch('FilerFile', file_pattern)
var size_pattern = '\s\zs\d\+\%(\.\d\+\)\?[BKMGTP]\ze\%(\s\+\d\{4}-\d\{2}-\d\{2} \d\{2}:\d\{2}\)\?$'
SyntaxMatch('FilerSize', size_pattern)
SyntaxMatch('FilerMarkedLine', '^\s*' .. mark_pattern .. '.*')

highlight default link FilerHeader Keyword
highlight default link FilerMarked Special
highlight default link FilerMarkedLine Special
highlight default link FilerTreeIcon Comment
highlight default link FilerDirectory Keyword
highlight default link FilerFile Normal
highlight default link FilerSize Number
highlight default FilerTimestampVeryFresh ctermfg=117 guifg=#87d7ff
highlight default FilerTimestampFresh ctermfg=81 guifg=#5fd7ff
highlight default FilerTimestampRecent ctermfg=39 guifg=#00afff
highlight default FilerTimestampNeutral ctermfg=67 guifg=#5f87d7
highlight default FilerTimestampOld ctermfg=60 guifg=#5f5f87
highlight default FilerTimestampVeryOld ctermfg=95 guifg=#875f5f
highlight default link FilerTimestampUnknown Comment

b:current_syntax = 'filer'
