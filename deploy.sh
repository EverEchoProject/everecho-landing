#!/usr/bin/env bash
# Quick deploy: sync entire landing site to /opt/everecho-landing
#
# Usage:
#   ./deploy.sh
#   ./deploy.sh --no-check   # skip HTTPS verification
#
# Copies everything except .git, nginx/, and this script.
# 用法
# 在项目目录执行：

# cd /home/rocky/projects/everecho-landing
# ./deploy.sh
# 会把整个项目（index.html、static/ 等）同步到 /opt/everecho-landing/，并自动检查线上是否可访问。

# 脚本行为
# 使用 rsync 整目录同步（有 --delete，会删掉线上已移除的文件）
# 不会复制：.git/、nginx/、deploy.sh（Nginx 配置留在服务器 /etc/nginx/conf.d/）
# 部署后自动检查 https://everechoai.com/ 和一张 static 图片
# 跳过线上检查：

# ./deploy.sh --no-check
# 日常流程
# # 1. 改落地页文件
# # 2. 一键部署
# ./deploy.sh
# 脚本路径：/home/rocky/projects/everecho-landing/deploy.sh

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEPLOY_DIR="${DEPLOY_DIR:-/opt/everecho-landing}"
DOMAIN="${DOMAIN:-everechoai.com}"
SKIP_CHECK=0

for arg in "$@"; do
  case "$arg" in
    --no-check) SKIP_CHECK=1 ;;
    -h|--help)
      sed -n '2,8p' "$0"
      exit 0
      ;;
    *)
      echo "Unknown option: $arg" >&2
      exit 1
      ;;
  esac
done

log() {
  printf '[deploy] %s\n' "$*"
}

mkdir -p "$DEPLOY_DIR"

EXCLUDES=(
  --exclude '.git/'
  --exclude 'nginx/'
  --exclude 'deploy.sh'
)

if command -v rsync >/dev/null 2>&1; then
  log "Syncing $PROJECT_DIR -> $DEPLOY_DIR"
  rsync -av --delete "${EXCLUDES[@]}" "$PROJECT_DIR/" "$DEPLOY_DIR/"
else
  log "rsync not found, using cp (will not remove deleted files)"
  find "$DEPLOY_DIR" -mindepth 1 -maxdepth 1 ! -name '.git' -exec rm -rf {} +
  cp -r "$PROJECT_DIR/index.html" "$DEPLOY_DIR/"
  [[ -d "$PROJECT_DIR/static" ]] && cp -r "$PROJECT_DIR/static" "$DEPLOY_DIR/"
  for path in "$PROJECT_DIR"/*; do
    base="$(basename "$path")"
    case "$base" in
      .git|nginx|deploy.sh|index.html|static) continue ;;
      *)
        [[ -e "$path" ]] && cp -r "$path" "$DEPLOY_DIR/"
        ;;
    esac
  done
fi

log "Deployed files:"
ls -la "$DEPLOY_DIR"

if [[ $SKIP_CHECK -eq 1 ]]; then
  log "Done (skipped HTTPS check)"
  exit 0
fi

log "Checking https://${DOMAIN}/"
if curl -fsS "https://${DOMAIN}/" >/dev/null; then
  curl -fsS -o /dev/null -w "https://${DOMAIN}/ -> %{http_code}\n" "https://${DOMAIN}/"
  if [[ -d "$DEPLOY_DIR/static" ]]; then
    sample="$(find "$DEPLOY_DIR/static" -type f | head -1)"
    if [[ -n "$sample" ]]; then
      rel="${sample#$DEPLOY_DIR/}"
      curl -fsS -o /dev/null -w "https://${DOMAIN}/${rel} -> %{http_code}\n" "https://${DOMAIN}/${rel}"
    fi
  fi
  log "Deploy finished successfully"
else
  echo "Warning: https://${DOMAIN}/ is not reachable" >&2
  exit 1
fi
