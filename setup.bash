#!/bin/bash
# /opt/roboparty/setup.bash

# SPDX-License-Identifier: GPL-3.0
# Copyright (C) 2026 wentywenty

# Source this file to set up the RoboParty environment

export CMAKE_PREFIX_PATH="/opt/roboparty${CMAKE_PREFIX_PATH:+:$CMAKE_PREFIX_PATH}"
export PKG_CONFIG_PATH="/opt/roboparty/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"

# Add library and binary paths
export LD_LIBRARY_PATH="/opt/roboparty/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export PATH="/opt/roboparty/bin${PATH:+:$PATH}"

# Python
PYTHON_VER=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null)
if [ -n "$PYTHON_VER" ]; then
    export PYTHONPATH="/opt/roboparty/lib/python${PYTHON_VER}/site-packages${PYTHONPATH:+:$PYTHONPATH}"
fi

# AMENT: auto-source all package-level local_setup.bash under share/
if [ -d "/opt/roboparty/share" ]; then
    export AMENT_PREFIX_PATH="/opt/roboparty${AMENT_PREFIX_PATH:+:$AMENT_PREFIX_PATH}"
    for pkg_setup in /opt/roboparty/share/*/local_setup.bash; do
        [ -f "$pkg_setup" ] && source "$pkg_setup"
    done
fi
