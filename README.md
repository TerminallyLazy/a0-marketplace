# Agent Zero Plugin Marketplace

The official plugin registry for [Agent Zero](https://github.com/frdel/agent-zero).

## For Users

Browse and install plugins directly from Agent Zero's built-in Marketplace (sidebar button), or visit the [marketplace website](https://a0-marketplace.vercel.app).

## For Plugin Authors

### Submitting a Plugin

1. Create your plugin following the [Agent Zero Plugin System](https://github.com/TerminallyLazy/a0-marketplace/blob/main/PLUGIN_SYSTEM.md) conventions.
2. Ensure your plugin repo contains a valid `plugin.json` at the plugin root.
3. Submit via the [marketplace website](https://a0-marketplace.vercel.app/submit), or open a PR adding your plugin to `registry.json`.

### Plugin Entry Format

Each plugin in `registry.json` has the following fields:

| Field | Required | Description |
|-------|----------|-------------|
| `id` | Yes | Unique identifier, matches the plugin directory name |
| `name` | Yes | Display name |
| `description` | Yes | Short description |
| `author` | Yes | Author name or GitHub handle |
| `repo_url` | Yes | GitHub repository URL |
| `plugin_path` | Yes | Path to plugin within the repo (use `.` for standalone repos) |
| `version` | Yes | Semantic version |
| `featured` | No | Set by maintainers only |
| `tags` | No | Array of category tags |
| `icon` | No | Material Symbols icon name |
| `min_agent_zero_version` | No | Minimum compatible Agent Zero version |

### Requirements

- Plugin must have a valid `plugin.json` at its root.
- Repo must be publicly accessible on GitHub.
- Plugin must follow Agent Zero plugin conventions.
- No malicious code, credential harvesting, or data exfiltration.

## Registry Structure

```
a0-marketplace/
  registry.json                        # Plugin catalog
  README.md                            # This file
  .github/
    PULL_REQUEST_TEMPLATE/
      plugin-submission.md             # PR template for submissions
```
