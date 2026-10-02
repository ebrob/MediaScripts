# Topaz Video AI on Hyperion, driven from the laptop via MCP

**Status:** plan only. Nothing installed. As of 2026-10-02 Hyperion (192.168.0.186)
did not answer ping or SSH from the laptop, so step 0 comes first.

**Goal:** from a Claude session on this laptop, call an `upscale_video` tool that
runs Topaz on Hyperion's GPU and returns the upscaled file, without touching
Hyperion's GUI.

## Known facts about Hyperion

- AMD Ryzen 7 3700X, 64 GB RAM, Gigabyte GeForce RTX 2070 SUPER (8 GB, Turing).
- Can mount the `tracklessdeep` NAS share, so the NAS transfer route is settled.
- No Topaz licence yet. The CLI is allowed by the licence once bought; an
  unlicensed install exports with a watermark, so buy before the real test.
- Topaz upscaling is allowed under the repo's rules (decided 2026-10-02).
- Windows 10 Home. Home cannot host Remote Desktop, so SSH is the only remote
  route; OpenSSH Server does install on Home (Settings > Apps > Optional
  features, or the PowerShell command in Step 0). Windows 10 is past end of
  support (October 2025) unless Extended Security Updates are enrolled; check
  that the current Topaz release still supports it.
- Still unknown: whether SSH is set up.

**What the 2070 SUPER means:** it is supported, but 8 GB of VRAM is the limit.
Expect heavy models (Iris, Nyx, Gaia) at 1080p to 4K to be slow and
sometimes to need tiling or a smaller scale. Our 480p drafts and 1080p finals
suit it well: 480p to 1080p is the comfortable job. Benchmark one 5 s clip
before promising throughput. The 3700X's CPU matters little; decode is light.

## Design in one paragraph

Topaz Video AI ships a command-line ffmpeg (`ffmpeg.exe` in its install folder,
with `tvai_up`, `tvai_fi` and related filters). It is not a separate API.
So the "MCP" is a small server we write that runs on Hyperion, wraps that
ffmpeg, and exposes a few tools. The laptop's Claude connects to it over the LAN.
Files move through a share both machines can see, so no video travels through
the MCP protocol itself.

```
laptop (Claude)  --MCP/HTTP-->  topaz-mcp on Hyperion  -->  Topaz ffmpeg (GPU)
       \                                 |
        '------ SMB share / NAS (tracklessdeep) ---------'
```

## Step 0 — Reach Hyperion

- Confirm it is on, awake (disable sleep), and its real IP. Give it a DHCP
  reservation so 192.168.0.186 stays put.
- Check the laptop and Hyperion are on the same subnet/VLAN.
- Windows: allow ping (File and Printer Sharing echo rule) if wanted; enable
  OpenSSH Server (`Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0`,
  start and auto-start `sshd`). Set up key auth from the laptop.
- Verify: `ssh <user>@192.168.0.186 nvidia-smi` returns the GPU.

## Step 1 — Install Topaz on Hyperion

1. Confirm the GPU and driver (NVIDIA, current Studio/Game Ready driver).
2. Install Topaz Video AI (now sold as Topaz Video) from the Topaz site. It needs
   a licence and a logged-in account on that machine, so this is a manual,
   one-time step at Hyperion.
3. Open the GUI once, sign in, and let it download the models you want
   (Proteus, Iris, Artemis, Gaia, Nyx, Apollo, Chronos). The CLI only
   uses models already downloaded.
4. Note the install path, typically `C:\Program Files\Topaz Labs LLC\Topaz Video AI\`,
   and the model directory env vars the app sets (`TVAI_MODEL_DIR`,
   `TVAI_MODEL_DATA_DIR`). The CLI needs both set.
5. Smoke test by hand in PowerShell with a 5 s clip, using the `ffmpeg.exe`
   from that folder and a `tvai_up` filter (model, scale, etc.). Copy the exact
   filter string the GUI shows under "Export > Show command". That string is
   the ground truth for the wrapper.

Open questions to settle at the machine: whether a headless session (no
logged-in desktop) can run the CLI. The no `-sr`/`-esr` rule covers AtlasCloud
resolution options; Topaz upscaling is separately approved.

## Step 2 — File transfer

Pick one:

- **NAS (chosen):** both machines mount `tracklessdeep`
  (`Cumulonimbus`). Mount it on Hyperion as a fixed drive letter (e.g. `T:`)
  with saved credentials, and make it persistent at logon so the service sees it. Laptop writes the source to `amethyst-passage/scenes/...`;
  Hyperion reads the same path and writes the result beside it. This matches the
  repo's existing off-repo media layout.
- **Projects drive:** not suitable unless it is shared to Hyperion.
- **scp/rsync over SSH:** fallback if Hyperion cannot mount the NAS.

The MCP takes paths relative to a configured root and maps them to a Windows
path, so Claude can keep citing repo-relative paths.

## Step 3 — The MCP server (`tools/topaz/server/`)

Python with the `mcp` SDK (FastMCP), running on Hyperion as a service.

Tools:

| Tool | Does |
|---|---|
| `topaz_status` | GPU, free VRAM, queue length, Topaz version, models present |
| `topaz_upscale` | `input`, `scale` or target resolution, `model`, `output` → starts a job, returns `job_id` |
| `topaz_job` | state, progress (parsed from ffmpeg stderr), output path, log tail |
| `topaz_cancel` | kills the job |
| `topaz_list_models` | what the installed build offers |

Design points:

- Jobs run one at a time through a queue; a GPU is the limit.
- Long renders are async (start, then poll), because MCP calls should not block
  for minutes.
- Never pass user strings into a shell. Build the argument list from validated
  fields, and restrict paths to the configured root.
- Output is a new file (`name-topaz.mov` or `.mp4`), never an overwrite. Follow
  the repo's rule that finals are `.mov`, drafts `.mp4`.
- Transport: streamable HTTP bound to the LAN with a bearer token. Alternative
  with no network listener: stdio over SSH,
  `ssh hyperion python -m topaz_mcp`.
- Run it with NSSM or Task Scheduler "at logon" if Topaz needs a desktop
  session, otherwise as a service.

## Step 4 — Register on the laptop

Add to the repo `.mcp.json` (gitignored, holds live keys; do not commit):

```json
{ "mcpServers": { "topaz": { "type": "http",
  "url": "http://192.168.0.186:8765/mcp",
  "headers": { "Authorization": "Bearer <token>" } } } }
```

or the SSH stdio form. MCP servers load at session start, so restart the session.

## Step 5 — Provenance and docs

Per the repo's provenance rule, every upscale gets a line in the shot's notes or
a sibling `provenance.md`: filename, tool (Topaz Video AI vX.Y), model, scale,
date, source file. Add a "Topaz" section to `tools/services.md` once working.

## Build order

1. Step 0 (reach Hyperion), then the manual install and smoke test (Step 1).
2. Hand-run ffmpeg on one real shot take; check quality and speed.
3. Write the server with `topaz_status` and `topaz_upscale`; test locally on Hyperion.
4. Wire up the NAS paths; test from the laptop with curl.
5. Register in `.mcp.json`; upscale one take from a Claude session.

## Still needed

- OpenSSH enabled on Hyperion with a key from the laptop.
- A Topaz licence purchased and signed in on Hyperion.
