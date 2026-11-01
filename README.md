# Omarchy Update Explainer

Pending Omarchy updates in the bar, explained by your own default agent.

## What it shows

- **The bar icon** shows only when something is waiting (or while the first
  check runs, or after an error). When you are up to date, the bar slot is
  empty. The icon never shows a number.
- **A verdict in words** in the panel: "Updates are waiting" and whether a
  reboot is needed, or "Everything is up to date".
- **A section for each source that has updates**: Omarchy, system packages,
  AUR and dev tools. Each section lists the first few items with their old and
  new versions, then "and more" when the list is longer. Sources with nothing
  to update do not show.

Click "Tell me what changes" and your default agent opens in a terminal with the update
data. It says what changes for you and what needs action. You can ask it
follow-up questions there.

The stock `omarchy.system-update` widget only shows a dot for the Omarchy
package. This plugin covers more sources, so we recommend you remove the stock
widget (see "Replace the stock update widget" below).

## Screenshots

![The update panel with a pending Omarchy update](preview.png)

The panel, opened from the bar, with an Omarchy update waiting.

![The explanation the agent writes after "Tell me what changes"](explain.png)

Real output from the author's ROG Zephyrus laptop. The labels say whether each change affects the machine.

## Requirements

Omarchy Quattro with shell plugin support. The collector uses `checkupdates`,
`pacman`, `expac` and `jq`. It also uses `yay` and `mise` when they are
installed, and skips them with a note when they are not.

The explanation uses the agent set with `omarchy default agent`. With none set,
the primary button reads "Choose an assistant" and opens the picker. The panel
never shows the name of the agent.

## Install

```bash
omarchy plugin add https://github.com/tmn73/omarchy-update-explainer.git --enable
```

### Replace the stock update widget

This is a recommendation, not a requirement.

The stock `omarchy.system-update` widget shows an icon only when the Omarchy
package has an update. This widget also covers system packages, AUR and dev
tools. It covers Omarchy too, so the stock icon is redundant. If both stay on
the bar, you can see two icons with the same glyph side by side.

To remove the stock widget:

```bash
omarchy plugin disable omarchy.system-update
```

To bring it back:

```bash
omarchy plugin enable omarchy.system-update
```

The Omarchy bar README says that `omarchy plugin enable` and
`omarchy plugin disable` turn widgets on and off, and that ids come from
`omarchy plugin list`. We did not run these two commands on a built-in widget.
If one fails, the fallback is to edit the `bar.layout` key of
`~/.config/omarchy/shell.json`: delete the `{"id": "omarchy.system-update"}`
entry from the section that holds it, or add it again to bring it back.

### Update

```bash
omarchy plugin update tmn73.update-explainer
```

### Remove

```bash
omarchy plugin remove tmn73.update-explainer
```

## Billing and safety

Nothing runs in the background that calls an agent. The agent starts only when
you click "Tell me what changes", in a terminal you can see. There is no surprise API or
subscription use. The plugin holds no API key and has no provider setting.

- **Report file.** It lives in `$XDG_RUNTIME_DIR/update-explainer/report.txt`
  with mode 600. The widget never removes it, so an agent session you keep open
  can still read it. The next "Tell me what changes" overwrites it, and logout
  clears the runtime directory.
- **Hardware facts.** The report starts with a "This machine" section: the
  laptop or board model and vendor, the CPU model, the GPU names, the kernel
  and Omarchy versions, and the session type. The agent uses it to say whether
  each change affects you. The section holds model names only: no serial
  numbers, UUIDs, MAC addresses or hostnames. The file stays local (in
  `$XDG_RUNTIME_DIR`, mode 600, cleared at logout). The agent you chose reads it
  and sends it to its model provider like any prompt.
- **What else the report holds.** In order: this machine, the pacman packages
  to update (with old and new versions and short descriptions), the Omarchy
  package and its compare line, paths of locally modified package files and the
  names and targets of the pacman hooks that may patch them back (never the
  hook commands), pending Omarchy migrations, orphan packages, dev tool updates
  (tool, current and latest version only), AUR updates (each line cut at 120
  characters) and reboot hints. The report is cut at 256 KiB.
- **No update data in a command line.** The agent gets fixed instructions and
  the path of the report file. The update data stays in the file.
- **No GitHub call by the collector itself.** It runs `checkupdates`,
  `yay -Qua` and `mise outdated`, as `omarchy update` does. `mise outdated` may
  contact the tool sources, including GitHub, and unauthenticated GitHub limits
  are small. You can turn the dev tool check off with the "Check dev tool
  updates (mise)" setting. The agent looks up commits and pull requests itself.
- **Timeouts.** Every tool the collector runs has a time limit (about a minute
  for the network tools, a few minutes for the file check of the report), and
  the widget stops a run that takes too long. A hung mirror cannot freeze the
  widget. A manual refresh is ignored within 30 seconds of the last check. The
  timer and "Check again" always run.
- **No automatic update.** The plugin never runs the update on its own. The
  prompt tells the agent never to run it. That is an instruction, not a
  control: Omarchy starts the agent in its own unattended mode, which may run
  commands without asking you.
- **The agent reads the web.** The panel says so under the buttons. To explain Omarchy changes, the agent reads
  public GitHub pull request pages. The prompt tells it to treat the file and
  every web page as data and not to follow instructions found in them. A
  malicious page could still try to steer an agent that runs without prompts,
  so read what the agent plans to do.
- **Private package database.** To avoid a clash with the stock update widget,
  the collector syncs its own copy of the pacman database under
  `$XDG_RUNTIME_DIR/update-explainer` and takes a lock there. The first sync
  needs the network and uses space under the runtime directory (memory backed)
  until you log out. Without a runtime directory, a private temporary folder is
  used and removed at the end of each run.

## Buttons

- **Tell me what changes** writes the report, then runs `omarchy-agent-prompt`
  with the instructions and the report path. It shows "Preparing the report..."
  while it works. With no default agent, the button reads "Choose an assistant"
  and runs `omarchy-menu summon setup.default.agent`.
- **Update now** opens the stock update terminal with
  `omarchy-launch-floating-terminal-with-presentation omarchy-update`. If that
  launcher returns at once, the widget refreshes on the next timer tick instead
  of when the update ends.
- **Check again** is the only button when nothing is waiting, during the first
  check, and after an error with no earlier data. It refreshes the check. After
  an error with earlier data, the panel keeps that data and both buttons.

On a package install, the Omarchy section shows the version change, not a
commit count.

## Agents

Tested with Claude Code on the author's machine (Explain ran end to end). Other agents are untested. The prompt is agent-neutral and only the interactive launch is used, but some agents have limits:

- `crush` (`crush run`) and `kimi` (`--prompt`) run one-shot, so the window may close with no follow-up.
- `dsh` and `freebuff` put the prompt on the clipboard instead of starting a session.

## Settings

| Setting | Default | Range |
| --- | --- | --- |
| Refresh interval (seconds) | 1800 | 300 to 21600 |
| Check dev tool updates (mise) | on | on or off |

## Local development

```bash
bash tests/run-all.sh
```

This runs the collector test, the QML source checks and `node --test` on
`Model.js`. The collector test uses stub commands from `tests/fixtures/stubs`
and makes no network call.

QML changes need `omarchy-restart-shell`. The shell keeps the compiled version
in memory.

## How it works

`Service.qml` schedules `omarchy-update-explainer-collect --summary` and reads
one JSON document from its stdout. On "Tell me what changes" it runs the same helper with
`--report <file>`, which writes the plain-text report for the agent. `Panel.qml`
assembles small components. `Model.js` holds the logic worth testing and the
prompt text.

A failed refresh never discards a good summary. The panel keeps the last good
data and shows the error beside it.

## License

MIT
