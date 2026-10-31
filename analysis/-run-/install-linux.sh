#!/usr/bin/env bash
set -euo pipefail

APP_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$APP_DIR"

fail() {
  echo "错误：$1" >&2
  exit 1
}

NODE_BIN="$(command -v node || true)"
NODE_MAJOR=0
if [ -n "$NODE_BIN" ]; then
  NODE_MAJOR="$("$NODE_BIN" -p "process.versions.node.split('.')[0]")"
fi
if [ "$NODE_MAJOR" -lt 18 ]; then
  command -v curl >/dev/null 2>&1 || fail "缺少 curl，无法自动下载 Node.js。"
  command -v python3 >/dev/null 2>&1 || fail "缺少 python3，无法读取 Node.js 官方发行版本信息。"
  command -v tar >/dev/null 2>&1 || fail "缺少 tar，无法解压 Node.js。"
  case "$(uname -m)" in
    x86_64|amd64) NODE_ARCH=x64 ;;
    aarch64|arm64) NODE_ARCH=arm64 ;;
    *) fail "不支持自动安装的 CPU 架构：$(uname -m)" ;;
  esac
  echo "从 Node.js 官方站点下载 Node.js 24（Linux ${NODE_ARCH}）..."
  NODE_VERSION="$(curl -fsSL https://nodejs.org/dist/index.json | python3 -c 'import json,sys; print(next(v["version"] for v in json.load(sys.stdin) if v["version"].startswith("v24.")))')" || fail "无法获取 Node.js 官方版本信息。"
  RUNTIME_DIR="$APP_DIR/.runtime/node"
  mkdir -p "$RUNTIME_DIR"
  ARCHIVE="node-${NODE_VERSION}-linux-${NODE_ARCH}.tar.xz"
  curl -fL "https://nodejs.org/dist/${NODE_VERSION}/${ARCHIVE}" -o "$RUNTIME_DIR/$ARCHIVE"
  tar -xJf "$RUNTIME_DIR/$ARCHIVE" -C "$RUNTIME_DIR"
  rm -f "$RUNTIME_DIR/$ARCHIVE"
  export PATH="$RUNTIME_DIR/node-${NODE_VERSION}-linux-${NODE_ARCH}/bin:$PATH"
  NODE_BIN="$(command -v node)"
  export npm_config_prefix="$RUNTIME_DIR/npm-global"
  export PATH="$npm_config_prefix/bin:$PATH"
fi
command -v npm >/dev/null 2>&1 || fail "Node.js 已准备，但未找到 npm。"

[ -f "$APP_DIR/bin/yt-dlp" ] || fail "缺少 bin/yt-dlp，请放入与本机 CPU 架构匹配的 Linux 版本。"
[ -f "$APP_DIR/bin/ffmpeg" ] || fail "缺少 bin/ffmpeg，请放入与本机 CPU 架构匹配的 Linux 版本。"
chmod +x "$APP_DIR/bin/yt-dlp" "$APP_DIR/bin/ffmpeg"
"$APP_DIR/bin/yt-dlp" --version
"$APP_DIR/bin/ffmpeg" -version

echo "安装项目依赖..."
npm install

PM2_BIN="$(command -v pm2 || true)"
if [ -z "$PM2_BIN" ]; then
  echo "安装 PM2..."
  if [ -n "${npm_config_prefix:-}" ]; then
    PM2_PREFIX="$npm_config_prefix"
  else
    PM2_PREFIX="$(npm prefix --global)"
  fi
  npm_config_prefix="$PM2_PREFIX" npm install --global pm2
  PM2_BIN="$PM2_PREFIX/bin/pm2"
fi
[ -x "$PM2_BIN" ] || fail "未找到 PM2 可执行文件：$PM2_BIN"

echo "启动或更新 PM2 服务..."
"$PM2_BIN" startOrRestart "$APP_DIR/ecosystem.config.js" --only media-parser-site --update-env
"$PM2_BIN" save
"$PM2_BIN" status
echo "安装完成。访问 http://127.0.0.1:2570/"
echo "查看日志：$PM2_BIN logs media-parser-site"
