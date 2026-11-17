# claude-kanban

Phase 2 of the remote Claude Code setup: a Kanban board in the Obsidian vault that Claude works
through unattended, either right away or overnight, plus a morning report. The repo also holds the
`claude` user's Claude Code config for Remote Control (phase 1): `CLAUDE.md`, `settings.json`,
hooks and the usage cap.

The NixOS side (user, Remote Control services, suspend/wake) lives in the `dev` repo. The few
additions it needs for this repo are listed under [dev repo additions](#dev-repo-additions).

## How it works

```mermaid
flowchart LR
  phone["Obsidian on phone<br/>(cards in claude/tasks)"] <-->|LiveSync| couch[(CouchDB on serv)]
  couch <-->|livesync-bridge,<br/>claude/ only| folder["/srv/.../data/claude<br/>on serv"]
  folder -->|path unit: run-now card| trigger["board-now-trigger<br/>WoL + ssh"]
  trigger -->|claude-kanban@now| runner
  timer["02:00 wake timer<br/>on the PC"] -->|claude-kanban@night| runner
  runner["board-run on the PC<br/>(claude user)"] <-->|rsync over ssh| folder
  runner --> claude["claude -p<br/>sandboxed per task type"]
  runner -->|push branch, draft PR| github[(GitHub)]
  folder -->|path unit: new report| ha["Home Assistant<br/>push notification"]
```

1. You add a card in Obsidian and drag it to **queued**.
2. A card with `run: now` makes serv wake the PC and start a run within about a minute.
   Everything else waits for the 02:00 run.
3. The runner pulls the `claude/` folder from serv, runs each queued card through headless
   `claude -p`, and pushes the results back after every card. LiveSync delivers them to your phone.
4. At the end of the night run it writes `claude/reports/YYYY-MM-DD.md`, and serv sends a
   Home Assistant notification. The PC goes back to sleep through the phase 1 idle timer.

## The board

Columns are the values of `status`:

| Status | Set by | Meaning |
| --- | --- | --- |
| `inbox` | you | Idea, not ready to run |
| `queued` | you | Ready; runs now or tonight depending on `run` |
| `running` | runner | Being worked on |
| `review` | runner | Finished: read the result note or review the PR |
| `blocked` | runner | Needs your answer, see `question` |
| `done` | you | Accepted |

Card properties:

| Property | Values | Notes |
| --- | --- | --- |
| `type` | `research`, `design`, `code` | Decides the tools and sandbox, see below |
| `run` | `night`, `now` | `now` wakes the PC as soon as the card is queued |
| `repo` | folder name in `~/code` | Code cards only, e.g. `grocery` |
| `created` | `YYYY-MM-DD HH:mm` | From the template; queued cards run oldest first |
| `ran`, `summary` | written by runner | Last run time and a 2–3 sentence summary |
| `result` | written by runner | Link to the result note (`[[<card>-result]]`) |
| `pr` | written by runner | Draft PR URL (code cards) |
| `question` | written by runner | Why the card is blocked |

The card body has three sections from the template: **Brief** (the task), **Done when** (what a good
result looks like) and **Answer**. To unblock a card, write your answer under **Answer** and move it
back to `queued`. A follow-up on a code card works the same way: the next run continues on the same
branch, and the push updates the existing PR.

## Task types and isolation

The rule that makes unattended runs acceptable: **a run that reads the web has no shell and no
credentials; a run with a shell has no web tools and no credentials.** No run ever holds the
GitHub token or SSH keys. The runner itself, outside Claude, does the commit, push and PR.

| Type | Claude may | Hidden from the run | Output |
| --- | --- | --- | --- |
| `research`, `design` | Read files, web search and fetch, write `output/` in the board folder | `~/code`, worktrees, `~/.ssh`, `~/.config/gh` | `output/<card>-result.md`, card to `review` |
| `code` | Read and edit the worktree, `nix develop --command …`, read-only git | The vault, `~/.ssh`, `~/.config/gh` | Changes left uncommitted; runner commits, pushes `claude/board-<card>`, opens a draft PR |
| report | No tools at all; gets a JSON of facts | `~/code`, the vault, keys | Report body |

Three layers enforce this:

1. **Run settings.** `run-settings/<type>.json` with `--permission-mode dontAsk`, so anything not on
   the allow list is refused. `--setting-sources project` keeps the Remote Control permissions and
   hooks in `~/.claude/settings.json` out of board runs.
2. **Sandbox.** Each `claude -p` runs as a transient `systemd-run --user` unit with
   `InaccessiblePaths=` for the hidden paths, `NoNewPrivileges` and a runtime limit. This is the
   real boundary: a deny rule like `Bash(curl:*)` is easy to get around through
   `nix develop --command`, a hidden directory is not.
3. **Prompts.** `prompts/*.md` tell Claude that page and repo content is data, not instructions,
   and to stop with `blocked` instead of guessing.

Code runs still have network access, because `nix develop` and language package managers need it.
The protection there is that there is nothing worth stealing in reach, and every change lands as a
draft PR that you review.

## Morning report

`board-report` runs at the end of every night run and covers everything since the previous report:

- board cards that ran, from `state/events.jsonl`;
- PRs on `claude/*` branches created or merged in any repo in `~/code`, including Remote Control
  work during the day;
- commits by the `claude` user's git identity;
- a usage-cap stop, if one happened.

The runner collects these facts with `gh` and `git`, then a tool-less `claude -p` turns them into a
short report: what needs you, what got done, other changes. If that step fails, a plain list is
written instead. When nothing happened, no report is written.

## Usage cap

`CAP_WEEKLY` (default 60) is a percentage of the account's weekly limit. It is enforced in two places:

- `claude-home/hooks/usage-gate.sh` is a `UserPromptSubmit` hook. At or above the cap it exits with
  code 2, which refuses the prompt and shows the reason, including on the phone.
- `board-run` checks before every card and stops the run at the cap. The remaining cards stay
  `queued`, and the report says the run stopped.

The weekly percentage is account-wide, so your own Claude use elsewhere counts towards it. In
practice the cap means "the PC stops once the week's total reaches 60%".

`bin/usage-pct` finds the number from, in order:

1. the hook's own input, if it contains `rate_limits`;
2. `~/.cache/claude-kanban/usage.json`, written by `claude-home/statusline.sh` from the documented
   status-line field `rate_limits.seven_day.used_percentage`, when less than 6 hours old;
3. `cachedUsageUtilization` in `~/.claude.json`, which is undocumented and may change.

If none of these has data, `USAGE_UNKNOWN=allow` lets work continue. Check what it sees with
`bin/usage-pct --debug`.

## Repository layout

```
claude-kanban/
├── bin/
│   ├── board-run            runner: board-run now|night
│   ├── board-report         morning report
│   ├── usage-pct            weekly usage in percent
│   └── lib.sh               shared helpers: frontmatter, sync, sandbox, events
├── claude-home/             → ~/.claude/ for the claude user (Remote Control)
│   ├── settings.json        model, permissions, hooks, status line
│   ├── statusline.sh        shows usage, caches rate_limits
│   └── hooks/
│       ├── usage-gate.sh    refuses prompts above the cap
│       └── activity.sh      restarts the idle-suspend clock
├── code-root/CLAUDE.md      → ~/code/CLAUDE.md, rules for every repo
├── run-settings/            permissions per board run type
├── prompts/                 prompts per board run type
├── systemd/claude-kanban@.service   user unit, instances now and night
├── config.example.env       → ~/.config/claude-kanban/config.env
├── install.sh               links everything into place (PC, as claude)
├── serv/
│   ├── bin/                 board-now-trigger, board-report-notify
│   ├── systemd/             path and service units
│   ├── livesync-bridge/     bridge config and compose snippet
│   ├── ha/automation.yaml   report notification
│   └── serv.example.env     → /etc/claude-kanban/serv.env
└── vault/claude/            copy into the vault as claude/
    ├── Board.base
    ├── templates/task.md
    └── tasks/example-mqtt-brokers.md
```

`CLAUDE.md` sits in `~/code` rather than `~/.claude` on purpose. Remote Control sessions and code
runs work below `~/code` and load it. Research runs work in the board folder and don't, so the
coding rules don't leak into them.

## Setup

### dev repo additions

The NixOS config in the `dev` repo needs three additions:

```nix
users.users.claude = {
  packages = with pkgs; [ jq yq-go rsync gh git ];
  openssh.authorizedKeys.keys = [
    # serv's trigger key may only start a run-now pass
    ''restrict,command="systemctl --user start --no-block claude-kanban@now.service" ssh-ed25519 AAAA... serv-board-trigger''
  ];
};

# Wake from S3 at 02:00 and start the night run
systemd.services.claude-kanban-night = {
  serviceConfig.Type = "oneshot";
  script = "${pkgs.systemd}/bin/systemctl --user -M claude@ start --no-block claude-kanban@night.service";
};
systemd.timers.claude-kanban-night = {
  wantedBy = [ "timers.target" ];
  timerConfig = { OnCalendar = "*-*-* 02:00"; WakeSystem = true; Persistent = false; };
};
```

`WakeSystem` needs a system timer, not a user timer, hence the `systemctl --user -M claude@` hop.
If the board doesn't wake reliably from S3 on an RTC alarm, schedule a Wake-on-LAN in Home Assistant
at 01:58 instead.

### PC, as `claude`

1. `git clone <this repo> ~/claude-kanban && ~/claude-kanban/install.sh`. This links `settings.json`,
   `~/code/CLAUDE.md` and the user unit, creates `~/.config/claude-kanban/config.env` and the board
   folders. An existing `~/.claude/settings.json` is backed up first. Merge anything you added in
   phase 1.
2. `ssh-keygen -t ed25519 -f ~/.ssh/board-sync -N ''`, then put the public key on serv (below).
3. Run `ssh -i ~/.ssh/board-sync boardsync@serv` once to accept the host key.
4. Make sure the commit identity and signing from phase 1 are in `~/.gitconfig`. Runner commits use them.
5. Restart the Remote Control service so it picks up the new settings, run one prompt from the
   phone, then check `~/claude-kanban/bin/usage-pct --debug`.

`~/.claude/settings.json` is a symlink into this repo. If a `/config` change in Claude Code replaces
it with a regular file, re-run `install.sh`; it backs up the file and restores the link.

### serv

1. `sudo apt install rsync jq curl wakeonlan`, and create a `boardsync` user.
2. Add `serv/livesync-bridge/compose.yaml` to the LiveSync compose project, running as `boardsync`'s
   uid and gid. Put `serv/livesync-bridge/config.json` in `./livesync-bridge/dat/`, filled in with the
   CouchDB database, credentials and E2EE passphrase. Compare the key names with the upstream
   `dat/config.sample.json` before starting it.
3. Start the bridge. `/srv/livesync-bridge/data/claude` should fill with the vault's `claude/` folder.
4. In `~boardsync/.ssh/authorized_keys`, restrict the PC's key to that folder:

   ```
   restrict,command="rrsync /srv/livesync-bridge/data/claude" ssh-ed25519 AAAA... pc-board-sync
   ```

5. As `boardsync`: `ssh-keygen -t ed25519 -f ~/.ssh/board-trigger -N ''`. Its public key goes into
   the dev repo snippet above.
6. `git clone <this repo> /opt/claude-kanban`, copy `serv/serv.example.env` to
   `/etc/claude-kanban/serv.env` and fill in the PC's MAC and hostname.
7. Copy `serv/systemd/*` to `/etc/systemd/system/`, then
   `systemctl enable --now claude-kanban-now.path claude-kanban-report.path`.

### Home Assistant

Import `serv/ha/automation.yaml`. Set your phone's `notify.mobile_app_…` service and your vault's
name in the `obsidian://` link.

### Vault

1. Copy `vault/claude/` into the vault root as `claude/`.
2. Enable the core plugins Bases and Templates. Set the template folder to `claude/templates`.
3. Open `claude/Board.base` and switch the view's layout to **Kanban**, grouped by `status`.
   The native Kanban layout needs Obsidian 1.14 or newer.
4. New card: create a note in `claude/tasks/` with a short slug as its name (it becomes the branch
   name), insert the template, fill in the brief, drag it to `queued`.

## First run

Test in this order, one step at a time:

- [ ] `systemd-run --user --wait --pipe -p InaccessiblePaths=$HOME/.ssh ls ~/.ssh` fails with
      permission denied. If it doesn't, the sandbox isn't working; don't continue.
- [ ] `claude --help` lists `--setting-sources` and `dontAsk` for `--permission-mode` on your version.
- [ ] `~/claude-kanban/bin/board-run now` with the example card set to `queued` and `run: now`:
      the card goes to `review` and the result note appears on the phone.
- [ ] A research card whose brief asks it to run a shell command: it refuses and says so in the note.
- [ ] A small code card on a scratch repo: a draft PR appears, signed, on `claude/board-<card>`.
- [ ] Queue a `run: now` card on the phone while the PC sleeps: it wakes and runs within about
      2 minutes (`journalctl -u claude-kanban-now` on serv).
- [ ] `systemctl --user start claude-kanban@night` writes a report, and HA notifies the phone.
- [ ] Set `CAP_WEEKLY=1`: a Remote Control prompt is refused with the cap message, and the runner
      stops before the first card. Reset it afterwards.

## Known limits

- **Usage data in server mode is unverified.** Whether the status line renders in
  `claude remote-control` sessions, and so whether the cache gets written, is not documented. The
  `~/.claude.json` fallback is undocumented. Check `usage-pct --debug` after a day of use.
- **Newest file wins in sync.** Both rsync directions use `--update`. If you edit a card while it is
  running, the runner's write at the end can overwrite your edit or lose to it. Edit cards that are
  not `running`.
- **One report per day.** A second night run on the same day overwrites that day's report.
- **Failures block the card, not the run.** If a push or `gh pr create` fails, the card goes to
  `blocked` with the run folder in `question`, and the runner moves on to the next card.
- **Unattended web reading is still the riskiest part.** The sandbox limits what a manipulated run
  can reach. It does not make the research output trustworthy, so read the sources before acting on
  a result.

## Sources

- [Claude Code Remote Control](https://code.claude.com/docs/en/remote-control): server mode, limits, push notifications
- [Claude Code status line](https://code.claude.com/docs/en/statusline): `rate_limits` fields, `refreshInterval`
- [Claude Code hooks](https://code.claude.com/docs/en/hooks): `UserPromptSubmit`, exit code 2
- [Claude Code CLI reference](https://code.claude.com/docs/en/cli-reference): `-p`, `--settings`, `--setting-sources`, `--permission-mode`
- [livesync-bridge](https://github.com/vrtmrz/livesync-bridge): replicating a vault folder to disk
- [Base Board plugin page](https://community.obsidian.md/plugins/base-board): notes the native Bases Kanban layout in Obsidian 1.14
