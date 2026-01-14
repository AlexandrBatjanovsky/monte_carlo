{
  description = "Julia CUDA Monte Carlo Project with NixVim";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    nixvim.url = "github:nix-community/nixvim";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, nixvim, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config = {
            allowUnfree = true;
            cudaSupport = true;
          };
        };

        # Определяем библиотеки CUDA
        cuda-libs = with pkgs; [
          cudaPackages.cuda_nvcc
          cudaPackages.cudatoolkit
          linuxPackages.nvidia_x11
          libGL
          stdenv.cc.cc.lib
        ];

        # Конфигурируем Neovim специально под этот проект
        myNixvim = nixvim.legacyPackages.${system}.makeNixvim {
          # Добавляем julia в PATH самого редактора
          extraPackages = [ pkgs.julia-bin ];

          plugins = {
            web-devicons.enable = true;
            telescope.enable = true;
            lualine.enable = true;

            # 1. Форматирование при сохранении (очень приятно)
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

            # 2. Показывать, какие комбинации есть (must-have для iron и lsp)
            which-key = {
              enable = true;
              settings = {
                delay = 300;
              };
            };

            # 3. Быстрый прыжок по коду
            flash = {
              enable = true;
              settings = {
                labels = "asdfghjklqwertyuiopzxcvbnm";
                search = {
                  mode = "exact";
                };
                jump = {
                  autojump = true;
                };
              };
            };

            treesitter = {
              enable = true;
              nixGrammars = true;
              # ensureInstalled = [ "julia" "latex" ];
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
                  # Этим флагом мы говорим Julia использовать текущую папку как проект
                  "--project=."
                  "-e"
                  ''
                    using LanguageServer;
                    # Указываем явно путь к функции запуска
                    # Первый аргумент - stdin, второй - stdout
                    # Третий - путь к проекту, четвертый - путь к депо (опционально)
                    server = LanguageServer.LanguageServerInstance(stdin, stdout, pwd());
                    run(server);
                  ''
                ];
                extraOptions = {
                  settings = {
                    julia = {
                    # Разрешить серверу использовать текущее окружение для поиска символов
                    usePlotPane = true;
                    useSymbolServer = true;
                    # Важно для CUDA: разрешить индексацию зависимостей
                    indexAllPackages = true;
                    };
                  };
                };

                # чтобы Neovim показывал типы переменных прямо в коде
                onAttach.function = ''
                  if client.server_capabilities.inlayHintProvider then
                    vim.lsp.inlay_hint.enable(true)
                  end
                '';
              };
            };

            # Автодополнение
            cmp-nvim-lsp.enable = true;
            cmp-buffer.enable = true;
            cmp-path.enable = true;
            luasnip.enable = true;
            cmp = {
              enable = true;
              autoEnableSources = true;
              settings = {
                sources = [
                  { name = "nvim_lsp"; }   # Данные от Julia Language Server
                  { name = "luasnip"; }    # Сниппеты (шаблоны кода)
                  { name = "path"; }       # Пути к файлам
                  { name = "buffer"; }     # ckова из текущего текста
                  { name = "latex_symbols"; }
                ];
                # Настройка клавиш для выбора
                mapping = {
                  "<Tab>" = "cmp.mapping.select_next_item()";
                  "<S-Tab>" = "cmp.mapping.select_prev_item()";
                  "<CR>" = "cmp.mapping.confirm({ select = true })";
                  "<C-Space>" = "cmp.mapping.complete()"; # Принудительный вызов меню
                };
                snippet.expand = ''
                  function(args)
                    require('luasnip').lsp_expand(args.body)
                  end
                '';
              };

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
            nvim-tree = {
              enable = true;
              # Автоматически закрывать дерево, если оно последнее оставшееся окно
              settings = {
                # Подсвечивать открытый файл в дереве
                update_focused_file.enable = true;
                # Настройки отображения
                renderer = {
                  highlight_git = true;
                  icons.show.git = true;
                };
              };
            };

            aerial = {
              enable = true;
              settings.backends = [ "lsp" "treesitter" ];
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
              options.desc = "Flash Treesitter (выбор блоков кода)";
            }
            {
                mode = "n";
                key = "<C-n>"; # Ctrl + n
                action = "<cmd>NvimTreeToggle<cr>";
                options.desc = "Toggle File Explorer";
            }
            {
                mode = "n";
                key = "<leader>a";
                action = "<cmd>AerialToggle right<cr>";
            }
          ];

          opts = {
            number = true;
            shiftwidth = 4;
          };
        };
      in
      {
        devShells.default = pkgs.mkShell {
          # Пакеты, доступные в shell
          buildInputs = [
            pkgs.julia-bin
            pkgs.pkg-config
            myNixvim # Наш редактор теперь часть окружения!
          ] ++ cuda-libs;

          shellHook = ''
            export CUDA_WERROR=0
            export NIX_LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath cuda-libs}:/run/opengl-driver/lib"
            export NIX_LD=$(cat ${pkgs.stdenv.cc}/nix-support/dynamic-linker)
            export LD_LIBRARY_PATH="/run/opengl-driver/lib:${pkgs.lib.makeLibraryPath cuda-libs}:$LD_LIBRARY_PATH"

            # Алиас, чтобы запуская 'nvim', ты запускал именно NixVim версию
            alias vim="nvim"
            echo "⚡ Julia + CUDA + NixVim Flake Environment Ready"
          '';
        };
      });
}
