# Herdr for Omarchy

An Omarchy bar widget for monitoring [Herdr](https://herdr.dev) agents. It shows active or blocked agent counts in the bar and opens a detailed, keyboard-accessible panel with the status of every agent.

![Herdr agent activity panel in the Omarchy bar](preview.png)

## Requirements

- Omarchy with the Quattro shell plugin system
- [Herdr](https://herdr.dev) available on `PATH`, with its server running
- `jq`
- GNU coreutils (`timeout`)
- An Omarchy-compatible Nerd Font for the status icons

The plugin polls `herdr agent list` locally every three seconds. It makes no network requests and does not modify Herdr or Omarchy configuration directly.

## Install

Review the source before installing. Omarchy plugins run as unsandboxed code inside the long-running shell process.

```bash
omarchy plugin add https://github.com/fabean/omarchy-herdr.git --enable
```

The widget is placed in the right bar section by default. If it was installed without `--enable`, enable it later:

```bash
omarchy plugin enable io.github.fabean.herdr --section right
```

## Use

- Left-click the widget to open or close the agent panel.
- Right-click the widget to refresh immediately.
- Hover the widget for a per-state count.
- In the panel, press `R` or `Enter` to refresh and `Escape` to close.
- When Herdr is unavailable, the widget displays an offline indicator.

## Settings

Per-widget settings, set from the bar's plugin settings, with `omarchy bar set`, or in the widget's `shell.json` layout entry.

| Key | Default | Effect |
| --- | --- | --- |
| `showGlyph` | `true` | Show the herd glyph. |
| `showCount` | `true` | Show the agent count. |
| `showDots` | `false` | Show one dot per agent. |
| `dotOrder` | `Pane` | `Pane` keeps each dot in the same place for the life of its pane, so only its colour changes. `Status` puts blocked agents first, which reorders the row on every state change. |
| `maxDots` | `8` | Agents past this many get no dot of their own; the tooltip counts them. |
| `pulseBlocked` | `true` | Fade the dot of any agent waiting for your input. |

With all three blocks off the widget would have nothing left to click, so the glyph comes back.

```bash
omarchy bar set io.github.fabean.herdr showDots true --json
omarchy bar set io.github.fabean.herdr showGlyph false --json
omarchy bar set io.github.fabean.herdr showCount false --json
```

## Update

```bash
omarchy plugin update io.github.fabean.herdr
```

## Remove

```bash
omarchy plugin remove io.github.fabean.herdr
```

Removal deletes only the plugin checkout and removes the widget from the Omarchy bar configuration. It does not remove Herdr or its data.

## Develop

Validate the plugin against the installed Omarchy manifest schema:

```bash
omarchy plugin validate .
```

For local testing, install from a local Git remote or copy the repository into `~/.config/omarchy/plugins/io.github.fabean.herdr` and rescan plugins.

## License

[MIT](LICENSE)
