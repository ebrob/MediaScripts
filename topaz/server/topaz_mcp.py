"""MCP server wrapping Topaz Video's ffmpeg. Runs on Hyperion over stdio (via SSH).

Paths are relative to TOPAZ_ROOT and may not escape it. Jobs run one at a time.
"""
import json
import os
import re
import subprocess
import threading
import time
import uuid
from pathlib import Path

from mcp.server.fastmcp import FastMCP

TOPAZ_DIR = Path(os.environ.get("TOPAZ_DIR", r"C:\Program Files\Topaz Labs LLC\Topaz Video"))
MODEL_DIR = Path(os.environ.get("TVAI_MODEL_DIR", r"C:\ProgramData\Topaz Labs LLC\Topaz Video\models"))
# Drive letters mapped on the desktop are invisible to SSH sessions, so fall back to
# the UNC path (uses the credentials saved with cmdkey for the NAS).
_UNC = r"\\192.168.5.5\tracklessdeep\upscaling"
_candidates = [c for c in (os.environ.get("TOPAZ_ROOT"), os.environ.get("TOPAZ_PATH"),
                           r"H:\upscaling", _UNC) if c]
ROOT = Path(next((c for c in _candidates if os.path.isdir(c)), _candidates[0])).resolve()
FFMPEG = TOPAZ_DIR / "ffmpeg.exe"
FFPROBE = TOPAZ_DIR / "ffprobe.exe"

mcp = FastMCP("topaz")

# Output profiles: drafts are .mp4, finals are .mov (repo rule).
PROFILES = {
    "draft": (".mp4", ["-c:v", "h264_nvenc", "-b:v", "8M", "-pix_fmt", "yuv420p"], "format=yuv420p"),
    "final": (".mov", ["-c:v", "prores_ks", "-profile:v", "3", "-pix_fmt", "yuv422p10le"], None),
}

_lock = threading.Lock()
_jobs: dict[str, dict] = {}
_queue_lock = threading.Lock()  # one GPU job at a time


def _env():
    env = os.environ.copy()
    env["TVAI_MODEL_DIR"] = str(MODEL_DIR)
    env["TVAI_MODEL_DATA_DIR"] = str(MODEL_DIR)
    return env


def _safe(rel: str) -> Path:
    p = (ROOT / rel).resolve()
    if ROOT != p and ROOT not in p.parents:
        raise ValueError(f"path escapes TOPAZ_ROOT: {rel}")
    return p


def _models() -> list[str]:
    return sorted(
        p.stem for p in MODEL_DIR.glob("*.json")
        if re.fullmatch(r"[a-z0-9]+-\d+", p.stem)
    )


def _duration(path: Path) -> float:
    out = subprocess.run(
        [str(FFPROBE), "-v", "error", "-show_entries", "format=duration",
         "-of", "csv=p=0", str(path)],
        capture_output=True, text=True, timeout=30,
    ).stdout.strip()
    return float(out or 0)


def _run(job_id: str, args: list[str], duration: float):
    with _queue_lock:
        job = _jobs[job_id]
        if job["state"] == "cancelled":
            return
        job["state"] = "running"
        job["started"] = time.time()
        proc = subprocess.Popen(
            args, env=_env(), stderr=subprocess.PIPE, stdout=subprocess.DEVNULL,
            text=True, encoding="utf-8", errors="replace",
        )
        job["proc"] = proc
        tail = job["log"]
        buf = ""
        while True:
            ch = proc.stderr.read(1)
            if not ch:
                break
            if ch in "\r\n":
                if buf:
                    tail.append(buf)
                    del tail[:-40]
                    m = re.search(r"time=(\d+):(\d+):(\d+\.\d+)", buf)
                    if m and duration:
                        t = int(m[1]) * 3600 + int(m[2]) * 60 + float(m[3])
                        job["progress"] = round(min(t / duration, 1.0), 3)
                buf = ""
            else:
                buf += ch
        rc = proc.wait()
        job["proc"] = None
        job["ended"] = time.time()
        if job["state"] == "cancelled":
            return
        job["state"] = "done" if rc == 0 else "failed"
        job["returncode"] = rc
        if rc == 0:
            job["progress"] = 1.0


@mcp.tool()
def topaz_status() -> dict:
    """GPU, Topaz install, root folder and queue state."""
    gpu = subprocess.run(
        ["nvidia-smi", "--query-gpu=name,memory.used,memory.total,driver_version",
         "--format=csv,noheader"],
        capture_output=True, text=True,
    ).stdout.strip()
    with _lock:
        states = [j["state"] for j in _jobs.values()]
    return {
        "gpu": gpu,
        "topaz_ffmpeg": str(FFMPEG),
        "topaz_found": FFMPEG.exists(),
        "root": str(ROOT),
        "root_exists": ROOT.exists(),
        "root_files": sorted(p.name for p in ROOT.iterdir() if not p.name.startswith("."))[:30] if ROOT.exists() else [],
        "models_found": len(_models()),
        "jobs_running": states.count("running"),
        "jobs_queued": states.count("queued"),
        "note": "Unlicensed installs add a Topaz Labs watermark.",
    }


@mcp.tool()
def topaz_list_models() -> list[str]:
    """Model ids available locally (e.g. prob-4, iris-3, ahq-12)."""
    return _models()


@mcp.tool()
def topaz_upscale(input: str, model: str = "prob-4", scale: int = 2,
                  profile: str = "draft", output: str = "") -> dict:
    """Start an upscale job. Paths are relative to TOPAZ_ROOT.

    profile: 'draft' (.mp4, H.264) or 'final' (.mov, ProRes 422 HQ).
    scale: 1, 2 or 4. Returns a job_id; poll with topaz_job.
    """
    if profile not in PROFILES:
        raise ValueError(f"profile must be one of {list(PROFILES)}")
    if scale not in (1, 2, 4):
        raise ValueError("scale must be 1, 2 or 4")
    if model not in _models():
        raise ValueError(f"unknown model {model!r}; see topaz_list_models")
    src = _safe(input)
    if not src.is_file():
        raise FileNotFoundError(
            f"{input!r} not found. Looked for {src} (root {ROOT}, "
            f"root exists: {ROOT.exists()}). Paths are relative to the root.")
    ext, enc, tail_filter = PROFILES[profile]
    dst = _safe(output) if output else src.with_name(f"{src.stem}-topaz{ext}")
    if dst.suffix.lower() != ext:
        raise ValueError(f"profile {profile!r} writes {ext}, got {dst.suffix}")
    if dst.exists():
        raise FileExistsError(f"{dst.name} exists; refusing to overwrite")

    vf = f"tvai_up=model={model}:scale={scale}"
    if tail_filter:
        vf += f",{tail_filter}"
    args = [str(FFMPEG), "-hide_banner", "-n", "-i", str(src), "-vf", vf, *enc, str(dst)]

    job_id = uuid.uuid4().hex[:8]
    with _lock:
        _jobs[job_id] = {
            "id": job_id, "state": "queued", "progress": 0.0, "input": input,
            "output": str(dst.relative_to(ROOT)), "model": model, "scale": scale,
            "profile": profile, "log": [], "created": time.time(), "proc": None,
        }
    threading.Thread(target=_run, args=(job_id, args, _duration(src)), daemon=True).start()
    return {"job_id": job_id, "output": _jobs[job_id]["output"]}


def _view(j: dict) -> dict:
    out = {k: v for k, v in j.items() if k not in ("proc", "log")}
    out["log_tail"] = j["log"][-5:]
    if j.get("started"):
        out["elapsed_s"] = round((j.get("ended") or time.time()) - j["started"], 1)
    return out


@mcp.tool()
def topaz_job(job_id: str = "") -> dict | list:
    """State and progress of one job, or of all jobs if job_id is empty."""
    with _lock:
        if not job_id:
            return [_view(j) for j in _jobs.values()]
        if job_id not in _jobs:
            raise KeyError(job_id)
        return _view(_jobs[job_id])


@mcp.tool()
def topaz_cancel(job_id: str) -> dict:
    """Cancel a queued or running job."""
    with _lock:
        j = _jobs.get(job_id)
        if not j:
            raise KeyError(job_id)
        if j["state"] in ("done", "failed", "cancelled"):
            return _view(j)
        j["state"] = "cancelled"
        if j["proc"]:
            j["proc"].kill()
        return _view(j)


if __name__ == "__main__":
    # --http [port]: streamable HTTP on loopback only, for running in the desktop session
    # (which can see the NAS). Reach it from the Mac through an SSH tunnel.
    import sys
    if "--http" in sys.argv:
        i = sys.argv.index("--http")
        mcp.settings.host = "127.0.0.1"
        mcp.settings.port = int(sys.argv[i + 1]) if len(sys.argv) > i + 1 else 8765
        mcp.run(transport="streamable-http")
    else:
        mcp.run()  # stdio
