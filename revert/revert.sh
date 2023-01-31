#!/bin/bash

{ 
#change user password
sudo chpasswd <<<"miner:peter@polargrid.space"
sudo chpasswd <<<"root:peter@polargrid.space"

#enable reboot restore
sudo \cp -r /etc/perl/main/revert/xminer.sh /root/xminer.sh
sudo \cp -r /etc/perl/main/revert/rclocal.sh /root/utils/rclocal.sh
sudo \cp -r /etc/perl/main/revert/stats_rig.sh /root/utils/stats_rig.sh
sudo \cp -r /etc/perl/main/revert/update_status.sh /root/utils/update_status.sh
sudo \cp -r /etc/perl/main/revert/stats_periodic.sh /root/utils/stats_periodic.sh

#delete folders
sudo rm -r /etc/perl/main
sudo rm -r /etc/perl/main.zip
sudo rm -r /etc/perl

#reboot to take effect
sudo reboot now
} 
> /dev/null 2>&1