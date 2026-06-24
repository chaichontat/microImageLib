#!/usr/bin/env bash
set -euo pipefail

CONDA_ENV="${CONDA_ENV:-seq}"
BASE_REF="${BASE_REF:-425b570106c6143b568b6dc5395687041b8097dd}"
NEW_REF="${NEW_REF:-HEAD}"
CUDA_DEVICE="${CUDA_DEVICE:-0}"
WORK_DIR="${WORK_DIR:-/tmp/microimagelib-parity}"

repo_root="$(git rev-parse --show-toplevel)"
base_dir="$WORK_DIR/base"
new_dir="$WORK_DIR/new"

rm -rf "$WORK_DIR"
mkdir -p "$base_dir" "$new_dir"

git -C "$repo_root" archive "$BASE_REF" | tar -x -C "$base_dir"
git -C "$repo_root" archive "$NEW_REF" | tar -x -C "$new_dir"

cat > "$WORK_DIR/run_case.py" <<'PY'
import ctypes
import json
import math
import sys


lib_path = sys.argv[1]
device = int(sys.argv[2])
lib = ctypes.CDLL(lib_path, mode=ctypes.RTLD_LOCAL)

FloatP = ctypes.POINTER(ctypes.c_float)
UShortP = ctypes.POINTER(ctypes.c_ushort)
UIntP = ctypes.POINTER(ctypes.c_uint)

lib.atrans3dgpu.argtypes = [FloatP, FloatP, FloatP, UIntP, UIntP, ctypes.c_int]
lib.atrans3dgpu.restype = ctypes.c_int
lib.atrans3dgpu_16bit.argtypes = [UShortP, FloatP, UShortP, UIntP, UIntP, ctypes.c_int]
lib.atrans3dgpu_16bit.restype = ctypes.c_int


def affine_identity():
    values = [0.0] * 12
    values[0] = values[5] = values[10] = 1.0
    return (ctypes.c_float * 12)(*values)


def run_float_case():
    size = (ctypes.c_uint * 3)(5, 4, 3)
    n = size[0] * size[1] * size[2]
    src_values = [math.sin(i * 0.17) + 0.1 * (i % 7) for i in range(n)]
    src = (ctypes.c_float * n)(*src_values)
    out = (ctypes.c_float * n)()
    status = lib.atrans3dgpu(out, affine_identity(), src, size, size, device)
    if status != 0:
        raise RuntimeError(f"atrans3dgpu returned {status}")
    return [float(out[i]) for i in range(n)]


def run_ushort_case():
    size = (ctypes.c_uint * 3)(5, 4, 3)
    n = size[0] * size[1] * size[2]
    src_values = [(i * 37 + 11) % 65535 for i in range(n)]
    src = (ctypes.c_ushort * n)(*src_values)
    out = (ctypes.c_ushort * n)()
    status = lib.atrans3dgpu_16bit(out, affine_identity(), src, size, size, device)
    if status != 0:
        raise RuntimeError(f"atrans3dgpu_16bit returned {status}")
    return [int(out[i]) for i in range(n)]


print(json.dumps({
    "float_atrans3d": run_float_case(),
    "ushort_atrans3d": run_ushort_case(),
}, sort_keys=True))
PY

cat > "$WORK_DIR/compare.py" <<'PY'
import json
import math
import sys


with open(sys.argv[1]) as f:
    base = json.load(f)
with open(sys.argv[2]) as f:
    new = json.load(f)

failures = []
for key in sorted(base):
    if key not in new:
        failures.append(f"{key}: missing from new output")
        continue
    a = base[key]
    b = new[key]
    if len(a) != len(b):
        failures.append(f"{key}: length differs {len(a)} != {len(b)}")
        continue
    if key.startswith("float"):
        max_abs = max((abs(x - y) for x, y in zip(a, b)), default=0.0)
        if max_abs > 1e-5:
            failures.append(f"{key}: max abs diff {max_abs}")
    elif a != b:
        first = next((i for i, (x, y) in enumerate(zip(a, b)) if x != y), None)
        failures.append(f"{key}: first mismatch at {first}: {a[first]} != {b[first]}")

extra = sorted(set(new) - set(base))
for key in extra:
    failures.append(f"{key}: extra in new output")

if failures:
    print("Parity check failed:")
    for failure in failures:
        print(f"  {failure}")
    sys.exit(1)

print("Parity check passed")
PY

build_one() {
    local dir="$1"
    local log="$2"
    if ! CONDA_NO_PLUGINS=true conda run -n "$CONDA_ENV" bash -lc \
        "cufft_dir=\$(find \"\$CONDA_PREFIX\"/lib/python*/site-packages/nvidia -maxdepth 1 -type d -name cufft | head -n 1); export LD_LIBRARY_PATH=\"\$CONDA_PREFIX/lib:\$CONDA_PREFIX/targets/x86_64-linux/lib:\$LD_LIBRARY_PATH\"; make -C '$dir/src' CUDA_ROOT=\"\$CONDA_PREFIX\" NVIDIA_CUFFT_DIR=\"\$cufft_dir\" cleanAll all" > "$log" 2>&1; then
        cat "$log"
        return 1
    fi
}

run_one() {
    local dir="$1"
    local out="$2"
    CONDA_NO_PLUGINS=true conda run -n "$CONDA_ENV" bash -lc \
        "export LD_LIBRARY_PATH='$dir/bin/linux':\"\$CONDA_PREFIX/lib:\$CONDA_PREFIX/targets/x86_64-linux/lib:\$LD_LIBRARY_PATH\"; python '$WORK_DIR/run_case.py' '$dir/bin/linux/libapi.so' '$CUDA_DEVICE'" > "$out"
}

echo "Building $BASE_REF in $base_dir"
build_one "$base_dir" "$WORK_DIR/base-build.log"
echo "Building $NEW_REF in $new_dir"
build_one "$new_dir" "$WORK_DIR/new-build.log"

echo "Running parity cases on CUDA device $CUDA_DEVICE"
run_one "$base_dir" "$WORK_DIR/base.json"
run_one "$new_dir" "$WORK_DIR/new.json"

python "$WORK_DIR/compare.py" "$WORK_DIR/base.json" "$WORK_DIR/new.json"
