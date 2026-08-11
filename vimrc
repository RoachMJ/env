" ============================================================
" Vundle — Plugin Manager
" ============================================================
set nocompatible
filetype off

set rtp+=~/.vim/bundle/Vundle.vim
call vundle#begin()

" Vundle manages itself
Plugin 'VundleVim/Vundle.vim'

" ── File Navigation ──────────────────────────────────────────
Plugin 'preservim/nerdtree'                      " File explorer
Plugin 'Xuyuanp/nerdtree-git-plugin'            " Git status in NERDTree
Plugin 'ryanoasis/vim-devicons'                  " File icons (Nerd Font)
Plugin 'tiagofumo/vim-nerdtree-syntax-highlight' " Color icons by filetype
Plugin 'junegunn/fzf'                            " Fuzzy finder core
Plugin 'junegunn/fzf.vim'                        " Fuzzy finder vim integration
Plugin 'christoomey/vim-tmux-navigator'          " Seamless vim/tmux pane nav
Plugin 'mhinz/vim-startify'                      " Start screen / dashboard

" ── Git ──────────────────────────────────────────────────────
Plugin 'airblade/vim-gitgutter'                  " Git diff in gutter
Plugin 'tpope/vim-fugitive'                      " Git commands inside vim
Plugin 'tpope/vim-rhubarb'                       " GitHub integration

" ── Syntax & Language Support ────────────────────────────────
Plugin 'sheerun/vim-polyglot'                    " 100+ language syntax packs
Plugin 'hashivim/vim-terraform'                  " Terraform/HCL syntax + fmt
Plugin 'pearofducks/ansible-vim'                 " Ansible/YAML syntax
Plugin 'ekalinin/Dockerfile.vim'                 " Dockerfile syntax
Plugin 'chr4/nginx.vim'                          " nginx config syntax
Plugin 'preservim/vim-markdown'                  " Markdown syntax
Plugin 'fatih/vim-go'                            " Go tooling: fmt, imports, test, Delve debug

" ── Autocompletion ───────────────────────────────────────────
Plugin 'ycm-core/YouCompleteMe'                  " Autocompletion engine
Plugin 'ervandew/supertab'                       " Tab completion
Plugin 'tpope/vim-surround'                      " Surround text objects
Plugin 'tpope/vim-commentary'                    " Toggle comments gcc/gc
Plugin 'jiangmiao/auto-pairs'                    " Auto close brackets/quotes

" ── Status Line ──────────────────────────────────────────────
Plugin 'vim-airline/vim-airline'                 " Status bar
Plugin 'vim-airline/vim-airline-themes'          " Status bar themes

" ── Search ───────────────────────────────────────────────────
Plugin 'mileszs/ack.vim'                         " Ack/ag/rg search
Plugin 'google/vim-searchindex'                  " Show match count

" ── Visual ───────────────────────────────────────────────────
Plugin 'morhetz/gruvbox'                         " Colorscheme
Plugin 'Yggdroot/indentLine'                     " Indent guides
Plugin 'ntpeters/vim-better-whitespace'          " Highlight trailing whitespace

" ── Diagnostics ──────────────────────────────────────────────
Plugin 'dense-analysis/ale'                      " Async lint/diagnostics engine

" ── Editor Utilities ─────────────────────────────────────────
Plugin 'preservim/tagbar'                        " Code outline sidebar
Plugin 'mbbill/undotree'                         " Visual undo tree
Plugin 'tpope/vim-repeat'                        " Repeat plugin commands
Plugin 'wellle/targets.vim'                       " Better text objects
Plugin 'RRethy/vim-illuminate'                   " Highlight word under cursor
Plugin 'farmergreg/vim-lastplace'                " Reopen at last position
Plugin 'tpope/vim-obsession'                     " Session persistence
Plugin 'kshenoy/vim-signature'                   " Show marks in the gutter
Plugin 'liuchengxu/vim-which-key'                " Popup cheat sheet for leader keys

call vundle#end()
filetype plugin indent on

" matchit — extends % to match if/end, tags, etc (ships with vim)
packadd! matchit

" vim-go owns the Go filetype; stop polyglot's bundled go syntax from fighting it
let g:polyglot_disabled = ['go']

" ============================================================
" General Settings
" ============================================================
set encoding=utf-8
set fileencoding=utf-8
set termencoding=utf-8
set mouse=a                  " Enable mouse in all modes
set ttymouse=sgr             " Mouse support in tmux
set number                   " Line numbers
set relativenumber           " Relative line numbers
set cursorline               " Highlight current line
set showmatch                " Highlight matching brackets
set showcmd                  " Show command in status line
set ruler                    " Show cursor position
set scrolloff=8              " Keep 8 lines above/below cursor
set sidescrolloff=8
set wrap                     " Wrap long lines
set linebreak                " Wrap at word boundaries
set hidden                   " Switch buffers without saving
set autoread                 " Auto reload files changed outside vim
set confirm                  " Confirm before closing unsaved buffers
set history=1000
set undolevels=1000
set undofile                 " Persistent undo across sessions
set undodir=~/.vim/undodir
set timeoutlen=500            " How long to wait for a mapped key sequence (also drives which-key)

" ── Search ───────────────────────────────────────────────────
set incsearch                " Search as you type
set hlsearch                 " Highlight search results
set ignorecase               " Case insensitive search
set smartcase                " Case sensitive when uppercase present

" ── Indentation ─────────────────────────────────────────────
set tabstop=2
set shiftwidth=2
set softtabstop=2
set expandtab                " Spaces not tabs
set smartindent
set autoindent

" ── Splits ───────────────────────────────────────────────────
set splitbelow               " New horizontal splits go below
set splitright               " New vertical splits go right

" ── Performance ──────────────────────────────────────────────
set lazyredraw
set ttyfast
set updatetime=300

" ── True Color ───────────────────────────────────────────────
if exists('+termguicolors')
  let &t_8f = "\<Esc>[38;2;%lu;%lu;%lum"
  let &t_8b = "\<Esc>[48;2;%lu;%lu;%lum"
  set termguicolors
endif

" ── Colorscheme ──────────────────────────────────────────────
set background=dark
colorscheme gruvbox
let g:gruvbox_contrast_dark = 'medium'

" ── Clipboard ────────────────────────────────────────────────
set clipboard=unnamed        " Use system clipboard

" ── Backups ──────────────────────────────────────────────────
set noswapfile
set nobackup
set nowritebackup

" ============================================================
" Plugin Configuration
" ============================================================

" ── NERDTree ─────────────────────────────────────────────────
let g:NERDTreeShowHidden = 1
let g:NERDTreeMinimalUI = 1
let g:NERDTreeDirArrows = 1
let g:NERDTreeIgnore = ['\.git$', '\.terraform$', '\.DS_Store$', '__pycache__']
let g:NERDTreeWinSize = 35
let g:NERDTreeStatusline = ''

" Auto open NERDTree when opening a directory
autocmd StdinReadPre * let s:std_in=1
autocmd VimEnter * if argc() == 1 && isdirectory(argv()[0]) && !exists('s:std_in') |
    \ execute 'NERDTree' argv()[0] | wincmd p | enew | execute 'cd '.argv()[0] | endif

" Close vim if NERDTree is the only window left
autocmd BufEnter * if tabpagenr('$') == 1 && winnr('$') == 1 &&
    \ exists('b:NERDTree') && b:NERDTree.isTabTree() | quit | endif

" NERDTree git plugin symbols
let g:NERDTreeGitStatusIndicatorMapCustom = {
    \ 'Modified'  :'✹',
    \ 'Staged'    :'✚',
    \ 'Untracked' :'✭',
    \ 'Renamed'   :'➜',
    \ 'Unmerged'  :'═',
    \ 'Deleted'   :'✖',
    \ 'Dirty'     :'✗',
    \ 'Ignored'   :'☒',
    \ 'Clean'     :'✔︎',
    \ 'Unknown'   :'?',
    \ }

" ── DevIcons ─────────────────────────────────────────────────
let g:webdevicons_enable = 1
let g:webdevicons_enable_nerdtree = 1
let g:webdevicons_enable_airline_tabline = 1
let g:webdevicons_enable_airline_statusline = 1

" ── FZF ──────────────────────────────────────────────────────
let g:fzf_layout = { 'down': '~30%' }
let g:fzf_preview_window = ['right:50%', 'ctrl-/']
command! -bang -nargs=* Rg
    \ call fzf#vim#grep(
    \   'rg --column --line-number --no-heading --color=always --smart-case -- '.shellescape(<q-args>),
    \   1, fzf#vim#with_preview(), <bang>0)

" ── Airline ──────────────────────────────────────────────────
let g:airline_theme = 'gruvbox'
let g:airline_powerline_fonts = 1
let g:airline#extensions#tabline#enabled = 1
let g:airline#extensions#tabline#formatter = 'unique_tail'
let g:airline#extensions#gitgutter#enabled = 1
let g:airline#extensions#branch#enabled = 1
let g:airline#extensions#ale#enabled = 1
let g:airline_left_sep = ''
let g:airline_left_alt_sep = ''
let g:airline_right_sep = ''
let g:airline_right_alt_sep = ''

" ── GitGutter ────────────────────────────────────────────────
let g:gitgutter_enabled = 1
let g:gitgutter_map_keys = 0
let g:gitgutter_sign_added = '+'
let g:gitgutter_sign_modified = '~'
let g:gitgutter_sign_removed = '-'
let g:gitgutter_sign_removed_first_line = '-'
let g:gitgutter_sign_modified_removed = '~'

" ── Terraform ────────────────────────────────────────────────
let g:terraform_fmt_on_save = 1
let g:terraform_align = 1

" ── vim-go ───────────────────────────────────────────────────
let g:go_fmt_command = 'goimports'
let g:go_auto_type_info = 1
let g:go_highlight_functions = 1
let g:go_highlight_function_calls = 1
let g:go_highlight_types = 1
let g:go_highlight_operators = 1
let g:go_highlight_build_constraints = 1
let g:go_debug_windows = {
    \ 'vars':  'leftabove 40vnew',
    \ 'stack': 'leftabove 20new',
    \ }

" ── IndentLine ───────────────────────────────────────────────
let g:indentLine_char = '│'
let g:indentLine_enabled = 1

" ── Ack/ripgrep ──────────────────────────────────────────────
if executable('rg')
    let g:ackprg = 'rg --vimgrep --smart-case'
endif

" ── Tagbar ───────────────────────────────────────────────────
" Requires universal-ctags installed on the box (check `which ctags`),
" otherwise the outline window will just be empty.
let g:tagbar_width = 30
let g:tagbar_autofocus = 1

" ── Better Whitespace ────────────────────────────────────────
let g:better_whitespace_enabled = 1
let g:strip_whitespace_on_save = 1
let g:strip_whitespace_confirm = 0

" ── vim-illuminate ───────────────────────────────────────────
let g:Illuminate_delay = 300

" ── ALE (linting / diagnostics) ─────────────────────────────
let g:ale_sign_error = '✗'
let g:ale_sign_warning = '⚠'
let g:ale_lint_on_text_changed = 'normal'
let g:ale_lint_on_insert_leave = 1
let g:ale_lint_on_save = 1

" ── vim-startify ─────────────────────────────────────────────
let g:startify_change_to_vcs_root = 1
let g:startify_bookmarks = [ {'c': '~/.vimrc'} ]

" ── vim-obsession ────────────────────────────────────────────
" Start a session with :Obsess ./Session.vim, resume with vim -S

" ============================================================
" Key Mappings
" ============================================================
let mapleader = " "

" ── NERDTree ─────────────────────────────────────────────────
nnoremap <leader>e  :NERDTreeToggle<CR>
nnoremap <leader>ef :NERDTreeFind<CR>

" ── FZF ──────────────────────────────────────────────────────
nnoremap <leader>ff :Files<CR>
nnoremap <leader>fg :Rg<CR>
nnoremap <leader>fb :Buffers<CR>
nnoremap <leader>fh :History<CR>
nnoremap <leader>fc :Commands<CR>
nnoremap <leader>fm :Maps<CR>

" ── Git ──────────────────────────────────────────────────────
nnoremap <leader>gs  :Git<CR>
nnoremap <leader>gb  :Git blame<CR>
nnoremap <leader>gd  :Git diff<CR>
nnoremap <leader>gl  :Git log<CR>
nnoremap <leader>gp  :Git push<CR>
nnoremap <leader>gu  :GitGutterUndoHunk<CR>
nnoremap <leader>ghs :GitGutterStageHunk<CR>
nnoremap ]h          :GitGutterNextHunk<CR>
nnoremap [h          :GitGutterPrevHunk<CR>

" ── Go / Delve debugging ─────────────────────────────────────
nmap <leader>db <Plug>(go-debug-breakpoint)
nmap <leader>ds :GoDebugStart<CR>
nmap <leader>dc :GoDebugContinue<CR>
nmap <leader>dn :GoDebugNext<CR>
nmap <leader>do :GoDebugStepOut<CR>
nmap <leader>dt :GoDebugStop<CR>
nmap <leader>gr :GoRun<CR>
nmap <leader>gt :GoTest<CR>

" ── Tagbar ───────────────────────────────────────────────────
nnoremap <leader>tt :TagbarToggle<CR>

" ── Undotree ─────────────────────────────────────────────────
nnoremap <leader>u :UndotreeToggle<CR>

" ── Splits ───────────────────────────────────────────────────
nnoremap <leader>sv :vsplit<CR>
nnoremap <leader>sh :split<CR>
nnoremap <leader>se <C-w>=

" ── Buffers ──────────────────────────────────────────────────
nnoremap <leader>bd :bd<CR>
nnoremap <leader>bn :bnext<CR>
nnoremap <leader>bp :bprev<CR>

" ── Search ───────────────────────────────────────────────────
nnoremap <leader>/ :noh<CR>
nnoremap <leader>a :Ack<Space>

" ── Save / Quit ──────────────────────────────────────────────
nnoremap <leader>w :w<CR>
nnoremap <leader>q :q<CR>
nnoremap <leader>Q :qa!<CR>

" ── Move lines up/down ───────────────────────────────────────
nnoremap <A-j> :m .+1<CR>==
nnoremap <A-k> :m .-2<CR>==
vnoremap <A-j> :m '>+1<CR>gv=gv
vnoremap <A-k> :m '<-2<CR>gv=gv

" ── Tmux navigator ───────────────────────────────────────────
let g:tmux_navigator_no_mappings = 1
nnoremap <silent> <C-h> :TmuxNavigateLeft<CR>
nnoremap <silent> <C-j> :TmuxNavigateDown<CR>
nnoremap <silent> <C-k> :TmuxNavigateUp<CR>
nnoremap <silent> <C-l> :TmuxNavigateRight<CR>

" ── Clear search highlight ───────────────────────────────────
nnoremap <Esc> :noh<CR>

" ── Better indenting in visual mode ──────────────────────────
vnoremap < <gv
vnoremap > >gv

" ── Open file under cursor ───────────────────────────────────
nnoremap <leader>gf gf

" ── Session persistence ──────────────────────────────────────
nnoremap <leader>os :Obsession<CR>
nnoremap <leader>oS :Obsession!<CR>

" ── Which-key popup ───────────────────────────────────────────
nnoremap <silent> <leader> :WhichKey '<Space>'<CR>

let g:which_key_map = {
      \ 'e'  : 'NERDTree toggle',
      \ 'w'  : 'save',
      \ 'q'  : 'quit',
      \ 'Q'  : 'quit all (!)',
      \ 'u'  : 'undotree toggle',
      \ '/'  : 'clear search highlight',
      \ 'a'  : 'ack search',
      \ }

let g:which_key_map.e = { 'name' : '+nerdtree',
      \ 'e'  : ['NERDTreeToggle', 'toggle'],
      \ 'f'  : ['NERDTreeFind', 'find current file'],
      \ }

let g:which_key_map.f = { 'name' : '+fzf',
      \ 'f' : ['Files', 'find files'],
      \ 'g' : ['Rg', 'ripgrep'],
      \ 'b' : ['Buffers', 'buffers'],
      \ 'h' : ['History', 'history'],
      \ 'c' : ['Commands', 'commands'],
      \ 'm' : ['Maps', 'maps'],
      \ }

let g:which_key_map.g = { 'name' : '+git/go',
      \ 's'  : ['Git', 'git status'],
      \ 'b'  : ['Git blame', 'git blame'],
      \ 'd'  : ['Git diff', 'git diff'],
      \ 'l'  : ['Git log', 'git log'],
      \ 'p'  : ['Git push', 'git push'],
      \ 'u'  : ['GitGutterUndoHunk', 'undo hunk'],
      \ 'r'  : ['GoRun', 'go run'],
      \ 't'  : ['GoTest', 'go test'],
      \ 'f'  : ['normal! gf', 'go to file under cursor'],
      \ }

let g:which_key_map.d = { 'name' : '+debug (go)',
      \ 'b' : ['call go#debug#Breakpoint()', 'toggle breakpoint'],
      \ 's' : ['GoDebugStart', 'start'],
      \ 'c' : ['GoDebugContinue', 'continue'],
      \ 'n' : ['GoDebugNext', 'step next'],
      \ 'o' : ['GoDebugStepOut', 'step out'],
      \ 't' : ['GoDebugStop', 'stop'],
      \ }

let g:which_key_map.t = { 'name' : '+tagbar',
      \ 't' : ['TagbarToggle', 'toggle'],
      \ }

let g:which_key_map.s = { 'name' : '+splits',
      \ 'v' : ['vsplit', 'vertical'],
      \ 'h' : ['split', 'horizontal'],
      \ 'e' : ['wincmd =', 'equalize'],
      \ }

let g:which_key_map.b = { 'name' : '+buffer',
      \ 'd' : ['bd', 'delete'],
      \ 'n' : ['bnext', 'next'],
      \ 'p' : ['bprev', 'prev'],
      \ }

let g:which_key_map.o = { 'name' : '+session',
      \ 's' : ['Obsession', 'start/track session'],
      \ 'S' : ['Obsession!', 'stop session'],
      \ }

call which_key#register('<Space>', "g:which_key_map")

" ============================================================
" File Type Settings
" ============================================================
autocmd FileType yaml       setlocal ts=2 sw=2 expandtab
autocmd FileType json       setlocal ts=2 sw=2 expandtab
autocmd FileType terraform  setlocal ts=2 sw=2 expandtab
autocmd FileType hcl        setlocal ts=2 sw=2 expandtab
autocmd FileType sh         setlocal ts=2 sw=2 expandtab
autocmd FileType bash       setlocal ts=2 sw=2 expandtab
autocmd FileType markdown   setlocal wrap linebreak spell
autocmd FileType python     setlocal shiftwidth=2 softtabstop=2 expandtab

" ============================================================
" Misc / Legacy Settings
" ============================================================
set backspace=indent,eol,start
set smarttab
" ---- Show file path -----
set statusline+=%F
" -------------------------
inoremap jj <ESC>
inoremap kk <ESC>
syntax on
highlight Cursor ctermfg=white ctermbg=lightblue
highlight Folded ctermfg=magenta

" ------ Tabline Settings ----------
set showtabline=2
hi TabLineFill ctermfg=black ctermbg=DarkGreen
hi TabLine ctermfg=Blue ctermbg=Yellow
hi TabLineSel ctermfg=Black ctermbg=Gray
map <C-T> gt

"------- Cursor Settings -----------
" Reference chart of values:
"   Ps = 0  -> blinking block.
"   Ps = 1  -> blinking block (default).
"   Ps = 2  -> steady block.
"   Ps = 3  -> blinking underline.
"   Ps = 4  -> steady underline.
"   Ps = 5  -> blinking bar (xterm).
"   Ps = 6  -> steady bar (xterm).
let &t_SI = "\e[3 q"
let &t_EI = "\e[2 q"
