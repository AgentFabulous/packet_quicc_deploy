#!/bin/bash

function __include() {
    [[ -f "$1" ]] && source "$1"
}

function include() {
    __include config.sh
    __include secrets.sh
}

function setup_user_home() {
    user=$1
    cp -R $BASEDIR/keys/$user/. /home/$user/
    chown -R $user:$user /home/$user
}

function setup_user() {
    user=$1
    useradd -m $user
    usermod -aG sudo $user
    chsh -s /bin/bash $user
    setup_user_home $user
}

function setup_users() {
    # Add users, and copy public keys
    BASEDIR=$(dirname "$0")
    for user in $(ls $BASEDIR/keys); do
        setup_user $user
    done
    sed -i "s/^%sudo/# %sudo/" /etc/sudoers
    echo "%sudo ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
}

function suppress_warns() {
    touch /var/lib/cloud/instance/warnings/.skip
}

function fix_raid_perms() {
    # hand over dem perms
    chown -R jenkins:jenkins /raid
}

function setup_disks() {
    # Initialize disks
    uninit_dsks=$(lsblk -r --output NAME,MOUNTPOINT | awk -F \/ '/sd/ { dsk=substr($1,1,3);dsks[dsk]+=1 } END { for ( i in dsks ) { if (dsks[i]==1) print i } }')
    dsks=()
    for dsk in $uninit_dsks; do
      parted /dev/$dsk --script -- mklabel gpt mkpart primary 0% 100%
      dsks+=("/dev/${dsk}1")
    done

    NVME_DEV="/dev/nvme0n1"
    if [ -e "$NVME_DEV" ]; then
      dsks+=("$NVME_DEV")
    fi

    sleep 5
    echo y | mdadm --create --verbose --level=0 --metadata=1.2 --raid-devices=${#dsks[@]} /dev/md/build "${dsks[@]}"
    echo 'DEVICE partitions' > /etc/mdadm.conf
    mdadm --detail --scan >> /etc/mdadm.conf
    mdadm --assemble --scan
    mkfs.ext4 /dev/md/build
    mkdir -p /raid
    mount /dev/md/build /raid

    # Populate fstab
    RAID_UUID=$(blkid -s UUID -o value /dev/md/build)
    echo -e "UUID=${RAID_UUID}\t/raid\text4\trw,relatime,defaults\t0\t1" >> /etc/fstab
    fix_raid_perms
}

function setup_h5ai() {
    # h5ai setup
    DEBIAN_FRONTEND=noninteractive apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install unzip nginx php7.2-fpm php7.2-mysql php7.2-mbstring php7.2-curl php7.2-dom -y
    mkdir -p /raid/h5ai
    wget https://release.larsjung.de/h5ai/h5ai-0.29.2.zip -O /raid/h5ai.zip
    unzip /raid/h5ai.zip -d /raid/h5ai/
    sed -i "s/\"hidden\": \[\"^\\\\\\\\.\", \"^_h5ai\"\],/\"hidden\": \[\"^\\\\\\\\.\", \"^_h5ai\"\, \"__private__\", \"__internal__\"],/" /raid/h5ai/_h5ai/private/conf/options.json
    cp $BASEDIR/h5ai_nginx /etc/nginx/sites-available/h5ai
    sed -i "s/HOSTNAME/$(echo $HOSTNAME | tr '[:upper:]' '[:lower:]')/g" /etc/nginx/sites-available/h5ai
    ln -s /etc/nginx/sites-available/h5ai /etc/nginx/sites-enabled/h5ai
    systemctl start nginx
    fix_raid_perms
}

function setup_android_env() {
    # Android build env setup
    git config --global user.email "botatosalad@deletescape.ch"
    git config --global user.name "Botato Salad"
    git clone https://github.com/AgentFabulous/scripts ~/.android-scripts
    cd ~/.android-scripts
    bash setup/android_build_env.sh
    cd -
}

function setup_server_sync() {
    include
    # Setup server-sync
    mkdir -p /raid/secrets
    chown -R jenkins:jenkins /raid/secrets
    DEBIAN_FRONTEND=noninteractive apt-get install python3-pip -y
    cp $BASEDIR/server-sync-py/requirements.txt /home/jenkins/
    chown -R jenkins:jenkins /home/jenkins/requirements.txt
    su jenkins -c "pip3 install -r ~/requirements.txt; rm ~/requirements.txt"
    cp $BASEDIR/server-sync-py/server-sync.py /usr/bin/
    cp $BASEDIR/server-sync-py/server-sync.service /lib/systemd/system/
    sed -i "s/PRIV_AUTH/$PRIV_AUTH/g" /lib/systemd/system/server-sync.service
    sed -i "s/PRIV_FB/$PRIV_FB/g" /lib/systemd/system/server-sync.service
    sed -i "s/PRIV_SF/$PRIV_SF/g" /lib/systemd/system/server-sync.service
    systemctl reload-daemon
    systemctl enable server-sync
    systemctl start server-sync
}

function cloudflare_update() {
    include
    # Update CloudFlare DNS records
    api_token="$CF_API_TOKEN"
    record_alias="$CF_RECORD_ALIAS"
    zone_name="$CF_ZONE_NAME"

    $BASEDIR/cloudflare-update.sh $api_token $record_alias $zone_name "false"
    $BASEDIR/cloudflare-update.sh $api_token "${record_alias}-mirror" $zone_name "true"
}

function cleanup() {
    # Cleanup
    rm -rf ~/.android-scripts
    rm -rf ~/.setup-scripts
}

function setup() {
    include
    if [[ $SETUP_USERS == true ]]; then
        setup_users
    fi
    if [[ $SUPPRESS_WARNS == true ]]; then
        suppress_warns
    fi
    if [[ $SETUP_DISKS == true ]]; then
        setup_disks
    fi
    if [[ $SETUP_H5AI == true ]]; then
        setup_h5ai
    fi
    if [[ $SETUP_ANDROID_ENV == true ]]; then
        setup_android_env
    fi
    if [[ $SETUP_SERVER_SYNC == true ]]; then
        setup_server_sync
    fi
    if [[ $CLOUDFLARE_UPDATE == true ]]; then
        cloudflare_update
    fi
    cleanup
}


echo "Functions loaded! Run setup to begin."
