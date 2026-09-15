#!/usr/bin/env bash
set -euo pipefail

bundle_root="${1:-.cache/exact-host-toolchain}"
package_version="20260909T191259.git33e8fdd8.debian-0"
expected_binary_sha="2ae45a19d347c39338f8ffa4b5468f097b96419f23fb814e08cbaed8b965f4e2"
pillow_version="12.3.0"
ready_file="$bundle_root/READY"
rootfs="$bundle_root/rootfs"
python_lib="$bundle_root/python"

mkdir -p "$bundle_root"

if [[ ! -f "$ready_file" ]]; then
    echo "Building exact cached host SCAD bundle from OBS package..."
    rm -rf "$bundle_root"
    mkdir -p "$bundle_root/debs/partial" "$rootfs" "$python_lib"

    # Match docker.scad-toolchain:v0.4.1: the immutable image installed
    # openscad-nightly from the official OpenSCAD OBS repository. Download the
    # exact package build and whatever runtime dependencies this clean runner is
    # missing, but do not install them into the host OS.
    sudo wget -qO /etc/apt/trusted.gpg.d/obs-openscad-nightly.asc \
      https://files.openscad.org/OBS-Repository-Key.pub
    echo 'deb https://download.opensuse.org/repositories/home:/t-paul/xUbuntu_24.04/ /' \
      | sudo tee /etc/apt/sources.list.d/openscad-nightly.list >/dev/null
    sudo apt-get -o Acquire::Retries=2 update >/dev/null

    sudo apt-get \
      -o Acquire::Retries=2 \
      -o Dir::Cache::archives="$PWD/$bundle_root/debs" \
      --download-only \
      install -y --no-install-recommends \
      "openscad-nightly=$package_version" >/dev/null

    shopt -s nullglob
    packages=("$bundle_root"/debs/*.deb)
    if (( ${#packages[@]} == 0 )); then
      echo "ERROR: apt downloaded no packages for exact host bundle." >&2
      exit 1
    fi
    for package in "${packages[@]}"; do
      dpkg-deb -x "$package" "$rootfs"
    done

    python3 -m pip install \
      --disable-pip-version-check \
      --no-compile \
      --target "$python_lib" \
      "Pillow==$pillow_version" >/dev/null

    binary="$rootfs/usr/bin/openscad-nightly"
    test -x "$binary"
    actual_sha="$(sha256sum "$binary" | awk '{print $1}')"
    if [[ "$actual_sha" != "$expected_binary_sha" ]]; then
      echo "ERROR: exact OpenSCAD binary hash mismatch: $actual_sha" >&2
      exit 1
    fi

    rm -rf "$bundle_root/debs"
    cat > "$ready_file" <<EOF
openscad_package=$package_version
openscad_binary_sha256=$expected_binary_sha
pillow_version=$pillow_version
runner_image=ubuntu-24.04
EOF
fi

openscad_bin="$rootfs/usr/bin/openscad-nightly"
test -x "$openscad_bin"
actual_sha="$(sha256sum "$openscad_bin" | awk '{print $1}')"
[[ "$actual_sha" == "$expected_binary_sha" ]]

# The download-only apt transaction extracts only dependencies missing from the
# clean runner. Prefer those cached libraries while retaining the runner's
# already-present system libraries as fallback.
lib_paths=()
for candidate in \
  "$rootfs/usr/lib/x86_64-linux-gnu" \
  "$rootfs/lib/x86_64-linux-gnu" \
  "$rootfs/usr/lib" \
  "$rootfs/lib"; do
  [[ -d "$candidate" ]] && lib_paths+=("$candidate")
done
if (( ${#lib_paths[@]} > 0 )); then
  joined_libs="$(IFS=:; echo "${lib_paths[*]}")"
  export LD_LIBRARY_PATH="$joined_libs${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
export PYTHONPATH="$python_lib${PYTHONPATH:+:$PYTHONPATH}"

"$openscad_bin" --version
python3 -c 'from PIL import Image; print("Pillow:", Image.__version__)'
printf 'Exact OpenSCAD binary SHA-256: %s\n' "$actual_sha"
printf 'Exact host bundle size: '
du -sh "$bundle_root"

{
  echo "OPENSCAD_BIN=$openscad_bin"
  echo "PYTHONPATH=$PYTHONPATH"
  if [[ -n "${LD_LIBRARY_PATH:-}" ]]; then
    echo "LD_LIBRARY_PATH=$LD_LIBRARY_PATH"
  fi
} >> "$GITHUB_ENV"
