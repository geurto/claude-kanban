# Working rules for /home/claude/code

These rules apply to every repository in this folder, in Remote Control sessions and in board runs.
A repository's own CLAUDE.md adds to them and wins where the two disagree.

## Who you work for

Peter, a robotics developer. He prompts you from his phone, so:
- Keep messages short. Lead with the result, then what he needs to decide.
- When you need a decision, ask one clear question and wait. Don't guess on anything
  that changes an API, a data format, or a dependency.
- When you finish a task, end with: what changed, how you tested it, and the PR link.

## Environment

- This is NixOS. Every repository has a `flake.nix` with a dev shell.
- Run every build, test, lint and format command through it:
  `nix develop --command <cmd>`, for example `nix develop --command cargo test`.
- Never install tools globally, with `nix profile`, `pip --user`, `npm -g` or similar.
- If a repository has no `flake.nix`, say so and propose one before you do anything else.
- If the dev shell lacks a tool you need, add it to the flake in the same branch and say so.
- There is no Docker or Podman on this machine.

## Git workflow

- Never commit to `main` (or the default branch) and never force-push.
- Start from an up-to-date default branch: `git fetch` first, then branch as
  `claude/<short-topic>`, for example `claude/fix-mqtt-reconnect`.
- Make small commits with conventional-commit messages (`fix:`, `feat:`, `refactor:`, `docs:`, `test:`).
- Before you call a task done, run the tests and the linters that the repository uses.
- When the work is done, push the branch and open a draft PR:
  `git push -u origin claude/<topic>` then `gh pr create --draft --fill`.
  Put in the PR body: the problem, the change, how you tested it, anything left open.
- If tests fail and you can't fix them, still open the draft PR and list what fails and why.
- Board runs are the exception: their task prompt says to leave the changes uncommitted, and
  the runner commits, pushes and opens the PR. Follow the prompt there.
- `gh` can't create repositories here. For a new project, create the folder, `git init`, a
  `flake.nix`, a README, and the first commit on `main`. Then ask Peter to create the empty
  GitHub repo and give the token access to it, and add the remote once he confirms.

## Code

- Match the style already in the repository. Don't reformat files you aren't changing.
- Prefer small, readable changes over clever ones. Add tests for behaviour you change.
- Don't add dependencies without saying why in the PR.
- Never put secrets, tokens or hostnames from this machine in code or commits.
