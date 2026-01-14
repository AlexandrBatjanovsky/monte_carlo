{
  description = "Julia development environment with NixVim";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    nixvim.url = "github:nix-community/nixvim";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, nixvim, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        
        # Настройка самого Neovim через NixVim
        nvim = nixvim.legacyPackages.${system}.makeNixvim {
          # Можно добавить дополнительные пакеты (например, саму Julia), 
          # чтобы они были доступны внутри Neovim
          extraPackages = with pkgs; [
            julia-bin 
          ];

          plugins = {
            # Подсветка синтаксиса
            treesitter = {
              enable = true;
              # Вместо .builtins используем прямой список парсеров
              grammarPackages = [ 
                pkgs.vimPlugins.nvim-treesitter-parsers.julia 
                pkgs.vimPlugins.nvim-treesitter-parsers.latex # опционально, но полезно для Julia
              ];
            };

            # ... твои прошлые плагины ...
            web-devicons.enable = true;
            telescope.enable = true;
            lualine.enable = true;
  
            # Чтобы LSP подхватывал изменения сразу
            # lsp.servers.julials.enable = true;

            # LSP (Language Server)
            lsp = {
              enable = true;
              servers.julials = {
                enable = true;
                # Отключаем поиск пакета в Nix, так как мы используем julia-bin
                package = null; 
                # Указываем команду для запуска явно
                cmd = [
                  "julia"
                  "--startup-file=no"
                  "--history-file=no"
                  "-e"
                  "using LanguageServer; run_server()"
                ];
              };
            };

            # Автодополнение
            cmp = {
              enable = true;
              settings.sources = [
                { name = "nvim_lsp"; }
                { name = "buffer"; }
              ];
            };

            # Интерактивная консоль (REPL)
            iron = {
              enable = true;
              settings = {
                config = {
                  # Определяем, как открывать REPL
                  repl_open_cmd = "vertical botright 80 split"; # Откроет справа шириной 80
                  repl_definition = {
                    julia = {
                      command = [ "julia" ];
                    };
                  };
                };
                # Добавляем обязательный ключ __default для команд открытия
                # (Это именно то, на что ругался лог)
                repl_open_cmd_names = {
                  "__default" = "vertical botright 80 split";
                };
                keymaps = {
                  send_motion = "<space>sc";
                  visual_send = "<space>sc";
                };
              };
            };            
          };
          opts = {
            number = true;         # Номера строк
            shiftwidth = 4;        # Табуляция
            expandtab = true;
          };
          
          globals.mapleader = " "; # Назначаем Leader-клавишу
      };
      in
      {
        # Теперь Neovim можно запустить через 'nix run'
        packages.default = nvim;

        # Или использовать в devShell
        devShells.default = pkgs.mkShell {
          buildInputs = [ nvim ];
        };
      });
}
