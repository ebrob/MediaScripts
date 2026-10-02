# Topaz Video on Hyperion, driven from the Mac via MCP

**Status (2026-10-02):** working end to end. Tailscale + SSH access, the MCP server
(registered on the Mac over stdio/SSH) and NAS access from SSH sessions are all
verified. Remaining: the Topaz licence (output carries a watermark until then).

**Goal:** from a Claude session on the Mac ("AirSpaceBoundary"), call `topaz_upscale`,
which runs Topaz on Hyperion's GPU and writes the result to the NAS, without touching
Hyperion's GUI.

```
Mac (Claude) --SSH over Tailscale, stdio--> topaz_mcp.py on Hyperion --> Topaz ffmpeg (GPU)
      \                                              |
       '---- NAS tracklessdeep (\\192.168.5.5), upscaling share ----'
```

No video travels through MCP; both machines see the same NAS folder.

## The machines

**Hyperion** (the GPU box)
- Windows 10 Home, user `robli`. Ryzen 7 3700X, 64 GB RAM, **RTX 3060 Ti (8 GB)**,
  driver 581.29. (An early draft said 2070 SUPER; that was wrong.)
- LAN 192.168.0.186 (wired, gateway 192.168.0.1). Tailscale 100.109.112.32 (`hyperion`).
- Power plan High performance; sleep set to never on AC by `setup-ssh.ps1`.
- Has NordVPN adapters (disconnected); unrelated.

**AirSpaceBoundary** (the Mac)
- macOS, Tailscale 100.82.115.5. LAN 192.168.4.161/22 behind a Tenda AXE5700 VR router.
- NAS is visible on the Mac at `/Volumes/tracklessdeep/upscaling/`.

**NAS** `tracklessdeep` (host name Cumulonimbus), `\\192.168.5.5\tracklessdeep`, work
folder `upscaling`. The name `Cumulonimbus` does **not** resolve from Hyperion; use the IP.

## Network and remote access

The Mac is on a different subnet behind the Tenda VR router (own DHCP/NAT), so plain SSH
to 192.168.0.186 timed out. Leave the Tenda alone (it is a dedicated VR router).
**Tailscale** (GitHub sign-in, same account on both machines) bypasses it.

- Hyperion: OpenSSH Server running (Windows 10 Home can host SSH but not Remote Desktop),
  key auth, default shell pwsh, firewall rule `OpenSSH (LAN only)` plus the stock rule
  for port 22. All set by `topaz/setup-ssh.ps1`, run once in an admin PowerShell with
  the Mac's public key.
- Mac: `ssh robli@100.109.112.32` (or `robli@hyperion`). The user name is `robli`.
- Hyperion must be powered on and awake. It does not need to stay logged in at the desktop
  now (see the NAS section).

## Topaz on Hyperion

- Topaz Video **1.1.0** (built 2025-12-15; the renamed "Video AI") in
  `C:\Program Files\Topaz Labs LLC\Topaz Video\`. Models (~1.9 GB, 81 ids) in
  `C:\ProgramData\Topaz Labs LLC\Topaz Video\models`.
- Machine-wide env vars `TVAI_MODEL_DIR` and `TVAI_MODEL_DATA_DIR` point at the models
  folder (set by `setup-ssh.ps1`; the server also sets them for the ffmpeg child).
- **Licence:** the install is unlicensed/expired and the GUI prompts to upgrade/renew.
  Exports carry a large "Topaz Labs" watermark. Fine for testing, not for deliverables.
  Buy or renew before real use, check what a renewal covers, and check that the current
  release still supports Windows 10 before upgrading.
- Bundled ffmpeg 8.0 has `tvai_up`, `tvai_fi`, `tvai_pe`, `tvai_cpe`, `tvai_stb`.
  **No libx264.** `h264_nvenc` rejects 10-bit input, so drafts add `format=yuv420p`;
  finals use `prores_ks` (also needs no libx264). There is no separate legacy CLI: the
  `ffmpeg.exe` in the install folder is the CLI and shares the GUI's licence.
- Hand-run example (what the server builds):
  `ffmpeg -i in.mp4 -vf "tvai_up=model=prob-4:scale=2,format=yuv420p" -c:v h264_nvenc -b:v 8M out.mp4`
- Python 3.12 (user install via winget), venv at `topaz/server/.venv`, `mcp<2` pinned
  (mcp 2.x renamed `FastMCP`).

## Benchmarks (RTX 3060 Ti)

| Clip | Model | Output | Time |
|---|---|---|---|
| 2 s, 24 fps, 854x480 synthetic -> 1708x960 | `prob-4` 2x | H.264 or ProRes | about 10.5 s (about 4.6 fps) |
| 7 s shot test clip (shot-28b take 09) | `gcg-5` 2x | ProRes `.mov` (278 MB) | 54 s (about 3 fps) |

8 GB VRAM: heavy models (Iris, Nyx, Gaia) at high resolutions may be slow or need a
smaller scale. Rerun on a real full-length take before promising throughput.

## The MCP server: `topaz/server/topaz_mcp.py`

stdio transport run over SSH: no network listener, no token.

| Tool | Does |
|---|---|
| `topaz_status` | GPU, Topaz found, root, `root_exists`, root file list, `nas_mount_error`, model count, queue |
| `topaz_list_models` | local model ids (e.g. `prob-4`, `gcg-5`, `ahq-12`) |
| `topaz_upscale` | `input`, `model` (default `prob-4`), `scale` 1/2/4, `profile` draft/final, optional `output` -> `job_id` |
| `topaz_job` | state, progress, elapsed, log tail (one job or all) |
| `topaz_cancel` | kill a queued or running job |

- Paths are relative to the root (just the file name for a file directly in `upscaling`)
  and cannot escape it.
- One GPU job at a time, run async: start, then poll `topaz_job`.
- Never overwrites. Output is `<name>-topaz.mp4` (`draft`, H.264) or `<name>-topaz.mov`
  (`final`, ProRes 422 HQ, 10-bit 4:2:2), per the repo's draft/final rule.
- Arguments are built as a list from validated fields; nothing goes through a shell.
- `topaz/server/smoke_test.py <clip> [profile] [model] [scale]` drives the server over
  stdio like a real client (also checks the path-escape guard).
- Errors name the path looked for and whether the root exists.
- Each Claude session on the Mac starts its own server process over SSH, so changes to
  `topaz_mcp.py` need a fresh session on the Mac to take effect.

## NAS access from SSH sessions

Drive letters (`H:`) and saved Windows credentials belong to the desktop logon session
and are invisible to SSH logons. The server picks its root from, in order: `TOPAZ_ROOT`,
`TOPAZ_PATH`, `H:\upscaling`, `\\192.168.5.5\tracklessdeep\upscaling`. If none exists
(the usual case over SSH), it runs `server/mount-nas.ps1`, which connects that session
with `New-SmbMapping` using a DPAPI-encrypted credential at
`%LOCALAPPDATA%\topaz-mcp\nas.cred.xml`.

- Create the credential file once, as robli on Hyperion in a normal PowerShell window:
  `topaz\setup-nas-credential.ps1`. Only that Windows user on that machine can decrypt it.
  The password is never in the repo and was never seen by Claude.
- `TOPAZ_PATH` is a machine-wide env var currently set to a `\\Cumulonimbus\...` path that
  does not resolve from Hyperion. The server skips candidates that do not exist, so it is
  harmless, but setting it to `\\192.168.5.5\tracklessdeep\upscaling` is tidier (needs admin).
- Fallback if SSH-session NAS access ever stops working: run the server over HTTP in the
  logged-in desktop session (loopback only) and reach it from the Mac through an SSH
  tunnel. It was built and tested once, then removed in favour of the credential approach.

## Register on the Mac

```bash
claude mcp add topaz -- ssh -T robli@100.109.112.32 "C:\GitHub\MediaScripts\topaz\server\.venv\Scripts\python.exe C:\GitHub\MediaScripts\topaz\server\topaz_mcp.py"
```

Restart the Claude session, then run `topaz_status`. Expect `root_exists: true`, the
files in the folder, an empty `nas_mount_error`, and `topaz_found: true`.

## Using it

1. Put the clip in `/Volumes/tracklessdeep/upscaling/` on the Mac.
2. `topaz_upscale` with `input` set to the file name, a model, `scale`, and
   `profile: "draft"` (quick `.mp4`) or `"final"` (ProRes `.mov`).
3. Poll `topaz_job` with the returned `job_id` until `done`; the result lands beside the source.

## Troubleshooting (found while building it)

| Symptom | Cause / fix |
|---|---|
| SSH to 192.168.0.186 times out from the Mac | Different subnet behind the Tenda router. Use the Tailscale address. |
| `ipconfig` / `Test-NetConnection` not found | Those are Windows commands; on the Mac use `ifconfig` and `nc -vz`. |
| `topaz_upscale` fails, `root_exists: false` | The SSH session cannot see the NAS: check the credential file exists and `nas_mount_error`. |
| Mac sees old `C:\topaz-work` root or old behaviour | The Mac's server process predates a code change. Fully restart the Claude session. |
| `Model not found: prob-4` | A shell started before `TVAI_MODEL_DIR` was set machine-wide. Open a new shell (the server sets it itself). |
| `Unknown encoder 'libx264'` | Topaz's ffmpeg has none. Use `h264_nvenc` or `prores_ks`. |
| `10 bit encode not supported` (nvenc) | Add `format=yuv420p` after `tvai_up`. |
| `No module named 'mcp.server.fastmcp'` | mcp 2.x installed; the venv pins `mcp<2`. |
| Watermark on output | Topaz is unlicensed/expired. See Licence above. |

## Open items

1. **Licence:** buy or renew Topaz and sign in on Hyperion; decide whether to upgrade.
2. Upscale a real take for deliverable use once licensed, and benchmark it.
3. **Provenance:** each upscale gets a line in the shot notes or a sibling `provenance.md`
   (filename, Topaz Video version, model, scale, date, source). Add a Topaz section to
   `tools/services.md` once working.
4. Clean up test clips in `H:\upscaling` (`test.mp4`, `test-topaz.mp4`, the shot-28b test
   upscale) and `C:\topaz-work`.
5. Optional: set `TOPAZ_PATH` to the IP form of the UNC path; add a Tailscale auto-start
   check if Hyperion is rebooted unattended.

## Files in `topaz/`

| File | Purpose |
|---|---|
| `plan.md` | This document |
| `setup-ssh.ps1` | One-time admin setup: OpenSSH, firewall, key, sleep, Topaz env vars |
| `setup-nas-credential.ps1` | One-time: save the NAS login encrypted for the SSH-session mount |
| `server/topaz_mcp.py` | The MCP server |
| `server/mount-nas.ps1` | Connects an SSH session to the NAS using the saved credential |
| `server/smoke_test.py` | End-to-end test over stdio |
| `server/.venv/` | Python environment (gitignored) |
