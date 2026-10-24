#!/bin/bash
# Export the Web build and publish it to GitHub Pages (gh-pages branch).
set -euo pipefail
cd "$(dirname "$0")"

GODOT=/Applications/Godot.app/Contents/MacOS/Godot
mkdir -p build/web
"$GODOT" --headless --path . --export-release Web build/web/index.html

cd build/web
touch .nojekyll
rm -rf .git
git init -q -b gh-pages
git add -A
git commit -q -m "Web build $(date +%Y-%m-%d\ %H:%M)"
git remote add origin git@github.com:AnisimovIvan/tri-chasa-nochi.git
git push -q -f origin gh-pages
echo "Published: https://anisimovivan.github.io/tri-chasa-nochi/ (Pages updates in ~1 min)"
