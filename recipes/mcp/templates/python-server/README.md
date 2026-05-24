# aurum-weather: AurumOS Python MCP server template

A minimal, runnable [Model Context Protocol](https://modelcontextprotocol.io)
server in ~80 lines of Python, built with Anthropic's official `mcp` SDK
(the high-level `FastMCP` helper). Use it as the starting point for your own
MCP servers.

## What's inside

- `aurum_weather/server.py` - declares two tools: `get_weather(city)` and
  `list_cities()`. Replace the fixtures with real API calls to ship.
- `aurum_weather/__main__.py` - boots the stdio transport so the server
  speaks the JSON-RPC dialect Claude Code expects.
- `pyproject.toml` - installable as `pip install -e .`, exposes the
  `aurum-weather` console script.

## Try it locally

```bash
# 1. Install in editable mode (uses pyproject.toml).
pip install -e .

# 2. Run the server (it just sits on stdio waiting for a client).
python -m aurum_weather
```

## Register with Claude Code

```bash
claude mcp add aurum-weather --command python --args -m aurum_weather
```

You can now ask Claude things like "what's the weather in Tokyo?" and it
will call `get_weather` over MCP. To remove later:

```bash
claude mcp remove aurum-weather
```

## Customise

1. Rename the package: `mv aurum_weather my_server` and update
   `pyproject.toml` (name + scripts entry).
2. Edit `server.py` - every function decorated with `@server.tool()` becomes
   an MCP tool whose schema is auto-derived from the type hints + docstring.
3. For resources (read-only blobs the LM can pull) use `@server.resource()`;
   for prompts use `@server.prompt()`. See the FastMCP examples in the
   [official SDK](https://github.com/modelcontextprotocol/python-sdk).

## References

- Spec: <https://spec.modelcontextprotocol.io>
- Python SDK: <https://github.com/modelcontextprotocol/python-sdk>
- Claude Code MCP docs: <https://docs.claude.com/en/docs/claude-code/mcp>
