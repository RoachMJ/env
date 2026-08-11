--------------------------------------------------------------------------
-- Neovim config — Lua/lazy.nvim port of the Vundle .vimrc
-- Install to: ~/.config/nvim/init.lua  (use install.sh to bootstrap)
--------------------------------------------------------------------------

-- ============================================================
-- General Settings  (same intent as the vimrc's General Settings block)
-- ============================================================
local opt = vim.opt
local g   = vim.g

g.mapleader = " "
g.maplocalleader = " "

opt.encoding      = "utf-8"
opt.mouse         = "a"
opt.number        = true
opt.relativenumber = false -- was on in your original vimrc; turned off since the shifting numbers weren't useful to you
opt.cursorline    = true
opt.showmatch     = true
opt.showcmd       = true
opt.ruler         = true
opt.scrolloff     = 8
opt.sidescrolloff = 8
opt.wrap          = true
opt.linebreak     = true
opt.hidden        = true
opt.autoread      = true
opt.confirm       = true
opt.history       = 1000
opt.undolevels    = 1000
opt.undofile      = true
opt.undodir       = vim.fn.expand("~/.local/share/nvim/undodir")
opt.timeoutlen    = 500

opt.incsearch  = true
opt.hlsearch   = true
opt.ignorecase = true
opt.smartcase  = true

opt.tabstop     = 2
opt.shiftwidth  = 2
opt.softtabstop = 2
opt.expandtab   = true
opt.smartindent = true
opt.autoindent  = true
opt.smarttab    = true
opt.backspace   = { "indent", "eol", "start" }

opt.splitbelow = true
opt.splitright = true

opt.lazyredraw = true
opt.updatetime = 300

opt.termguicolors = true
opt.background = "dark"

opt.clipboard = "unnamedplus"

opt.swapfile   = false
opt.backup     = false
opt.writebackup = false

opt.showtabline = 2
opt.signcolumn  = "yes"

-- jj / kk to escape insert mode (from your original vimrc)
vim.keymap.set("i", "jj", "<Esc>")
vim.keymap.set("i", "kk", "<Esc>")

-- ============================================================
-- Bootstrap lazy.nvim
-- ============================================================
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
-- vim.loop was fully removed in Nvim 0.12 in favor of vim.uv — the (vim.uv or
-- vim.loop) fallback keeps this working on older Neovim versions too.
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  vim.fn.system({
    "git", "clone", "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable", lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- ============================================================
-- Plugins
-- ============================================================
require("lazy").setup({

  -- ── Colorscheme ────────────────────────────────────────────
  {
    "catppuccin/nvim",
    name = "catppuccin",
    priority = 1000,
    lazy = false,
    config = function()
      require("catppuccin").setup({
        -- Flavors: "latte" (light), "frappe", "macchiato", "mocha" (darkest)
        -- Swap the line below to "latte" if you want the light/cream variant.
        flavour = "mocha",
        integrations = {
          cmp = true,
          gitsigns = true,
          treesitter = true,
          telescope = true,
          native_lsp = { enabled = true },
          nvim_tree = true,
          mason = true,
          which_key = true,
        },
      })
      vim.cmd.colorscheme("catppuccin")

      -- Catppuccin's default ErrorMsg/WarningMsg fill the whole message
      -- line with a solid background (that's the neon-pink "hit ENTER to
      -- continue" wall). Softened to bold colored text, no fill.
      vim.api.nvim_set_hl(0, "ErrorMsg", { fg = "#f38ba8", bg = "NONE", bold = true })
      vim.api.nvim_set_hl(0, "WarningMsg", { fg = "#f9e2af", bg = "NONE", bold = true })
      vim.api.nvim_set_hl(0, "MoreMsg", { fg = "#a6e3a1", bg = "NONE", bold = true })
      vim.api.nvim_set_hl(0, "Question", { fg = "#89b4fa", bg = "NONE", bold = true })
    end,
  },

  -- ── File Navigation ───────────────────────────────────────
  { "nvim-tree/nvim-web-devicons" },
  {
    "nvim-tree/nvim-tree.lua",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function()
      require("nvim-tree").setup({
        view = { width = 35 },
        filters = { dotfiles = false },
        git = { enable = true },
        renderer = { group_empty = true },
      })
    end,
  },
  {
    "nvim-telescope/telescope.nvim",
    tag = "0.1.8",
    dependencies = {
      "nvim-lua/plenary.nvim",
      { "nvim-telescope/telescope-fzf-native.nvim", build = "make" },
    },
    config = function()
      local telescope = require("telescope")
      telescope.setup({
        defaults = {
          file_ignore_patterns = { "%.git/", "%.terraform/", "__pycache__/" },
        },
      })
      pcall(telescope.load_extension, "fzf")
    end,
  },
  { "christoomey/vim-tmux-navigator" },

  -- ── Git ───────────────────────────────────────────────────
  {
    "lewis6991/gitsigns.nvim",
    config = function()
      require("gitsigns").setup({
        signs = {
          add = { text = "+" },
          change = { text = "~" },
          delete = { text = "-" },
          topdelete = { text = "-" },
          changedelete = { text = "~" },
        },
        on_attach = function(bufnr)
          local gs = require("gitsigns")
          local function map(mode, l, r, desc)
            vim.keymap.set(mode, l, r, { buffer = bufnr, desc = desc })
          end
          map("n", "]h", gs.next_hunk, "Next hunk")
          map("n", "[h", gs.prev_hunk, "Prev hunk")
          map("n", "<leader>gu", gs.reset_hunk, "Undo hunk")
          map("n", "<leader>ghs", gs.stage_hunk, "Stage hunk")
        end,
      })
    end,
  },
  { "tpope/vim-fugitive" },
  { "tpope/vim-rhubarb" },

  -- ── Treesitter (syntax, replaces vim-polyglot / language syntax packs) ──
  -- nvim-treesitter did a full rewrite; `main` is the current branch and the
  -- old `nvim-treesitter.configs` module + ensure_installed option are gone.
  -- Requires the `tree-sitter` CLI on $PATH (install.sh installs it).
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "main",
    build = ":TSUpdate",
    init = function()
      local ensure_installed = {
        "go", "python", "yaml", "json", "hcl", "terraform",
        "dockerfile", "bash", "markdown", "markdown_inline",
        "lua", "vim", "vimdoc", "query", "gitcommit", "regex",
      }
      local already_installed = require("nvim-treesitter.config").get_installed()
      local to_install = vim.iter(ensure_installed)
        :filter(function(p) return not vim.tbl_contains(already_installed, p) end)
        :totable()
      if #to_install > 0 then
        require("nvim-treesitter").install(to_install)
      end

      vim.api.nvim_create_autocmd("FileType", {
        callback = function()
          -- Enable treesitter highlighting (replaces regex syntax) and indent
          pcall(vim.treesitter.start)
          pcall(function()
            vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
          end)
        end,
      })
    end,
  },
  { "hashivim/vim-terraform" },      -- terraform fmt-on-save (kept, still handy)
  { "pearofducks/ansible-vim" },     -- ansible doc lookups / conventions
  { "fatih/vim-go", ft = "go", build = ":GoUpdateBinaries" },

  -- ── LSP + Completion (replaces YouCompleteMe/supertab) ───────
  {
    "neovim/nvim-lspconfig",
    dependencies = {
      "williamboman/mason.nvim",
      "williamboman/mason-lspconfig.nvim",
      "hrsh7th/cmp-nvim-lsp",
    },
    config = function()
      require("mason").setup()
      local servers = {
        "gopls", "pyright", "terraformls", "bashls",
        "yamlls", "jsonls", "dockerls", "ansiblels",
      }
      -- Nvim 0.11+ / nvim-lspconfig v2+: mason-lspconfig now calls
      -- vim.lsp.enable() itself for every Mason-installed server instead of
      -- the old require('lspconfig')[server].setup{} pattern.
      require("mason-lspconfig").setup({
        ensure_installed = servers,
        automatic_enable = true,
      })

      -- Global default capabilities merged into every server config.
      local capabilities = require("cmp_nvim_lsp").default_capabilities()
      vim.lsp.config("*", { capabilities = capabilities })

      -- Buffer-local keymaps once a server actually attaches
      -- (replaces the old per-server on_attach callback).
      vim.api.nvim_create_autocmd("LspAttach", {
        callback = function(args)
          local bufnr = args.buf
          local map = function(mode, lhs, rhs, desc)
            vim.keymap.set(mode, lhs, rhs, { buffer = bufnr, desc = desc })
          end
          map("n", "gd", vim.lsp.buf.definition, "Goto definition")
          map("n", "gD", vim.lsp.buf.declaration, "Goto declaration")
          map("n", "gi", vim.lsp.buf.implementation, "Goto implementation")
          map("n", "gr", vim.lsp.buf.references, "References")
          map("n", "K", vim.lsp.buf.hover, "Hover docs")
          map("n", "<leader>rn", vim.lsp.buf.rename, "Rename symbol")
          map("n", "<leader>ca", vim.lsp.buf.code_action, "Code action")
          map("n", "[d", vim.diagnostic.goto_prev, "Prev diagnostic")
          map("n", "]d", vim.diagnostic.goto_next, "Next diagnostic")
          map("n", "<leader>cd", vim.diagnostic.open_float, "Line diagnostics")
        end,
      })

      vim.diagnostic.config({
        signs = {
          text = {
            [vim.diagnostic.severity.ERROR] = "✗",
            [vim.diagnostic.severity.WARN]  = "⚠",
            [vim.diagnostic.severity.INFO]  = "i",
            [vim.diagnostic.severity.HINT]  = "h",
          },
        },
        virtual_text = true,
        underline = true,
      })

      -- Headless installer helper — used by install.sh
      vim.api.nvim_create_user_command("MasonInstallAll", function()
        local registry = require("mason-registry")
        for _, name in ipairs(servers) do
          local ok, pkg = pcall(registry.get_package, name)
          if ok and not pkg:is_installed() then
            pkg:install()
          end
        end
      end, {})
    end,
  },
  {
    "hrsh7th/nvim-cmp",
    dependencies = {
      "hrsh7th/cmp-nvim-lsp",
      "hrsh7th/cmp-buffer",
      "hrsh7th/cmp-path",
      "L3MON4D3/LuaSnip",
      "saadparwaiz1/cmp_luasnip",
      "rafamadriz/friendly-snippets",
    },
    config = function()
      local cmp = require("cmp")
      local luasnip = require("luasnip")
      require("luasnip.loaders.from_vscode").lazy_load()

      cmp.setup({
        snippet = {
          expand = function(args) luasnip.lsp_expand(args.body) end,
        },
        mapping = cmp.mapping.preset.insert({
          ["<C-Space>"] = cmp.mapping.complete(),
          ["<CR>"] = cmp.mapping.confirm({ select = true }),
          ["<Tab>"] = cmp.mapping(function(fallback)
            if cmp.visible() then cmp.select_next_item()
            elseif luasnip.expand_or_jumpable() then luasnip.expand_or_jump()
            else fallback() end
          end, { "i", "s" }),
          ["<S-Tab>"] = cmp.mapping(function(fallback)
            if cmp.visible() then cmp.select_prev_item()
            elseif luasnip.jumpable(-1) then luasnip.jump(-1)
            else fallback() end
          end, { "i", "s" }),
        }),
        sources = cmp.config.sources({
          { name = "nvim_lsp" },
          { name = "luasnip" },
        }, {
          { name = "buffer" },
          { name = "path" },
        }),
      })
    end,
  },

  -- ── Async linting (fills gaps LSP diagnostics don't cover) ──
  {
    "mfussenegger/nvim-lint",
    config = function()
      require("lint").linters_by_ft = {
        sh = { "shellcheck" },
        bash = { "shellcheck" },
        yaml = { "yamllint" },
      }
      vim.api.nvim_create_autocmd({ "BufWritePost", "InsertLeave" }, {
        callback = function() require("lint").try_lint() end,
      })
    end,
  },

  -- ── Outline (LSP-based — no ctags binary dependency) ─────────
  {
    "stevearc/aerial.nvim",
    dependencies = { "nvim-treesitter/nvim-treesitter", "nvim-tree/nvim-web-devicons" },
    config = function()
      require("aerial").setup({ backends = { "lsp", "treesitter" } })
    end,
  },

  -- ── Status Line / Tabline (replaces airline) ─────────────────
  {
    "nvim-lualine/lualine.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function()
      require("lualine").setup({ options = { theme = "catppuccin" } })
    end,
  },
  {
    "akinsho/bufferline.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function()
      require("bufferline").setup({ options = { diagnostics = "nvim_lsp" } })
    end,
  },

  -- ── Editor Utilities ─────────────────────────────────────────
  { "mbbill/undotree" },
  { "kylechui/nvim-surround", config = function() require("nvim-surround").setup() end },
  { "numToStr/Comment.nvim", config = function() require("Comment").setup() end },
  {
    "windwp/nvim-autopairs",
    config = function() require("nvim-autopairs").setup() end,
  },
  { "tpope/vim-repeat" },
  { "wellle/targets.vim" },
  { "RRethy/vim-illuminate" },
  { "farmergreg/vim-lastplace" },
  { "tpope/vim-obsession" },
  { "kshenoy/vim-signature" },
  { "ntpeters/vim-better-whitespace",
    config = function()
      g.better_whitespace_enabled = 1
      g.strip_whitespace_on_save = 1
      g.strip_whitespace_confirm = 0
    end,
  },
  {
    "lukas-reineke/indent-blankline.nvim",
    main = "ibl",
    config = function() require("ibl").setup() end,
  },

  -- ── Which-key popup (native Lua implementation) ──────────────
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    config = function()
      require("which-key").setup({})
      require("which-key").add({
        { "<leader>e", group = "nerdtree/explorer" },
        { "<leader>f", group = "find" },
        { "<leader>g", group = "git/go" },
        { "<leader>d", group = "debug (go)" },
        { "<leader>t", group = "tagbar/outline" },
        { "<leader>s", group = "splits" },
        { "<leader>b", group = "buffer" },
        { "<leader>o", group = "session" },
        { "<leader>c", group = "codex/code action" },
      })
    end,
  },

  -- ── Codex CLI integration ─────────────────────────────────────
  -- NOTE: several community codex.nvim implementations exist with
  -- slightly different command names. This is the most fully-featured
  -- one at time of writing — check `:h codex` (or its README) after
  -- install to confirm the exact command names, then adjust the
  -- keymaps below if they differ.
  {
    "anirudhsundar/codex.nvim",
    cmd = { "Codex", "CodexToggle" },
    config = function()
      -- pcall so a missing/renamed setup() call doesn't break the rest
      -- of your config if this plugin's API changes.
      pcall(function() require("codex").setup({}) end)
    end,
  },

}, {
  ui = { border = "rounded" },
})

-- ============================================================
-- Key Mappings  (mirrors the vimrc leader scheme)
-- ============================================================
local map = vim.keymap.set

-- NERDTree -> nvim-tree
map("n", "<leader>e",  ":NvimTreeToggle<CR>", { desc = "Toggle file tree" })
map("n", "<leader>ef", ":NvimTreeFindFile<CR>", { desc = "Find current file in tree" })

-- FZF -> Telescope
map("n", "<leader>ff", ":Telescope find_files<CR>", { desc = "Find files" })
map("n", "<leader>fg", ":Telescope live_grep<CR>", { desc = "Ripgrep" })
map("n", "<leader>fb", ":Telescope buffers<CR>", { desc = "Buffers" })
map("n", "<leader>fh", ":Telescope oldfiles<CR>", { desc = "History" })
map("n", "<leader>fc", ":Telescope commands<CR>", { desc = "Commands" })
map("n", "<leader>fm", ":Telescope keymaps<CR>", { desc = "Maps" })
map("n", "<leader>a",  ":Telescope live_grep<CR>", { desc = "Ack-style search" })

-- Git
map("n", "<leader>gs", ":Git<CR>", { desc = "Git status" })
map("n", "<leader>gb", ":Git blame<CR>", { desc = "Git blame" })
map("n", "<leader>gd", ":Gdiffsplit<CR>", { desc = "Git diff" })
map("n", "<leader>gl", ":Git log<CR>", { desc = "Git log" })
map("n", "<leader>gp", ":Git push<CR>", { desc = "Git push" })
map("n", "<leader>gf", "gf", { desc = "Open file under cursor" })

-- Go / Delve debugging (unchanged from vim-go)
map("n", "<leader>db", "<Plug>(go-debug-breakpoint)", { desc = "Toggle breakpoint" })
map("n", "<leader>ds", ":GoDebugStart<CR>", { desc = "Debug start" })
map("n", "<leader>dc", ":GoDebugContinue<CR>", { desc = "Debug continue" })
map("n", "<leader>dn", ":GoDebugNext<CR>", { desc = "Debug step next" })
map("n", "<leader>do", ":GoDebugStepOut<CR>", { desc = "Debug step out" })
map("n", "<leader>dt", ":GoDebugStop<CR>", { desc = "Debug stop" })
map("n", "<leader>gr", ":GoRun<CR>", { desc = "Go run" })
map("n", "<leader>gt", ":GoTest<CR>", { desc = "Go test" })

-- Outline (tagbar -> aerial)
map("n", "<leader>tt", ":AerialToggle<CR>", { desc = "Toggle outline" })

-- Undotree
map("n", "<leader>u", ":UndotreeToggle<CR>", { desc = "Toggle undo tree" })

-- Splits
map("n", "<leader>sv", ":vsplit<CR>", { desc = "Vertical split" })
map("n", "<leader>sh", ":split<CR>", { desc = "Horizontal split" })
map("n", "<leader>se", "<C-w>=", { desc = "Equalize splits" })

-- Buffers
map("n", "<leader>bd", ":bd<CR>", { desc = "Delete buffer" })
map("n", "<leader>bn", ":bnext<CR>", { desc = "Next buffer" })
map("n", "<leader>bp", ":bprev<CR>", { desc = "Prev buffer" })

-- Search
map("n", "<leader>/", ":noh<CR>", { desc = "Clear search highlight" })
map("n", "<Esc>", ":noh<CR>", { desc = "Clear search highlight" })

-- Save / Quit
map("n", "<leader>w", ":w<CR>", { desc = "Save" })
map("n", "<leader>q", ":q<CR>", { desc = "Quit" })
map("n", "<leader>Q", ":qa!<CR>", { desc = "Quit all (!)" })

-- Move lines up/down
map("n", "<A-j>", ":m .+1<CR>==", { desc = "Move line down" })
map("n", "<A-k>", ":m .-2<CR>==", { desc = "Move line up" })
map("v", "<A-j>", ":m '>+1<CR>gv=gv", { desc = "Move selection down" })
map("v", "<A-k>", ":m '<-2<CR>gv=gv", { desc = "Move selection up" })

-- Tmux navigator
g.tmux_navigator_no_mappings = 1
map("n", "<C-h>", ":TmuxNavigateLeft<CR>", { silent = true })
map("n", "<C-j>", ":TmuxNavigateDown<CR>", { silent = true })
map("n", "<C-k>", ":TmuxNavigateUp<CR>", { silent = true })
map("n", "<C-l>", ":TmuxNavigateRight<CR>", { silent = true })

-- Better indenting in visual mode
map("v", "<", "<gv")
map("v", ">", ">gv")

-- Session persistence
map("n", "<leader>os", ":Obsession<CR>", { desc = "Start/track session" })
map("n", "<leader>oS", ":Obsession!<CR>", { desc = "Stop session" })

-- Codex — check the plugin's actual command names after install and
-- adjust these two if they differ (see NOTE in the plugin spec above).
map("n", "<leader>cc", ":CodexToggle<CR>", { desc = "Toggle Codex" })
map("v", "<leader>cs", ":Codex<CR>", { desc = "Send selection to Codex" })

map("n", "<C-t>", "gt") -- legacy tab-nav mapping from your original vimrc

-- ============================================================
-- File Type Settings
-- ============================================================
local ft_group = vim.api.nvim_create_augroup("FileTypeSettings", { clear = true })
local function ft_indent(pattern, width)
  vim.api.nvim_create_autocmd("FileType", {
    group = ft_group,
    pattern = pattern,
    callback = function()
      vim.bo.tabstop = width
      vim.bo.shiftwidth = width
      vim.bo.expandtab = true
    end,
  })
end
ft_indent({ "yaml", "json", "terraform", "hcl", "sh", "bash", "python" }, 2)

vim.api.nvim_create_autocmd("FileType", {
  group = ft_group,
  pattern = "markdown",
  callback = function()
    vim.wo.wrap = true
    vim.wo.linebreak = true
    vim.bo.spell = true
  end,
})

-- Reload files changed outside Neovim
vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter" }, {
  command = "checktime",
})
