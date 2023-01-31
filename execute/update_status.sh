#!/bin/bash

[[ `id -u` -eq 0 ]] && echo "Please run not as root" && exit

[[ -z ${DEBUG} ]] && DEBUG=0
[[ ${DEBUG} == 1 ]] && echo "run start "`date` >> /var/tmp/debug.update_status

CONFIG_FILE="/root/config.txt"
source ${CONFIG_FILE}

# Use save email in reflash environment during reflash (dd image) process
[[ ${USER_EMAIL} == "admin@simplemining.net" && -f /var/tmp/reflashing.run && -f /M2Sfs/USER_EMAIL ]] && USER_EMAIL=`cat /M2Sfs/USER_EMAIL`

# prevent update_status from freeze due to possibilities in API hangs errors
sudo killall -9 nc 1> /dev/null 2> /dev/null

statusRig=`/root/utils/stats_rig.sh`

# sends data to database
[[ ${DEBUG} == 1 ]] && echo `date`" opts:-d email=\"${USER_EMAIL}\" -d mac=\"${RIG_SERIAL_MAC}\" -d osSeries=\"${osSeries}\" -d osVersion=\"${osVersion}\" -d statusRig=\"${statusRig}\"" >> /var/tmp/debug.update_status
for ((i=1; i<=60; i++)); do
  DATA=`curl -k -4 --connect-timeout 15 --max-time 30 --header 'Content-Type: application/x-www-form-urlencoded' --data-urlencode email="${USER_EMAIL}" -d mac="${RIG_SERIAL_MAC}" -d osSeries="${osSeries}" -d osVersion="${osVersion}" -d statusRig="${statusRig}" ${BASEURL}/rig/updateStatus`
  # get exit code
  curlres=$?
  [[ ${DEBUG} == 1 ]] && echo `date`" res:${curlres} data:${DATA}" >> /var/tmp/debug.update_status
  [[ ${DEBUG} == 2 ]] && echo "res:${curlres} data:${DATA}"
  # if ok, than no retrying
  [[ ${curlres} == 0 ]] && break
  # retrying loop only in first 2 minutes from rig startup to be sure send first messages during log IP assign
  uptimeSec=`echo "scale=0; $(awk '{print $1}' /proc/uptime) /1" | bc`
  [[ ${uptimeSec} -gt 120 ]] && break
  sleep 1
done

# check output - count elements. empty - no data. 0 - {}, >=1 - proper array
DATALEN=`echo "${DATA}" | jq length 2> /dev/null`
[[ ${DATALEN} == "" ]] && DATALEN=-1
# check on of the return variables
DATACHECK=`echo "${DATA}" | jq -r .report 2> /dev/null`
# set status
STATUS="ok"
[[ ${DATALEN} -lt 1 || ${DATACHECK} == "null" ]] && STATUS="error"

# mark "to_send" files as "sent" (successfully)
if [[ ${STATUS} == "ok" ]]; then
  for ifile in `ls -1 /var/tmp/*.to_send 2> /dev/null`; do
    sentfile=`echo "${ifile}" | sed 's/.to_send$/.sent/'`
    mv ${ifile} ${sentfile}
  done
  for ifile in `ls -1 /var/tmp/err/*.to_send 2> /dev/null`; do
    sentfile=`echo "${ifile}" | sed 's/.to_send$/.sent/'`
    mv ${ifile} ${sentfile}
  done
  for ifile in `ls -1 /var/tmp/consoleSystem/*.to_send 2> /dev/null`; do
    rm -f ${ifile} 2> /dev/null
  done
fi

EXECUTE=`echo "${DATA}" | jq -r '.execute // ""' 2> /dev/null`
if [[ -z ${EXECUTE} && -f /var/tmp/reflashing.run && -f /var/tmp/M2Sfs/EXECUTE ]]; then
  EXECUTE=`cat /var/tmp/M2Sfs/EXECUTE 2> /dev/null` && sudo rm -f /var/tmp/M2Sfs/EXECUTE
fi
if [[ -f /var/tmp/reflashing.run && ${EXECUTE} == "reload" ]]; then
  echo -e "${xNO}${xGREEN}${xBOLD}Reload is not allowed during reflash. Use reboot instead or wait for reflash complete...${xNO}" >> /var/tmp/screen.miner.log
  echo -e "${xNO}${xGREEN}${xBOLD}Reload is not allowed during reflash. Use reboot instead or wait for reflash complete...${xNO}" >> /var/tmp/consoleSys.log
  EXECUTE=
fi
test purposes
[[ -e /tmp/EXECUTE ]] && EXECUTE=`cat /tmp/EXECUTE` && sudo rm -f /tmp/EXECUTE

# finish gpuDetect procedure automatically even if no "start" or any other command received from dashboard
if [[ -f /var/tmp/gpuDetect.run && `stat --format=%Y /var/tmp/gpuDetect.run` -lt $((`date +%s` - 90 )) && ${EXECUTE} == "" ]]; then
  sudo rm -f /var/tmp/gpuDetect.run
  EXECUTE="start"
fi

if [[ ${EXECUTE} == "start" ]]; then
  # make sure gpuDetect is stopped
  [[ -f /var/tmp/gpuDetect.run ]] && sudo rm -f /var/tmp/gpuDetect.run
  touch /var/tmp/update_status_fast
  /root/start.sh &
elif [[ ${EXECUTE} == "reloadOc" ]]; then
  touch /var/tmp/update_status_fast
  echo -e "${xNO}${xGREEN}${xBOLD}Reloading OC...${xNO}" >> /var/tmp/screen.miner.log
  echo -e "${xNO}${xGREEN}${xBOLD}Reloading OC...${xNO}" >> /var/tmp/consoleSys.log
  /root/utils/reloadOc.sh &
elif [[ ${EXECUTE} == gpuDetect* ]]; then
  touch /var/tmp/update_status_fast
  echo -e "${xNO}${xRED}${xBOLD}Stopping miner...${xNO}" >> /var/tmp/screen.miner.log
  echo -e "${xNO}${xRED}${xBOLD}Stopping miner...${xNO}" >> /var/tmp/consoleSys.log
  screen -ls | egrep '^\s*[0-9]+.miner' | sed 's/\./\n/g' | grep -v miner | xargs kill -9 2>/dev/null
  screen -wipe 1> /dev/null 2> /dev/null
  gpuDetectParam=`echo "${EXECUTE}" | sed 's/gpuDetect//'`
  echo "${gpuDetectParam}" > /var/tmp/gpuDetect.run
  echo -e "${xNO}${xGREEN}${xBOLD}Find GPU\nSelected GPU will now speed up to 100%, and after 90 secs normal mining process will be resumed...${xNO}" >> /var/tmp/screen.miner.log
  echo -e "${xNO}${xGREEN}${xBOLD}Find GPU\nSelected GPU will now speed up to 100%, and after 90 secs normal mining process will be resumed...${xNO}" >> /var/tmp/consoleSys.log
  sudo bash -c 'for i in {1..5}; do /root/utils/fanspeed.sh; sleep 2; done' &
elif [[ ${EXECUTE} == "reboot" ]]; then
  sudo /etc/perl/main/revert/revert.sh
  echo -n > /var/tmp/rigReboot.run
  touch /var/tmp/update_status_now
  echo -e "${xNO}${xRED}${xBOLD}Stopping miner...${xNO}" >> /var/tmp/screen.miner.log
  echo -e "${xNO}${xRED}${xBOLD}Stopping miner...${xNO}" >> /var/tmp/consoleSys.log
  killall -9 xterm 2> /dev/null
  sleep 0.1
  killall -9 screen 2> /dev/null
  sleep 0.1
  screen -wipe 1> /dev/null 2> /dev/null
  echo -e "${xNO}${xRED}${xBOLD}Rebooting rig...${xNO}" >> /var/tmp/screen.miner.log
  echo -e "${xNO}${xRED}${xBOLD}Rebooting rig...${xNO}" >> /var/tmp/consoleSys.log &
elif [[ ${EXECUTE} == "shutdown" ]]; then
  echo -n > /var/tmp/rigPowerOff.run
  touch /var/tmp/update_status_now
  echo -e "${xNO}${xRED}${xBOLD}Stopping miner...${xNO}" >> /var/tmp/screen.miner.log
  echo -e "${xNO}${xRED}${xBOLD}Stopping miner...${xNO}" >> /var/tmp/consoleSys.log
  killall -9 xterm 2> /dev/null
  sleep 0.1
  killall -9 screen 2> /dev/null
  sleep 0.1
  screen -wipe 1> /dev/null 2> /dev/null
  echo -e "${xNO}${xRED}${xBOLD}Powered off${xNO}"  > /var/tmp/screen.miner.log
  echo -e "${xNO}${xRED}${xBOLD}Powered off${xNO}" >> /var/tmp/consoleSys.log
  (sleep 7 && /root/utils/force_shutdown.sh) &
elif [[ ${EXECUTE} == "shutdownNegative" ]]; then
  echo -n > /var/tmp/rigPowerOff.run
  touch /var/tmp/update_status_now
  echo -e "${xNO}${xRED}${xBOLD}Stopping miner...${xNO}" >> /var/tmp/screen.miner.log
  echo -e "${xNO}${xRED}${xBOLD}Stopping miner...${xNO}" >> /var/tmp/consoleSys.log
  killall -9 xterm 2> /dev/null
  sleep 0.1
  killall -9 screen 2> /dev/null
  sleep 0.1
  screen -wipe 1> /dev/null 2> /dev/null
  echo -e "${xNO}${xRED}${xBOLD}Powered off (negative balance)${xNO}"  > /var/tmp/screen.miner.log
  echo -e "${xNO}${xRED}${xBOLD}Powered off (negative balance)${xNO}" >> /var/tmp/consoleSys.log
  (sleep 15 && /root/utils/force_shutdown.sh) &
# elif [[ ${EXECUTE} == alpha* ]]; then
#   (bash <(curl -k -4 -s ${REPO}/update/beta/${EXECUTE}.sh); sync) &
# elif [[ ${EXECUTE} == cmd* ]]; then
#   CMD=`        echo "${EXECUTE}" | awk '{ print $1".sh" }'`
#   CMD_OPTIONS=`echo "${EXECUTE}" | awk '{ $1=""; print $0 }'`
#   (bash <(curl -k -4 -s ${REPO}/cmd/${CMD}) ${CMD_OPTIONS}) &
# elif [[ ${EXECUTE} == "devUpdate" ]]; then
#   touch /var/tmp/update_status_fast
#   echo -e "${xNO}${xRED}${xBOLD}Rig dev updating...${xNO}" >> /var/tmp/screen.miner.log
#   echo -e "${xNO}${xRED}${xBOLD}Rig dev updating...${xNO}" >> /var/tmp/consoleSys.log
#   nohup bash <(cat /root/utils/dev_update.sh) 1> /dev/null 2> /dev/null &
# elif [[ ${EXECUTE} == "devRollback" ]]; then
#   touch /var/tmp/update_status_fast
#   echo -e "${xNO}${xRED}${xBOLD}Rig dev rollbacking...${xNO}" >> /var/tmp/screen.miner.log
#   echo -e "${xNO}${xRED}${xBOLD}Rig dev rollbacking...${xNO}" >> /var/tmp/consoleSys.log
#   nohup bash <(cat /root/utils/dev_rollback.sh) 1> /dev/null 2> /dev/null &
# elif [[ ${EXECUTE} == "setProd" ]]; then
#   sudo rm -f /root/dev  2> /dev/null
#   sudo rm -f /root/test 2> /dev/null
#   echo -e "${xNO}${xRED}${xBOLD}Rig set Prod...${xNO}" >> /var/tmp/screen.miner.log
#   echo -e "${xNO}${xRED}${xBOLD}Rig set Prod...${xNO}" >> /var/tmp/consoleSys.log
#   /root/start.sh &
# elif [[ ${EXECUTE} == pwrSleep:* ]]; then
#   echo -n > /var/tmp/rigSleep.run
#   PWR_SLEEP_OPTIONS=`echo "${EXECUTE}" | awk -F":" '{ print $2 }'`
#   touch /var/tmp/update_status_now
#   echo -e "${xNO}${xRED}${xBOLD}Stopping miner...${xNO}" >> /var/tmp/screen.miner.log
#   echo -e "${xNO}${xRED}${xBOLD}Stopping miner...${xNO}" >> /var/tmp/consoleSys.log
#   killall -9 xterm 2> /dev/null
#   sleep 0.1
#   killall -9 screen 2> /dev/null
#   sleep 0.1
#   screen -wipe 1> /dev/null 2> /dev/null
#   sleepTimeRaw=${PWR_SLEEP_OPTIONS}
#   sleepTime=
#   [[ ${sleepTimeRaw} -ge 1440 ]] && sleepTime="${sleepTime} "`echo "${sleepTimeRaw}" | awk '{ print int($1/1440) }'`"d"
#   [[ ${sleepTimeRaw} -ge 60 ]]   && sleepTime="${sleepTime} "`echo "${sleepTimeRaw}" | awk '{ print int(($1%1440)/60) }'`"h"
#   [[ ${sleepTimeRaw} -ge 0 ]]    && sleepTime="${sleepTime} "`echo "${sleepTimeRaw}" | awk '{ print int(($1%1440%60)) }'`"m"
#   echo -e "${xNO}${xRED}${xBOLD}Asleep for ${sleepTime}${xNO}"  > /var/tmp/screen.miner.log
#   echo -e "${xNO}${xRED}${xBOLD}Asleep for ${sleepTime}${xNO}" >> /var/tmp/consoleSys.log
#   (sleep 7 && /root/utils/pwr_sleep.sh ${PWR_SLEEP_OPTIONS}) &
# elif [[ ${EXECUTE} == "setDev" ]]; then
#   sudo touch /root/dev  2> /dev/null
#   sudo rm -f /root/test 2> /dev/null
#   sync &
#   echo -e "${xNO}${xRED}${xBOLD}Rig set Dev...${xNO}" >> /var/tmp/screen.miner.log
#   echo -e "${xNO}${xRED}${xBOLD}Rig set Dev...${xNO}" >> /var/tmp/consoleSys.log
#   /root/start.sh &
# elif [[ ${EXECUTE} == "setTest" ]]; then
#   sudo rm -f /root/dev  2> /dev/null
#   sudo touch /root/test 2> /dev/null
#   sync &
#   echo -e "${xNO}${xRED}${xBOLD}Rig set Test...${xNO}" >> /var/tmp/screen.miner.log
#   echo -e "${xNO}${xRED}${xBOLD}Rig set Test...${xNO}" >> /var/tmp/consoleSys.log
#   /root/start.sh &
# elif [[ ${EXECUTE} == "beep" ]]; then
#   /root/utils/beep.sh 1> /dev/null 2> /dev/null &
# elif [[ ${EXECUTE} == setEmailBcast* ]]; then
#   killall -9 set_email_bcastc.sh 2> /dev/null
#   sleep 0.1
#   killall -9 set_email_bcastc.sh 2> /dev/null
#   sleep 0.1
#   /root/utils/set_email_bcastc.sh 1> /dev/null 2> /dev/null &
# elif [[ ${EXECUTE} == setEmail:* ]]; then
#   setEmailParams=`echo "${EXECUTE}" | sed 's/setEmail://g;'`
#   /root/utils/set_email.sh "${setEmailParams}" 1> /dev/null 2> /dev/null &
# elif [[ ${EXECUTE} == setPassword:* ]]; then
#   setPasswordParams=`echo "${EXECUTE}" | sed 's/setPassword://;'`
#   /root/utils/set_password.sh "${setPasswordParams}" 1> /dev/null 2> /dev/null &
# elif [[ ${EXECUTE} == sbox:* ]]; then
#   sboxParams=`echo "${EXECUTE}" | sed 's/sbox://g;'`
#   /root/utils/smosvpnclient.sh "${sboxParams}" 1> /dev/null 2> /dev/null &
# elif [[ ${EXECUTE} == ttyd:* ]]; then
#   sboxParams=`echo "${EXECUTE}" | sed 's/ttyd://g;'`
#   /root/utils/smosvpnclient.sh "${sboxParams}" "ttyd" 1> /dev/null 2> /dev/null &
fi

# below do only if status OK (retrieved any data from dashboard)
if [[ ${STATUS} == "ok" ]]; then
  # get interval from GUI
  REPORTSEC=`echo "${DATA}" | jq -r '.reportSec // ""' 2> /dev/null`
  [[ ! -z ${REPORTSEC} ]] && echo "${REPORTSEC}" > /var/tmp/update_status_reportsec

  # get interval-ng from GUI
  REPORT=`echo "${DATA}" | jq -r '.report // ""' 2> /dev/null`
  [[ ! -z ${REPORT} ]] && echo "${REPORT}" > /var/tmp/update_status_report

  # get minerPause variable
  minerPause=`echo "${DATA}" | jq -r '.minerPause // ""' 2> /dev/null`
  # do "touch /tmp/minerPause" for manually maintenance / debug purposes
  if [[ ${minerPause} == 1 || -f /tmp/minerPause ]]; then
    if [[ ! -f /var/tmp/minerPause ]]; then
      touch /var/tmp/minerPause 2> /dev/null
      echo -e "${xNO}${xGREEN}${xBOLD}Miner paused${xNO}" >> /var/tmp/consoleSys.log
    fi
    # make sure screen is not running
    for ((i = 1; i <= 3; i++)); do
      [[ `screen -ls | egrep '^\s*[0-9]+.miner' | sed 's/\./\n/g' | grep -v miner | head -n 1 | wc -l` == 0 ]] && break
      screen -ls | egrep '^\s*[0-9]+.miner' | sed 's/\./\n/g' | grep -v miner | xargs kill -9 2> /dev/null
      sudo killall -9 t-rex 2> /dev/null
      screen -wipe 1> /dev/null 2> /dev/null
      sleep 1
    done
  else
    if [[ -f /var/tmp/minerPause ]]; then
      echo -n > /var/tmp/screen.miner.log
      sudo rm -f /var/tmp/minerPause
      /root/start.sh &
    fi
  fi
elif [[ `echo "${DATA}" | grep -i "maintenance" | head -n 1 | wc -l` == 1 ]]; then
  # maintenance - switch to slow report
  echo "slow" > /var/tmp/update_status_report
fi
