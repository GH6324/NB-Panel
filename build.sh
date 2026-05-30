#!/bin/bash

# NB面板 编译脚本
set -e

echo "=== NB面板 编译 ==="

# 1. 前端构建
echo "构建前端..."
cd web
npm install --ignore-scripts
npx vite build --outDir ../cmd/server/dist --emptyOutDir
cd ..

# 2. Go 编译
echo "编译 Go..."
export PATH="/usr/local/go/bin:$PATH"
CGO_ENABLED=1 go build -ldflags="-s -w" -trimpath -o nb-panel ./cmd/server/

echo "✅ 编译完成: nb-panel"
ls -lh nb-panel
