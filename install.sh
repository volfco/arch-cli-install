#!/bin/bash

set -e

if [[ -e /dev/nvme0n1 ]]; then
  BASE="/dev/nvme0n1"
  EFI_PART="/dev/nvme0n1p1"
  SWP_PART="/dev/nvme0n1p2"
  ROT_PART="/dev/nvme0n1p3"
  LIB_PART="/dev/nvme0n1p5"
  OPT_PART="/dev/nvme0n1p6"
  FS_TYPE="f2fs"
else
  BASE="/dev/sda"
  EFI_PART="/dev/sda1"
  SWP_PART="/dev/sda2"
  ROT_PART="/dev/sda3"
  LIB_PART="/dev/sda5"
  OPT_PART="/dev/sda6"
  FS_TYPE="xfs"
fi

# Wipe the existing disk
wipefs --all --force "${BASE}"

# Filesystem mount warning
echo "This script will create and format the partitions as follows:"
echo "${EFI_PART} - 512Mib will be mounted as /boot/efi"
echo "${SWP_PART} - 8GiB will be used as swap"

# to create the partitions programatically (rather than manually)
# https://superuser.com/a/984637

sed -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/' <<EOF | fdisk "${BASE}"
  o # clear the in memory partition table
  n # new partition
  p # primary partition
  1 # partition number 1
    # default - start at beginning of disk
  +512M # 512 MB boot parttion
  N # Remove Label

  n # new partition
  p # primary partition
  2 # partion number 2
    # default, start immediately after preceding partition
  +8G # 8 GB swap parttion
  Y # Remove Label

  a # make a partition bootable
  1 # bootable partition is partition 1 -- /dev/sda1

  p # print the in-memory partition table
  w # write the partition table
EOF

# Format the partitions
mkfs.fat -F32 "${EFI_PART}"

# if $1 is unset, then we're going to do full disk
if [[ -z "$1" ]]; then
  echo "${ROT_PART} - rest of space will be mounted as /"
  sed -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/' <<EOF | fdisk "${BASE}"
  n # new partition
  p # primary partition
  3 # partion number 3
    # default, start immediately after preceding partition
    # default, extend partition to end of disk

  p # print the in-memory partition table
  w # write the partition table
  q # and we're done
EOF

  # format /
  "mkfs.$FS_TYPE" -f "${ROT_PART}"

elif [[ "$1" == "container" ]]; then
  echo "${ROT_PART} - 40G mounted as /"
  echo "${LIB_PART} - 40G mounted as /var/lib"
  echo "${OPT_PART} - Rest mounted as /opt"

  sed -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/' <<EOF | fdisk "${BASE}"
  n # new partition
  p # primary partition
  3 # partion number 3
    # default, start immediately after preceding partition
  +40G # Make 40G Disk
  Y # Say Yes (if prompted. if not, doesn't do anything)

  n # new partition
  e # extended partition
    # default first sector
    # last sector of desk

  n # new partition
    # default, start immediately after preceding partition (fdisk detects that we're in extended land)
  +40G # for /var/lib (docker & podman)

  n # new partition
    # default, start immediately after preceding partition (fdisk detects that we're in extended land)
    # rest of disk

  p # print the in-memory partition table
  w # write the partition table
EOF

  # Format /, /var/lib, /opt
  "mkfs.$FS_TYPE" -f "${ROT_PART}"
  "mkfs.$FS_TYPE" -f "${LIB_PART}"
  "mkfs.$FS_TYPE" -f "${OPT_PART}"
fi

# Set up time
timedatectl set-ntp true

# Set Mirror
echo "Server = https://ftp.osuosl.org/pub/archlinux/\$repo/os/\$arch" >/etc/pacman.d/mirrorlist
echo "Server = https://mirrors.rit.edu/archlinux/\$repo/os/\$arch" >>/etc/pacman.d/mirrorlist

# Initate pacman keyring
pacman-key --init
pacman-key --populate archlinux
# pacman-key --refresh-keys

# Mount the partitions
mount "${ROT_PART}" /mnt
if [[ -e "${LIB_PART}" ]]; then
  mount "${LIB_PART}" /mnt/var/lib
fi
if [[ -e "${OPT_PART}" ]]; then
  mount "${OPT_PART}" /mnt/opt
fi
mkdir -pv /mnt/boot/efi
mount "${EFI_PART}" /mnt/boot/efi
mkswap "${SWP_PART}"
swapon "${SWP_PART}"

# Install Arch Linux
pacstrap /mnt base linux linux-firmware linux-headers ethtool efibootmgr grub os-prober intel-ucode amd-ucode openssh mkinitcpio vi nano xfsprogs f2fs-tools git fakeroot binutils sudo

# Generate fstab
genfstab -U /mnt >>/mnt/etc/fstab

# Chroot into new system
arch-chroot /mnt /bin/bash <<"EOT"
# timezone
ln -sf /usr/share/zoneinfo/America/Los_Angeles /etc/localtime
hwclock --systohc
# system locale
sed -i '/en_US.UTF-8 UTF-8/s/^#//g' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" >> /etc/locale.conf
# TODO Hostname?
# make init disk
mkinitcpio -P

# bootloader
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=arch
grub-mkconfig -o /boot/grub/grub.cfg

#sed -i 'GRUB_CMDLINE_LINUX_DEFAULT=' /boot/grub/grub.cfg

ACTIVE_NIC=$(networkctl --no-pager --no-legend list | grep routable | awk '{print $2}')
echo -e "[Match]\nName=$ACTIVE_NIC\n\n[Network]\nDHCP=yes" > /etc/systemd/network/20-wired.network

# root password
echo -e "password\npassword" | passwd
mkdir -p /root/.ssh
echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDCT+nucANjleLvdumjMM3+2NYUGepV4492XwvMVLOEjiVoQmquhqvhAPUQ8vF7Y/wBKBJy0uVRt433eZYgFEilJ8SnaiUq/pHy15dzhdLuEkiiLLW3yzxLfS7DUDASfRX9mNBlE/WZSBJsk7lgjMr93rm9d3KUxW5CH8BSF+RMZ1r2Rto+c5BG8NlL4l3XiHhNtIrOjuycgyjVUuIvy9CBBbKxcYVo9c2L9iM/s5BcffmTh9JmVZ8wJhSqI9yLXAgFEvFoDAcUkxW1le9WWbU+Z8MQU4HU1u1RnJ3CFkGy8zdDkkhm/AIZd3LZw5TSh1d8qgN7Hp6ETuLjPtJem/FckVdwNJWQqmkwrXd6xOwcpkiBqH6gX/1Jy+f0gW0rP0yG8x6NiWMQNNYeI2ZwGk9DEdVN0QH6OOcdSkn+pU8YjcyDbQTBRqb0jfb22SAz2OUSlupXU003pl3PAZQRnFSSma0J6WJpuf7IEeNCnR2e2wgfXt8nPkzLdMEsAXAVGbE=" > /root/.ssh/authorized_keys

systemctl enable systemd-networkd.service
systemctl enable systemd-resolved.service
systemctl enable sshd.service

echo "nobody ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

cd /tmp
git clone https://aur.archlinux.org/trizen.git
chmod 777 -R /tmp/trizen
cd /tmp/trizen
echo -e "y" | sudo -u nobody HOME=/tmp makepkg -si

lspci | grep I219-V > /dev/null && sudo -u nobody HOME=/tmp trizen -S --noconfirm e1000e-dkms


EOT
