# Unified Plugin System - Implementation Summary

This document describes the current plugin architecture in Agent Zero.

## Overview

Agent Zero uses a convention-over-configuration plugin model. Plugin capabilities are discovered from directory structure. The platform supports:
- Backend capabilities (API handlers, tools, helpers, Python lifecycle extensions, prompts, agent profiles)
- Frontend capabilities (WebUI extension hooks and full plugin-owned UI components)

## Architecture

### Core Principles

- Convention over configuration: plugin behavior is inferred from directory layout.
- Backend-driven routing: backend exposes plugin APIs and static assets.
- Explicit WebUI breakpoints: core UI declares insertion points using `<x-extension id="...">`.
- Standard component loading: injected plugin HTML is loaded through existing `<x-component>` / `components.js`.

### Components

1. Backend plugin discovery (`python/helpers/plugins.py`)
   - `get_plugin_roots()` resolves plugin roots in priority order (`usr/plugins` first, then `plugins`).
   - `list_plugins()` builds the effective plugin set (first root wins on ID conflicts).
   - `get_plugin_paths(*subpaths)` resolves plugin directories for convention-based scanning.
   - `get_webui_extensions(extension_point, filters)` scans `extensions/webui/<extension_point>/` and returns matching files.

2. Path resolution (`python/helpers/subagents.py`)
   - `get_paths(..., include_plugins=True)` includes plugin candidates for prompts/tools/path-based resolution.
   - Used by core loading flows such as prompts and tools.

3. Python extension runtime (`python/helpers/extension.py`)
   - `call_extensions(extension_point, agent, **kwargs)` executes extension classes.
   - Searches core `python/extensions/<point>/` and plugin `plugins/*/extensions/python/<point>/`.
   - Extension classes derive from `Extension` and implement `async execute()`.

4. API and static routes (`run_ui.py`, `python/api/load_webui_extensions.py`)
   - `GET /plugins/<plugin_id>/<path>` serves plugin static assets.
   - Plugin API handlers are mounted under `/api/plugins/<plugin_id>/<handler>`.
   - `POST /api/load_webui_extensions` returns extension files for a requested WebUI extension point and file filters.

5. Frontend WebUI extension runtime (`webui/js/extensions.js`)
   - HTML extension flow:
     - Core UI contains `<x-extension id="<extension_point>"></x-extension>`.
     - `loadHtmlExtensions()` discovers breakpoints and calls backend API with HTML filters.
     - Returned files are injected as `<x-component path="..."></x-component>`.
     - Existing `components.js` loads each component.
   - JS extension flow:
     - `callJsExtensions("<extension_point>", ...args)` loads `*.js`/`*.mjs` extension modules and executes their default exports.
     - Convention for mutable flows: pass one context object by reference so extensions can update shared state for downstream processing.
   - Both JS and HTML extension lookups are cached per extension point.

6. Alpine placement helpers (`webui/js/initFw.js`)
   - Directives support precise insertion/repositioning after an extension is loaded:
     - `x-move-to-start`
     - `x-move-to-end`
     - `x-move-to`
     - `x-move-before`
     - `x-move-after`
   - Behavior difference:
     - `x-move-to-start`, `x-move-to-end`, and `x-move-to` insert into the selected parent as a child node.
     - `x-move-before` and `x-move-after` insert next to a selected reference node (same parent as the reference).
     - This can lead to different visual spacing when parent-level styles differ from sibling-level styles.
   - Repository authoring convention: HTML UI extensions should include a root `x-data` scope and one explicit `x-move-*` directive.

## File Structure

```text
/plugins/
  +-- memory/
  |   +-- api/                                  # Plugin API handlers
  |   +-- tools/                                # Agent tools
  |   +-- helpers/                              # Shared Python helpers
  |   +-- prompts/                              # Prompt templates
  |   +-- agents/                               # Agent profiles
  |   +-- extensions/
  |   |   +-- python/                           # Python lifecycle extensions
  |   |   |   +-- embedding_model_changed/
  |   |   |   +-- message_loop_prompts_after/
  |   |   |   +-- monologue_end/
  |   |   |   +-- monologue_start/
  |   |   |   +-- system_prompt/
  |   |   +-- webui/                            # WebUI hook extensions
  |   |       +-- sidebar-quick-actions-main-start/
  |   |       |   +-- memory-entry.html
  |   |       +-- set_messages_before_loop/
  |   |           +-- testingext.js
  |   +-- webui/                                # Full plugin-owned UI components/pages
  |       +-- memory-dashboard.html
  |       +-- memory-dashboard-store.js
  |       +-- memory-detail-modal.html
  +-- README.md

/usr/plugins/                                   # User overrides (higher priority)
  +-- <plugin_id>/
```

## Capability Conventions

- `api/*.py` - API endpoint handlers (`ApiHandler` subclasses)
- `tools/*.py` - agent tools (`Tool` subclasses)
- `helpers/*.py` - shared Python helper modules
- `extensions/python/<point>/*.py` - Python lifecycle extensions
- `extensions/webui/<point>/*` - WebUI extension assets (HTML/JS hook contributions)
- `webui/**` - plugin-owned UI components/pages loaded directly by path
- `prompts/**/*.md` - prompt templates
- `agents/` - agent profiles

## WebUI Extension Points

WebUI extension points are string IDs shared between core UI and plugins.

Current extension points in core UI / runtime (branch PR 998):
- `sidebar-start`
- `sidebar-end`
- `sidebar-top-wrapper-start`
- `sidebar-top-wrapper-end`
- `sidebar-quick-actions-main-start`
- `sidebar-quick-actions-main-end`
- `sidebar-quick-actions-dropdown-start`
- `sidebar-quick-actions-dropdown-end`
- `sidebar-chats-list-start`
- `sidebar-chats-list-end`
- `sidebar-tasks-list-start`
- `sidebar-tasks-list-end`
- `sidebar-bottom-wrapper-start`
- `sidebar-bottom-wrapper-end`
- `chat-input-start`
- `chat-input-end`
- `chat-input-progress-start`
- `chat-input-progress-end`
- `chat-input-box-start`
- `chat-input-box-end`
- `chat-input-bottom-actions-start`
- `chat-input-bottom-actions-end`
- `chat-top-start`
- `chat-top-end`
- `welcome-screen-start`
- `welcome-screen-end`
- `modal-shell-start`
- `modal-shell-end`
- `set_messages_before_loop`
- `set_messages_after_loop`

## Usage

### Creating a plugin

1. Create `plugins/<plugin_id>/`.
2. Add backend capabilities by convention (`api/`, `tools/`, `helpers/`, `extensions/python/`, `prompts/`, `agents/`).
3. Add WebUI hook extensions under `extensions/webui/<extension_point>/` where `<extension_point>` matches an existing core `<x-extension id="...">`.
4. For HTML UI entries, use the baseline pattern: root `x-data` plus one explicit `x-move-*` directive.
   `x-move-to*` directives insert as children of the selected parent; `x-move-before/after` insert as siblings of a selected reference node.
5. Add full plugin pages/components under `webui/` if they are opened directly (for example from modals or buttons).

### Python extension example

```python
# plugins/my-plugin/extensions/python/monologue_end/_50_my_extension.py
from python.helpers.extension import Extension

class MyExtension(Extension):
    async def execute(self, **kwargs):
        pass
```

### HTML WebUI extension example

```html
<!-- plugins/my-plugin/extensions/webui/sidebar-quick-actions-main-start/my-button.html -->
<div x-data>
  <button
    x-move-after=".config-button#dashboard"
    class="config-button"
    id="my-plugin-button"
    @click="openModal('../plugins/my-plugin/webui/my-modal.html')"
    title="My Plugin">
    <span class="material-symbols-outlined">extension</span>
  </button>
</div>
```

### Full plugin UI page example

```html
<!-- opened directly by path -->
<x-component path="../plugins/memory/webui/memory-dashboard.html"></x-component>
```

## Known Limitations / Follow-up

- WebUI extension point naming and ownership conventions should be formally documented to avoid collisions.
- Ordering rules between multiple plugins targeting the same extension point are currently implicit (filesystem order) and should be made explicit.
- Project-specific plugin roots are still commented out in `get_plugin_roots()` and are not active yet.
