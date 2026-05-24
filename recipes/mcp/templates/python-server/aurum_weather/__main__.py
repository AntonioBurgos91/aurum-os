"""Entry-point so `python -m aurum_weather` boots the stdio MCP server."""

from .server import server


def main() -> None:
    # FastMCP.run() defaults to stdio transport - the one Claude Code uses
    # when you register a server with `claude mcp add --command python`.
    server.run()


if __name__ == "__main__":
    main()
