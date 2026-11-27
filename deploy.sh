#!/bin/bash
set -e

cd /home/deploy/zortfolio

echo "Pulling latest changes..."
git fetch origin
git reset --hard origin/dev

echo "Building..."
zig build -Doptimize=ReleaseFast

echo "Restarting..."
sudo systemctl restart zortfolio

echo "Deployment complete!"
