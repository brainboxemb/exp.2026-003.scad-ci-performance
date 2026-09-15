#!/usr/bin/env bash
set -euo pipefail

bundle_root="${1:-.cache/exact-host-toolchain}"
image="${SCAD_IMAGE:-ghcr.io/brainboxemb/scad-toolchain:v0.4.1}"
package_version="20260909T191259.git33e8fdd8.debian-0"
expected_binary_sha="2ae45a19d347c39338f8ffa4b5468f097b96419f23fb814e08cbaed8b965f4e2"
pillow_version="12.3.0"
ready_file="$bundle_root/READY"
rootfs="$bundle_root/rootfs"
python_lib="$bundle_root/python"

mkdir -p "$bundle_root"

if [[ ! -f "$ready_file" ]]; then
    echo "Building exact cached host SCAD bundle from immutable image $image..."
    rm -rf "$bundle_root"
    mkdir -p "$rootfs" "$python_lib"

    docker pull "$image"

    # Copy only the openscad-nightly package payload. Avoid archiving directory
    # entries from dpkg -L because that would recursively pull unrelated files.
    docker run --rm "$image" bash -lc '
      set -euo pipefail
      dpkg-query -W -f="${Version}\n" openscad-nightly
      dpkg-query -L openscad-nightly \
        | while IFS= read -r path; do
            if [[ -f "$path" || -L "$path" ]]; then printf "%s\n" "$path"; fi
          done \
        | tar -h -cf - -T -
    ' | tar -xf - -C "$rootfs"

    # The exact binary is dynamically linked. Cache the shared-library closure
    # used by the binary plus the Qt offscreen/image plugins needed by CLI PNG
    # rendering. Host libraries remain fallback; cached copies take precedence.
    docker run --rm "$image" bash -lc '
      set -euo pipefail
      targets=(/usr/bin/openscad-nightly)
      for dir in \
        /usr/lib/x86_64-linux-gnu/qt6/plugins/platforms \
        /usr/lib/x86_64-linux-gnu/qt6/plugins/imageformats; do
        if [[ -d "$dir" ]]; then
          while IFS= read -r plugin; do targets+=("$plugin"); done < <(find "$dir" \( -type f -o -type l \) -name "*.so*")
        fi
      done
      {
        printf "%s\n" "${targets[@]}"
        for target in "${targets[@]}"; do
          ldd "$target" 2>/dev/null \
            | awk '\''/=> \/[^ ]+/ {print $3} /^\// {print $1}'\''
        done
      } | sort -u | while IFS= read -r path; do
        [[ -e "$path" ]] && printf "%s\n" "$path"
      done | tar -h -cf - -T -
    ' | tar -xf - -C "$rootfs"

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

    cat > "$ready_file" <<EOF
source_image=$image
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
export QT_QPA_PLATFORM=offscreen
qt_plugins="$rootfs/usr/lib/x86_64-linux-gnu/qt6/plugins"
[[ -d "$qt_plugins" ]] && export QT_PLUGIN_PATH="$qt_plugins"

"$openscad_bin" --version
python3 -c 'from PIL import Image; print("Pillow:", Image.__version__)'
printf 'Exact OpenSCAD binary SHA-256: %s\n' "$actual_sha"
printf 'Exact host bundle size: '
du -sh "$bundle_root"

{
  echo "OPENSCAD_BIN=$openscad_bin"
  echo "PYTHONPATH=$PYTHONPATH"
  echo "QT_QPA_PLATFORM=$QT_QPA_PLATFORM"
  [[ -n "${LD_LIBRARY_PATH:-}" ]] && echo "LD_LIBRARY_PATH=$LD_LIBRARY_PATH"
  [[ -n "${QT_PLUGIN_PATH:-}" ]] && echo "QT_PLUGIN_PATH=$QT_PLUGIN_PATH"
} >> "$GITHUB_ENV"
