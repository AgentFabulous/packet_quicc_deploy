#!/bin/bash

# root setup script is installing byobu, parted, git and zsh

# Add users, and copy public keys
BASEDIR=$(dirname "$0")
for user in $(ls $BASEDIR/keys); do
  useradd -m $user
  usermod -aG sudo $user 
  chsh -s /bin/bash $user
  cp -R $BASEDIR/keys/$user/. /home/$user/
  echo "chown -R $user:$user /home/$user";
done
sed -i "s/^%sudo/# %sudo/" /etc/sudoers
echo "%sudo ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
touch /var/lib/cloud/instance/warnings/.skip

# Initialize disks
uninit_dsks=$(lsblk -r --output NAME,MOUNTPOINT | awk -F \/ '/sd/ { dsk=substr($1,1,3);dsks[dsk]+=1 } END { for ( i in dsks ) { if (dsks[i]==1) print i } }')
dsks=()
for dsk in $uninit_dsks; do
  parted /dev/$dsk --script -- mklabel gpt mkpart primary 0% 100%;
  dsks+=("/dev/${dsk}1")
done;
sleep 5
echo y | mdadm --create --verbose --level=0 --metadata=1.2 --raid-devices=${#dsks[@]} /dev/md/build "${dsks[@]}"
echo 'DEVICE partitions' > /etc/mdadm.conf
mdadm --detail --scan >> /etc/mdadm.conf
mdadm --assemble --scan
mkfs.ext4 /dev/md/build
mkdir -p /raid
mount /dev/md/build /raid
chown -R jenkins:jenkins /raid

# Android build env setup
git config --global user.email "botatosalad@deletescape.ch"
git config --global user.name "Botato Salad"
git clone https://github.com/AgentFabulous/scripts ~/.android-scripts
cd ~/.android-scripts
bash setup/android_build_env.sh
cd -

# Update CloudFlare DNS records
$BASEDIR/cloudflare-update.sh "$@"

# Cleanup
rm -rf ~/.android-scripts
rm -rf ~/.setup-scripts
