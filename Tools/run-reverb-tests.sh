#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

build_dir="build/reverb-tools"
mkdir -p "$build_dir"
clang++ -std=c++17 -O2 -I ThirdParty/SignalsmithDSP/include -I ThirdParty/SignalsmithDSP \
  -c Sources/Audio/ReverbDSP.cpp -o "$build_dir/ReverbDSP.o"
clang++ -std=c++17 -O2 Tools/reverb_dsp_test.cpp "$build_dir/ReverbDSP.o" \
  -o "$build_dir/reverb-dsp-test"
"$build_dir/reverb-dsp-test"
swiftc -O -swift-version 6 -strict-concurrency=complete \
  -import-objc-header Sources/Audio/ReverbDSP.h \
  Sources/Model/ReverbParameters.swift Sources/Audio/ReverbUnit.swift Tools/reverb_test.swift \
  "$build_dir/ReverbDSP.o" -lc++ -o "$build_dir/reverb-test"
"$build_dir/reverb-test"

if [[ "${1:-}" == "--demo" ]]; then
  swiftc -O -swift-version 6 -strict-concurrency=complete \
    -import-objc-header Sources/Audio/ReverbDSP.h \
    Sources/Model/ReverbParameters.swift Sources/Audio/ReverbUnit.swift Tools/reverb_demo.swift \
    "$build_dir/ReverbDSP.o" -lc++ -o "$build_dir/reverb-demo"
  "$build_dir/reverb-demo"
fi
