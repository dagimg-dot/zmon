# Themes

zmon ships two themes of its own, Graphite Dark and Graphite Light, and 32 themes ported from [vicinae](https://github.com/vicinaehq/vicinae) (GPL-3.0). The ported files live in `core/theme/themes/`, each marked with where it came from, and keep vicinae's file format, so any vicinae theme also works in zmon.

The palettes belong to their original authors:

| Themes | Palette |
|---|---|
| Ayu Dark, Ayu Mirage | [Ayu](https://github.com/ayu-theme/ayu-colors) |
| Catppuccin Frappé, Latte, Macchiato, Mocha | [Catppuccin](https://github.com/catppuccin/catppuccin) |
| Dracula | [Dracula](https://draculatheme.com) |
| elementary OS Dark, Light | [elementary OS](https://elementary.io) styling |
| Evergarden Fall, Spring, Summer, Winter | [Evergarden](https://github.com/everviolet/evergarden) |
| Gruvbox Dark, Light | [Gruvbox](https://github.com/morhetz/gruvbox) |
| Kanagawa | [Kanagawa](https://github.com/rebelot/kanagawa.nvim) |
| Adwaita Dark, Light | GNOME [libadwaita](https://gitlab.gnome.org/GNOME/libadwaita) palette |
| Nord, Nord Light | [Nord](https://www.nordtheme.com) |
| One Dark | Atom's [One Dark](https://github.com/atom/atom) |
| Rosé Pine, Moon, Dawn | [Rosé Pine](https://rosepinetheme.com) |
| Solarized Dark, Light, Osaka | [Solarized](https://ethanschoonover.com/solarized/), [Solarized Osaka](https://github.com/craftzdog/solarized-osaka.nvim) |
| Tokyo Night, Storm | [Tokyo Night](https://github.com/enkia/tokyo-night-vscode-theme) |
| Vesper | [Vesper](https://github.com/raunofreiberg/vesper) by Rauno Freiberg |
| Zenwritten Dark, Light | [zenbones](https://github.com/zenbones-theme/zenbones.nvim) |

## Adding a theme

Put a `.toml` file in `$XDG_DATA_HOME/zmon/themes/` (usually `~/.local/share/zmon/themes/`). Its file name, without `.toml`, is its id. A file with the same id as a built-in theme replaces it. The format is vicinae's: see `core/theme/themes/vesper.toml` for a theme that sets many colours, and `core/theme/themes/nord.toml` for one that sets only the core ones and lets the rest be derived.
