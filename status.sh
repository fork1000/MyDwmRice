#!/bin/sh
# Get screen width
SCREEN_WIDTH=$(xrandr | grep '*' | awk '{print $1}' | cut -d 'x' -f 1)
[ -z "$SCREEN_WIDTH" ] && SCREEN_WIDTH=1920

# Approximate character width
CHAR_WIDTH=9
TOTAL_CHARS=$((SCREEN_WIDTH / CHAR_WIDTH))

# File to store our virtual brightness counter
BRIGHT_FILE="/tmp/dwm_brightness_level"

# Initialize file if it doesn't exist
if [ ! -f "$BRIGHT_FILE" ]; then
    # Try to get initial value from hardware, otherwise start at 50
    RAW=$(brightnessctl get 2>/dev/null)
    MAX=$(brightnessctl max 2>/dev/null)
    if [ -n "$RAW" ] && [ -n "$MAX" ] && [ "$MAX" -gt 0 ]; then
        echo $(( (RAW * 100) / MAX )) > "$BRIGHT_FILE"
    else
        echo "50" > "$BRIGHT_FILE"
    fi
fi

# --- ACTION HANDLERS ---
if [ "$1" = "vol_up" ]; then
    VOL=$(pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null | head -n 1 | grep -o '[0-9]\+%' | head -n 1 | tr -d '%')
    [ -z "$VOL" ] && VOL=0
    if [ "$VOL" -ge 100 ]; then 
        TARGET=0 
    else 
        TARGET=$((VOL + 10))
        [ "$TARGET" -gt 100 ] && TARGET=100 
    fi
    pactl set-sink-volume @DEFAULT_SINK@ ${TARGET}% >/dev/null 2>&1
    pactl set-sink-mute @DEFAULT_SINK@ 0 >/dev/null 2>&1
    exit 0

elif [ "$1" = "vol_mute" ]; then
    pactl set-sink-mute @DEFAULT_SINK@ toggle >/dev/null 2>&1
    exit 0

elif [ "$1" = "bright_up" ]; then
    CURRENT=$(cat "$BRIGHT_FILE")
    
    if [ "$CURRENT" -ge 100 ]; then
        NEXT=1
    elif [ "$CURRENT" -le 1 ]; then
        NEXT=10
    else
        NEXT=$((CURRENT + 10))
        [ "$NEXT" -gt 100 ] && NEXT=100
    fi
    
    echo "$NEXT" > "$BRIGHT_FILE"
    
    # Apply to hardware using raw value to avoid rounding issues
    MAX=$(brightnessctl max 2>/dev/null)
    if [ -n "$MAX" ] && [ "$MAX" -gt 0 ]; then
        RAW_TARGET=$(( (NEXT * MAX + 50) / 100 ))
        brightnessctl set "${RAW_TARGET}" >/dev/null 2>&1
    fi
    exit 0
fi

# --- DISPLAY LOOP ---
while true; do
    # --- BATTERY ---
    BAT=$(cat /sys/class/power_supply/BAT0/capacity 2>/dev/null)
    BAT_STATUS=$(cat /sys/class/power_supply/BAT0/status 2>/dev/null)
    if [ "$BAT_STATUS" = "Charging" ]; then
        BAT_STR="[${BAT}%]"
    else
        BAT_STR="${BAT}%"
    fi

    # --- WIFI STATUS ---
    WIFI_STR="[disconnected]"
    for iface in /sys/class/net/*; do
        if [ -d "$iface/wireless" ]; then
            STATE=$(cat "$iface/operstate" 2>/dev/null)
            if [ "$STATE" = "up" ] || [ "$STATE" = "unknown" ]; then
                WIFI_STR="[connected]"
            fi
            break
        fi
    done

    # --- VOLUME ---
    VOL=$(pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null | head -n 1 | grep -o '[0-9]\+%' | head -n 1 | tr -d '%')
    MUTED=$(pactl get-sink-mute @DEFAULT_SINK@ 2>/dev/null | grep -o 'yes')
    if [ "$MUTED" = "yes" ]; then
        VOL_STR="[M]"
    else
        [ -z "$VOL" ] && VOL=0
        VOL_STR="[V${VOL}]"
    fi

    # --- BRIGHTNESS (VIRTUAL COUNTER) ---
    BRIGHT=$(cat "$BRIGHT_FILE")
    [ -z "$BRIGHT" ] && BRIGHT=0
    BRIGHT_STR="[B${BRIGHT}]"

    TIME_STR=$(date +'%H:%M:%S')

    # --- POSITIONING ---
    LEFT_OFFSET=18
    LEFT_PAD=$(( (TOTAL_CHARS / 2) - LEFT_OFFSET ))
    
    RIGHT_CONTENT="${WIFI_STR} ${VOL_STR} ${BRIGHT_STR} ${BAT_STR}"
    RIGHT_PAD=$(( TOTAL_CHARS - LEFT_PAD - ${#TIME_STR} - ${#RIGHT_CONTENT} ))

    [ "$LEFT_PAD" -lt 0 ] && LEFT_PAD=0
    [ "$RIGHT_PAD" -lt 0 ] && RIGHT_PAD=0

    xsetroot -name "$(printf "%${LEFT_PAD}s" '')$TIME_STR$(printf "%${RIGHT_PAD}s" '')$RIGHT_CONTENT"
    sleep 0.001
done
