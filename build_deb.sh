#!/bin/bash
# SPDX-License-Identifier: GPL-3.0
# Copyright (C) 2026 wentywenty
#
# Build RoboParty base deb package

set -e

echo "==> Installing build dependencies..."
sudo apt-get update
sudo apt-get install -y dpkg-dev debhelper devscripts python3

echo "==> Building deb package..."
dpkg-buildpackage -us -uc -b

echo "==> Moving deb to current directory..."
mv ../roboparty-base_*.deb . 2>/dev/null || true

echo "==> Done!"
ls -la roboparty-base_*.deb 2>/dev/null || echo "No .deb file found, check build output above."
