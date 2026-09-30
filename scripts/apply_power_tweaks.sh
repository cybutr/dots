#!/usr/bin/env bash
# Power/performance tweaks for this laptop (Intel CometLake-H + Nvidia Quadro
# T2000 hybrid, Lenovo ThinkPad w/ thinkpad_acpi, CachyOS/Arch base).
#
# Review this file before running it. Run with: sudo bash apply_power_tweaks.sh
# Every block is independently commented with what it does and how to revert.
set -e

echo "== 1. Nvidia runtime power management =="
# Currently: Runtime D3 status: Disabled by default (idle draw ~2.2W that
# could drop further). Enables fine-grained dynamic power management.
# REVERT: rm /etc/modprobe.d/nvidia-pm.conf && mkinitcpio -P && reboot
if [ -f /etc/modprobe.d/nvidia-pm.conf ] && grep -q "NVreg_DynamicPowerManagement=0x02" /etc/modprobe.d/nvidia-pm.conf; then
    echo "  -> already applied, skipping (no need to rebuild initramfs again)."
else
    cat > /etc/modprobe.d/nvidia-pm.conf <<'EOF'
options nvidia NVreg_DynamicPowerManagement=0x02
EOF
    # nvidia-drm modeset=1 is already set in your existing nvidia.conf — untouched.
    mkinitcpio -P
    echo "  -> written /etc/modprobe.d/nvidia-pm.conf, initramfs regenerated."
fi
echo "  -> REBOOT required (if not done yet) to verify with:"
echo "       cat /proc/driver/nvidia/gpus/*/power | grep Runtime"
echo "       nvidia-smi --query-gpu=power.draw --format=csv"

echo
echo "== 2. auto-cpufreq (OPTIONAL — DISABLED BY DEFAULT, READ FIRST) =="
# auto-cpufreq REPLACES power-profiles-daemon (it disables/masks it during
# its own install). Your topbar's power-profile chip and eco_daemon.py both
# call `powerprofilesctl`, which stops working once power-profiles-daemon is
# gone — you would lose that chip/feature until reverted.
# Available directly from the cachyos repo already in your pacman config
# (confirmed: `cachyos/auto-cpufreq 3.1.0-1`), no AUR build needed.
# Uncomment the block below ONLY if you're fine with that tradeoff:
#
# pacman -S --noconfirm auto-cpufreq
# systemctl disable --now power-profiles-daemon
# auto-cpufreq --install
#
# REVERT: auto-cpufreq --remove && systemctl enable --now power-profiles-daemon

echo
echo "== 3. PCIe ASPM: skipped =="
# This laptop's firmware does not hand ASPM control to the OS — the kernel
# rejects the write with -EPERM regardless of privilege (confirmed by
# testing; not a permissions issue). Forcing it via the pcie_aspm=force boot
# parameter is a known stability risk (PCIe/NVMe misbehavior) on hardware the
# firmware didn't sign off on, so this is intentionally left alone.
echo "  -> not supported by this hardware's firmware, left untouched."

echo
echo "== 4. Battery charge threshold -> 80% (extends battery lifespan) =="
# Your battery driver (thinkpad_acpi) supports charge_control_end_threshold.
# Caps charging at 80% instead of 100% — trades some runtime-per-charge for
# significantly slower long-term capacity fade.
# REVERT: systemctl disable --now battery-charge-limit.service && rm /etc/systemd/system/battery-charge-limit.service
#         echo 100 > /sys/class/power_supply/BAT0/charge_control_end_threshold
cat > /etc/systemd/system/battery-charge-limit.service <<'EOF'
[Unit]
Description=Set battery charge threshold to 80%
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo 80 > /sys/class/power_supply/BAT0/charge_control_end_threshold'

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now battery-charge-limit.service
echo "  -> current threshold: $(cat /sys/class/power_supply/BAT0/charge_control_end_threshold)"

echo
echo "== 5. earlyoom (kills the biggest memory hog before a hard freeze) =="
# Complementary to ananicy-cpp (which only reprioritizes, doesn't kill).
# REVERT: systemctl disable --now earlyoom && pacman -Rns earlyoom
pacman -S --noconfirm --needed earlyoom
systemctl enable --now earlyoom
echo "  -> $(systemctl is-active earlyoom)"

echo
echo "== 6. Extra ananicy-cpp rules for common heavy apps =="
# Staged at ~/.config/hypr/eco/zz-heavy-apps.rules (same pattern as the
# existing zz-spotify.rules override) — installs it system-wide.
# REVERT: rm /etc/ananicy.d/zz-heavy-apps.rules && systemctl restart ananicy-cpp
cp /home/czeddaru/.config/hypr/eco/zz-heavy-apps.rules /etc/ananicy.d/zz-heavy-apps.rules
systemctl restart ananicy-cpp
echo "  -> $(systemctl is-active ananicy-cpp)"

echo
echo "== 7. vm.swappiness / vfs_cache_pressure: already tuned, skipped =="
# Checked before proposing anything: swappiness is already 150 and
# vfs_cache_pressure already 50 (both non-default), set system-wide by the
# cachyos-settings package (/usr/lib/sysctl.d/70-cachyos-settings.conf) —
# already the sane zram-tuned values this item would have proposed. Left
# untouched to avoid a redundant/conflicting sysctl.d override.
echo "  -> already tuned by cachyos-settings, nothing to change."

echo
echo "== 8. irqbalance (spreads IRQ load across all 12 threads) =="
# Not installed. On this 6C/12T laptop, cheap and safe — reversible, no
# reboot needed, immediate effect.
# REVERT: systemctl disable --now irqbalance && pacman -Rns irqbalance
pacman -S --noconfirm --needed irqbalance
systemctl enable --now irqbalance
echo "  -> $(systemctl is-active irqbalance)"

echo
echo "== 9. CPU governor / EPP: already sane, skipped =="
# intel_pstate active, governor=powersave (correct modern default — HWP lets
# frequency still scale up under load, unlike legacy acpi-cpufreq powersave),
# energy_performance_preference=balance_performance (a sane middle default).
# Nothing here is misconfigured — left untouched rather than change it just
# to change it.
echo "  -> intel_pstate + powersave + balance_performance already correct."

echo
echo "== 10. Leaked-process re-scan: nothing new found =="
# Re-scanned all scripts under ~/.config/hypr/scripts for while-true/polling
# loops not already covered: every long-lived Process command launched from
# the QML files already routes through scripts/quickshell/lifeline.sh (54
# call sites, TopBar.qml has zero unwrapped inotifywait/--follow/dbus-monitor
# commands left). The exec.conf-launched daemons (eco_daemon.py,
# leak_reaper.py, ws_accent.py, smartws.py) are single-instance via their own
# pidfile/lock, confirmed still exactly 1 copy each running. No action taken.
echo "  -> no new leak sources found, nothing to fix."

echo
echo "All done. Reboot for the Nvidia change to take effect."
