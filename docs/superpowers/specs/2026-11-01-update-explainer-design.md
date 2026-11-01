# Update Explainer: design

Plugin id: `tmn73.update-explainer`. Kind: Omarchy bar widget.

## Intent

Before an Omarchy update, the user wants to know in plain words what it will
change for them. Existing marketplace plugins list pending packages and
commits (checked: `jampick/omarchy-update-review`,
`liambeck99/omarchy-update-center`, `RajShimpi/omarchy-updates`,
`dz9oo/omarchy-updates`). None of them explains the update. This plugin adds
the explanation, written by the user's own default agent.

## Goals

- A bar widget shows when an update is pending, with one count.
- A panel shows the count for each source: Omarchy, system packages, AUR,
  dev tools (mise).
- One button, "Explain with <agent>", opens the default agent in a terminal
  with the update data and a prompt. The agent explains the update, flags
  anything that needs action, and can answer follow-up questions.
- One button, "Update now", starts the normal Omarchy update in a terminal.
- The plugin works with any default agent that Omarchy supports. It never
  assumes Claude.

## Non-goals

- No headless or background LLM call. The plugin never reads the agent answer
  back into the widget.
- No automatic update. The plugin never runs `omarchy update` without a click.
- No LLM provider, API key or model setting inside the plugin.
- No history of past updates.

## Anti-goals

The plugin fails, even if it works, when:

- it bills the user in a way the user did not start (a background call that
  uses an API key or a subscription);
- update data or any user text appears in a process argument list;
- the explanation looks verified when the agent did not read the sources.

## Constraints

- Omarchy gives only an interactive launcher: `omarchy agent prompt "<text>"`
  opens the default agent in a terminal. There is no headless mode.
- The default agent name is in `~/.config/omarchy/defaults/agent`. The command
  `omarchy-default-agent` prints it, and prints nothing when none is set.
- `omarchy-update-available` checks only the Omarchy package (`checkupdates`
  for `omarchy` or `omarchy-dev`, plus git commits behind upstream on a dev
  checkout). It does not cover pacman, AUR or mise.
- The plugin must bundle its own collector. It cannot use the user's
  `~/.claude/skills` folder.
- Plugin structure follows `tmn73.jira` (source in `~/dev/omarchy-jira`): a
  `manifest.json` with kind `bar-widget`, a `Service.qml` that runs a bundled
  helper through `Quickshell.Io` and reads JSON from stdout, a `Panel.qml`,
  and shell and JS tests with fixtures.
- Text that leaves the session is English, with no em dashes.

## Approaches considered

| Approach | Trade-off | Verdict |
| --- | --- | --- |
| A. Interactive: bar click, panel, `omarchy agent prompt` | Works with every agent. No billing surprise. No summary inside the widget. | Chosen |
| B. Headless: run each agent in its own non-interactive mode (`claude -p`, `codex exec`) | Summary shows in a popup. Needs one command per agent. Billing depends on the user's login and environment (`claude -p` bills the API when `ANTHROPIC_API_KEY` is set). Anthropic terms for background subscription use are unchecked. | Rejected |
| C. User supplies an API key | Works for anyone. Needs key storage and a provider setting. | Rejected |

The user chose A after seeing the mockups.

## Design

Mockups: kept outside the repository (the final look is in the screenshots of the README).

Flow, started by the user at every step:

1. The widget shows a dot and a count when something is pending, and a quiet
   icon when everything is current.
2. A click opens the panel. The panel shows the verdict line (items pending,
   download size, reboot needed or not) and one row for each source.
3. "Explain with <agent>" runs the collector, writes its output to a file,
   and runs `omarchy agent prompt` with instructions and the file path.
4. The agent opens in a floating terminal and explains the update.
5. "Update now" starts the normal Omarchy update.

States: up to date, pending, checking, check failed, no default agent. With
no default agent, the explain button becomes "Choose default agent" and opens
the Omarchy picker (`omarchy agent --pick` does this from the keybinding).

Prompt rules:

- It names no agent and no agent-specific tool or skill.
- It tells the agent to read the data file, to read the pull requests behind
  Omarchy commits, to answer in the user's language, and to keep the answer
  short: a verdict line, at most 5 bullets for Omarchy, at most 5 for apps
  and tools, and a heads-up only when action is needed.
- It tells the agent never to run the update.

Safety rules:

- The data file holds all update text. The prompt holds only instructions and
  the file path.
- The file lives in the user runtime directory with mode 600. This is a call
  by the designer, not by the user.
- The widget never writes outside its own state and that file.

## Calls made by the designer

These settle points a builder review raised. Each is a call, not a user
decision. Change any of them if the builder finds a better way.

- **Argv.** The text in the argument list is fixed instructions plus the data
  file path. That is allowed. The anti-goal covers update data and user text,
  not the fixed instructions or a path under the runtime directory.
- **Unreadable file.** The prompt tells the agent: if you cannot read the data
  file, say so and stop. Smoke tests run with Claude Code. Other agents are
  untested and the README says so.
- **No GitHub call in the collector.** The collector makes no call to GitHub.
  It runs `checkupdates`, `yay -Qua` and `mise outdated`, which contact their
  own servers, as `omarchy update` does. It lists the Omarchy version range and
  the git compare range (`OLD...NEW`), and the commit list only where a local
  checkout has it. The agent looks up the commits and pull requests itself.
  This keeps the collector read-only and keeps marketplace review simple. On a
  package install, the Omarchy row shows the version change, not a commit
  count.
- **Sources line.** The prompt requires the agent to end with one line that
  names the sources it read and the ones it could not read. This is the
  guard for the third anti-goal. A test checks that the prompt contains the
  requirement.
- **Update terminal.** "Update now" opens its own terminal, separate from the
  agent. The widget checks again when that terminal closes and at the next
  refresh.
- **Data file lifetime.** Each "Explain" click overwrites the file. The widget
  deletes it when a check finds nothing pending, and when the widget closes.
- **Size and reboot.** The verdict shows "at least N MB" when some source
  gives no size, and hides the size when no source does. Reboot needed comes
  from the collector's reboot check, as in `collect.sh`.

## Left to the builder

- Port `~/.claude/skills/omarchy-next-update/collect.sh` (128 lines) into a
  bundled helper. It follows the phases of `/usr/share/omarchy/bin/omarchy-update`:
  pacman, Omarchy migrations, orphan removal, mise, AUR, reboot check. Keep it
  read-only. Output JSON for the widget and a plain-text file for the agent.
- Define the count (one total of all pending items, as in the mockup).
- Choose the refresh interval and the setting range (the Jira plugin uses
  900 s, range 60 to 3600 s).
- Find the right Omarchy launcher for "Update now" in a terminal.
- Read the plugin API for opening a panel from a bar widget.
- Write tests with fixtures for the collector and the state logic.
- Write the README, including update and removal steps, as the other tmn73
  plugins do.

## Open questions for the user

None. The builder review left no question that only the user can answer.
