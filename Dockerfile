# syntax=docker/dockerfile:1
#
# keygen — single-container image (no docker-compose)
#
# Runs two processes under supervisord inside ONE container:
#   keygen-api  -> docker/serve_cors.py    (CORS-enabled wrapper around bin/serve.py, port 8080)
#   keygen-web  -> `python3 -m http.server` serving the static web/ frontend (container port 8000)
#
# web/js/settings.js is required by the frontend but is .gitignored upstream.
# docker/entrypoint.sh generates it at container start from
# web/js/settings.js.example, substituting the KEYGEN_ENDPOINT env var so the
# browser knows where to find the API.

FROM ubuntu:24.04

LABEL org.opencontainers.image.source="https://github.com/ervanalb/keygen" \
      org.opencontainers.image.description="keygen: OpenSCAD tools for generating physical keys"

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PYTHONUNBUFFERED=1 \
    WEB_PORT=8000 \
    KEYGEN_ENDPOINT=http://localhost:8080 \
    CORS_ALLOW_ORIGIN=*

# ---------------------------------------------------------------------------
# Pinned system dependencies (versions as published in Ubuntu 24.04 "noble")
#   python3    - runs bin/*.py, bin/serve.py, and the static file server
#   make       - builds build/keys.json from the repo's Makefile
#   openscad   - renders .scad -> .stl (invoked by bin/keygen.py)
#   xvfb       - virtual framebuffer; openscad's Qt/OpenGL stack needs a
#                display even for headless CLI STL export
#   supervisor - runs keygen-api + keygen-web as one foreground process tree,
#                forwarding signals so `docker stop` shuts down cleanly
# ---------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
        python3=3.12.3-0ubuntu2.1 \
        make=4.3-4.1build2 \
        openscad=2021.01-6build4 \
        xvfb=2:21.1.12-1ubuntu1.6 \
        supervisor=4.2.5-1ubuntu0.1 \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# openscad needs a display (see above) even though it's only ever used here
# from the CLI for STL export. Rename the real binary and install a thin
# wrapper as `openscad` (earlier on $PATH) that transparently runs it under
# xvfb-run, so bin/keygen.py works completely unmodified.
RUN mv /usr/bin/openscad /usr/bin/openscad.real
COPY docker/openscad-wrapper.sh /usr/local/bin/openscad
RUN chmod +x /usr/local/bin/openscad

# Non-root runtime user. UID 1000 is already taken by the 'ubuntu' user that
# ships in the official ubuntu:24.04 image, so use a higher, unlikely-to-clash UID/GID.
RUN useradd --create-home --home-dir /home/keygen --shell /usr/sbin/nologin --uid 10001 --user-group keygen

WORKDIR /app
COPY --chown=keygen:keygen . .

# Pre-build the key catalog at image-build time so containers start instantly.
# (entrypoint.sh also runs this on start, so a bind-mounted dev checkout with
# no build/keys.json yet still works.)
RUN chmod +x bin/*.py docker/entrypoint.sh docker/serve_cors.py && \
    make build/keys.json && \
    chown -R keygen:keygen /app

COPY docker/supervisord.conf /etc/supervisor/supervisord.conf

# NOTE: no `USER keygen` here. supervisord (PID 1) must run as root so it
# can open /dev/stdout and /dev/stderr to wire up child logging (a non-root
# process can't reopen those by path — see docker/supervisord.conf for why).
# The actual application processes (keygen-api, keygen-web) still run as
# the unprivileged 'keygen' user, via supervisord's per-program `user=`
# directive.
ENV HOME=/home/keygen

EXPOSE 8000 8080

ENTRYPOINT ["/app/docker/entrypoint.sh"]
CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/supervisord.conf"]
