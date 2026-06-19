#!/bin/sh
# Transparent wrapper: openscad's Qt/OpenGL stack requires a display even
# for plain CLI STL export. xvfb-run spins up a throwaway virtual
# framebuffer for the duration of the call, then tears it down.
#
# Installed as /usr/local/bin/openscad (ahead of the real binary, which is
# renamed to /usr/bin/openscad.real), so callers like bin/keygen.py that
# simply invoke "openscad" on $PATH need no changes.
exec xvfb-run --auto-servernum --server-args="-screen 0 1024x768x24" /usr/bin/openscad.real "$@"
