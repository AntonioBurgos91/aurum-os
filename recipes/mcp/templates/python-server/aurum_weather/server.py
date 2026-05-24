"""Tiny MCP server with one tool, written against the Anthropic Python SDK.

Run as a stdio MCP server (the transport Claude Code uses):

    python -m aurum_weather

Register with Claude Code:

    claude mcp add aurum-weather --command python --args -m aurum_weather

Then in any Claude Code session you can ask "what's the weather in Paris?"
and Claude will call this server's get_weather tool over stdio.
"""

from __future__ import annotations

from typing import Any

from mcp.server.fastmcp import FastMCP
from pydantic import BaseModel, Field

# FastMCP is the high-level helper that turns decorated Python functions into
# MCP-conformant tools/resources/prompts. The plain `mcp.server.Server` class
# is also available if you need finer-grained control over the JSON-RPC layer.
server = FastMCP("aurum-weather")


class WeatherReport(BaseModel):
    """Structured weather payload returned to the LM client."""

    city: str
    temperature_c: float = Field(..., ge=-90, le=70)
    conditions: str
    humidity_pct: int = Field(..., ge=0, le=100)


# Stub fixtures so the template runs offline. A real implementation would call
# an HTTP API here (open-meteo, NOAA, ...) and shape the response into
# `WeatherReport`.
_FIXTURES: dict[str, WeatherReport] = {
    "buenos aires": WeatherReport(
        city="Buenos Aires", temperature_c=23.0,
        conditions="partly cloudy", humidity_pct=58,
    ),
    "paris": WeatherReport(
        city="Paris", temperature_c=11.0,
        conditions="overcast, drizzle", humidity_pct=82,
    ),
    "tokyo": WeatherReport(
        city="Tokyo", temperature_c=18.0,
        conditions="clear", humidity_pct=45,
    ),
}


@server.tool()
def get_weather(city: str) -> dict[str, Any]:
    """Return the current weather for ``city``.

    Args:
        city: City name (case-insensitive). Try "Paris", "Tokyo",
              "Buenos Aires" against the bundled fixtures.
    """
    report = _FIXTURES.get(city.lower())
    if report is None:
        return {
            "error": f"no data for city: {city!r}",
            "known_cities": sorted(_FIXTURES),
        }
    return report.model_dump()


@server.tool()
def list_cities() -> list[str]:
    """List the cities the get_weather tool currently has data for."""
    return sorted(_FIXTURES)
