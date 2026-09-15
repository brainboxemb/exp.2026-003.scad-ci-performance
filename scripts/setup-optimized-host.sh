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
wrapper="$bundle_root/openscad-exact"
library_dirs_file="$bundle_root/library-dirs.txt"

mkdir -p "$bundle_root"

if [[ ! -f "$ready_file" ]]; then
    echo "Building exact cached host SCAD bundle from immutable image $image..."
    rm -rf "$bundle_root"
    mkdir -p "$rootfs" "$python_lib"

    docker pull "$image"

    docker run --rm "$image" bash -lc '
      set -euo pipefail
      dpkg-query -L openscad-nightly \
        | while IFS= read -r path; do
            if [[ -f "$path" || -L "$path" ]]; then printf "%s\n" "$path"; fi
          done \
        | tar -h -cf - -T -
    ' | tar -xf - -C "$rootfs"

    docker run --rm "$image" bash -lc '
      set -euo pipefail
      declare -A seen=()
      queue=(/usr/bin/openscad-nightly)
      for loader in /lib64/ld-linux-x86-64.so.2 /lib/x86_64-linux-gnu/ld-linux-x86-64.so.2; do
        [[ -e "$loader" ]] && queue+=("$loader")
      done
      for dir in \
        /usr/lib/x86_64-linux-gnu/qt6/plugins/platforms \
        /usr/lib/x86_64-linux-gnu/qt6/plugins/imageformats; do
        if [[ -d "$dir" ]]; then
          while IFS= read -r plugin; do queue+=("$plugin"); done < <(find "$dir" \( -type f -o -type l \) -name "*.so*")
        fi
      done

      paths_file="$(mktemp)"
      while (( ${#queue[@]} > 0 )); do
        target="${queue[0]}"
        queue=("${queue[@]:1}")
        [[ -e "$target" ]] || continue
        [[ -n "${seen[$target]+x}" ]] && continue
        seen["$target"]=1
        printf "%s\n" "$target" >> "$paths_file"

        while IFS= read -r dep; do
          [[ -e "$dep" ]] || continue
          [[ -n "${seen[$dep]+x}" ]] || queue+=("$dep")
        done < <(
          ldd "$target" 2>/dev/null \
            | awk '\''/=> \/[^ ]+/ {print $3} $1 ~ /^\// {print $1}'\'' \
            | sort -u
        )
      done

      sort -u "$paths_file" | tar -h -cf - -T -
      rm -f "$paths_file"
    ' | tar -xf - -C "$rootfs"

    docker run --rm "$image" bash -lc '
      set -euo pipefail
      paths_file="$(mktemp)"
      for path in \
        /usr/lib/x86_64-linux-gnu/dri \
        /usr/share/glvnd/egl_vendor.d \
        /usr/share/drirc.d; do
        if [[ -d "$path" ]]; then
          find "$path" \( -type f -o -type l \) -print >> "$paths_file"
        elif [[ -f "$path" || -L "$path" ]]; then
          printf "%s\n" "$path" >> "$paths_file"
        fi
      done
      sort -u "$paths_file" | tar -h -cf - -T -
      rm -f "$paths_file"
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

    (
      cd "$rootfs"
      find . -type f -name '*.so*' -printf '%h\n' | sort -u
    ) > "$library_dirs_file"

    cat > "$wrapper" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
bundle_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
rootfs="$bundle_dir/rootfs"
lib_paths=()
while IFS= read -r relative_dir; do
  relative_dir="${relative_dir#./}"
  [[ -n "$relative_dir" ]] && lib_paths+=("$rootfs/$relative_dir")
done < "$bundle_dir/library-dirs.txt"
joined_libs="$(IFS=:; echo "${lib_paths[*]}")"

export QT_QPA_PLATFORM=offscreen
qt_plugins="$rootfs/usr/lib/x86_64-linux-gnu/qt6/plugins"
[[ -d "$qt_plugins" ]] && export QT_PLUGIN_PATH="$qt_plugins"
dri="$rootfs/usr/lib/x86_64-linux-gnu/dri"
[[ -d "$dri" ]] && export LIBGL_DRIVERS_PATH="$dri"
egl_vendor="$rootfs/usr/share/glvnd/egl_vendor.d/50_mesa.json"
[[ -f "$egl_vendor" ]] && export __EGL_VENDOR_LIBRARY_FILENAMES="$egl_vendor"

loader="$(find "$rootfs" \( -type f -o -type l \) -name 'ld-linux-x86-64.so.2' -print -quit)"
if [[ -z "$loader" || ! -x "$loader" ]]; then
  echo "ERROR: exact image ELF loader not found in cached bundle." >&2
  find "$rootfs" -maxdepth 4 -name 'ld-linux*' -ls >&2 || true
  exit 1
fi

exec "$loader" --library-path "$joined_libs" "$rootfs/usr/bin/openscad-nightly" "$@"
EOF
    chmod +x "$wrapper"

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
test -x "$wrapper"
test -s "$library_dirs_file"
actual_sha="$(sha256sum "$openscad_bin" | awk '{print $1}')"
[[ "$actual_sha" == "$expected_binary_sha" ]]

export PYTHONPATH="$python_lib${PYTHONPATH:+:$PYTHONPATH}"

"$wrapper" --version
python3 -c 'from PIL import Image; print("Pillow:", Image.__version__)'
printf 'Exact OpenSCAD binary SHA-256: %s\n' "$actual_sha"
printf 'Exact host bundle size: '
du -sh "$bundle_root"

{
  echo "OPENSCAD_BIN=$wrapper"
  echo "PYTHONPATH=$PYTHONPATH"
} >> "$GITHUB_ENV"
