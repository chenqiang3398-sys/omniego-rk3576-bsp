#!/bin/bash -e

export DEBIAN_FRONTEND=noninteractive

: "${ROOTFS_HOSTNAME:=rk3576-ubuntu}"
: "${TARGET_USER:=linaro}"
: "${TARGET_PASSWORD:=linaro}"
: "${UBUNTU_PROFILE:=minimal}"

apt-get update
find /tmp/ubuntu-packages -type f -name '*.packages' -print0 \
	| sort -z \
	| xargs -0 cat \
	| sed '/^[[:space:]]*#/d;/^[[:space:]]*$/d' \
	| xargs -r apt-get install -y --no-install-recommends

# Verify the exact vendor payload selected for RK3576 before installation.
# Installing all .debs in one apt transaction lets apt order interdependent
# MPP/RGA/GStreamer packages and fails the image build on unresolved Depends.
if [ -f /tmp/ubuntu-packages/vendor-packages.sha256 ]; then
	(cd /tmp/ubuntu-packages && sha256sum -c vendor-packages.sha256)
fi
shopt -s nullglob
vendor_debs=(/tmp/ubuntu-packages/*.deb)
if [ "${#vendor_debs[@]}" -gt 0 ]; then
	apt-get install -y --no-install-recommends "${vendor_debs[@]}"
fi

# rknpu2.tar is the vendor's userspace runtime payload, not a Debian package.
# Extract only RK3576 runtime/tools/model files; do not import models for other
# SoCs or any unrelated files from the Debian rootfs.
if [ -f /tmp/ubuntu-packages/rknpu2-rk3576.tar ]; then
	tar -xf /tmp/ubuntu-packages/rknpu2-rk3576.tar -C / \
		./usr/lib/librknnrt.so \
		./usr/bin/rknn_common_test \
		./usr/bin/rknn_server \
		./usr/bin/restart_rknn.sh \
		./usr/bin/start_rknn.sh \
		./usr/share/model/dog_224x224.jpg \
		./usr/share/model/cat_224x224.jpg \
		./usr/share/model/RK3576/mobilenet_v1.rknn
	chmod 0755 /usr/bin/rknn_common_test /usr/bin/rknn_server \
		/usr/bin/restart_rknn.sh /usr/bin/start_rknn.sh
fi
ldconfig

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

if [ "$UBUNTU_PROFILE" = desktop ]; then
	# LightDM owns the X11 login lifecycle; Mali acceleration is added in P3.
	install -d -m 0755 /etc/lightdm/lightdm.conf.d
	cat > /etc/lightdm/lightdm.conf.d/50-rk3576.conf <<EOF
[Seat:*]
greeter-session=lightdm-gtk-greeter
user-session=xfce
EOF
	systemctl enable lightdm.service
	systemctl set-default graphical.target
else
	systemctl set-default multi-user.target
fi

# RKAIQ is included for the later MIPI-camera phase, but starting it without a
# connected sensor only creates repeated RKCIF errors. Enable it with the
# matching sensor/IQ file during board-camera integration.
systemctl disable rkaiq_3A.service 2>/dev/null || true

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
