#!/usr/bin/env bash
# 重新生成 Fixtures/expected/*.json。
#
# 这些期望值是「同实现自证」的黄金文件：它保证以后改代码时结果变化可见，
# 不代表它们等于游戏内真值（真值口径见 README）。
#
# 用法（仓库根目录）：bash scripts/regen_fixtures.sh
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$ROOT/Packages/DamageKit"

for input in "$PKG"/Fixtures/*.json; do
  name="$(basename "$input" .json)"
  bash "$ROOT/scripts/swiftw.sh" run --package-path "$PKG" damagekit-cli \
    "$input" --data-root "$ROOT/web/app/site" > "$PKG/Fixtures/expected/$name.json"
  echo "wrote $name.json"
done
