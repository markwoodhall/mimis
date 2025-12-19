# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is **Mimis**, a Neovim distribution written in Fennel, focused on Lisp languages (Clojure, Fennel, Janet) and org-mode.

## Commands

- `:MimisInstall` - Install plugins and regenerate helptags
- `:MimisUpdate` - Upgrade vim-plug and update all plugins

## Architecture

### Bootstrap Flow

1. `init.vim` → disables built-ins, sets up Fennel compiler, loads `fnl/init.fnl`
2. `fnl/init.fnl` → loads options first, then calls `package.enable` (registers plugins) and `package.setup` (configures them)

### Module System

Modules live in `fnl/modules/` and follow a consistent pattern:

```fennel
(fn depends [] [...])  ; Optional: list of module dependencies
(fn enable [args])     ; Called during plugin registration (vim-plug)
(fn setup [args])      ; Called after plugins load to configure them
{: enable : setup : depends}
```

**Key modules:**
- `fnl/modules/packages/package.fnl` - The module loader that orchestrates `enable` and `setup` phases
- `fnl/modules/packages/*.fnl` - Language packs (clojure, fennel, sql) that declare dependencies on base modules

### Plugin Management

- Uses vim-plug (`fnl/plugins.fnl`)
- `fnl/packagelock.fnl` contains pinned commit hashes for `:stable` and `:latest` channels
- Plugins are registered in `enable` phase, configured in `setup` phase

### Core Libraries

- `fnl/mimis.fnl` - Utility functions (split panes, collection helpers, keymap helpers)
- `lua/nvim.lua` - Fennel helper for Neovim API access (bundled Fennel compiler at `lua/fennel.lua`)

### Important Conventions

- Leader key is Space, local leader is Comma
- Use `mimis.leader-map` for leader-prefixed keybindings
- Options are set in `fnl/modules/options.fnl` and must load before modules that depend on vim settings
- Fennel path includes both `fnl/` and `fnl/modules/` directories