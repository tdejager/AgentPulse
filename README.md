# AgentPulse

<p align="center">
  <img src="icon-source.png" width="128" height="128" alt="AgentPulse icon">
</p>

<p align="center">
  A native macOS app that monitors Claude Code sessions, detects when they need your input, and sends you a notification.
</p>

<p align="center">
  <img src="screenshot.png" width="400" alt="AgentPulse screenshot">
</p>

## Install

Requires the Xcode Command Line Tools (`xcode-select --install`).

```bash
pixi global install --git https://github.com/tdejager/AgentPulse.git
```

Or build manually:

```bash
git clone https://github.com/tdejager/AgentPulse.git
cd AgentPulse
pixi run bundle
open build/AgentPulse.app
```

## Usage

Launch AgentPulse and start Claude Code sessions in your terminal. Sessions appear automatically.

| State | Meaning |
|-------|---------|
| **Active** (green) | Agent is working |
| **Waiting for input** (orange) | Turn complete or agent asked a question |
| **Needs approval** (red) | Agent needs permission to run a tool |
| **Idle** (gray) | No recent activity |

Notifications fire when a session needs attention. Clicking a session row switches to the correct terminal tab (Ghostty only for now, other terminals welcome as PRs).

## Development

```bash
pixi run build       # swift debug build
pixi run test        # run state analysis tests
pixi run bundle      # build .app bundle
pixi run run         # bundle + launch
pixi run run-mock    # bundle + launch with fake sessions
pixi run clean       # remove build artifacts
```

Adding support for a new agent (e.g. Codex) is a single file implementing the `AgentBackend` protocol.

## Requirements

- macOS 14+ (Sonoma)
- Xcode Command Line Tools
- Ghostty (for tab switching)

## License

MIT
