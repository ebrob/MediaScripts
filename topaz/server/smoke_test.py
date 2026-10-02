"""Drive topaz_mcp over stdio like a real client.

Usage: python smoke_test.py <clip-relative-to-TOPAZ_ROOT> [profile] [model] [scale]
"""
import asyncio
import json
import sys
from pathlib import Path

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

SERVER = str(Path(__file__).with_name("topaz_mcp.py"))


async def call(s, name, **kw):
    r = await s.call_tool(name, kw)
    text = r.content[0].text if r.content else ""
    return r.isError, json.loads(text) if text.startswith(("{", "[")) else text


async def main(clip, profile="draft", model="prob-4", scale=2):
    params = StdioServerParameters(command=sys.executable, args=[SERVER])
    async with stdio_client(params) as (r, w), ClientSession(r, w) as s:
        await s.initialize()
        print("status:", (await call(s, "topaz_status"))[1])
        print("traversal:", await call(s, "topaz_upscale", input="..\\Windows\\win.ini"))
        err, job = await call(s, "topaz_upscale", input=clip, profile=profile, model=model, scale=scale)
        print("start:", err, job)
        if err:
            return
        while True:
            await asyncio.sleep(3)
            _, j = await call(s, "topaz_job", job_id=job["job_id"])
            print(j["state"], j["progress"])
            if j["state"] in ("done", "failed", "cancelled"):
                print({k: v for k, v in j.items() if k != "log_tail"}, j["log_tail"][-2:])
                break


a = sys.argv[1:]
asyncio.run(main(a[0], *(a[1:3]), *([int(a[3])] if len(a) > 3 else [])))
