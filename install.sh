#!/bin/bash

if [[ -e /dev/nvme0n1 ]]; then
  BASE="/dev/nvme0n1"
  EFI_PART="/dev/nvme0n1p1"
  SWP_PART="/dev/nvme0n1p2"
  ROT_PART="/dev/nvme0n1p3"
  FS_TYPE="f2fs"
else
  BASE="/dev/sda"
  EFI_PART="/dev/sda1"
  SWP_PART="/dev/sda2"
  ROT_PART="/dev/sda3"
  FS_TYPE="xfs"
fi

# Wipe the existing disk
wipefs -af "$BASE"

# Filesystem mount warning
echo "This script will create and format the partitions as follows:"
echo "$EFI_PART - 512Mib will be mounted as /boot/efi"
echo "$SWP_PART - 8GiB will be used as swap"
echo "$ROT_PART - rest of space will be mounted as /"

sleep 10


sed -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/' << EOF | gdisk "$BASE"
  o # clear the in memory partition table
  y # answer yes
  
  n # new partition
  1 # partition number 1
  #  # default - start at beginning of disk 
  +512M # 512 MB boot parttion
  EF00 # File System type (Linux filesystem)
  
  n # new partition
  2  # partion number 2
  #  # default, start immediately after preceding partition
  +8G # 8 GB swap parttion
  8300 # File System type (Linux filesystem)
  
  n # new partition
  3 # partion number 3
    # default, start immediately after preceding partition
    # default, extend partition to end of disk
  8300 # File System type (Linux filesystem)
  
  p # print the in-memory partition table
  w # write the partition table
  y # answer yes
  q # and we're done
EOF

# Format the partitions
"mkfs.$FS_TYPE" -f "$ROT_PART"
mkfs.vfat -F32 -n EFI "$EFI_PART"

# Set up time
timedatectl set-ntp true

# Set Mirror
echo "Server = https://ftp.osuosl.org/pub/archlinux/\$repo/os/\$arch" > /etc/pacman.d/mirrorlist
echo "Server = https://mirrors.rit.edu/archlinux/\$repo/os/\$arch" >> /etc/pacman.d/mirrorlist

# Initate pacman keyring
# pacman-key --init
# pacman-key --populate archlinux
# pacman-key --refresh-keys

# Mount the partitions
mount "$ROT_PART" /mnt
mkdir -pv /mnt/boot
mount "$EFI_PART" /mnt/boot
mkswap "$SWP_PART"
swapon "$SWP_PART"

# Install Arch Linux
pacstrap /mnt base linux linux-firmware efibootmgr os-prober intel-ucode amd-ucode openssh mkinitcpio vi nano xfsprogs f2fs-tools

# Generate fstab
genfstab -U /mnt >> /mnt/etc/fstab

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
bootctl install

ACTIVE_NIC=$(networkctl --no-pager --no-legend list | grep routable | awk '{print $2}')
echo -e "[Match]\nName=$ACTIVE_NIC\n\n[Network]\nDHCP=yes" > /etc/systemd/network/20-wired.network

# root password
echo -e "password\npassword" | passwd 
mkdir -p /root/.ssh
echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDCT+nucANjleLvdumjMM3+2NYUGepV4492XwvMVLOEjiVoQmquhqvhAPUQ8vF7Y/wBKBJy0uVRt433eZYgFEilJ8SnaiUq/pHy15dzhdLuEkiiLLW3yzxLfS7DUDASfRX9mNBlE/WZSBJsk7lgjMr93rm9d3KUxW5CH8BSF+RMZ1r2Rto+c5BG8NlL4l3XiHhNtIrOjuycgyjVUuIvy9CBBbKxcYVo9c2L9iM/s5BcffmTh9JmVZ8wJhSqI9yLXAgFEvFoDAcUkxW1le9WWbU+Z8MQU4HU1u1RnJ3CFkGy8zdDkkhm/AIZd3LZw5TSh1d8qgN7Hp6ETuLjPtJem/FckVdwNJWQqmkwrXd6xOwcpkiBqH6gX/1Jy+f0gW0rP0yG8x6NiWMQNNYeI2ZwGk9DEdVN0QH6OOcdSkn+pU8YjcyDbQTBRqb0jfb22SAz2OUSlupXU003pl3PAZQRnFSSma0J6WJpuf7IEeNCnR2e2wgfXt8nPkzLdMEsAXAVGbE=" > /root/.ssh/authorized_keys

systemctl enable systemd-networkd.service
systemctl enable systemd-resolved.service
systemctl enable sshd.service
exit
EOT

