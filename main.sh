#!/bin/bash

# root setup script is installing byobu, parted, git and zsh

# Add users, and copy public keys
BASEDIR=$(dirname "$0")
for user in $(ls $BASEDIR/keys); do
  useradd -m $user
  usermod -aG sudo $user 
  cp -R $BASEDIR/keys/$user/. /home/$user/
  echo "chown -R $user:$user /home/$user";
done
sed -i "s/^%sudo/# %sudo/" /etc/sudoers
echo "%sudo ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# Initialize disks
parted /dev/sdc --script -- mklabel gpt mkpart primary 0% 100%
parted /dev/sdd --script -- mklabel gpt mkpart primary 0% 100%
mkfs.ext4 /dev/sdc1
mkfs.ext4 /dev/sdd1
mkdir -p /volumes/v1
mkdir -p /volumes/v2
mount /dev/sdc1 /volumes/v1
mount /dev/sdd1 /volumes/v2
chown -R jenkins:jenkins /volumes
