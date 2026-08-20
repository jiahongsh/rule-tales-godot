# Godot MCP Native vendoring record

- Upstream: https://github.com/yurineko73/Godot-MCP-Native
- Version reported by `plugin.cfg`: `1.0.8`
- Vendored commit: `eef4807190e7765e69d59c9e707d0ba170f6770d`
- Retrieved: 2026-08-18
- License: MIT; see `LICENSE` in this directory.

Local change:

- `native_mcp/mcp_http_server_legacy.gd` binds the HTTP server to
  `127.0.0.1`. Upstream calls `TCPServer.listen(port)`, whose Godot 4.7.1
  default bind address is `"*"`. The local binding deliberately prevents
  unauthenticated editor-control endpoints from being exposed to the LAN.

The add-on is development tooling. While enabled, upstream registers
`MCPRuntimeProbe` as a project autoload so runtime debugging can communicate
with the editor. Do not enable remote access or add credentials to project
files. Re-audit the binding, autoload, tool permissions, Godot compatibility,
and local patch before updating from upstream.
