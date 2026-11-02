#!/bin/bash
# Rebuilds the root filesystem on every start. Only /home persists.
set -euo pipefail

USER_NAME=jared
USER_ID=1000
HOME_DIR=/home/$USER_NAME
STATE_DIR=/home/.devbox

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  build-essential ca-certificates curl git gnupg iproute2 jq less locales openssh-client \
  openssh-server procps ripgrep sudo tmux tzdata unzip vim-tiny zsh

if ! id "$USER_NAME" >/dev/null 2>&1; then
  groupadd --gid "$USER_ID" "$USER_NAME"
  useradd --uid "$USER_ID" --gid "$USER_ID" --shell /usr/bin/zsh --home-dir "$HOME_DIR" --no-create-home "$USER_NAME"
fi
echo "$USER_NAME ALL=(ALL) NOPASSWD:ALL" >/etc/sudoers.d/$USER_NAME
if [ ! -d "$HOME_DIR" ]; then
  install -d -o "$USER_ID" -g "$USER_ID" -m 0755 "$HOME_DIR"
fi

install -d -m 0700 "$STATE_DIR/ssh"
for type in ed25519 rsa; do
  key="$STATE_DIR/ssh/ssh_host_${type}_key"
  [ -f "$key" ] || ssh-keygen -q -t "$type" -N '' -f "$key"
done
install -d -m 0755 /etc/ssh/authorized_keys /run/sshd
install -m 0644 /etc/devbox/authorized_keys /etc/ssh/authorized_keys/$USER_NAME
cat >/etc/ssh/sshd_config.d/devbox.conf <<EOF
HostKey $STATE_DIR/ssh/ssh_host_ed25519_key
HostKey $STATE_DIR/ssh/ssh_host_rsa_key
AuthorizedKeysFile .ssh/authorized_keys /etc/ssh/authorized_keys/%u
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
AllowUsers $USER_NAME
EOF

/usr/sbin/sshd -D -e &
sshd_pid=$!

# Herdr lives in ~/.local/bin once `herdr machine add` has installed it.
(
  while true; do
    runuser -u "$USER_NAME" -- env -i HOME="$HOME_DIR" USER="$USER_NAME" SHELL=/usr/bin/zsh \
      LANG=C.UTF-8 TZ="${TZ:-UTC}" PATH="$HOME_DIR/.local/bin:/usr/local/bin:/usr/bin:/bin" \
      sh -c 'command -v herdr >/dev/null && exec herdr server' || true
    sleep 30
  done
) &

trap 'kill -TERM "$sshd_pid" 2>/dev/null' TERM INT
wait "$sshd_pid"
