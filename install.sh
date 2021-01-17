#! /bin/bash

# Wipe the existing disk
wipefs -af /dev/sda

# Filesystem mount warning
echo "This script will create and format the partitions as follows:"
echo "/dev/sda1 - 512Mib will be mounted as /boot/efi"
echo "/dev/sda2 - 8GiB will be used as swap"
echo "/dev/sda3 - rest of space will be mounted as /"

# to create the partitions programatically (rather than manually)
# https://superuser.com/a/984637
sed -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/' << EOF | fdisk /dev/sda
  o # clear the in memory partition table
  n # new partition
  p # primary partition
  1 # partition number 1
    # default - start at beginning of disk 
  +512M # 512 MB boot parttion
  n # new partition
  p # primary partition
  2 # partion number 2
    # default, start immediately after preceding partition
  +8G # 8 GB swap parttion
  n # new partition
  p # primary partition
  3 # partion number 3
    # default, start immediately after preceding partition
    # default, extend partition to end of disk
  a # make a partition bootable
  1 # bootable partition is partition 1 -- /dev/sda1
  p # print the in-memory partition table
  w # write the partition table
  q # and we're done
EOF

# Format the partitions
mkfs.xfs -f /dev/sda3
mkfs.fat -F32 /dev/sda1

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
mount /dev/sda3 /mnt
mkdir -pv /mnt/boot/efi
mount /dev/sda1 /mnt/boot/efi
mkswap /dev/sda2
swapon /dev/sda2

# Install Arch Linux
pacstrap /mnt base linux linux-firmware efibootmgr grub os-prober intel-ucode amd-ucode systemd-networkd openssh mkinitcpio vi nano

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
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=arch
grub-mkconfig -o /boot/grub/grub.cfg

# root password
echo -e "password\npassword" | passwd 
mkdir -p /root/.ssh
echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDCT+nucANjleLvdumjMM3+2NYUGepV4492XwvMVLOEjiVoQmquhqvhAPUQ8vF7Y/wBKBJy0uVRt433eZYgFEilJ8SnaiUq/pHy15dzhdLuEkiiLLW3yzxLfS7DUDASfRX9mNBlE/WZSBJsk7lgjMr93rm9d3KUxW5CH8BSF+RMZ1r2Rto+c5BG8NlL4l3XiHhNtIrOjuycgyjVUuIvy9CBBbKxcYVo9c2L9iM/s5BcffmTh9JmVZ8wJhSqI9yLXAgFEvFoDAcUkxW1le9WWbU+Z8MQU4HU1u1RnJ3CFkGy8zdDkkhm/AIZd3LZw5TSh1d8qgN7Hp6ETuLjPtJem/FckVdwNJWQqmkwrXd6xOwcpkiBqH6gX/1Jy+f0gW0rP0yG8x6NiWMQNNYeI2ZwGk9DEdVN0QH6OOcdSkn+pU8YjcyDbQTBRqb0jfb22SAz2OUSlupXU003pl3PAZQRnFSSma0J6WJpuf7IEeNCnR2e2wgfXt8nPkzLdMEsAXAVGbE=" > /root/.ssh/authorized_keys

systemctl enable NetworkManager.service
systemctl enable sshd.service
exit
EOT

reboot
