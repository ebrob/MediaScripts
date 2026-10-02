# Topaz Video on Hyperion, driven from the Mac via MCP

**Status (2026-10-02):** working on Hyperion itself. Remote access over Tailscale + SSH
is verified. The MCP server passes a local stdio test. Not yet verified: registering it
from the Mac, and whether an SSH session can see the `H:` drive.

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
- Known issue: `topaz_status` GPU line showed an NVML error when run from the
  Claude session. `nvidia-smi` works in a normal shell. Recheck over SSH.
- `topaz/server/smoke_test.py <clip>` drives the server over stdio like a real client.

## Register on the Mac

```bash
claude mcp add topaz -- ssh -T robli@100.109.112.32 "C:\GitHub\MediaScripts\topaz\server\.venv\Scripts\python.exe C:\GitHub\MediaScripts\topaz\server\topaz_mcp.py"
```

Restart the Claude session, then run `topaz_status`.

## Open items

1. **SSH and `H:`:** mapped drives are per logon session. Check from the Mac:
   `ssh -T robli@100.109.112.32 "Test-Path H:\upscaling"`. If `False`, switch the
   root to the UNC path `\\192.168.5.5\tracklessdeep\upscaling` with saved
   credentials. If SSH key logins cannot use saved credentials, run the server as a
   scheduled task in the logged-in session instead. Hyperion must stay logged in either way.
2. Register the MCP on the Mac and upscale a real take.
3. Licence: buy or renew Topaz and sign in on Hyperion; decide whether to upgrade.
4. Provenance: each upscale gets a line in the shot notes or a sibling `provenance.md`
   (filename, Topaz Video version, model, scale, date, source). Add a Topaz section to
   `tools/services.md` once working.
5. Remove the `test.mp4` / `test-topaz.mp4` clips from `H:\upscaling`.
