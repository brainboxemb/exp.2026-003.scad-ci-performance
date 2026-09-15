#!/usr/bin/env bash
set -euo pipefail

variant="${1:?usage: run-benchmark.sh <variant>}"
source_file="fixture/benchmark.scad"
out_dir="out/${variant}"
openscad_bin="${OPENSCAD_BIN:-openscad}"
watermark_text="SCAD CI performance benchmark"

rm -rf "$out_dir"
mkdir -p "$out_dir"

if command -v xvfb-run >/dev/null 2>&1; then
    openscad_run=(xvfb-run -a "$openscad_bin")
else
    openscad_run=("$openscad_bin")
fi

now_ns() {
    date +%s%N
}

version="$($openscad_bin --version 2>&1 | head -n 1)"
workload_start_ns="$(now_ns)"

export_start_ns="$(now_ns)"
"${openscad_run[@]}" \
    -o "$out_dir/benchmark.stl" \
    "$source_file"
export_end_ns="$(now_ns)"

render_start_ns="$(now_ns)"
"${openscad_run[@]}" \
    --render \
    --projection=o \
    --imgsize=1024,768 \
    --autocenter \
    --viewall \
    -o "$out_dir/benchmark.png" \
    "$source_file"
render_end_ns="$(now_ns)"

watermark_start_ns="$(now_ns)"
python3 scripts/watermark.py \
    "$out_dir/benchmark.png" \
    --text "$watermark_text"
watermark_end_ns="$(now_ns)"

workload_end_ns="$(now_ns)"

test -s "$out_dir/benchmark.stl"
test -s "$out_dir/benchmark.png"

VARIANT="$variant" \
OPENSCAD_VERSION_TEXT="$version" \
OUT_DIR="$out_dir" \
WORKLOAD_START_NS="$workload_start_ns" \
WORKLOAD_END_NS="$workload_end_ns" \
EXPORT_START_NS="$export_start_ns" \
EXPORT_END_NS="$export_end_ns" \
RENDER_START_NS="$render_start_ns" \
RENDER_END_NS="$render_end_ns" \
WATERMARK_START_NS="$watermark_start_ns" \
WATERMARK_END_NS="$watermark_end_ns" \
BENCH_SETUP_START_NS="${BENCH_SETUP_START_NS:-}" \
BENCH_SETUP_END_NS="${BENCH_SETUP_END_NS:-}" \
python3 - <<'PY'
import hashlib
import importlib.metadata
import json
import os
from pathlib import Path

out_dir = Path(os.environ["OUT_DIR"])


def ns(name: str) -> int:
    return int(os.environ[name])


def duration_ms(start: str, end: str) -> float:
    return round((ns(end) - ns(start)) / 1_000_000, 3)


def file_info(path: Path) -> dict:
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    return {
        "path": str(path),
        "bytes": path.stat().st_size,
        "sha256": digest,
    }

setup_start = os.environ.get("BENCH_SETUP_START_NS", "")
setup_end = os.environ.get("BENCH_SETUP_END_NS", "")
setup_ms = None
if setup_start and setup_end:
    setup_ms = round((int(setup_end) - int(setup_start)) / 1_000_000, 3)

try:
    pillow_version = importlib.metadata.version("Pillow")
except importlib.metadata.PackageNotFoundError:
    pillow_version = "unknown"

data = {
    "schema": "brainboxemb.scad-ci-performance.v1",
    "variant": os.environ["VARIANT"],
    "github_sha": os.environ.get("GITHUB_SHA", ""),
    "runner_os": os.environ.get("RUNNER_OS", ""),
    "runner_arch": os.environ.get("RUNNER_ARCH", ""),
    "openscad_version": os.environ["OPENSCAD_VERSION_TEXT"],
    "pillow_version": pillow_version,
    "timing_ms": {
        "setup": setup_ms,
        "stl_export": duration_ms("EXPORT_START_NS", "EXPORT_END_NS"),
        "png_render": duration_ms("RENDER_START_NS", "RENDER_END_NS"),
        "watermark": duration_ms("WATERMARK_START_NS", "WATERMARK_END_NS"),
        "workload_total": duration_ms("WORKLOAD_START_NS", "WORKLOAD_END_NS"),
    },
    "outputs": {
        "stl": file_info(out_dir / "benchmark.stl"),
        "png": file_info(out_dir / "benchmark.png"),
    },
}

(out_dir / "timing.json").write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
print(json.dumps(data, indent=2))
PY
