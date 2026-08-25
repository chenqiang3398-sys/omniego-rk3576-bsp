#!/bin/bash -e

export DEBIAN_FRONTEND=noninteractive

: "${ROOTFS_HOSTNAME:=rk3576-ubuntu}"
: "${TARGET_USER:=linaro}"
: "${TARGET_PASSWORD:=linaro}"

apt-get update
xargs -r apt-get install -y --no-install-recommends < /tmp/base.packages

echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
update-locale LANG=en_US.UTF-8

echo "$ROOTFS_HOSTNAME" > /etc/hostname
cat > /etc/hosts <<EOF
127.0.0.1 localhost
127.0.1.1 $ROOTFS_HOSTNAME
::1 localhost ip6-localhost ip6-loopback
EOF

if ! id "$TARGET_USER" >/dev/null 2>&1; then
	useradd -m -s /bin/bash -G sudo,adm,video,render,audio "$TARGET_USER"
fi
echo "$TARGET_USER:$TARGET_PASSWORD" | chpasswd

install -d -m 0755 /etc/systemd/system/serial-getty@ttyFIQ0.service.d
cat > /etc/systemd/system/serial-getty@ttyFIQ0.service.d/override.conf <<'EOF'
[Service]
TTYPath=/dev/ttyFIQ0
EOF
systemctl enable serial-getty@ttyFIQ0.service

install -d -m 0755 /etc/systemd/system/ssh.service.d
cat > /etc/systemd/system/ssh.service.d/host-keys.conf <<'EOF'
[Service]
ExecStartPre=
ExecStartPre=/usr/bin/ssh-keygen -A
ExecStartPre=/usr/sbin/sshd -t
EOF
systemctl enable ssh.service
systemctl enable NetworkManager.service
systemctl set-default multi-user.target

cat > /etc/fstab <<'EOF'
PARTUUID=614e0000-0000-4b53-8000-1d28000054a9 / ext4 defaults,noatime 0 1
LABEL=oem /oem ext4 defaults,nofail 0 2
LABEL=userdata /userdata ext4 defaults,nofail 0 2
proc /proc proc defaults 0 0
debugfs /sys/kernel/debug debugfs defaults,nofail 0 0
EOF
mkdir -p /oem /userdata /sys/kernel/debug

cat > /etc/issue <<'EOF'
Ubuntu 24.04 LTS \n \l
EOF

rm -f /etc/ssh/ssh_host_*
rm -f /etc/machine-id /var/lib/dbus/machine-id
touch /etc/machine-id
ln -sf /etc/machine-id /var/lib/dbus/machine-id

apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
