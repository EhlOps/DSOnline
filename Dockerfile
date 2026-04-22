FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive

# TARGETARCH is injected by Docker at build time (e.g. "arm64" or "amd64").
# Used to pick the correct melonDS AppImage for the host architecture.
ARG TARGETARCH

# Install system packages and download melonDS AppImage in one layer.
# wget/unzip are purged after use so they don't bloat the final image.
# --no-install-recommends trims ~100MB of GTK/doc extras.
# openbox replaces xfce4 (~150-200MB saved) — melonDS only needs a window manager.
RUN apt-get update && apt-get install -y --no-install-recommends \
    openbox \
    python3-xdg \
    xterm \
    tigervnc-standalone-server \
    tigervnc-common \
    novnc \
    websockify \
    dbus-x11 \
    x11-xserver-utils \
    libsdl2-2.0-0 \
    libgl1 \
    libegl1 \
    libopengl0 \
    libgl1-mesa-dri \
    libslirp0 \
    fuse \
    squashfs-tools \
    wget \
    unzip \
    && ARCH=$([ "$TARGETARCH" = "arm64" ] && echo "aarch64" || echo "x86_64") \
    && DOWNLOAD_URL=$(wget -qO- "https://api.github.com/repos/melonDS-emu/melonDS/releases/latest" \
        | grep -o "https://[^\"]*appimage-${ARCH}[^\"]*\.zip" | head -1) \
    && wget -q -O /tmp/melonds.zip "$DOWNLOAD_URL" \
    && unzip -j /tmp/melonds.zip "*.AppImage" -d /tmp/melonds_ex \
    && mv /tmp/melonds_ex/*.AppImage /tmp/melonds.AppImage \
    && chmod +x /tmp/melonds.AppImage \
    && cd /tmp && /tmp/melonds.AppImage --appimage-extract \
    && mv /tmp/squashfs-root /opt/melonds \
    && printf '#!/bin/bash\nexec /opt/melonds/AppRun "$@"\n' > /usr/local/bin/melonds \
    && chmod +x /usr/local/bin/melonds \
    && rm -rf /tmp/melonds.zip /tmp/melonds_ex /tmp/melonds.AppImage \
    && ldconfig \
    && apt-get purge -y --auto-remove wget unzip squashfs-tools \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /tmp/.X11-unix && chmod 1777 /tmp/.X11-unix

RUN useradd -m -s /bin/bash -u 1000 vncuser

USER vncuser
WORKDIR /home/vncuser

RUN mkdir -p \
    ~/.vnc \
    ~/.config/openbox \
    ~/.config/melonDS/player1 \
    ~/.config/melonDS/player2 \
    ~/.config/melonDS/player3 \
    ~/.config/melonDS/player4 \
    ~/.config/melonDS/player5 \
    ~/.config/melonDS/player6 \
    ~/.config/melonDS/player7 \
    ~/.config/melonDS/player8 \
    ~/roms \
    && printf '#!/bin/bash\nexec openbox-session\n' > ~/.vnc/xstartup \
    && chmod +x ~/.vnc/xstartup \
    && printf '<openbox_menu>\n  <menu id="root-menu" label="Desktop">\n    <item label="Open Terminal">\n      <action name="Execute"><command>xterm</command></action>\n    </item>\n  </menu>\n</openbox_menu>\n' > ~/.config/openbox/menu.xml

COPY --chown=vncuser:vncuser scripts/start.sh /home/vncuser/start.sh
RUN chmod +x /home/vncuser/start.sh

# Healthy when Player 1 noVNC port is accepting connections
HEALTHCHECK --interval=30s --timeout=10s --start-period=20s --retries=3 \
    CMD bash -c 'exec 3<>/dev/tcp/localhost/5901'

EXPOSE 5901 5902 6081 6082
CMD ["/home/vncuser/start.sh"]
