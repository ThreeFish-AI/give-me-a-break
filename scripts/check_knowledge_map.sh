#!/usr/bin/env bash
# 知识索引同步校验（项目特有语义，AGENTS.md「知识索引同步」要求）。
# 校验 .agents/knowledge-map.md 中所有 markdown 相对链接 ](path) 指向的文件确实存在。
# 设计要点：
#   - 仅匹配 ](path) 真链接，排除反引号代码路径 `Sources/...`（knowledge-map 关键代码位置表用反引号）。
#   - 跳过外链（http/https/mailto），由 lychee 负责。
#   - 用进程替换 < <(...) 让 while 跑在主 shell，fail 标志可正确传回（避免管道子 shell 变量丢失陷阱）。
#   - 用 ( cd .agents && [ -e "$path" ] ) 子 shell 测试，POSIX 可移植（不依赖 GNU realpath -m）。
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

MAP=".agents/knowledge-map.md"
fail=0

if [ ! -f "$MAP" ]; then
  echo "::error file=$MAP::知识索引文件不存在"
  exit 1
fi

echo "==> 校验 $MAP 的相对链接可达性"

# shellcheck disable=SC2312 # 进程替换是有意为之（让 fail 标志传回主 shell）
while IFS= read -r link; do
  case "$link" in
    http://*|https://*|mailto:*) continue ;;   # 外链由 lychee 负责
  esac
  path="${link%%#*}"    # 去锚点 #...
  path="${path%%\?*}"   # 去查询串 ?...
  [ -z "$path" ] && continue
  if ! ( cd .agents && [ -e "$path" ] ); then
    echo "::error file=$MAP::失效的知识索引链接: $link"
    fail=1
  fi
done < <(grep -oE '\]\(([^)]+)\)' "$MAP" | sed -E 's/^\]\(//; s/\)$//')

if [ "$fail" -eq 0 ]; then
  echo "✓ 知识索引链接全部有效"
else
  exit 1
fi
