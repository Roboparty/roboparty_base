#!/bin/bash
# $ROBOOS_PREFIX/setup.bash

# SPDX-License-Identifier: GPL-3.0
# Copyright (C) 2026 wentywenty

# Source this file to set up the RoboOS environment

ROBOOS_PREFIX="${ROBOOS_PREFIX:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
export ROBOOS_PREFIX

export CMAKE_PREFIX_PATH="$ROBOOS_PREFIX${CMAKE_PREFIX_PATH:+:$CMAKE_PREFIX_PATH}"
export PKG_CONFIG_PATH="$ROBOOS_PREFIX/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"

# Add library and binary paths
export LD_LIBRARY_PATH="$ROBOOS_PREFIX/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export PATH="$ROBOOS_PREFIX/bin${PATH:+:$PATH}"

# Python
PYTHON_VER=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null)
if [ -n "$PYTHON_VER" ]; then
    export PYTHONPATH="$ROBOOS_PREFIX/lib/python${PYTHON_VER}/site-packages${PYTHONPATH:+:$PYTHONPATH}"
fi

# AMENT: auto-source all package-level local_setup.bash under share/
if [ -d "$ROBOOS_PREFIX/share" ]; then
    export AMENT_PREFIX_PATH="$ROBOOS_PREFIX${AMENT_PREFIX_PATH:+:$AMENT_PREFIX_PATH}"
    for pkg_setup in "$ROBOOS_PREFIX"/share/*/local_setup.bash; do
        [ -f "$pkg_setup" ] && source "$pkg_setup"
    done
fi
