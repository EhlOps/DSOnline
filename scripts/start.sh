#!/bin/bash

export HOME=/home/vncuser
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export XDG_RUNTIME_DIR=/tmp/runtime-vncuser
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

# ── Configuration ─────────────────────────────────────────────────────────────
GEOMETRY="${VNC_GEOMETRY:-1280x720}"
NUM_PLAYERS="${NUM_PLAYERS:-2}"

# ── Player config directories (supports arbitrary N) ──────────────────────────
for i in $(seq 1 "$NUM_PLAYERS"); do
    mkdir -p "$HOME/.config/melonDS/player$i"
    mkdir -p "$HOME/.cache/player$i/openbox/sessions"

    # Per-player writable ROM directory inside the player volume.
    # ROMs are mounted read-only, so melonDS can't write saves next to them.
    # Symlinks here point at the real ROM files; melonDS writes .sav files
    # alongside the symlinks (which ARE writable), keeping saves per-player.
    roms_dir="$HOME/.config/melonDS/player$i/roms"
    mkdir -p "$roms_dir"
    for rom in "$HOME"/roms/*; do
        [ -f "$rom" ] || continue
        link="$roms_dir/$(basename "$rom")"
        [ -e "$link" ] || ln -s "$rom" "$link"
    done

    # Pre-seed melonDS.ini so the file browser opens the writable ROM dir.
    melon_conf="$HOME/.config/melonDS/player$i/melonDS"
    mkdir -p "$melon_conf"
    if [ ! -f "$melon_conf/melonDS.ini" ]; then
        printf '[General]\nLastROMFolder=%s\n' "$roms_dir" > "$melon_conf/melonDS.ini"
    fi
done

# ── Clean up stale VNC locks ──────────────────────────────────────────────────
for i in $(seq 1 "$NUM_PLAYERS"); do
    pkill -f "Xtigervnc :$i" 2>/dev/null || true
    rm -f "/tmp/.X${i}-lock" "/tmp/.X11-unix/X${i}" 2>/dev/null || true
done

# ── Start Xtigervnc servers directly (vncserver wrapper ignores -rfbauth) ─────
for i in $(seq 1 "$NUM_PLAYERS"); do
    Xtigervnc ":$i" \
        -rfbport "$((5900 + i))" \
        -geometry "$GEOMETRY" \
        -depth 24 \
        -SecurityTypes None \
        -localhost no &
    echo "[start] Xtigervnc :$i started on port $((5900 + i))"
done

# ── Give X servers a moment to initialize ─────────────────────────────────────
sleep 1

# ── Start window managers ─────────────────────────────────────────────────────
for i in $(seq 1 "$NUM_PLAYERS"); do
    DISPLAY=":$i" XDG_CACHE_HOME="$HOME/.cache/player$i" openbox-session &
done

# ── Launch melonDS instances ───────────────────────────────────────────────────
declare -a PIDS=()
for i in $(seq 1 "$NUM_PLAYERS"); do
    DISPLAY=":$i" XDG_CONFIG_HOME="$HOME/.config/melonDS/player$i" \
        LIBGL_ALWAYS_SOFTWARE=1 SDL_AUDIODRIVER=dummy \
        melonds &
    PIDS[$i]=$!
    echo "[start] Player $i melonDS started (PID ${PIDS[$i]})"
done

# ── Start noVNC websockify bridges ────────────────────────────────────────────
for i in $(seq 1 "$NUM_PLAYERS"); do
    novnc_port=$((6080 + i))
    vnc_port=$((5900 + i))
    websockify --web=/usr/share/novnc/ --blacklist-timeout=0 "$novnc_port" "localhost:$vnc_port" &
    echo "[start] Player $i VNC :$vnc_port → noVNC :$novnc_port"
done

# ── Shutdown handler ──────────────────────────────────────────────────────────
cleanup() {
    echo "[start] Shutting down..."
    for pid in "${PIDS[@]}"; do
        kill "$pid" 2>/dev/null || true
    done
    exit 0
}
trap cleanup SIGTERM SIGINT

# ── Watchdog loop ─────────────────────────────────────────────────────────────
# Checks every 5 seconds and restarts any melonDS instance that has exited.
# sleep runs in background so SIGTERM interrupts wait immediately.
while true; do
    for i in $(seq 1 "$NUM_PLAYERS"); do
        if ! kill -0 "${PIDS[$i]}" 2>/dev/null; then
            echo "[watchdog] Player $i melonDS exited, restarting..."
            DISPLAY=":$i" XDG_CONFIG_HOME="$HOME/.config/melonDS/player$i" \
                LIBGL_ALWAYS_SOFTWARE=1 SDL_AUDIODRIVER=dummy \
                melonds &
            PIDS[$i]=$!
        fi
    done
    sleep 5 &
    wait $! 2>/dev/null || true
done
