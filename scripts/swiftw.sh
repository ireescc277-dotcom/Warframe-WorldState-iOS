#!/usr/bin/env bash
# Swift on Windows 会为「大小写不同的同名环境变量」（HTTP_PROXY / http_proxy）
# 直接 fatalError。这里先清掉小写副本，再转发给真正的 swift。
set -e
SWIFT_ROOT="/c/Users/LocalAdmin/AppData/Local/Programs/Swift"
export PATH="$SWIFT_ROOT/Toolchains/6.4.2+Asserts/usr/bin:$SWIFT_ROOT/Runtimes/6.4.2/usr/bin:$PATH"
export SDKROOT="C:\\Users\\LocalAdmin\\AppData\\Local\\Programs\\Swift\\Platforms\\6.4.2\\Windows.platform\\Developer\\SDKs\\Windows.sdk"
unset http_proxy https_proxy all_proxy no_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY NO_PROXY
exec swift "$@"
