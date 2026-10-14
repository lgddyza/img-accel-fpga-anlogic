#!/bin/sh
# Start the AI viewer and restore the original HDMI viewer if it exits.
connector=${1:-188}
sleep 2
sh /root/jpeg_rk/start_jpeg_hdmi_ai.sh "$connector" \
    > /root/road_damage_yolov8n/hdmi_ai_ui_fixed.log 2>&1
exec sh /root/jpeg_rk/start_jpeg_hdmi_60.sh "$connector" \
    > /root/road_damage_yolov8n/hdmi_ai_ui_fallback.log 2>&1
