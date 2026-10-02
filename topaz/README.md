# Topaz upscaling via MCP

Run Topaz Video on Hyperion's GPU (RTX 3060 Ti) from a Claude session on the Mac. The
MCP server runs on Hyperion over SSH (stdio); video never travels through MCP, both
machines see the same NAS folder.

```
Mac (Claude) --SSH, stdio--> topaz_mcp.py on Hyperion --> Topaz ffmpeg (GPU)
      \                                  |
       '-- NAS tracklessdeep, upscaling share --'
```

## Setup

- **Hyperion** (Windows 10, user `robli`, 192.168.4.23): run `setup-ssh.ps1` once in an
  admin PowerShell (OpenSSH, key, sleep, Topaz env vars), then
  `setup-nas-credential.ps1` once as `robli` (encrypted NAS login for SSH sessions).
- **Mac**: register the server, then restart the Claude session.

  ```bash
  claude mcp add topaz -- ssh -T robli@192.168.4.23 "C:\GitHub\MediaScripts\topaz\server\.venv\Scripts\python.exe C:\GitHub\MediaScripts\topaz\server\topaz_mcp.py"
  ```

  Or use a project `.mcp.json`; see [plan.md](plan.md#register-on-the-mac).
- Check with `topaz_status`: expect `root_exists: true` and `topaz_found: true`.

## Use

1. Put the clip in `/Volumes/tracklessdeep/upscaling/`.
2. `topaz_upscale` with `input` (file name), `model` (default `prob-4`), `scale` 1/2/4,
   `profile` `draft` (H.264 `.mp4`) or `final` (ProRes `.mov`).
3. Poll `topaz_job` with the `job_id` until done. Output lands beside the source as
   `<name>-topaz.mp4` / `.mov`; nothing is overwritten.

Tools: `topaz_status`, `topaz_list_models`, `topaz_upscale`, `topaz_job`, `topaz_cancel`.
One GPU job runs at a time.

## Caveats

- Topaz is unlicensed, so output carries a watermark. Not for deliverables yet.
- Hyperion must be powered on and awake.
- Restart the Claude session after changing `server/topaz_mcp.py`.

Full details, benchmarks and troubleshooting: [plan.md](plan.md).
