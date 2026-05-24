/**
 * Minimal MCP server in TypeScript, mirroring the Python `aurum_weather`
 * template. Speaks stdio JSON-RPC, registers a single `get_weather` tool.
 *
 * Build + run:
 *   npm install
 *   npm run build
 *   node dist/index.js          # speaks MCP on stdin/stdout
 *
 * Register with Claude Code (after `npm run build`):
 *   claude mcp add aurum-weather-ts --command node --args dist/index.js
 */

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";

type Report = {
  city: string;
  temperature_c: number;
  conditions: string;
  humidity_pct: number;
};

const FIXTURES: Record<string, Report> = {
  "buenos aires": {
    city: "Buenos Aires",
    temperature_c: 23,
    conditions: "partly cloudy",
    humidity_pct: 58,
  },
  paris: {
    city: "Paris",
    temperature_c: 11,
    conditions: "overcast, drizzle",
    humidity_pct: 82,
  },
  tokyo: {
    city: "Tokyo",
    temperature_c: 18,
    conditions: "clear",
    humidity_pct: 45,
  },
};

const server = new McpServer({
  name: "aurum-weather-ts",
  version: "0.1.0",
});

// Tool: get_weather - returns a structured weather report for the requested city.
server.tool(
  "get_weather",
  "Return current weather for a city.",
  { city: z.string().describe("City name (case-insensitive).") },
  async ({ city }) => {
    const report = FIXTURES[city.toLowerCase()];
    if (!report) {
      return {
        content: [
          {
            type: "text",
            text: JSON.stringify({
              error: `no data for city: ${city}`,
              known_cities: Object.keys(FIXTURES).sort(),
            }),
          },
        ],
      };
    }
    return { content: [{ type: "text", text: JSON.stringify(report) }] };
  },
);

// Tool: list_cities - exposes the fixture set so the LM can discover options.
server.tool(
  "list_cities",
  "List cities for which weather data is available.",
  {},
  async () => ({
    content: [
      { type: "text", text: JSON.stringify(Object.keys(FIXTURES).sort()) },
    ],
  }),
);

// Boot on stdio so `claude mcp add --command node` can talk to us.
await server.connect(new StdioServerTransport());
