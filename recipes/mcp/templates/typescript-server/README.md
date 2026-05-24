# aurum-weather-ts: AurumOS TypeScript MCP server template

Minimal TypeScript counterpart to the Python `aurum-weather` template. Use it
when your tools need to live in the Node ecosystem (existing npm libraries,
type-checked SDKs, etc.).

## Setup

```bash
npm install
npm run build
node dist/index.js          # speaks MCP on stdio
```

For iterative dev without a build step:

```bash
npm run dev                 # runs src/index.ts under tsx
```

## Register with Claude Code

```bash
claude mcp add aurum-weather-ts --command node --args dist/index.js
```

## References

- Spec: <https://spec.modelcontextprotocol.io>
- TypeScript SDK: <https://github.com/modelcontextprotocol/typescript-sdk>
- Claude Code MCP docs: <https://docs.claude.com/en/docs/claude-code/mcp>
