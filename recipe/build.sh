#!/bin/bash

set -o xtrace -o nounset -o pipefail -o errexit

# crates.io downloads flake on CI workers ("curl failed: Transferred a partial
# file") and cargo doesn't retry that error itself; retry at the shell level
retry() {
    local attempt
    for attempt in 1 2 3; do
        "$@" && return 0
        echo "attempt ${attempt} failed: $*" >&2
        sleep 15
    done
    return 1
}

# Bundle Rust licenses for xpu (formerly gpu_stats) and parquet-rust-wrapper
pushd xpu
retry cargo-bundle-licenses --format yaml --output ../THIRDPARTY_XPU.yml
popd

pushd parquet-rust-wrapper
retry cargo-bundle-licenses --format yaml --output ../THIRDPARTY_PARQUET.yml
popd

# Unset CARGO_BUILD_TARGET: conda's rust compiler activation sets it, but
# xpu/hatch.py hardcodes "target/release/" and doesn't account for the
# target-triple subdirectory that CARGO_BUILD_TARGET introduces.
unset CARGO_BUILD_TARGET

# Build wandb-core with CGO: the default non-CGO path (new in 0.27.x) runs
# objcopy --remove-section .gnu.version* on the binary (auditwheel workaround
# in core/hatch.py) which corrupts it on our workers — wandb-core then
# segfaults (exit -11) at startup. CGO uses the external linker (no strip).
if [[ ${target_platform} == linux-* ]]; then
    export WANDB_ENABLE_CGO=true
fi

${PYTHON} -m pip install --no-deps --no-build-isolation -vv .

pushd core
rm LICENSE
cp ../LICENSE LICENSE
go-licenses save . --save_path="./license-files/"
popd
