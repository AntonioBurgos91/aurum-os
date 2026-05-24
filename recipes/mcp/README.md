# MCP - Model Context Protocol

[MCP](https://modelcontextprotocol.io) is Anthropic's open protocol for
exposing tools, resources, and prompts to LLM applications. It is becoming
the de-facto standard for "give a model access to my data / my APIs / my
sandbox" - Claude Code, Cursor, Zed and others speak it natively.

The 30-second mental model:

- An **MCP server** is a small process that owns one or more tools/resources.
  It speaks JSON-RPC over either stdio (most common) or HTTP+SSE.
- An **MCP client** (Claude Code, your own app, ...) discovers the server's
  capabilities at handshake and then routes tool calls to it.
- The server is *not* an LLM. It just declares typed tool schemas and
  executes them when the client asks.

## Official docs

- Protocol spec: <https://spec.modelcontextprotocol.io>
- Python SDK:    <https://github.com/modelcontextprotocol/python-sdk>
- TypeScript SDK:<https://github.com/modelcontextprotocol/typescript-sdk>
- Claude Code:   <https://docs.claude.com/en/docs/claude-code/mcp>

## Templates shipped here

| Path                         | Language   | Entry point                              |
| ---------------------------- | ---------- | ---------------------------------------- |
| `templates/python-server/`   | Python 3.11+ | `python -m aurum_weather`              |
| `templates/typescript-server/` | TypeScript | `node dist/index.js`                   |

Both implement the same toy `get_weather` + `list_cities` tools so you can
diff them and pick whichever stack fits your project.

## Bootstrap a new server

Use the AurumOS CLI helper to copy the Python template into a fresh
directory and rename the package:

```bash
aurum-mcp-template create ./my-server
cd my-server
pip install -e .
python -m my_server
```

(Pass `--ts` to copy the TypeScript template instead.)

## Register your server with Claude Code

```bash
# Python template
claude mcp add aurum-weather --command python --args -m aurum_weather

# TypeScript template (after `npm run build`)
claude mcp add aurum-weather-ts --command node --args dist/index.js
```

Verify the registration:

```bash
claude mcp list
```

Then ask Claude something that should hit a tool ("what's the weather in
Tokyo?") and watch it call your server over stdio.

## Why MCP and not, say, OpenAI function calling?

- It's provider-agnostic - the same server works behind Claude, GPT, Llama-
  via-Ollama, anything that has an MCP client.
- The server is a separate process, which means crash isolation, language
  freedom (Go, Rust, anything that can do JSON-RPC), and easy permissioning.
- Capabilities are *negotiated* at handshake, not hard-coded in the prompt,
  so the LM never sees a tool it isn't allowed to call.
