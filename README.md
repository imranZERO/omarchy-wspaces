# Wspaces

A lightweight Omarchy bar widget: workspace numbers with the icons of the apps open on each.

![Wspaces](preview.png)

## Install

```bash
omarchy plugin add https://github.com/imranZERO/omarchy-wspaces --enable
```

It is placed on the left of the bar. To move it:

```bash
omarchy bar move imranzero.wspaces --section center
```

No external dependencies: it uses only Omarchy, Hyprland and Quickshell, which ship with Omarchy.

## Usage

- Left-click a number: switch to that workspace
- Left-click an icon: focus that window
- Scroll: step through workspaces
- Hover an icon: tooltip with the window title

## Configure

```bash
omarchy bar set imranzero.wspaces iconSize 18 --json
omarchy bar set imranzero.wspaces showApps active
```

| key                    | default | values            |
|------------------------|---------|-------------------|
| `showApps`             | `all`   | `all`, `active`   |
| `iconSize`             | `16`    | 12–24             |
| `maxIcons`             | `8`     | 1–20              |
| `persistentWorkspaces` | `5`     | 0–10              |

## Remove

```bash
omarchy plugin remove imranzero.wspaces
```

## License

MIT
