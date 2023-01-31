#!/bin/bash

DEBUG=0
[[ ${DEBUG} == 1 ]] && echo -n > /var/tmp/debug.rclocal

touch /var/tmp/rigStart.run

# generate new host keys if do not exists

# Disable regular file and FIFO protection (default enabled since Ubuntu 20)
# do it as fast as possible during rig startup
sysctl fs.protected_regular=0 1>/dev/null 2>/dev/null
sysctl fs.protected_fifos=0   1>/dev/null 2>/dev/null

CONFIG_FILE="/root/config.txt"
source ${CONFIG_FILE}

# start fastest possible stats_periodic (via fanspeed) not waiting for full minute cron
# We want system primary stats be done fast (system vars, without gpu's data)
bash <(cat /root/utils/fanspeed.sh) 1>/dev/null 2>/dev/null &

# create screen log file
echo -n > /var/tmp/screen.miner.log 2>/dev/null
sudo chown miner:miner /var/tmp/screen.miner.* 2>/dev/null
sudo chmod 777         /var/tmp/screen.miner.* 2>/dev/null
echo -n > /var/tmp/consoleSys.log 2>/dev/null
sudo chown miner:miner /var/tmp/consoleSys.log 2>/dev/null
sudo chmod 777         /var/tmp/consoleSys.log 2>/dev/null


# make sure update_status will start fastest possible not waiting for full minute in cron
su miner -c 'bash <(cat /root/utils/update_status_manager.sh)'&

# restore nvidia disabled modules
MODS=`find /lib/modules -name nvidia.ko.disable`
if [[ ${MODS} != "" ]]; then
  for IMOD in ${MODS}; do
    IMOD2=`echo "${IMOD}" | sed 's/\.disable$//'`
    mv ${IMOD} ${IMOD2}
  done
  depmod -a 1>/dev/null 2>/dev/null
  sync
  echo
  echo -e "${xNO}${xRED}${xBOLD}NVIDIA modules restored. Rig will now reboot once...${xNO}"
  echo -e "${xNO}${xRED}${xBOLD}NVIDIA modules restored. Rig will now reboot once...${xNO}" >> /var/tmp/screen.miner.log
  echo -e "${xNO}${xRED}${xBOLD}NVIDIA modules restored. Rig will now reboot once...${xNO}" >> /var/tmp/consoleSys.log
  sleep 6
  reboot
fi

# if config include WIFI configuration arguments
WIFI_ENABLE=`cat /mnt/user/config.txt | (grep "^WIFI_ENABLE=" || echo "WIFI_ENABLE=0") | head -n 1 | sed 's/^WIFI_ENABLE=//' | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'`
if [[ ${WIFI_ENABLE} == 1 ]]; then
  WIFI_NETWORK=`cat /mnt/user/config.txt | grep "^WIFI_NETWORK=" | head -n 1 | sed 's/^WIFI_NETWORK=//' | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'`
  WIFI_PASSWORD=`cat /mnt/user/config.txt | grep "^WIFI_PASSWORD=" | head -n 1 | sed 's/^WIFI_PASSWORD=//' | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'`
  # verify current system wifi configuration
  echo -e "allow-hotplug wlan0\niface wlan0 inet dhcp\nwpa-ssid ${WIFI_NETWORK}\nwpa-psk ${WIFI_PASSWORD}\n" > /var/tmp/network_config_wifi.tmp
  if [[ ! -f /etc/network/interfaces.d/wifi || `md5sum /etc/network/interfaces.d/wifi | awk '{ print $1 }'` != `md5sum /var/tmp/network_config_wifi.tmp | awk '{ print $1 }'` ]]; then
    mv -f /var/tmp/network_config_wifi.tmp /etc/network/interfaces.d/wifi
    sync
    echo -e "${xNO}${xRED}${xBOLD}Detected new WiFi user configuration. Rig will now reboot once...${xNO}"
    echo -e "${xNO}${xRED}${xBOLD}Detected new WiFi user configuration. Rig will now reboot once...${xNO}" >> /var/tmp/screen.miner.log
    echo -e "${xNO}${xRED}${xBOLD}Detected new WiFi user configuration. Rig will now reboot once...${xNO}" >> /var/tmp/consoleSys.log
    sleep 1
    reboot
  fi
elif [[ -f /etc/network/interfaces.d/wifi ]]; then
  # disable WiFi configuration from system
  rm -f /etc/network/interfaces.d/wifi
  sync
  echo -e "${xNO}${xRED}${xBOLD}Detected new WiFi user configuration (deactivation). Rig will now reboot once...${xNO}"
  echo -e "${xNO}${xRED}${xBOLD}Detected new WiFi user configuration (deactivation). Rig will now reboot once...${xNO}" >> /var/tmp/screen.miner.log
  echo -e "${xNO}${xRED}${xBOLD}Detected new WiFi user configuration (deactivation). Rig will now reboot once...${xNO}" >> /var/tmp/consoleSys.log
  sleep 1
  reboot
fi

# wait for IP address max 60 seconds
iend=20
for ((i=1; i<=iend; i++)); do
  ipLan=`hostname -I | awk '{ print $1 }'`
  if [[ ! -z ${ipLan} ]]; then
    if [[ ${i} -gt 1 ]]; then
      echo -e "${xNO}${xGREEN}  ...OK${xNO}"
      echo -e "${xNO}${xGREEN}OK${xNO}" >> /var/tmp/screen.miner.log
      echo -e "${xNO}${xGREEN}OK${xNO}" >> /var/tmp/consoleSys.log
    fi
    break
  else
    if [[ ${i} == 1 ]]; then
      echo -e  "${xNO}${xGREEN}Waiting for IP address from your DHCP server...${xNO}"
      echo -ne "${xNO}${xGREEN}Waiting for IP address from your DHCP server...${xNO}" >> /var/tmp/screen.miner.log
      echo -ne "${xNO}${xGREEN}Waiting for IP address from your DHCP server...${xNO}" >> /var/tmp/consoleSys.log
    elif [[ ${i} == ${iend} ]]; then
      echo -e "${xNO}${xGREEN}${xBOLD}  ...giving up. May take more time.${xNO}"
      echo -e "${xNO}${xGREEN}${xBOLD}giving up. May take more time.${xNO}" >> /var/tmp/screen.miner.log
      echo -e "${xNO}${xGREEN}${xBOLD}giving up. May take more time.${xNO}" >> /var/tmp/consoleSys.log
      break
    else
      echo -e  "${xNO}${xGREEN}Waiting for IP address from your DHCP server...${xNO}"
      echo -ne "${xNO}${xGREEN} .${xNO}" >> /var/tmp/screen.miner.log
      echo -ne "${xNO}${xGREEN} .${xNO}" >> /var/tmp/consoleSys.log
    fi
  fi
  sleep 3
done

ipLan=`hostname -I | awk '{ print $1 }'`
[[ -z ${ipLan} ]] && ipLan="n/a"
echo -e "${rigName}" > /etc/perl/main/execute/rigName.txt
echo -e "${xNO}${xGREEN}Rig local IP: ${xBOLD}${ipLan}${xNO}${xGREEN}, name: ${xBOLD}${rigName}${xNO}"
echo -e "${xNO}${xGREEN}Rig local IP: ${xBOLD}${ipLan}${xNO}${xGREEN}, name: ${xBOLD}${rigName}${xNO}" >> /var/tmp/screen.miner.log
echo -e "${xNO}${xGREEN}Rig local IP: ${xBOLD}${ipLan}${xNO}${xGREEN}, name: ${xBOLD}${rigName}${xNO}" >> /var/tmp/consoleSys.log

# tuning system
[[ -e /proc/sys/kernel/softlockup_panic ]] && echo "1" > /proc/sys/kernel/softlockup_panic
echo "5" > /proc/sys/kernel/panic
echo "1" > /proc/sys/kernel/panic_on_io_nmi
echo "1" > /proc/sys/kernel/panic_on_oops
echo "1" > /proc/sys/kernel/panic_on_rcu_stall
echo "1" > /proc/sys/kernel/panic_on_unrecovered_nmi
echo "1" > /proc/sys/kernel/panic_on_warn
# less restricted panic:
#sysctl kernel.hardlockup_panic=1         1> /dev/null 2> /dev/null
#sysctl kernel.hung_task_panic=1          1> /dev/null 2> /dev/null
#sysctl kernel.panic=10                   1> /dev/null 2> /dev/null
#sysctl kernel.panic_on_io_nmi=0          1> /dev/null 2> /dev/null
#sysctl kernel.panic_on_oops=1            1> /dev/null 2> /dev/null
#sysctl kernel.panic_on_rcu_stall=0       1> /dev/null 2> /dev/null
#sysctl kernel.panic_on_unrecovered_nmi=0 1> /dev/null 2> /dev/null
#sysctl kernel.panic_on_warn=0            1> /dev/null 2> /dev/null
#sysctl kernel.panic_print=0              1> /dev/null 2> /dev/null
#sysctl kernel.softlockup_panic=1         1> /dev/null 2> /dev/null
#sysctl kernel.unknown_nmi_panic=0        1> /dev/null 2> /dev/null
#sysctl vm.panic_on_oom=0                 1> /dev/null 2> /dev/null

# improve disk writes to less
mount -o remount,noatime,nodiratime,commit=120 /
mount -o remount,noatime,nodiratime,ro /mnt/user
mount -o remount,ro /boot/efi 2>/dev/null

echo noop > /sys/block/sda/queue/scheduler 2>/dev/null
# warning kernel 5.0+ dont have option "noop"

sysctl vm.dirty_background_ratio=20 1>/dev/null
sysctl vm.dirty_expire_centisecs=0 1>/dev/null
sysctl vm.dirty_ratio=80 1>/dev/null
sysctl vm.dirty_writeback_centisecs=0 1>/dev/null
# increase kernel lever performance (less pages to search for by kernel)
sysctl vm.nr_hugepages=128 1>/dev/null

# clearing cache files
rm -f /home/miner/.cache/sessions/* 2>/dev/null
rm -f /etc/udev/rules.d/70-persistent-net.rules 2>/dev/null
rm -f /etc/X11/xorg* 2>/dev/null
rm -f /root/.Xauthority* 2>/dev/null
rm -f /root/.xaut* 2>/dev/null
rm -f /home/miner/.Xauthority* 2>/dev/null
# write changes ;-)
sync

# Octominer detect
lsusb -v 2>/dev/null | grep info@octominer.com | head -n 1 | wc -l > /var/tmp/hwOctominer
# Octominer booting stage message
[[ -f /var/tmp/hwOctominer && `cat /var/tmp/hwOctominer` == 1 ]] && /root/utils/octominer/octominer_boot.sh 1>/dev/null 2>/dev/null &

# listen for remote action of add rig (email) only if default mail set
[[ ${USER_EMAIL} == "admin@simplemining.net" ]] && /root/utils/set_email_bcastd.pl &

# setting system passwords

nohup bash <(cat /root/utils/cron_emrg.sh) 1>/dev/null 2>/dev/null &

for ((i=1; i<=3; i++)); do
  source ${CONFIG_FILE}
  if [[ ${osSeries} == "R" ]]; then
    aticonfig --initial --adapter=all &
    /root/utils/rclocal_advtools.sh
    # SRR start
    su miner -c 'bash /root/utils/run_in_screen.sh srr_pre /root/utils/SRR/keepalive.sh' &
    break
  elif [[ ${osSeries} == "RX" ]]; then
    gpuCount=`ls -1 /sys/class/drm/card*/device/pp_table 2>/dev/null | wc -l`
    jend=15
    for ((j=1; j<=${jend}; j++)); do
      echo -e "${xNO}${xGREEN}Waiting for all GPUs...${xNO}"
      if [[ ${j} == 1 ]]; then
        echo -ne "${xNO}${xGREEN}Waiting for all GPUs...${xNO}" >> /var/tmp/screen.miner.log
        echo -ne "${xNO}${xGREEN}Waiting for all GPUs...${xNO}" >> /var/tmp/consoleSys.log
      else
        echo -ne "${xNO}${xGREEN} .${xNO}" >> /var/tmp/screen.miner.log
        echo -ne "${xNO}${xGREEN} .${xNO}" >> /var/tmp/consoleSys.log
      fi
      sleep 3
      gpuCountNew=`ls -1 /sys/class/drm/card*/device/pp_table 2>/dev/null | wc -l`
      if [[ ${gpuCountNew} == ${gpuCount} ]]; then
        echo -e "${xNO}${xGREEN}  ...OK${xNO}"
        echo -e "${xNO}${xGREEN}OK${xNO}" >> /var/tmp/screen.miner.log
        echo -e "${xNO}${xGREEN}OK${xNO}" >> /var/tmp/consoleSys.log
        break
      fi
      if [[ ${j} == ${jend} ]]; then
        echo -e "${xNO}${xGREEN}${xBOLD}  ...giving up. May take more time.${xNO}"
        echo -e "${xNO}${xGREEN}${xBOLD}giving up. May take more time.${xNO}" >> /var/tmp/screen.miner.log
        echo -e "${xNO}${xGREEN}${xBOLD}giving up. May take more time.${xNO}" >> /var/tmp/consoleSys.log
        break
      fi
      gpuCount=${gpuCountNew}
    done
    echo "${gpuCount}" > /var/tmp/stats_gpu_count
    chown miner:miner /var/tmp/stats_gpu_count

    sudo /root/utils/oc_save_pp_table.sh

    # Fix Navi fans
    gfxId=0
    gfxIdRaw=0
    while [[ true ]]; do
      if [[ ! -e /sys/class/drm/card${gfxIdRaw} ]]; then
       # no more cards
       break
      fi
      if [[ -e /sys/class/drm/card${gfxIdRaw}/device/pp_table ]]; then # AMD mining GPU
        pciId=`ls -l /sys/class/drm/card${gfxIdRaw} | awk -F"/" '{ print $(NF-2) }'`
        isNavi10=`lspci -n -s "${pciId}" | egrep -i "${pciids_navi10}" | head -n 1 | wc -l`
        isNavi12=`lspci -n -s "${pciId}" | egrep -i "${pciids_navi12}" | head -n 1 | wc -l`
        isNavi21=`lspci -n -s "${pciId}" | egrep -i "${pciids_navi21}" | head -n 1 | wc -l`
        isNavi22=`lspci -n -s "${pciId}" | egrep -i "${pciids_navi22}" | head -n 1 | wc -l`
        isNavi23=`lspci -n -s "${pciId}" | egrep -i "${pciids_navi23}" | head -n 1 | wc -l`
        isNavi24=`lspci -n -s "${pciId}" | egrep -i "${pciids_navi24}" | head -n 1 | wc -l`
        # Fix Navi fans
        if [[ ${isNavi10} == 1 || ${isNavi12} == 1 || ${isNavi21} == 1 || ${isNavi22} == 1 || ${isNavi23} == 1 || ${isNavi24} == 1 ]]; then
          if [[ ${isNavi10} == 1 || ${isNavi12} == 1 ]]; then
            fstart=0
            fstop=0
          elif [[ ${isNavi21} == 1 || ${isNavi22} == 1 || ${isNavi23} == 1 || ${isNavi24} == 1 ]]; then
            fstart=35
            fstop=25
          fi
          # try 5 times
          jend=5
          for ((j=1 ; j<=${jend}; j++)); do
            ret=1
            timeout 5 /root/utils/navitool -i ${gfxIdRaw} --set-fstart ${fstart} 1>/dev/null 2>/dev/null
            [[ `timeout 5 /root/utils/navitool -i ${gfxIdRaw} --show-fstart | awk -F" = " '{ print $2 }'` != ${fstart} ]] && ret=0
            timeout 5 /root/utils/navitool -i ${gfxIdRaw} --set-fstop ${fstop} 1>/dev/null 2>/dev/null
            [[ `timeout 5 /root/utils/navitool -i ${gfxIdRaw} --show-fstop | awk -F" = " '{ print $2 }'` != ${fstop} ]] && ret=0
            timeout 5 /root/utils/navitool -i ${gfxIdRaw} --set-zrpm 0 1>/dev/null 2>/dev/null
            [[ `timeout 5 /root/utils/navitool -i ${gfxIdRaw} --show-zrpm | awk -F" = " '{ print $2 }'` != 0 ]] && ret=0
            if [[ ${isNavi21} == 1 || ${isNavi22} == 1 || ${isNavi23} == 1 || ${isNavi24} == 1 ]]; then
              # after sleep do change to unfreeze fan (GPU/driver?) (fanspeed will later back to value 1 itself)
              (sleep 30; echo 0 > /sys/class/drm/card${gfxIdRaw}/device/hwmon/hwmon*/fan1_enable) &
            fi
            [[ ${ret} == 1 ]] && break
            if [[ ${j} -lt ${jend} ]]; then
              sleep 5
            else
              echo -e "${xNO}${xBOLD}${xRED}Failed fix fan for GPU${gfxId}${xNO}"
              echo -e "${xNO}${xBOLD}${xRED}Failed fix fan for GPU${gfxId}${xNO}" >> /var/tmp/screen.miner.log
              echo -e "${xNO}${xBOLD}${xRED}Failed fix fan for GPU${gfxId}${xNO}" >> /var/tmp/consoleSys.log
            fi
          done
        fi
        gfxId=$((gfxId+1))
      fi # if AMD mining GPU
      gfxIdRaw=$((gfxIdRaw+1))
    done
    sleep 2

    # BC-250 Memory Timing
    isCyanskillfishPresent=0
    gfxId=0
    gfxIdRaw=0
    while [[ true ]]; do
      [[ ! -e /sys/class/drm/card${gfxIdRaw} ]] && break
      if [[ -e /sys/class/drm/card${gfxIdRaw}/device/pp_table ]]; then
        pciId=`ls -l /sys/class/drm/card${gfxIdRaw} | awk -F"/" '{ print $(NF-2) }'`
        isCyanskillfish=$(lspci -n -s "${pciId}" | grep -Ei "${pciids_cyanskillfish}" | head -n 1 | wc -l)
        [[ ${isCyanskillfish} == 1 ]] && isCyanskillfishPresent=1
        gfxId=$((gfxId+1))
      fi
      gfxIdRaw=$((gfxIdRaw+1))
    done
    # BC-250 memory timing
    [[ ${isCyanskillfishPresent} == 1 ]] && /root/utils/RobinMemTiming/RobinMemTiming-write.sh 1> /dev/null 2> /dev/null &

    /root/utils/rclocal_advtools.sh
    su miner -c 'bash /root/start.sh' 1>/dev/null 2>/dev/null &
    break
  elif [[ ${osSeries} == "NV" ]]; then
    [[ -f /usr/bin/nvidia-persistenced ]] && nvidia-persistenced --persistence-mode
    [[ -f /usr/bin/nvidia-persistenced ]] || nvidia-smi -pm 1

    /root/utils/xconfgenerate.sh

    re='3D controller: NVIDIA'
    if [[ `lspci` =~ $re  ]]; then
      export DISPLAY=:0.0
      [[ ${DEBUG} == 1 ]] && echo "running Xorg..." >> /var/tmp/debug.rclocal
      X -sharevts :0 &
      [[ ${DEBUG} == 1 ]] && echo "running xhost..." >> /var/tmp/debug.rclocal
      xhost +
    else
      [[ ${DEBUG} == 1 ]] && echo "running startx..." >> /var/tmp/debug.rclocal
      startx & # -display :2 -- :2 vt2 &
    fi
    /root/utils/rclocal_advtools.sh
    su miner -c 'bash /root/start.sh' &
    break
  else
    echo -e "${xNO}${xRED}${xBOLD}Failed detecting GPU. Retrying in 3 seconds...${xNO}"
    echo -e "${xNO}${xRED}${xBOLD}Failed detecting GPU. Retrying in 3 seconds...${xNO}" >> /var/tmp/screen.miner.log
    echo -e "${xNO}${xRED}${xBOLD}Failed detecting GPU. Retrying in 3 seconds...${xNO}" >> /var/tmp/consoleSys.log
    sleep 3
  fi
done
if [[ ${osSeries} == "none" ]]; then
  echo -e "${xNO}${xRED}${xBOLD}GPU type not recognized!${xNO}"
  echo -e "${xNO}${xRED}${xBOLD}GPU type not recognized!${xNO}" >> /var/tmp/screen.miner.log
  echo -e "${xNO}${xRED}${xBOLD}GPU type not recognized!${xNO}" >> /var/tmp/consoleSys.log
  # no GPUs detected or driver error. Message will be written later in xminer.sh after rigRegister
  sleep 2
  /root/utils/rclocal_advtools.sh
  su miner -c 'bash /root/start.sh' &
fi

# make flag with info, that rig is started
# and from this point all system services should work (Xorg, etc)
touch /var/tmp/rigStarted.run

# start fastest possible stats_periodic (via fanspeed) not waiting for full minute cron
# We want GPU stats be done fastest possible (GPS stats posssible just after creating /var/tmp/rigStarted.run)
bash <(cat /root/utils/fanspeed.sh) 1>/dev/null 2>/dev/null &

# watchdog
rmmod softdog 1>/dev/null 2>/dev/null
modprobe softdog soft_margin=300 1>/dev/null 2>/dev/null

touch /var/tmp/watchdog_keepalieve.flag
(systemctl stop watchdog; sleep 5; systemctl stop watchdog) & 1>/dev/null 2>/dev/null
(sleep 300; systemctl start watchdog) & 1>/dev/null 2>/dev/null

# disable error logs on LCD
sysctl -w kernel.printk="1 1 1 7" 1> /dev/null 2> /dev/null
