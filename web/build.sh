#!/bin/bash
set -e

cd "$(dirname "$0")"

echo "Building TypeScript web modules..."
npx -y esbuild src/index.ts src/dashboard.ts --bundle --outdir=dist --format=iife --external:crypto --minify

echo "Build complete: web/dist/index.js and web/dist/dashboard.js"
