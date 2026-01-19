{ pkgs, system, nixvim }:

nixvim.legacyPackages.${system}.makeNixvim {
  extraPackages = [ pkgs.julia-bin ];

  plugins = {
    web-devicons.enable = true;
    telescope.enable = true;
    lualine.enable = true;

    conform-nvim = {
      enable = true;
      settings = {
        formatters_by_ft = {
          julia = [ "juliaformatter" ];
        };
        format_on_save = {
          lsp_fallback = true;
          timeout_ms = 2000;
        };
      };
    };

    which-key = {
      enable = true;
      settings.delay = 300;
    };

    flash = {
      enable = true;
      settings = {
        labels = "asdfghjklqwertyuiopzxcvbnm";
        search.mode = "exact";
        jump.autojump = true;
      };
    };

    treesitter = {
      enable = true;
      nixGrammars = true;
      grammarPackages = with pkgs.vimPlugins.nvim-treesitter.builtGrammars; [
        julia
        latex
        markdown
        lua
        bash
      ];
    };

    lsp = {
      enable = true;
      servers.julials = {
        enable = true;
        package = null;
        cmd = [
          "julia"
          "--startup-file=no"
          "--history-file=no"
          "--project=."
          "-e"
          ''
            using LanguageServer;
            server = LanguageServer.LanguageServerInstance(stdin, stdout, pwd());
            run(server);
          ''
        ];
        extraOptions.settings.julia = {
          usePlotPane = true;
          useSymbolServer = true;
          indexAllPackages = true;
        };
        onAttach.function = ''
          if client.server_capabilities.inlayHintProvider then
            vim.lsp.inlay_hint.enable(true)
          end
        '';
      };
    };

    trouble.enable = true;

    cmp = {
      enable = true;
      autoEnableSources = true;
      settings = {
        sources = [
          { name = "nvim_lsp"; }
          { name = "luasnip"; }
          { name = "path"; }
          { name = "buffer"; }
          { name = "latex_symbols"; }
        ];
        mapping = {
          "<Tab>" = "cmp.mapping.select_next_item()";
          "<S-Tab>" = "cmp.mapping.select_prev_item()";
          "<CR>" = "cmp.mapping.confirm({ select = true })";
          "<C-Space>" = "cmp.mapping.complete()";
        };
        snippet.expand = ''
          function(args)
            require('luasnip').lsp_expand(args.body)
          end
        '';
      };
    };

    luasnip.enable = true;
    cmp-nvim-lsp.enable = true;
    cmp-buffer.enable = true;
    cmp-path.enable = true;

    iron = {
      enable = true;
      settings = {
        config = {
          repl_open_cmd = "vertical botright 80 split";
          repl_definition.julia.command = [ "julia" ];
        };
        repl_open_cmd_names."__default" = "vertical botright 80 split";
        keymaps = {
          send_motion = "<space>sc";
          visual_send = "<space>sc";
        };
      };
    };

    nvim-tree = {
      enable = true;
      settings = {
        update_focused_file.enable = true;
        renderer.highlight_git = true;
        renderer.icons.show.git = true;
      };
    };

    aerial = {
      enable = true;
      settings.backends = [ "lsp" "treesitter" ];
    };

    bufferline = {
      enable = true;
      settings.options.offsets = [
        {
          filetype = "NvimTree";
          text = "File Explorer";
          highlight = "Directory";
          separator = true;
        }
      ];
    };
  };

  keymaps = [
    {
      mode = "n";
      key = "s";
      action = ''<cmd>lua require("flash").jump()<cr>'';
      options.desc = "Flash Jump";
    }
    {
      mode = "n";
      key = "S";
      action = ''<cmd>lua require("flash").treesitter()<cr>'';
    }
    {
      mode = "n";
      key = "<C-n>";
      action = "<cmd>NvimTreeToggle<cr>";
    }
    {
      mode = "n";
      key = "<leader>a";
      action = "<cmd>AerialToggle right<cr>";
    }
    { mode = "n"; key = "<C-h>"; action = "<C-w>h"; }
    { mode = "n"; key = "<C-j>"; action = "<C-w>j"; }
    { mode = "n"; key = "<C-k>"; action = "<C-w>k"; }
    { mode = "n"; key = "<C-l>"; action = "<C-w>l"; }
    { mode = "n"; key = "<Tab>"; action = "<cmd>BufferLineCycleNext<cr>"; }
    { mode = "n"; key = "<S-Tab>"; action = "<cmd>BufferLineCyclePrev<cr>"; }
    {
      mode = "n";
      key = "<leader>x";
      action = "<cmd>Trouble diagnostics toggle<cr>";
    }
    {
      mode = "n";
      key = "<leader>ca";
      action.__raw = "function() vim.lsp.buf.code_action() end";
    }
  ];

  opts = {
    number = true;
    shiftwidth = 4;
  };
}
