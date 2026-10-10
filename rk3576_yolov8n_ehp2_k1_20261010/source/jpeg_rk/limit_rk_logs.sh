#!/bin/sh
# Bound RK system logs after a stale PCIe BAR caused a kernel-message storm.
set -eu

mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/30-jpeg-demo-size.conf <<'EOF'
[Journal]
SystemMaxUse=128M
SystemKeepFree=1G
EOF

# Kernel messages remain available through journalctl -k. Do not write a
# second unbounded copy into syslog and kern.log on this image.
if grep -q '^module(load="imklog")' /etc/rsyslog.conf; then
    cp -n /etc/rsyslog.conf /etc/rsyslog.conf.before-jpeg-demo
    sed -i 's/^module(load="imklog")/# module(load="imklog")  # kernel retained in journald/' \
        /etc/rsyslog.conf
fi

systemctl restart systemd-journald
systemctl restart rsyslog
journalctl --rotate >/dev/null
journalctl --vacuum-size=128M >/dev/null
df -h /root
journalctl --disk-usage
