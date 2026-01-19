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

        python-env = pkgs.python3.withPackages (ps: with ps; [
          # для openff-toolkit
          pip
          virtualenv
          setuptools
          wheel
          rdkit        # Сама библиотека
          numpy        # Обычно нужна в паре с RDKit
          # debugpy    # Можно добавить для отладки
        ]);

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

            trouble.enable = true;

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
            # Навигация по сплитам через Ctrl + стрелочки (или h,j,k,l)
            { mode = "n"; key = "<C-h>"; action = "<C-w>h"; } # Влево
            { mode = "n"; key = "<C-j>"; action = "<C-w>j"; } # Вниз
            { mode = "n"; key = "<C-k>"; action = "<C-w>k"; } # Вверх
            { mode = "n"; key = "<C-l>"; action = "<C-w>l"; } # Вправо
            
            # навигация по вкладкам
            { mode = "n"; key = "<Tab>"; action = "<cmd>BufferLineCycleNext<cr>"; }
            { mode = "n"; key = "<S-Tab>"; action = "<cmd>BufferLineCyclePrev<cr>"; }
            { mode = "n"; key = "<leader>x"; action = "<cmd>bdelete<cr>"; } # Закрыть буфер

            {  
            mode = "n";
              key = "<leader>x";
              action = "<cmd>Trouble diagnostics toggle<cr>";
              options.desc = "Открыть список всех проблем LSP";
            }

            {
              mode = "n";
              key = "<leader>ca";
              # Используем __raw для передачи Lua-функции напрямую
              action.__raw = "function() vim.lsp.buf.code_action() end";
              options.desc = "Code Actions (лампочка)";
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
            # для makie
            pkgs.libGL
            pkgs.libGLU
            pkgs.freeglut
            pkgs.libxkbcommon
            pkgs.wayland
            pkgs.xorg.libX11
            pkgs.xorg.libXcursor
            pkgs.xorg.libXrandr
            pkgs.xorg.libXinerama
            pkgs.xorg.libXi 
            
            pkgs.julia-bin
            pkgs.pkg-config
            python-env 
            myNixvim            

            myNixvim # Наш редактор теперь часть окружения!
          ] ++ cuda-libs;

          shellHook = ''
            export JULIA_PYTHONCALL_EXE="${python-env}/bin/python3"
            export JULIA_PYTHONCALL_SKIP_LIB_CHECK=yes
            export JULIA_CONDAPKG_OFFLINE=yes
            export JULIA_CONDAPKG_BACKEND=Null              
            
            # Позволяет GLFW использовать системные либы
            export JULIA_GLFW_LIBRARY="" 
            
            # NVIDIA + OpenGL пути
            export CUDA_WERROR=0
            
            # Формируем чистый путь к либам
            SHARED_LIBS="${pkgs.lib.makeLibraryPath (with pkgs; [
              libGL
              libGLU
              libxkbcommon
              wayland
              xorg.libX11
              stdenv.cc.cc.lib
            ])}:/run/opengl-driver/lib"
            
            export GDK_SCALE=2
                      
            export NIX_LD_LIBRARY_PATH="$SHARED_LIBS"
            export NIX_LD=$(cat ${pkgs.stdenv.cc}/nix-support/dynamic-linker)
            export LD_LIBRARY_PATH="$SHARED_LIBS:$LD_LIBRARY_PATH"

            # Магия для NVIDIA + Wayland + GLX
            export __GLX_VENDOR_LIBRARY_NAME=nvidia
            
            alias vim="nvim"
            echo "⚡ Julia + CUDA + NixVim Flake Environment Ready (Wayland/NVIDIA fix applied)"
          '';
        };
      });
}
