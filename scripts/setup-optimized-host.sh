#!/usr/bin/env bash
set -euo pipefail

bundle_root="${1:-.cache/optimized-host-toolchain}"
openscad_version="2026.09.09"
pillow_version="12.3.0"
ready_file="$bundle_root/READY"

mkdir -p "$bundle_root"

if [[ ! -f "$ready_file" ]]; then
    echo "Building cached user-space SCAD host bundle..."
    rm -rf "$bundle_root"
    mkdir -p "$bundle_root/download" "$bundle_root/runtime" "$bundle_root/python"

    appimage_name="OpenSCAD-${openscad_version}-x86_64.AppImage"
    base_url="https://files.openscad.org/snapshots"
    appimage="$bundle_root/download/$appimage_name"
    checksum="$appimage.sha256"

    curl --fail --location --retry 3 \
        "$base_url/$appimage_name" \
        --output "$appimage"
    curl --fail --location --retry 3 \
        "$base_url/$appimage_name.sha256" \
        --output "$checksum"
    (
        cd "$bundle_root/download"
        sha256sum --check "$(basename "$checksum")"
    )
    chmod +x "$appimage"

    mkdir -p "$bundle_root/openscad"
    (
        cd "$bundle_root/openscad"
        "../download/$appimage_name" --appimage-extract >/dev/null
    )

    # The current ubuntu-24.04 runner already provides libGL/libGLX and Xvfb,
    # but the official OpenSCAD AppImage needs the GLVND EGL/OpenGL pieces that
    # the historical setup action installs with apt on every fresh runner.
    # Download their .deb packages without installing them and extract them into
    # the cached bundle so the warm path remains entirely user-space.
    mkdir -p "$bundle_root/debs"
    (
        cd "$bundle_root/debs"
        apt-get download libegl1 libegl-mesa0 libopengl0 >/dev/null
        for package in ./*.deb; do
            dpkg-deb -x "$package" "$bundle_root/runtime"
        done
    )

    python3 -m pip install \
        --disable-pip-version-check \
        --no-compile \
        --target "$bundle_root/python" \
        "Pillow==$pillow_version"

    rm -rf "$bundle_root/debs"

    cat > "$ready_file" <<EOF
openscad_version=$openscad_version
pillow_version=$pillow_version
runner_image=ubuntu-24.04
EOF
fi

openscad_bin="$bundle_root/openscad/squashfs-root/AppRun"
runtime_lib="$bundle_root/runtime/usr/lib/x86_64-linux-gnu"
python_lib="$bundle_root/python"

test -x "$openscad_bin"
test -d "$runtime_lib"
test -d "$python_lib/PIL"

export LD_LIBRARY_PATH="$runtime_lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export PYTHONPATH="$python_lib${PYTHONPATH:+:$PYTHONPATH}"

"$openscad_bin" --version
python3 -c 'from PIL import Image; print("Pillow:", Image.__version__)'

{
    echo "OPENSCAD_BIN=$openscad_bin"
    echo "LD_LIBRARY_PATH=$LD_LIBRARY_PATH"
    echo "PYTHONPATH=$PYTHONPATH"
} >> "$GITHUB_ENV"

printf 'Optimized host bundle size: '
du -sh "$bundle_root"
