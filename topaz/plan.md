# Topaz Video on Hyperion, driven from the Mac via MCP

**Status (2026-10-02):** working end to end. Tailscale + SSH access, the MCP server
(registered on the Mac over stdio/SSH) and NAS access from SSH sessions are all
verified. Remaining: the Topaz licence (output is watermarked until then).

**Goal:** from a Claude session on the Mac ("AirSpaceBoundary"), call `topaz_upscale`,
which runs Topaz on Hyperion's GPU and writes the result to the NAS, without touching
Hyperion's GUI.

## Hyperion (as found)

- Windows 10 Home, user `robli`. Ryzen 7 3700X, 64 GB RAM, **RTX 3060 Ti (8 GB)**,
  driver 581.29. (An earlier draft of this plan said 2070 SUPER; that was wrong.)
- LAN 192.168.0.186 (wired). Tailscale 100.109.112.32 (`hyperion`).
- Topaz Video **1.1.0** (built 2025-12-15, the renamed "Video AI") in
  `C:\Program Files\Topaz Labs LLC\Topaz Video\`. Models (~1.9 GB) in
  `C:\ProgramData\Topaz Labs LLC\Topaz Video\models`. The GUI is offering an upgrade
  and a renewal. **The install is unlicensed/expired: exports carry a "Topaz Labs"
  watermark.** Fine for testing, not for deliverables. Buy or renew before real use,
  and check Windows 10 is still supported by the current release before upgrading.
- Bundled ffmpeg 8.0 has `tvai_up`, `tvai_fi`, `tvai_pe`, `tvai_cpe`, `tvai_stb`.
  **No libx264.** Use `h264_nvenc` (needs `format=yuv420p`; it rejects 10-bit) for
  drafts and `prores_ks` for finals.
- Python 3.12 (user install), venv at `topaz/server/.venv`, `mcp<2` pinned.
- OpenSSH Server running, key auth, default shell pwsh. Set up by `topaz/setup-ssh.ps1`
  (also sets sleep to never and the machine-wide `TVAI_MODEL_DIR` / `TVAI_MODEL_DATA_DIR`).
- NAS `tracklessdeep` is mounted on `H:` (`\\192.168.5.5\tracklessdeep`), work folder
  `H:\upscaling`.

## Network

The Mac (192.168.4.161/22) sits behind a Tenda AXE5700 VR router on its own subnet, so
it cannot reach Hyperion (192.168.0.x) directly: plain SSH timed out. Tailscale
(GitHub sign-in, both machines on the same account) bypasses this. Use
`ssh robli@100.109.112.32` or `robli@hyperion`. Leave the Tenda as it is.

## Benchmark (RTX 3060 Ti)

2 s, 24 fps, 854x480 clip, `prob-4`, 2x to 1708x960: about 10.5 s either to H.264
(`h264_nvenc`) or ProRes (`prores_ks`), about 4.6 fps. Synthetic clip; rerun on a
real shot before promising throughput. 8 GB VRAM: expect heavy models (Iris, Nyx,
Gaia) at high resolutions to be slow or need a smaller scale.

## The MCP server: `topaz/server/topaz_mcp.py`

stdio transport, run over SSH, so there is no network listener and no token.

| Tool | Does |
|---|---|
| `topaz_status` | GPU, Topaz found, root, model count, queue |
| `topaz_list_models` | local model ids |
| `topaz_upscale` | `input`, `model` (default `prob-4`), `scale` 1/2/4, `profile` draft/final, optional `output` -> `job_id` |
| `topaz_job` | state, progress, elapsed, log tail (one job or all) |
| `topaz_cancel` | kill a queued or running job |

- Paths are relative to `TOPAZ_ROOT` (default `H:\upscaling`) and cannot escape it.
- One GPU job at a time. Never overwrites: output is `<name>-topaz.mp4` (draft) or
  `.mov` (final, ProRes 422 HQ), per the repo's draft/final rule.
- Arguments are built as a list from validated fields; nothing goes through a shell.
- `topaz_status` also reports `root_exists`, the files in the root and `nas_mount_error`.
  (An NVML error on the GPU line only happened inside the setup session; over SSH it is fine.)
- `topaz/server/smoke_test.py <clip> [profile] [model] [scale]` drives the server over
  stdio like a real client.
- Tested: a 7 s clip with `gcg-5`, 2x, `final` took 54 s (about 3 fps) to a ProRes `.mov`.

## NAS access from SSH sessions

Drive letters and saved credentials from the desktop session are not visible to SSH
logons, so `H:` and plain UNC paths fail over SSH. The root is chosen from, in order:
`TOPAZ_ROOT`, `TOPAZ_PATH`, `H:\upscaling`, `\\192.168.5.5\tracklessdeep\upscaling`. If none
exists, the server runs `server/mount-nas.ps1`, which connects the session using a
DPAPI-encrypted credential at `%LOCALAPPDATA%\topaz-mcp\nas.cred.xml`. Create that file
once, as robli on Hyperion, with `topaz/setup-nas-credential.ps1` (the password is never
in the repo or seen by Claude). The host name `Cumulonimbus` does not resolve from
Hyperion; use the IP.

Fallback if this ever stops working: run the server over HTTP in the logged-in desktop
session (loopback only) and reach it from the Mac through an SSH tunnel. It was built
and tested once, then removed in favour of the credential approach.

## Register on the Mac

```bash
claude mcp add topaz -- ssh -T robli@100.109.112.32 "C:\GitHub\MediaScripts\topaz\server\.venv\Scripts\python.exe C:\GitHub\MediaScripts\topaz\server\topaz_mcp.py"
```

Restart the Claude session, then run `topaz_status`.

## Open items

1. Licence: buy or renew Topaz and sign in on Hyperion; decide whether to upgrade.
   Until then every export carries a Topaz Labs watermark.
2. Upscale a real take for deliverable use once licensed, and benchmark it.
4. Provenance: each upscale gets a line in the shot notes or a sibling `provenance.md`
   (filename, Topaz Video version, model, scale, date, source). Add a Topaz section to
   `tools/services.md` once working.
3. Clean up test clips in `H:\upscaling` (`test.mp4`, `test-topaz.mp4`, the shot-28b test
   upscale) and `C:\topaz-work`.
