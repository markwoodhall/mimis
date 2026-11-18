" The ACP chat buffer, on top of markdown.vim (loaded with its own concealing off).
" Sourced by modules/acp/render.fnl for each chat buffer.

" markdown.vim's code spans run until any later backtick, across paragraphs, so one
" stray backtick (or ``` mid-sentence) swaps code and prose for the rest of the chat.
" As in CommonMark: a span closes on a run of the same length and ends at a blank line,
" and ``` starting a line is a fence, not a span.
syntax clear markdownCode
syntax region markdownCode matchgroup=markdownCodeDelimiter
      \ start=/\%(\%(^\s*\)\@<=```\)\@!`\@<!\z(`\+\)`\@!/
      \ end=/`\@<!\z1`\@!\|^\s*$/ keepend contains=markdownLineStart concealends

" Markers hidden off the cursor's line, as in a rendered page: bold, italic and
" struck-out text, code spans' backticks, and a link's brackets and URL. markdown.vim's
" own concealing also blanks whole ``` fence lines, which hides where code starts, so
" it stays off and these are its inline rules again with their ends concealed.
syntax clear markdownItalic markdownBold markdownBoldItalic markdownStrike
syntax region markdownItalic matchgroup=markdownItalicDelimiter start="\*\S\@=" end="\S\@<=\*\|^$" skip="\\\*" contains=markdownLineStart,@Spell concealends
syntax region markdownItalic matchgroup=markdownItalicDelimiter start="\w\@<!_\S\@=" end="\S\@<=_\w\@!\|^$" skip="\\_" contains=markdownLineStart,@Spell concealends
syntax region markdownBold matchgroup=markdownBoldDelimiter start="\*\*\S\@=" end="\S\@<=\*\*\|^$" skip="\\\*" contains=markdownLineStart,markdownItalic,@Spell concealends
syntax region markdownBold matchgroup=markdownBoldDelimiter start="\w\@<!__\S\@=" end="\S\@<=__\w\@!\|^$" skip="\\_" contains=markdownLineStart,markdownItalic,@Spell concealends
syntax region markdownBoldItalic matchgroup=markdownBoldItalicDelimiter start="\*\*\*\S\@=" end="\S\@<=\*\*\*\|^$" skip="\\\*" contains=markdownLineStart,@Spell concealends
syntax region markdownBoldItalic matchgroup=markdownBoldItalicDelimiter start="\w\@<!___\S\@=" end="\S\@<=___\w\@!\|^$" skip="\\_" contains=markdownLineStart,@Spell concealends
syntax region markdownStrike matchgroup=markdownStrikeDelimiter start="\~\~\S\@=" end="\S\@<=\~\~\|^$" contains=markdownLineStart,@Spell concealends

" Headings without their #s. The chat window shows them in AcpH1..6, see acp.fnl.
syntax clear markdownH1 markdownH2 markdownH3 markdownH4 markdownH5 markdownH6
syntax region markdownH1 matchgroup=markdownH1Delimiter start=" \{,3}#\s"      end="#*\s*$" keepend oneline contains=@markdownInline,markdownAutomaticLink contained concealends
syntax region markdownH2 matchgroup=markdownH2Delimiter start=" \{,3}##\s"     end="#*\s*$" keepend oneline contains=@markdownInline,markdownAutomaticLink contained concealends
syntax region markdownH3 matchgroup=markdownH3Delimiter start=" \{,3}###\s"    end="#*\s*$" keepend oneline contains=@markdownInline,markdownAutomaticLink contained concealends
syntax region markdownH4 matchgroup=markdownH4Delimiter start=" \{,3}####\s"   end="#*\s*$" keepend oneline contains=@markdownInline,markdownAutomaticLink contained concealends
syntax region markdownH5 matchgroup=markdownH5Delimiter start=" \{,3}#####\s"  end="#*\s*$" keepend oneline contains=@markdownInline,markdownAutomaticLink contained concealends
syntax region markdownH6 matchgroup=markdownH6Delimiter start=" \{,3}######\s" end="#*\s*$" keepend oneline contains=@markdownInline,markdownAutomaticLink contained concealends

" A turn's own heading (## You, ## Agent) is hidden altogether: the bar and shade say
" whose block it is, and the hidden line is the block's top row. A prompt's time shows
" at the right (render.fnl).
syntax match AcpTurn /^## \%(You\|Agent\)\>.*$/ conceal

syntax clear markdownLinkText markdownLink
syntax region markdownLinkText matchgroup=markdownLinkTextDelimiter
      \ start="!\=\[\%(\_[^][]*\%(\[\_[^][]*\]\_[^][]*\)*]\%( \=[[(]\)\)\@=" end="\]\%( \=[[(]\)\@="
      \ nextgroup=markdownLink,markdownId skipwhite contains=@markdownInline,markdownLineStart concealends
syntax region markdownLink matchgroup=markdownLinkDelimiter start="(" end=")" keepend contained conceal

" The tool, permission, elicitation, egress, stop, acp and turn rows carry agent-supplied
" titles. Left to markdown, a stray backtick or fence in a title opens syntax that
" colours every line below it, so those rows (and the folded >> thinking) stay out of it,
" as do your comments.
syntax region AcpUiLine matchgroup=AcpUiPrefix
      \ start=/^>\%(>\| \%(tool\|permission\|elicitation\|egress\|stop\|acp\|turn\|comment\):\)/
      \ end=/$/ contains=NONE

" Where to start parsing when the chat is drawn part-way down. Languages included for
" fenced blocks bring their own sync, which applies to the whole buffer: sql.vim's
" looks back for an unclosed /* and starts inside a comment, and the /* of a path like
" acp/*.fnl in a tool row then turns the rest of the chat into one. A turn's heading
" is where nothing is open, so parsing starts at the nearest one above instead.
syntax sync clear
syntax sync match acpChatTurn grouphere NONE "^## \%(You\|Agent\)\>"
syntax sync maxlines=3000

" Tables: quiet pipes and rule, a header that stands out.
syntax match AcpTablePipe /|/ contained
syntax match AcpTableRow /^\s*|.*|\s*$/ contains=AcpTablePipe,@markdownInline,markdownStrike
syntax match AcpTableHeader /^\s*|.*|\s*\n\ze\s*|\%(\s*:\?-\+:\?\s*|\)\+\s*$/ contains=AcpTablePipe,@markdownInline,markdownStrike
syntax match AcpTableRule /^\s*|\%(\s*:\?-\+:\?\s*|\)\+\s*$/
