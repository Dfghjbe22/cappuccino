#!/bin/bash

[[ `id -u` -eq 0 ]] && echo "Please run NOT as root" && exit

CONFIG_FILE="/root/config.txt"
source ${CONFIG_FILE}

# verify consoleSys.log file permissions
# could be wrong if some root script creates file firstly
ifile=/var/tmp/consoleSys.log
[[ -f ${ifile} ]] && [[ `stat -c %a ${ifile}` != "777" || `stat -c %U ${ifile}` != "miner" ]] && sudo chmod 777 ${ifile} 2> /dev/null && sudo chown miner:miner ${ifile} 2> /dev/null

JSON='{}'

# wipe all dead screens
screen -wipe 1> /dev/null 2> /dev/null
# make sure screen has enabled logfile
screen -S miner -X logfile /var/tmp/screen.miner.log 1> /dev/null 2> /dev/null
screen -S miner -X logfile flush 1 1> /dev/null 2> /dev/null
screen -S miner -X log on 1> /dev/null 2> /dev/null
# rotate/shorten logfile if too big
if [[ -e /var/tmp/screen.miner.log ]]; then
  TMP_LINES=`cat /var/tmp/screen.miner.log | wc -l`
  if [[ ${TMP_LINES} -gt 1000 ]]; then
    tail -n 100 /var/tmp/screen.miner.log > /var/tmp/screen.miner.log.tmp 2> /dev/null
    mv -f /var/tmp/screen.miner.log.tmp /var/tmp/screen.miner.log 1> /dev/null 2> /dev/null
  fi
fi

# full console
CONSOLE=`cat /var/tmp/screen.miner.log`
# add system messages
CONSOLE+=`echo; cat /var/tmp/screen.miner.log.d-* 2> /dev/null`
# if minerPause
[[ -f /var/tmp/minerPause ]] && CONSOLE+=`echo -ne "\n${xNO}${xRED}${xBOLD}Paused${xNO}"`
# convert some LIGHT colors to darken (aha drops LIGHT colors)
#96 - lightcyan -> 36 - cyan
#95 - lightmagenta -> 33 - yellow
#92 - light -> 32 - green
CONSOLE=`echo "${CONSOLE}" | sed -e 's/\[96m/\[36m/g' | sed -e 's/\[95m/\[33m/g' | sed -e 's/\[92m/\[32m/g'`
# remove nbminer 49 (default background color), which gaves me black background in aha
CONSOLE=`echo "${CONSOLE}" | sed -e 's/\[49;/\[/g'`
# remove cryptodredge "default clearing" (ESC[39;49m) not supported on some terminals causing black text text on black background
CONSOLE=`echo "${CONSOLE}" | sed -e 's/\x1B\[39m//g' -e 's/\x1B\[49m//g'`
# remove "ATTR+one space" lines "[[96m ^M" (PhoenixMiner)
CONSOLE=`echo "${CONSOLE}" | sed -e 's/^\x1B\[36m\ \r$//g'`
# remove all single and multiple ^M characters (but only on end of lines)
# replace ^M characters with our sign and delete those lines (progress bars without last occurrence)
# replace linex with spaces only (!+) to empty line wign (and later remove those lines)
# replace ^M with standard unix EOL
# replace "\\" with "_"
# remove empty lines (by greping lines with at least one character)
# limit to X lines output
# convert to HTML
CONSOLE=`echo "${CONSOLE}" | sed 's/\r\{1,\}$//g' | sed -e 's/\r/XXXDELETEXXX\n/g' | sed -e 's/^[ ]*$/XXXDELETEXXX/g' | grep -av "XXXDELETEXXX" | sed 's/\r/\n/g; s/\\\\/_/g' | grep -a . | tail -n 18 | aha --no-header`
# remove some special characters from HTML code (after AHA)
# replace [space & < > " ' '] with underscore
CONSOLE=`echo "${CONSOLE}" | sed 's/&nbsp;/_/g; s/&amp;/_/g; s/&lt;/_/g; s/&gt;/_/g; s/&quot;/_/g; s/&ldquo;/_/g; s/&rdquo;/_/g'`
# remove amp
CONSOLE=`echo "${CONSOLE}" | sed 's/\&//g' | tr '"' "'"`

# preprocessing
# remove BASH colors&codes && \r && empty lines && only last 70 lines
CONSOLE_SHORT_PRE=`cat /var/tmp/screen.miner.log | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g; s/\\\\/_/g; s/\r/\n/g' | grep -a . | tail -n 70`

# default sent zeros. Later if any miner works, then zeros will be replaced by working values
CONSOLE_SHORT=
JSON=`echo "${JSON}" | jq ".hash=\"0.00\"" | jq ".hash2=\"\"" | jq ".acc=\"0\"" | jq ".rej=\"0\""`
gpuCount=`cat /var/tmp/stats_gpu_count 2> /dev/null || echo 0`
for ((i=0; i<${gpuCount}; i++)); do
  JSON=`echo "${JSON}" | jq ".gpuHash[\"${i}\"]=\"0.00\""`
done

# create messages: sleep/pause/power off,...
ifApiParse=1
[[ -f /var/tmp/rigStart.run ]]    && CONSOLE_SHORT="Starting"   && ifApiParse=0
[[ -f /var/tmp/minerStart.run ]]  && CONSOLE_SHORT="Starting"   && ifApiParse=0
[[ -f /var/tmp/minerPause ]]      && CONSOLE_SHORT="Paused"     && ifApiParse=0
[[ -f /var/tmp/gpuDetect.run ]]   && CONSOLE_SHORT="FindGPU"    && ifApiParse=0
[[ -f /var/tmp/rigReboot.run ]]   && CONSOLE_SHORT="Rebooting"  && ifApiParse=0
[[ -f /var/tmp/rigPowerOff.run ]] && CONSOLE_SHORT="PowerOFF"   && ifApiParse=0
[[ -f /var/tmp/rigSleep.run ]]    && CONSOLE_SHORT="Sleeping"   && ifApiParse=0
if [[ -f /var/tmp/reflashing.run ]]; then
  # get CONSOLEs content prepared by chroot script
  CONSOLE_SHORT=`cat /var/tmp/M2Sfs/CONSOLE_SHORT 2> /dev/null || echo "Reflashing"`
  CONSOLE=`      cat /var/tmp/M2Sfs/CONSOLE       2> /dev/null || echo "${CONSOLE}"`
  ifApiParse=0
fi
[[ -f /var/tmp/screen.miner.log.d-watchdog_system_ro ]] && CONSOLE_SHORT="Error"
# send only beacon (overwrite any prev option) if present
[[ -f /var/tmp/beacon ]] && CONSOLE_SHORT="beacon:"`cat /var/tmp/beacon 2> /dev/null`

if [[ ${ifApiParse} == 1 ]]; then
  minerUptime=`date -d "now - $(stat -c "%Y" /var/tmp/miner) seconds" +%s`
  # show missing API command option for miner starting 10sec since miner start
  [[ ${minerUptime} -ge 10 ]] && minerApiWrn=1 || minerApiWrn=

  ### avermore
  if [[ $(echo "${MINER_PATH}" | grep -i "/avermore" | head -n 1 | wc -l) == 1 ]]; then
    DATA=`echo '{"command":"summary"}' | timeout 5 nc -q 0 127.0.0.1 4028`
    if [[ -z ${DATA} ]]; then
      CONSOLE+="\n<span style='color:red;'><b>Please add to miner options in order to see stats: -api-listen (or wait if miner is just starting)</b></span>"
    else
      hash=`echo "${DATA}" | jq -r '.SUMMARY[0]."KHS 5s"' | awk '{ printf "%.2f", $1*1000 }'`
      acc=`echo "${DATA}"  | jq -r '.Accepted'`
      rej=`echo "${DATA}"  | jq -r '.Rejected'`
      JSON=`echo "${JSON}" | jq ".hash=\"${hash}\"" | jq ".acc=\"${acc}\"" | jq ".rej=\"${rej}\""`
    fi
  fi
  ### beam-cuda-miner
  if [[ $(echo "${MINER_PATH}" | grep -i "/beam-cuda-miner" | head -n 1 | wc -l) == 1 ]]; then
    DATA=`timeout 5 curl -s http://127.0.0.1:4080`
    if [[ -z ${DATA} ]]; then
      [[ ${minerApiWrn} ]] && CONSOLE+="\n<span style='color:red;'><b>Please add to miner options in order to see stats: --enable-api (or wait if miner is just starting)</b></span>"
    else
      hash=`echo "${DATA}" | jq -r '.hs_total' | awk '{ printf "%.2f", $1*1000 }'`
      acc=`echo "${DATA}"  | jq -r '.ar[0]'`
      rej=`echo "${DATA}"  | jq -r '.ar[1]'`
      JSON=`echo "${JSON}" | jq ".hash=\"${hash}\"" | jq ".acc=\"${acc}\"" | jq ".rej=\"${rej}\""`
      gpuHash=(`echo "${DATA}" | jq -r '.hs[]' | sed 's/^$/n\/a/g'`)
      for ((i=0; i<${#gpuHash[@]}; i++)); do
        igpuHash=`echo | awk "{ printf \"%.2f\", ${gpuHash[$i]}*1000 }"`
        JSON=`echo "${JSON}" | jq ".gpuHash[\"${i}\"]=\"${igpuHash}\""`
      done
    fi
  fi
  ### bminer
  if [[ $(echo "${MINER_PATH}" | grep -i "/bminer" | head -n 1 | wc -l) == 1 ]]; then
    DATA=`timeout 5 curl -s http://127.0.0.1:1880/api/status`
    if [[ -z ${DATA} ]]; then
      [[ ${minerApiWrn} ]] && CONSOLE+="\n<span style='color:red;'><b>Please add to miner options in order to see stats: -api 127.0.0.1:1880 (or wait if miner is just starting)</b></span>"
    else
      hash=`echo "${DATA}" | jq -r '.miners[].solver.solution_rate' | paste -s -d+ | bc | awk '{ printf "%.2f", $1 }'`
      acc=`echo "${DATA}"  | jq -r '.stratum.accepted_shares'`
      rej=`echo "${DATA}"  | jq -r '.stratum.rejected_shares'`
      JSON=`echo "${JSON}" | jq ".hash=\"${hash}\"" | jq ".acc=\"${acc}\"" | jq ".rej=\"${rej}\""`
      gpuHash=(`echo "${DATA}" | jq -r '.miners[].solver.solution_rate' | sed 's/^$/n\/a/g'`)
      for ((i=0; i<${#gpuHash[@]}; i++)); do
        JSON=`echo "${JSON}" | jq ".gpuHash[\"${i}\"]=\"${gpuHash[$i]}\""`
      done
    fi
  fi
  ### bzminer
  if [[ $(echo "${MINER_PATH}" | grep -i "/bzminer" | head -n 1 | wc -l) == 1 ]]; then
    DATA=`timeout 5 curl -s http://127.0.0.1:4014/status`
    if [[ -z ${DATA} ]]; then
      :
    else
      hash=`echo "${DATA}" | jq -r '.devices[].hashrate[0]' | paste -s -d+ | bc | awk '{ printf "%.2f", $1 }'`
      share=`echo "${DATA}" | jq -r '.pools[0].total_solutions'`
      rej=`echo "${DATA}"   | jq -r '.pools[0].rejected_solutions'`
      acc=`echo | awk "{ printf \"%.2f\", ${share}-${rej} }"`
      JSON=`echo "${JSON}" | jq ".hash=\"${hash}\"" | jq ".acc=\"${acc}\"" | jq ".rej=\"${rej}\""`
      gpuHash=(`echo "${DATA}" | jq -r '.devices[].hashrate[0]' | sed 's/^$/n\/a/g'`)
      for ((i=0; i<${#gpuHash[@]}; i++)); do
        JSON=`echo "${JSON}" | jq ".gpuHash[\"${i}\"]=\"${gpuHash[$i]}\""`
      done

      dualMine=`echo ${DATA} | jq -r 'try .pools[1].id // null'`
      if [[ ${dualMine} != "null" ]]; then
        hash2=`echo "${DATA}" | jq -r '.devices[].hashrate[1]' | paste -s -d+ | bc | awk '{ printf "%.2f", $1 }'`
        share2=`echo "${DATA}" | jq -r '.pools[1].total_solutions'`
        rej2=`echo "${DATA}"   | jq -r '.pools[1].rejected_solutions'`
        acc2=`echo | awk "{ printf \"%.2f\", ${share2}-${rej2} }"`
        JSON=`echo "${JSON}" | jq ".hash2=\"${hash2}\"" | jq ".acc2=\"${acc2}\"" | jq ".rej2=\"${rej2}\""`
        gpuHash2=(`echo "${DATA}" | jq -r '.devices[].hashrate[1]' | sed 's/^$/n\/a/g'`)
        for ((i=0; i<${#gpuHash2[@]}; i++)); do
          JSON=`echo "${JSON}" | jq ".gpuHash2[\"${i}\"]=\"${gpuHash2[$i]}\""`
        done
      fi
    fi
  fi
  ### ccminer alexis78
  if [[ $(echo "${MINER_PATH}" | grep -i "/ccminer.*alexis78" | head -n 1 | wc -l) == 1 ]]; then
    DATA=`echo "summary" | timeout 5 nc -q 0 127.0.0.1 4068 | sed -e 's/;/\n/g'`
    if [[ -z ${DATA} ]]; then
      :
    else
      hash=`echo "${DATA}" | grep "^KHS=" | awk -F"=" '{ print $2 }' | awk '{ printf "%.2f", $1*1000 }'`
      acc=`echo "${DATA}"  | grep "^ACC=" | awk -F"=" '{ print $2 }'`
      rej=`echo "${DATA}"  | grep "^REJ=" | awk -F"=" '{ print $2 }'`
      JSON=`echo "${JSON}" | jq ".hash=\"${hash}\"" | jq ".acc=\"${acc}\"" | jq ".rej=\"${rej}\""`
    fi
  fi
  ### ccminer KlausT
  if [[ $(echo "${MINER_PATH}" | grep -i "/ccminer.*klaust" | head -n 1 | wc -l) == 1 ]]; then
    DATA=`echo "summary" | timeout 5 nc -q 0 127.0.0.1 4068 | sed -e 's/;/\n/g'`
    if [[ -z ${DATA} ]]; then
      [[ ${minerApiWrn} ]] && CONSOLE+="\n<span style='color:red;'><b>Please add to miner options in order to see stats: --api-bind=127.0.0.1:4068 (or wait if miner is just starting)</b></span>"
    else
      hash=`echo "${DATA}" | grep "^KHS=" | awk -F"=" '{ print $2 }' | awk '{ printf "%.2f", $1*1000 }'`
      acc=`echo "${DATA}"  | grep "^ACC=" | awk -F"=" '{ print $2 }'`
      rej=`echo "${DATA}"  | grep "^REJ=" | awk -F"=" '{ print $2 }'`
      JSON=`echo "${JSON}" | jq ".hash=\"${hash}\"" | jq ".acc=\"${acc}\"" | jq ".rej=\"${rej}\""`
    fi
  fi
  ### ccminer monkin1010 (veruscoin)
  if [[ $(echo "${MINER_PATH}" | grep -i "/ccminer.*monkins1010" | head -n 1 | wc -l) == 1 ]]; then
    DATA=`echo "summary" | timeout 5 nc -q 0 127.0.0.1 4068 | sed -e 's/;/\n/g'`
    if [[ -z ${DATA} ]]; then
      :
    else
      hash=`echo "${DATA}" | grep -a "^KHS=" | awk -F"=" '{ print $2 }' | awk '{ printf "%.2f", $1*1000 }'`
      acc=`echo "${DATA}"  | grep -a "^ACC=" | awk -F"=" '{ print $2 }'`
      rej=`echo "${DATA}"  | grep -a "^REJ=" | awk -F"=" '{ print $2 }'`
      JSON=`echo "${JSON}" | jq ".hash=\"${hash}\"" | jq ".acc=\"${acc}\"" | jq ".rej=\"${rej}\""`
    fi
  fi
  ### ccminer-mtp-krnlx
  if [[ $(echo "${MINER_PATH}" | grep -i "/ccminer-mtp-krnlx" | head -n 1 | wc -l) == 1 ]]; then
    DATA=`echo "summary" | timeout 5 nc -q 0 127.0.0.1 4068 | sed -e 's/;/\n/g'`
    if [[ -z ${DATA} ]]; then
      [[ ${minerApiWrn} ]] && CONSOLE+="\n<span style='color:red;'><b>Please add to miner options in order to see stats: --api-bind=127.0.0.1:4068 (or wait if miner is just starting)</b></span>"
    else
      hash=`echo "${DATA}" | grep "^KHS=" | awk -F"=" '{ print $2 }' | awk '{ printf "%.2f", $1*1000 }'`
      acc=`echo "${DATA}"  | grep "^ACC=" | awk -F"=" '{ print $2 }'`
      rej=`echo "${DATA}"  | grep "^REJ=" | awk -F"=" '{ print $2 }'`
      JSON=`echo "${JSON}" | jq ".hash=\"${hash}\"" | jq ".acc=\"${acc}\"" | jq ".rej=\"${rej}\""`
    fi
  fi
  ### ccminer-tpruvot
  if [[ $(echo "${MINER_PATH}" | grep -i "/ccminer-tpruvot" | head -n 1 | wc -l) == 1 ]]; then
    DATA=`echo "summary" | timeout 5 nc -q 0 127.0.0.1 4068 | sed -e 's/;/\n/g'`
    if [[ -z ${DATA} ]]; then
      :
    else
      hash=`echo "${DATA}" | grep "^KHS=" | awk -F"=" '{ print $2 }' | awk '{ printf "%.2f", $1*1000 }'`
      acc=`echo "${DATA}"  | grep "^ACC=" | awk -F"=" '{ print $2 }'`
      rej=`echo "${DATA}"  | grep "^REJ=" | awk -F"=" '{ print $2 }'`
      JSON=`echo "${JSON}" | jq ".hash=\"${hash}\"" | jq ".acc=\"${acc}\"" | jq ".rej=\"${rej}\""`
    fi
  fi
  ### ccminer-zcoinofficial-djm34
  if [[ $(echo "${MINER_PATH}" | grep -i "/ccminer-zcoinofficial-djm34" | head -n 1 | wc -l) == 1 ]]; then
    DATA=`echo "summary" | timeout 5 nc -q 0 127.0.0.1 4068 | sed -e 's/;/\n/g'`
    if [[ -z ${DATA} ]]; then
      :
    else
      hash=`echo "${DATA}" | grep "^KHS=" | awk -F"=" '{ print $2 }' | awk '{ printf "%.2f", $1*1000 }'`
      acc=`echo "${DATA}"  | grep "^ACC=" | awk -F"=" '{ print $2 }'`
      rej=`echo "${DATA}"  | grep "^REJ=" | awk -F"=" '{ print $2 }'`
      JSON=`echo "${JSON}" | jq ".hash=\"${hash}\"" | jq ".acc=\"${acc}\"" | jq ".rej=\"${rej}\""`
    fi
  fi
  ### claymore
  if [[ $(echo "${MINER_PATH}" | grep -i "/claymore" | head -n 1 | wc -l) == 1 ]]; then
    DATA=`echo '{"id":0,"jsonrpc":"2.0","method":"miner_getstat2"}' | timeout 5 nc -q 0 127.0.0.1 3333`
    if [[ -z ${DATA} ]]; then
      [[ ${minerApiWrn} ]] && CONSOLE+="\n<span style='color:red;'><b>Please add to miner options in order to see stats: -mport 127.0.0.1:3333 (or wait if miner is just starting)</b></span>"
    else
      hash=`echo "${DATA}"  | jq -r '.result[2]' | awk -F";" '{ print $1 }' | awk '{ printf "%.2f", $1*1000 }'`
      share=`echo "${DATA}" | jq -r '.result[2]' | awk -F";" '{ print $2 }'`
      rej=`echo "${DATA}"   | jq -r '.result[2]' | awk -F";" '{ print $3 }'`
      acc=`echo | awk "{ printf \"%.2f\", ${share}-${rej} }"`
      JSON=`echo "${JSON}" | jq ".hash=\"${hash}\"" | jq ".acc=\"${acc}\"" | jq ".rej=\"${rej}\""`
      gpuHash=(`echo "${DATA}" | jq -r '.result[3]' | sed -e 's/;/\n/g' | sed 's/^$/n\/a/g'`)
      # PCI numbers of physical GPUs
      tmpGpuPci=`cat /var/tmp/stats_gpu_pcibus_jq 2>/dev/null | jq -c 'to_entries[]'`
      gpuPci=(`echo "${DATA}" | jq -r '.result[15]' | sed -e 's/;/\n/g' | sed 's/^$/n\/a/g'`)
      for ((i=0; i<${#gpuHash[@]}; i++)); do
        # PCI nr
        igpuPci=`echo | awk "{ printf \"%02x\", ${gpuPci[$i]} }"`
        # PCI nr to cardX nr
        icardIdx=`echo "${tmpGpuPci}" | grep -i "\"value\":\"$igpuPci" | jq -r '.key'`
        # Hash rate
        igpuHash=`echo | awk "{ printf \"%.2f\", ${gpuHash[$i]}*1000 }"`
        # JSON=`echo "${JSON}" | jq ".gpuHash[\"${i}\"]=\"${igpuHash}\""`
        JSON=`echo "${JSON}" | jq ".gpuHash[\"${icardIdx}\"]=\"${igpuHash}\""`
      done
    fi
  fi
  ### cryptodredge
  if [[ $(echo "${MINER_PATH}" | grep -i "/cryptodredge" | head -n 1 | wc -l) == 1 ]]; then
    DATA=`echo "summary" | timeout 5 nc -q 0 127.0.0.1 4068 | sed -e 's/;/\n/g'`
    DATA2=`echo "threads" | timeout 5 nc -q 0 127.0.0.1 4068 | sed -e 's/;/\n/g'`
    if [[ -z ${DATA} ]]; then
      [[ ${minerApiWrn} ]] && CONSOLE+="\n<span style='color:red;'><b>Please add to miner options in order to see stats: --api-bind 127.0.0.1:4068 (or wait if miner is just starting)</b></span>"
    else
      hash=`echo "${DATA}" | grep "^KHS=" | awk -F"=" '{ print $2 }' | awk '{ printf "%.2f", $1*1000 }'`
      acc=`echo "${DATA}"  | grep "^ACC=" | awk -F"=" '{ print $2 }'`
      rej=`echo "${DATA}"  | grep "^REJ=" | awk -F"=" '{ print $2 }'`
      JSON=`echo "${JSON}" | jq ".hash=\"${hash}\"" | jq ".acc=\"${acc}\"" | jq ".rej=\"${rej}\""`
      gpuHash=(`echo "${DATA2}" | grep "^KHS=" | awk -F= '{ print $2 }'`)
      # PCI numbers of physical GPUs
      tmpGpuPci=`cat /var/tmp/stats_gpu_pcibus_jq 2>/dev/null | jq -c 'to_entries[]'`
      gpuPci=(`echo "${DATA2}" | grep "^BUS=" | awk -F= '{ print $2 }'`)
      for ((i=0; i<${#gpuHash[@]}; i++)); do
        # PCI nr
        igpuPci=`echo | awk "{ printf \"%02x\", ${gpuPci[$i]} }"`
        # PCI nr to cardX nr
        icardIdx=`echo "${tmpGpuPci}" | grep -i "\"value\":\"$igpuPci" | jq -r '.key'`
        # Hash rate
        igpuHash=`echo | awk "{ printf \"%.2f\", ${gpuHash[$i]}*1000 }"`
        # JSON=`echo "${JSON}" | jq ".gpuHash[\"${i}\"]=\"${igpuHash}\""`
        JSON=`echo "${JSON}" | jq ".gpuHash[\"${icardIdx}\"]=\"${igpuHash}\""`
      done
    fi
  fi
  ### dstm
  if [[ $(echo "${MINER_PATH}" | grep -i "/dstm" | head -n 1 | wc -l) == 1 ]]; then
    DATA=`echo '{"method": "miner_getstat1", "jsonrpc": "2.0", "id": 1 }' | timeout 5 nc -q 0 127.0.0.1 2222`
    if [[ -z ${DATA} ]]; then
      [[ ${minerApiWrn} ]] && CONSOLE+="\n<span style='color:red;'><b>Please add to miner options in order to see stats: --telemetry (or wait if miner is just starting)</b></span>"
    else
      hash=`echo "${DATA}" | jq -r '.result[].sol_ps' | paste -s -d+ | bc | awk '{ printf "%.2f", $1 }'`
      acc=`echo "${DATA}"  | jq -r '.result[].accepted_shares' | paste -s -d+ | bc`
      rej=`echo "${DATA}"  | jq -r '.result[].rejected_shares' | paste -s -d+ | bc`
      JSON=`echo "${JSON}" | jq ".hash=\"${hash}\"" | jq ".acc=\"${acc}\"" | jq ".rej=\"${rej}\""`
      gpuHash=(`echo "${DATA}" | jq -r '.result[].sol_ps' | sed 's/^$/n\/a/g'`)
      for ((i=0; i<${#gpuHash[@]}; i++)); do
        JSON=`echo "${JSON}" | jq ".gpuHash[\"${i}\"]=\"${gpuHash[$i]}\""`
      done
    fi
  fi
  ### enemy
  if [[ $(echo "${MINER_PATH}" | grep -i "/enemy" | head -n 1 | wc -l) == 1 ]]; then
    DATA=`echo "summary" | timeout 5 nc -q 0 127.0.0.1 4068 | sed -e 's/;/\n/g'`
    if [[ -z ${DATA} ]]; then
      :
    else
      hash=`echo "${DATA}" | grep "^KHS=" | awk -F"=" '{ print $2 }' | awk '{ printf "%.2f", $1*1000 }'`
      acc=`echo "${DATA}"  | grep "^ACC=" | awk -F"=" '{ print $2 }'`
      rej=`echo "${DATA}"  | grep "^REJ=" | awk -F"=" '{ print $2 }'`
      JSON=`echo "${JSON}" | jq ".hash=\"${hash}\"" | jq ".acc=\"${acc}\"" | jq ".rej=\"${rej}\""`
    fi
  fi
  ### ethminer
  if [[ $(echo "${MINER_PATH}" | grep -i "/ethminer" | head -n 1 | wc -l) == 1 ]]; then
    DATA=`echo '{"method": "miner_getstat1", "jsonrpc": "2.0", "id": 1 }' | timeout 5 nc -q 0 127.0.0.1 3333`
    if [[ -z ${DATA} ]]; then
      [[ ${minerApiWrn} ]] && CONSOLE+="\n<span style='color:red;'><b>Please add to miner options in order to see stats: --api 3333 (or wait if miner is just starting)</b></span>"
    else
      hash=`echo "${DATA}"  | jq -r '.result[2]' | awk -F";" '{ print $1 }' | awk '{ printf "%.2f", $1*1000 }'`
      share=`echo "${DATA}" | jq -r '.result[2]' | awk -F";" '{ print $2 }'`
      rej=`echo "${DATA}"   | jq -r '.result[2]' | awk -F";" '{ print $3 }'`
      acc=`echo | awk "{ printf \"%.2f\", ${share}-${rej} }"`
      JSON=`echo "${JSON}" | jq ".hash=\"${hash}\"" | jq ".acc=\"${acc}\"" | jq ".rej=\"${rej}\""`
      gpuHash=(`echo "${DATA}" | jq -r '.result[3]' | sed -e 's/;/\n/g' | sed 's/^$/n\/a/g'`)
      for ((i=0; i<${#gpuHash[@]}; i++)); do
        igpuHash=`echo | awk "{ printf \"%.2f\", ${gpuHash[$i]}*1000 }"`
        JSON=`echo "${JSON}" | jq ".gpuHash[\"${i}\"]=\"${igpuHash}\""`
      done
    fi
  fi
  ### ewbf
  if [[ $(echo "${MINER_PATH}" | grep -i "/ewbf" | head -n 1 | wc -l) == 1 ]]; then
    DATA=`echo '{"id":"0", "method":"getstat"}' | timeout 5 nc -q 0 127.0.0.1 42000`
    if [[ -z ${DATA} ]]; then
      :
    else
      hash=`echo "${DATA}" | jq -r '.result[].speed_sps' | paste -s -d+ | bc | awk '{ printf "%.2f", $1 }'`
      acc=`echo "${DATA}"  | jq -r '.result[].accepted_shares' | paste -s -d+ | bc`
      rej=`echo "${DATA}"  | jq -r '.result[].rejected_shares' | paste -s -d+ | bc`
      JSON=`echo "${JSON}" | jq ".hash=\"${hash}\"" | jq ".acc=\"${acc}\"" | jq ".rej=\"${rej}\""`
      gpuHash=(`echo "${DATA}" | jq -r '.result[].speed_sps' | sed 's/^$/n\/a/g'`)
      for ((i=0; i<${#gpuHash[@]}; i++)); do
        JSON=`echo "${JSON}" | jq ".gpuHash[\"${i}\"]=\"${gpuHash[$i]}\""`
      done
    fi
  fi
   ### fahclient (coronavirus miner)
  if [[ $(echo "${MINER_PATH}" | grep -i "/fahclient" | head -n 1 | wc -l) == 1 ]]; then
    DATA=`echo "queue-info" | timeout 5 nc -q 0 127.0.0.1 36330 | sed 1,3d | sed s'/[>-]/ /g'`
    if [[ -z ${DATA} ]]; then
      :
    else
      hash=`echo "${DATA}"  | jq -r '.[].ppd' | paste -s -d+ | bc | awk '{ printf "%.2f", $1 }'`
      JSON=`echo "${JSON}" | jq ".hash=\"${hash}\""`

      gpuHash=(`echo "${DATA}" | jq -r '.[].ppd'`)
      gpuStatus=(`echo "${DATA}" | jq -r '.[].state' | awk '{ print substr($0, 1, 1) }' | sed 's/^$/0/g'`)
      GPU_STATUS_JSON="{}"
      # PCI numbers of physical GPUs
      tmpGpuPci=`cat /var/tmp/stats_gpu_pcibus_jq 2>/dev/null | jq -c 'to_entries[]'`
      gpuPci=(`echo "${DATA}" | jq -r '.[].slot'`)
      for ((i=0; i<${#gpuHash[@]}; i++)); do
        if [[ ${gpuPci[$i]} == "null" || ${gpuPci[$i]} == "" ]]; then
          icardIdx=${i}
        else
          # fix order (it is not assigning with PCInr as in phoenixminer)
          # also delete leading zero
          icardIdx=`echo "${gpuPci[$i]}" | awk '{ printf "%.0f", $1 }'`
        fi
        # Hash rate
        igpuHash=`echo | awk "{ printf \"%.2f\", ${gpuHash[$i]} }"`
        # status
        igpuStatus=${gpuStatus[$i]}
        JSON=`echo "${JSON}" | jq ".gpuHash[\"${icardIdx}\"]=\"${igpuHash}\""`
        GPU_STATUS_JSON=`echo "${GPU_STATUS_JSON}" | jq ".gpuStatus[\"${icardIdx}\"]=\"${igpuStatus}\""`
      done
      CONSOLE_SHORT=`echo "${GPU_STATUS_JSON}" | jq -r '.gpuStatus[]' | tr -d '\n'`
    fi
  fi
  ### gminer
  if [[ $(echo "${MINER_PATH}" | grep -i "/gminer" | head -n 1 | wc -l) == 1 ]]; then
    DATA=`timeout 5 curl -s http://127.0.0.1:3333/stat`
    if [[ -z ${DATA} ]]; then
      [[ ${minerApiWrn} ]] && CONSOLE+="\n<span style='color:red;'><b>Please add to miner options in order to see stats: --api 3333 (or wait if miner is just starting)</b></span>"
    else
      unit=`echo "${DATA}" | jq -r 'try .speed_unit // null'`
      unitMul=1 # H/s and Sol/s
      [[ ${unit} == "K/s" ]] && unitMul=1000
      [[ ${unit} == "M/s" ]] && unitMul=1000000
      [[ ${unit} == "G/s" ]] && unitMul=1000000000
      hash=`echo "${DATA}" | jq -r 'try .devices[].speed // 0' | paste -s -d+ | bc | awk '{ printf "%.2f", $1 }'`
      hash=`echo | awk "{ printf \"%.2f\", ${hash}*${unitMul} }"`
      acc=`echo "${DATA}"  | jq -r 'try .total_accepted_shares // 0'`
      rej=`echo "${DATA}"  | jq -r 'try .total_rejected_shares // 0'`
      JSON=`echo "${JSON}" | jq ".hash=\"${hash}\"" | jq ".acc=\"${acc}\"" | jq ".rej=\"${rej}\""`
      gpuHash=(`echo "${DATA}" | jq -r 'try .devices[].speed // 0' | sed -e 's/;/\n/g' | sed 's/^$/n\/a/g'`)
      # PCI numbers of physical GPUs
      tmpGpuPci=`cat /var/tmp/stats_gpu_pcibus_jq 2> /dev/null | jq -c 'to_entries[]'`
      gpuPci=(`echo "${DATA}" | jq -r 'try .devices[].bus_id // 0' | awk -F":" '{ print $2 }'`)
      for ((i=0; i<${#gpuHash[@]}; i++)); do
        # PCI nr
        igpuPci=`echo ${gpuPci[$i]}`
        # PCI nr to cardX nr
        icardIdx=`echo "${tmpGpuPci}" | grep -i "\"value\":\"${igpuPci}" | jq -r '.key'`
        # Hash rate
        igpuHash=`echo | awk "{ printf \"%.2f\", ${gpuHash[$i]}*${unitMul} }"`
        # JSON=`echo "${JSON}" | jq ".gpuHash[\"${i}\"]=\"${igpuHash}\""`
        JSON=`echo "${JSON}" | jq ".gpuHash[\"${icardIdx}\"]=\"${igpuHash}\""`
      done
      dualMine=`echo ${DATA} | jq -r 'try .total_accepted_shares2 // null'`
      if [[ ${dualMine} != "null" ]]; then
        unit2=`echo "${DATA}" | jq -r 'try .speed_unit2 // null'`
        unitMul2=1 # H/s and Sol/s
        [[ ${unit2} == "K/s" ]] && unitMul2=1000
        [[ ${unit2} == "M/s" ]] && unitMul2=1000000
        [[ ${unit2} == "G/s" ]] && unitMul2=1000000000
        hash2=`echo "${DATA}" | jq -r 'try .devices[].speed2 // 0' | paste -s -d+ | bc | awk '{ printf "%.2f", $1 }'`
        hash2=`echo | awk "{ printf \"%.2f\", ${hash2}*${unitMul2} }"`
        acc2=`echo "${DATA}"  | jq -r 'try .total_accepted_shares2 // 0'`
        rej2=`echo "${DATA}"  | jq -r 'try .total_rejected_shares2 // 0'`
        JSON=`echo "${JSON}" | jq ".hash2=\"${hash2}\"" | jq ".acc2=\"${acc2}\"" | jq ".rej2=\"${rej2}\""`
        gpuHash2=(`echo "${DATA}" | jq -r 'try .devices[].speed2 // 0' | sed -e 's/;/\n/g' | sed 's/^$/n\/a/g'`)
        # PCI numbers of physical GPUs
        #tmpGpuPci=`cat /var/tmp/stats_gpu_pcibus_jq 2> /dev/null | jq -c 'to_entries[]'`
        #gpuPci=(`echo "${DATA}" | jq -r 'try .devices[].bus_id // 0' | awk -F":" '{ print $2 }'`)
        for ((i=0; i<${#gpuHash2[@]}; i++)); do
          # PCI nr
          igpuPci=`echo ${gpuPci[$i]}`
          # PCI nr to cardX nr
          icardIdx=`echo "${tmpGpuPci}" | grep -i "\"value\":\"${igpuPci}" | jq -r '.key'`
          # Hash rate
          igpuHash2=`echo | awk "{ printf \"%.2f\", ${gpuHash2[$i]}*${unitMul2} }"`
          # JSON=`echo "${JSON}" | jq ".gpuHash2[\"${i}\"]=\"${igpuHash2}\""`
          JSON=`echo "${JSON}" | jq ".gpuHash2[\"${icardIdx}\"]=\"${igpuHash2}\""`
        done
      fi
    fi
  fi
  ### kawpowminer
  if [[ $(echo "${MINER_PATH}" | grep -i "/kawpowminer" | head -n 1 | wc -l) == 1 ]]; then
    DATA=`echo '{"method": "miner_getstat1", "jsonrpc": "2.0", "id": 1 }' | timeout 5 nc -q 0 127.0.0.1 3333`
    if [[ -z ${DATA} ]]; then
      [[ ${minerApiWrn} ]] && CONSOLE+="\n<span style='color:red;'><b>Please add to miner options in order to see stats: --api 3333 (or wait if miner is just starting)</b></span>"
    else
      hash=`echo "${DATA}"  | jq -r '.result[2]' | awk -F";" '{ print $1 }' | awk '{ printf "%.2f", $1*1000 }'`
      share=`echo "${DATA}" | jq -r '.result[2]' | awk -F";" '{ print $2 }'`
      rej=`echo "${DATA}"   | jq -r '.result[2]' | awk -F";" '{ print $3 }'`
      acc=`echo | awk "{ printf \"%.2f\", ${share}-${rej} }"`
      JSON=`echo "${JSON}" | jq ".hash=\"${hash}\"" | jq ".acc=\"${acc}\"" | jq ".rej=\"${rej}\""`
      gpuHash=(`echo "${DATA}" | jq -r '.result[3]' | sed -e 's/;/\n/g' | sed 's/^$/n\/a/g'`)
      for ((i=0; i<${#gpuHash[@]}; i++)); do
        igpuHash=`echo | awk "{ printf \"%.2f\", ${gpuHash[$i]}*1000 }"`
        JSON=`echo "${JSON}" | jq ".gpuHash[\"${i}\"]=\"${igpuHash}\""`
      done
    fi
  fi
  ### lolminer
  if [[ $(echo "${MINER_PATH}" | grep -i "/lolminer" | head -n 1 | wc -l) == 1 ]]; then
    DATA=`timeout 5 curl -s http://127.0.0.1:4444/summary`
    if [[ -z ${DATA} ]]; then
      [[ ${minerApiWrn} ]] && CONSOLE+="\n<span style='color:red;'><b>Please add to miner options in order to see stats: --apiport 4444 (or wait if miner is just starting)</b></span>"
    else
      # since 1.43 there is a new API (dual mining support) - not compatible backwards
      lolminer143=`echo ${DATA} | jq -r 'try .Algorithms // null'`
      if [[ ${lolminer143} != "null" ]]; then
        numAlgo=`echo "${DATA}" | jq -r 'try .Num_Algorithms // 1'`

        unit=`echo "${DATA}" | jq -r 'try .Algorithms[0].Performance_Unit // ""'`
        if [[ ${unit} == "Mh/s" ]]; then
          hash=`echo "${DATA}" | jq -r 'try .Algorithms[0].Total_Performance // 0' | awk '{ printf "%.2f", $1*1000*1000 }'`
        else
          hash=`echo "${DATA}" | jq -r 'try .Algorithms[0].Total_Performance // 0' | awk '{ printf "%.2f", $1 }'`
        fi
        acc=`echo "${DATA}" | jq -r 'try .Algorithms[0].Total_Accepted // 0'`
        rej=`echo "${DATA}" | jq -r 'try .Algorithms[0].Total_Rejected // 0'`
        JSON=`echo "${JSON}" | jq ".hash=\"${hash}\"" | jq ".acc=\"${acc}\"" | jq ".rej=\"${rej}\""`
        if [[ ${unit} == "Mh/s" ]]; then
          gpuHash=(`echo "${DATA}" | jq -r 'try .Algorithms[0].Worker_Performance[] // 0' | sed 's/^$/n\/a/g' | awk '{ printf "%.2f\n", $1*1000*1000 }'`)
        else
          gpuHash=(`echo "${DATA}" | jq -r 'try .Algorithms[0].Worker_Performance[] // 0' | sed 's/^$/n\/a/g' | awk '{ printf "%.2f\n", $1 }'`)
        fi
        for ((i=0; i<${#gpuHash[@]}; i++)); do
          JSON=`echo "${JSON}" | jq ".gpuHash[\"${i}\"]=\"${gpuHash[$i]}\""`
        done
        if [[ ${numAlgo} -ge 2 ]]; then
          unit2=`echo "${DATA}" | jq -r 'try .Algorithms[1].Performance_Unit // ""'`
          if [[ ${unit2} == "Mh/s" ]]; then
            hash2=`echo "${DATA}" | jq -r 'try .Algorithms[1].Total_Performance // 0' | awk '{ printf "%.2f", $1*1000*1000 }'`
          else
            hash2=`echo "${DATA}" | jq -r 'try .Algorithms[1].Total_Performance // 0' | awk '{ printf "%.2f", $1 }'`
          fi
          acc2=`echo "${DATA}" | jq -r 'try .Algorithms[1].Total_Accepted // 0'`
          rej2=`echo "${DATA}" | jq -r 'try .Algorithms[1].Total_Rejected // 0'`
          JSON=`echo "${JSON}" | jq ".hash2=\"${hash2}\"" | jq ".acc2=\"${acc2}\"" | jq ".rej2=\"${rej2}\""`
          if [[ ${unit2} == "Mh/s" ]]; then
            gpuHash2=(`echo "${DATA}" | jq -r 'try .Algorithms[1].Worker_Performance[] // 0' | sed 's/^$/n\/a/g' | awk '{ printf "%.2f\n", $1*1000*1000 }'`)
          else
            gpuHash2=(`echo "${DATA}" | jq -r 'try .Algorithms[1].Worker_Performance[] // 0' | sed 's/^$/n\/a/g'| awk '{ printf "%.2f\n", $1 }'`)
          fi
          for ((i=0; i<${#gpuHash2[@]}; i++)); do
            JSON=`echo "${JSON}" | jq ".gpuHash2[\"${i}\"]=\"${gpuHash2[$i]}\""`
          done
        fi
      else
        # up to lolMiner 1.42
        unit=`echo "${DATA}" | jq -r '.Session.Performance_Unit'`
        if [[ ${unit} == "mh/s" ]]; then
          # Ethash
          hash=`echo "${DATA}"  | jq -r '.Session.Performance_Summary' | awk '{ printf "%.2f", $1*1000*1000 }'`
        else
          hash=`echo "${DATA}"  | jq -r '.Session.Performance_Summary' | awk '{ printf "%.2f", $1 }'`
        fi
        share=`echo "${DATA}" | jq -r '.Session.Submitted'`
        acc=`echo "${DATA}"   | jq -r '.Session.Accepted'`
        rej=`echo | awk "{ printf \"%.2f\", ${share}-${acc} }"`
        JSON=`echo "${JSON}" | jq ".hash=\"${hash}\"" | jq ".acc=\"${acc}\"" | jq ".rej=\"${rej}\""`
        if [[ ${unit} == "mh/s" ]]; then
          gpuHash=(`echo "${DATA}" | jq -r '.GPUs[].Performance' | sed 's/^$/n\/a/g' | awk '{ printf "%.2f\n", $1*1000*1000 }'`)
        else
          gpuHash=(`echo "${DATA}" | jq -r '.GPUs[].Performance' | sed 's/^$/n\/a/g'`)
        fi
        for ((i=0; i<${#gpuHash[@]}; i++)); do
          JSON=`echo "${JSON}" | jq ".gpuHash[\"${i}\"]=\"${gpuHash[$i]}\""`
        done
      fi
    fi
  fi
  ## miniz
  if [[ $(echo "${MINER_PATH}" | grep -i "/miniz" | head -n 1 | wc -l) == 1 ]]; then
    # DATA=`timeout 5 curl -s 127.0.0.1:20000 -X '{"id":"0", "method":"getstat"}'` # just guess this method in Ub16
    # DATA=`echo "summary" | timeout 5 nc -q 0 127.0.0.1 20000` # just guess this method in Ub16
    # DATA=`timeout 5 curl -s http://127.0.0.1:20000/getstat` # since Ub20 not work without option --http0.9 (no such option in Ub16/18)
    # DATA=`echo '{"id":"0", "method":"getstat"}' | timeout 5 nc -q 0 127.0.0.1 20000 # works in Ub16/18/20
    DATA=`echo '{"id":"0", "method":"getstat"}' | timeout 5 nc -q 0 127.0.0.1 20000 | grep "^{"` # grep necessery since 1.8y3 because of: "Added HTTP headers to json api"
    if [[ -z ${DATA} ]]; then
      :
    else
      hash=`echo "${DATA}" | jq -r '.result[].speed_sps' | paste -s -d+ | bc | awk '{ printf "%.2f", $1 }'`
      acc=`echo "${DATA}"  | jq -r '.result[].accepted_shares' | paste -s -d+ | bc`
      rej=`echo "${DATA}"  | jq -r '.result[].rejected_shares' | paste -s -d+ | bc`
      JSON=`echo "${JSON}" | jq ".hash=\"${hash}\"" | jq ".acc=\"${acc}\"" | jq ".rej=\"${rej}\""`
      gpuHash=(`echo "${DATA}" | jq -r '.result[].speed_sps' | sed 's/^$/n\/a/g'`)
      for ((i=0; i<${#gpuHash[@]}; i++)); do
        JSON=`echo "${JSON}" | jq ".gpuHash[\"${i}\"]=\"${gpuHash[$i]}\""`
      done
    fi
  fi
  ## nanominer
  if [[ $(echo "${MINER_PATH}" | grep -i "/nanominer" | head -n 1 | wc -l) == 1 ]]; then
    DATA=`timeout 5 curl -s http://127.0.0.1:9090/stats`
    if [[ -z ${DATA} ]]; then
      :
    else
      hash=`echo "${DATA}" | jq -r '.Algorithms[0][].Total.Hashrate' | awk '{ printf "%.2f", $1 }'`
      acc=`echo "${DATA}"  | jq -r '.Algorithms[0][].Total.Accepted'`
      rej=`echo "${DATA}"  | jq -r '.Algorithms[0][].Total.Denied'`
      JSON=`echo "${JSON}" | jq ".hash=\"${hash}\"" | jq ".acc=\"${acc}\"" | jq ".rej=\"${rej}\""`
      gpuHash=(`echo "${DATA}" | jq -r '.Algorithms[0][] | to_entries[] \
        | select (.key|startswith("GPU")) | .value.Hashrate' | awk '{ printf "%.2f\n", $1 }' | sed 's/^$/n\/a/g'`)
      for ((i=0; i<${#gpuHash[@]}; i++)); do
        JSON=`echo "${JSON}" | jq ".gpuHash[\"${i}\"]=\"${gpuHash[$i]}\""`
      done
    fi
  fi
  ### nbminer-nebutech
  if [[ $(echo "${MINER_PATH}" | grep -i "/nbminer-nebutech" | head -n 1 | wc -l) == 1 ]]; then
    DATA=`timeout 5 curl -s http://127.0.0.1:22333/api/v1/status`
    if [[ -z ${DATA} ]]; then
      [[ ${minerApiWrn} ]] && CONSOLE+="\n<span style='color:red;'><b>Please add to miner options in order to see stats: --api 127.0.0.1:22333 (or wait if miner is just starting)</b></span>"
    else
      hash=`echo "${DATA}" | jq -r 'try .miner.total_hashrate_raw // 0' | awk '{ printf "%.2f", $1 }'`
      acc=` echo "${DATA}" | jq -r 'try .stratum.accepted_shares // 0'`
      rej=` echo "${DATA}" | jq -r 'try .stratum.rejected_shares // 0'`
      JSON=`echo "${JSON}" | jq ".hash=\"${hash}\"" | jq ".acc=\"${acc}\"" | jq ".rej=\"${rej}\""`
      gpuHash=(`echo "${DATA}" | jq -r 'try .miner.devices[].hashrate_raw // 0' | sed 's/^$/n\/a/g'`)
      for ((i=0; i<${#gpuHash[@]}; i++)); do
        JSON=`echo "${JSON}" | jq ".gpuHash[\"${i}\"]=\"${gpuHash[$i]}\""`
      done
    fi
  fi
  ### noncerpro-cuda
  if [[ $(echo "${MINER_PATH}" | grep -i "/noncerpro-cuda" | head -n 1 | wc -l) == 1 ]]; then
    DATA=`timeout 5 curl -s http://127.0.0.1:3000/api`
    if [[ -z ${DATA} ]]; then
      [[ ${minerApiWrn} ]] && CONSOLE+="\n<span style='color:red;'><b>Please add to miner options in order to see stats: --api (or wait if miner is just starting)</b></span>"
    else
      hash=`echo "${DATA}"  | jq -r '.totalHashrate' | awk '{ printf "%.2f", $1 }'`
      share=`echo "${DATA}" | jq -r '.totalShares'`
      rej=`echo "${DATA}"   | jq -r '.invalidShares'`
      acc=`echo | awk "{ printf \"%.2f\", ${share}-${rej} }"`
      JSON=`echo "${JSON}" | jq ".hash=\"${hash}\"" | jq ".acc=\"${acc}\"" | jq ".rej=\"${rej}\""`
      gpuHash=(`echo "${DATA}" | jq -r '.devices[].hashrate' | sed 's/^$/n\/a/g'`)
      for ((i=0; i<${#gpuHash[@]}; i++)); do
        JSON=`echo "${JSON}" | jq ".gpuHash[\"${i}\"]=\"${gpuHash[$i]}\""`
      done
    fi
  fi
  ### noncerpro-kadena
  if [[ $(echo "${MINER_PATH}" | grep -i "/noncerpro-kadena" | head -n 1 | wc -l) == 1 ]]; then
    DATA=`timeout 5 curl -s http://127.0.0.1:3000/api`
    if [[ -z ${DATA} ]]; then
      :
    else
      hash=`echo "${DATA}"  | jq -r '.totalHashrate' | awk '{ printf "%.2f", $1 }'`
      share=`echo "${DATA}" | jq -r '.totalShares'`
      rej=`echo "${DATA}"   | jq -r '.invalidShares'`
      acc=`echo | awk "{ printf \"%.2f\", ${share}-${rej} }"`
      JSON=`echo "${JSON}" | jq ".hash=\"${hash}\"" | jq ".acc=\"${acc}\"" | jq ".rej=\"${rej}\""`
      gpuHash=(`echo "${DATA}" | jq -r '.devices[].hashrate' | sed 's/^$/n\/a/g'`)
      for ((i=0; i<${#gpuHash[@]}; i++)); do
        JSON=`echo "${JSON}" | jq ".gpuHash[\"${i}\"]=\"${gpuHash[$i]}\""`
      done
    fi
  fi
  ### noncerpro-opencl
  if [[ $(echo "${MINER_PATH}" | grep -i "/noncerpro-opencl" | head -n 1 | wc -l) == 1 ]]; then
    DATA=`timeout 5 curl -s http://127.0.0.1:3000/api`
    if [[ -z ${DATA} ]]; then
      [[ ${minerApiWrn} ]] && CONSOLE+="\n<span style='color:red;'><b>Please add to miner options in order to see stats: --api (or wait if miner is just starting)</b></span>"
    else
      hash=`echo "${DATA}"  | jq -r '.totalHashrate' | awk '{ printf "%.2f", $1 }'`
      share=`echo "${DATA}" | jq -r '.totalShares'`
      rej=`echo "${DATA}"   | jq -r '.invalidShares'`
      acc=`echo | awk "{ printf \"%.2f\", ${share}-${rej} }"`
      JSON=`echo "${JSON}" | jq ".hash=\"${hash}\"" | jq ".acc=\"${acc}\"" | jq ".rej=\"${rej}\""`
      gpuHash=(`echo "${DATA}" | jq -r '.devices[].hashrate' | sed 's/^$/n\/a/g'`)
      for ((i=0; i<${#gpuHash[@]}; i++)); do
        JSON=`echo "${JSON}" | jq ".gpuHash[\"${i}\"]=\"${gpuHash[$i]}\""`
      done
    fi
  fi
  ### nsfminer
  if [[ $(echo "${MINER_PATH}" | grep -i "/nsfminer" | head -n 1 | wc -l) == 1 ]]; then
    DATA=`echo '{"method": "miner_getstat1", "jsonrpc": "2.0", "id": 1 }' | timeout 5 nc -q 0 127.0.0.1 3333`
    if [[ -z ${DATA} ]]; then
      [[ ${minerApiWrn} ]] && CONSOLE+="\n<span style='color:red;'><b>Please add to miner options in order to see stats: --api 3333 (or wait if miner is just starting)</b></span>"
    else
      hash=`echo "${DATA}"  | jq -r '.result[2]' | awk -F";" '{ print $1 }' | awk '{ printf "%.2f", $1*1000 }'`
      share=`echo "${DATA}" | jq -r '.result[2]' | awk -F";" '{ print $2 }'`
      rej=`echo "${DATA}"   | jq -r '.result[2]' | awk -F";" '{ print $3 }'`
      acc=`echo | awk "{ printf \"%.2f\", ${share}-${rej} }"`
      JSON=`echo "${JSON}" | jq ".hash=\"${hash}\"" | jq ".acc=\"${acc}\"" | jq ".rej=\"${rej}\""`
      gpuHash=(`echo "${DATA}" | jq -r '.result[3]' | sed -e 's/;/\n/g' | sed 's/^$/n\/a/g'`)
      for ((i=0; i<${#gpuHash[@]}; i++)); do
        igpuHash=`echo | awk "{ printf \"%.2f\", ${gpuHash[$i]}*1000 }"`
        JSON=`echo "${JSON}" | jq ".gpuHash[\"${i}\"]=\"${igpuHash}\""`
      done
    fi
  fi
  ### phoenixminer
  #https://github.com/nemosminer/Claymores-Dual-Ethereum/blob/master/Remote%20manager/API.txt
  if [[ $(echo "${MINER_PATH}" | grep -i "/phoenixminer" | head -n 1 | wc -l) == 1 ]]; then
    DATA=`echo '{"id":0,"jsonrpc":"2.0","method":"miner_getstat2"}' | timeout 5 nc -q 0 127.0.0.1 3333`
    if [[ -z ${DATA} ]]; then
      :
    else
      hash=` echo "${DATA}" | jq -r 'try .result[2] // 0' | awk -F";" '{ print $1 }' | awk '{ printf "%.2f", $1*1000 }'`
      share=`echo "${DATA}" | jq -r 'try .result[2] // 0' | awk -F";" '{ print $2 }'`
      rej=`  echo "${DATA}" | jq -r 'try .result[2] // 0' | awk -F";" '{ print $3 }'`
      acc=`echo | awk "{ printf \"%.f\", ${share}-${rej} }"`
      JSON=`echo "${JSON}" | jq ".hash=\"${hash}\"" | jq ".acc=\"${acc}\"" | jq ".rej=\"${rej}\""`

      gpuHash=(`echo "${DATA}" | jq -r 'try .result[3] // 0' | sed -e 's/;/\n/g' | sed 's/^$/n\/a/g'`)
      # PCI numbers of physical GPUs
      tmpGpuPci=`cat /var/tmp/stats_gpu_pcibus_jq 2> /dev/null | jq -c 'to_entries[]'`
      gpuPci=(`echo "${DATA}" | jq -r 'try .result[15] // 0' | sed -e 's/;/\n/g' | sed 's/^$/n\/a/g'`)
      for ((i=0; i<${#gpuHash[@]}; i++)); do
        if [[ ${gpuPci[$i]} == "null" || ${gpuPci[$i]} == "" ]]; then
          # upto 4.2c there is no PCI numbers of every GPUs used/enabled in miner. Use common 0,1,2,3,...
          icardIdx=${i}
        else
          # PCI nr
          igpuPci=`echo | awk "{ printf \"%02x\", ${gpuPci[$i]} }"`
          # PCI nr to cardX nr
          icardIdx=`echo "${tmpGpuPci}" | grep -i "\"value\":\"${igpuPci}" | jq -r '.key'`
        fi
        # Hash rate
        igpuHash=`echo | awk "{ printf \"%.2f\", ${gpuHash[$i]}*1000 }"`
        JSON=`echo "${JSON}" | jq ".gpuHash[\"${icardIdx}\"]=\"${igpuHash}\""`
      done
      secondAlgoData=`echo "${DATA}" | jq -r 'try .result[5] // "off"' | awk -F";" '{ print $1 }'`
      if [[ ${secondAlgoData} != "off" ]]; then
        hash2=` echo "${DATA}" | jq -r 'try .result[4] // 0' | awk -F";" '{ print $1 }' | awk '{ printf "%.2f", $1*1000 }'`
        share2=`echo "${DATA}" | jq -r 'try .result[4] // 0' | awk -F";" '{ print $2 }'`
        rej2=`  echo "${DATA}" | jq -r 'try .result[4] // 0' | awk -F";" '{ print $3 }'`
        acc2=`echo | awk "{ printf \"%.f\", ${share2}-${rej2} }"`
        JSON=`echo "${JSON}" | jq ".hash2=\"${hash2}\"" | jq ".acc2=\"${acc2}\"" | jq ".rej2=\"${rej2}\""`

        gpuHash2=(`echo "${DATA}" | jq -r 'try .result[5] // 0' | sed -e 's/;/\n/g' | sed 's/^$/n\/a/g'`)
        # PCI numbers of physical GPUs
        #tmpGpuPci=`cat /var/tmp/stats_gpu_pcibus_jq 2> /dev/null | jq -c 'to_entries[]'`
        #gpuPci=(`echo "${DATA}" | jq -r 'try .result[15] // 0' | sed -e 's/;/\n/g' | sed 's/^$/n\/a/g'`)
        for ((i=0; i<${#gpuHash2[@]}; i++)); do
          if [[ ${gpuPci[$i]} == "null" || ${gpuPci[$i]} == "" ]]; then
            # upto 4.2c there is no PCI numbers of every GPUs used/enabled in miner. Use common 0,1,2,3,...
            icardIdx=${i}
          else
            # PCI nr
            igpuPci=`echo | awk "{ printf \"%02x\", ${gpuPci[$i]} }"`
            # PCI nr to cardX nr
            icardIdx=`echo "${tmpGpuPci}" | grep -i "\"value\":\"${igpuPci}" | jq -r '.key'`
          fi
          # Hash rate
          igpuHash2=`echo | awk "{ printf \"%.2f\", ${gpuHash2[$i]}*1000 }"`
          JSON=`echo "${JSON}" | jq ".gpuHash2[\"${icardIdx}\"]=\"${igpuHash2}\""`
        done
      fi
    fi
  fi
  ### ravencoin
  if [[ $(echo "${MINER_PATH}" | grep -i "/ravencoin" | head -n 1 | wc -l) == 1 ]]; then
    DATA=`echo 'summary' | timeout 5 nc -q 0 127.0.0.1 4068 | sed -e 's/;/\n/g'`
    if [[ -z ${DATA} ]]; then
      :
    else
      hash=`echo "${DATA}" | grep "^KHS=" | awk -F"=" '{ print $2 }' | awk '{ printf "%.2f", $1 }'`
      acc=`echo "${DATA}"  | grep "^ACC=" | awk -F"=" '{ print $2 }'`
      rej=`echo "${DATA}"  | grep "^REJ=" | awk -F"=" '{ print $2 }'`
      JSON=`echo "${JSON}" | jq ".hash=\"${hash}\"" | jq ".acc=\"${acc}\"" | jq ".rej=\"${rej}\""`
    fi
  fi
  ### sgminer-fancyIX
  if [[ $(echo "${MINER_PATH}" | grep -i "/sgminer-fancyIX" | head -n 1 | wc -l) == 1 ]]; then
    DATA=`echo '{"command":"summary"}' | timeout 5 nc -q 0 127.0.0.1 4028`
    if [[ -z ${DATA} ]]; then
      [[ ${minerApiWrn} ]] && CONSOLE+="\n<span style='color:red;'><b>Please add to miner options in order to see stats: --api-listen (or wait if miner is just starting)</b></span>"
    else
      hash=`echo "${DATA}" | jq -r '.SUMMARY[0]."KHS 5s"' | awk '{ printf "%.2f", $1*1000 }'`
      acc=`echo "${DATA}"  | jq -r '.SUMMARY[0]."Accepted"'`
      rej=`echo "${DATA}"  | jq -r '.SUMMARY[0]."Rejected"'`
      JSON=`echo "${JSON}" | jq ".hash=\"${hash}\"" | jq ".acc=\"${acc}\"" | jq ".rej=\"${rej}\""`
    fi
  fi
  ### sgminer-gm-aceneun
  if [[ $(echo "${MINER_PATH}" | grep -i "/sgminer-gm-aceneun" | head -n 1 | wc -l) == 1 ]]; then
    DATA=`echo '{"command":"summary"}' | timeout 5 nc -q 0 127.0.0.1 4028`
    if [[ -z ${DATA} ]]; then
      [[ ${minerApiWrn} ]] && CONSOLE+="\n<span style='color:red;'><b>Please add to miner options in order to see stats: --api-listen (or wait if miner is just starting)</b></span>"
    else
      hash=`echo "${DATA}" | jq -r '.SUMMARY[0]."KHS 5s"' | awk '{ printf "%.2f", $1*1000 }'`
      acc=`echo "${DATA}"  | jq -r '.SUMMARY[0]."Accepted"'`
      rej=`echo "${DATA}"  | jq -r '.SUMMARY[0]."Rejected"'`
      JSON=`echo "${JSON}" | jq ".hash=\"${hash}\"" | jq ".acc=\"${acc}\"" | jq ".rej=\"${rej}\""`
    fi
  fi
  ### srbminer-multi
  if [[ $(echo "${MINER_PATH}" | grep -i "/srbminer-multi" | head -n 1 | wc -l) == 1 ]]; then
    DATA=`timeout 5 curl -s http://127.0.0.1:21550`
    if [[ -z ${DATA} ]]; then
      [[ ${minerApiWrn} ]] && CONSOLE+="\n<span style='color:red;'><b>Please add to miner options in order to see stats: --api-enable (or wait if miner is just starting)</b></span>"
    else
      hash=`echo "${DATA}"   | jq -r '.algorithms[0].hashrate."1min"' | awk '{ printf "%.2f", $1 }'`
      share=`echo "${DATA}"  | jq -r '.algorithms[0].shares.total'`
      acc=`echo "${DATA}"    | jq -r '.algorithms[0].shares.accepted'`
      rej=`echo "${DATA}"    | jq -r '.algorithms[0].shares.rejected'`
      JSON=`echo "${JSON}" | jq ".hash=\"${hash}\"" | jq ".acc=\"${acc}\"" | jq ".rej=\"${rej}\""`

      gpuHash=(`echo "${DATA}" | jq -r '.algorithms[0].hashrate.gpu' | jq 'del(.total)' | jq .'[]' | sed 's/^$/n\/a/g'`)
      # PCI numbers of physical GPUs
      tmpGpuPci=`cat /var/tmp/stats_gpu_pcibus_jq 2>/dev/null | jq -c 'to_entries[]'`
      gpuPci=(`echo "${DATA}" | jq -r '.gpu_devices[].bus_id' | sed 's/^$/n\/a/g'`)
      for ((i=0; i<${#gpuHash[@]}; i++)); do
        # PCI nr
        igpuPci=`echo | awk "{ printf \"%02x\", ${gpuPci[$i]} }"`
        # PCI nr to cardX nr
        icardIdx=`echo "${tmpGpuPci}" | grep -i "\"value\":\"${igpuPci}" | jq -r '.key'`
        # Hash rate
        igpuHash=`echo | awk "{ printf \"%.2f\", ${gpuHash[$i]} }"`
        # JSON=`echo "${JSON}" | jq ".gpuHash[\"${i}\"]=\"${igpuHash}\""`
        JSON=`echo "${JSON}" | jq ".gpuHash[\"${icardIdx}\"]=\"${igpuHash}\""`
      done
    fi
  fi
  ### t-rex
  if [[ $(echo "${MINER_PATH}" | grep -i "/t-rex" | head -n 1 | wc -l) == 1 ]]; then
    DATA=`timeout 5 curl -s http://127.0.0.1:4067/summary`
    if [[ -z ${DATA} ]]; then
      :
    else
      hash=`echo "${DATA}" | jq -r 'try .hashrate // 0' | awk '{ printf "%.2f", $1 }'`
      acc=` echo "${DATA}" | jq -r 'try .accepted_count // 0'`
      rej=` echo "${DATA}" | jq -r 'try .rejected_count // 0'`
      JSON=`echo "${JSON}" | jq ".hash=\"${hash}\"" | jq ".acc=\"${acc}\"" | jq ".rej=\"${rej}\""`
      gpuHash=(`echo "${DATA}" | jq -r 'try .gpus[].hashrate // 0' | sed 's/^$/n\/a/g'`)
      for ((i=0; i<${#gpuHash[@]}; i++)); do
        JSON=`echo "${JSON}" | jq ".gpuHash[\"${i}\"]=\"${gpuHash[$i]}\""`
      done
      dualMine=`echo ${DATA} | jq -r 'try .dual_stat // null'`
      if [[ ${dualMine} != "null" ]]; then
        hash2=`echo "${DATA}" | jq -r '.dual_stat.hashrate // 0' | awk '{ printf "%.2f", $1 }'`
        acc2=` echo "${DATA}" | jq -r '.dual_stat.accepted_count // 0'`
        rej2=` echo "${DATA}" | jq -r '.dual_stat.rejected_count // 0'`
        JSON=` echo "${JSON}" | jq ".hash2=\"${hash2}\"" | jq ".acc2=\"${acc2}\"" | jq ".rej2=\"${rej2}\""`
        gpuHash2=(`echo "${DATA}" | jq -r 'try .dual_stat.gpus[].hashrate // 0' | sed 's/^$/n\/a/g'`)
        for ((i=0; i<${#gpuHash2[@]}; i++)); do
          JSON=`echo "${JSON}" | jq ".gpuHash2[\"${i}\"]=\"${gpuHash2[$i]}\""`
        done
      fi
    fi
  fi
  ### teamblackminer
  if [[ $(echo "${MINER_PATH}" | grep -i "/teamblackminer" | head -n 1 | wc -l) == 1 ]]; then
    DATA=`timeout 5 curl -s http://127.0.0.1:4068/summary`
    if [[ ${DATA} == "" ]]; then
      [[ ${minerApiWrn} ]] && CONSOLE+="\n<span style='color:red;'><b>Please add to miner options in order to see stats: -b (or wait if miner is just starting)</b></span>"
    else
      hash=`echo "${DATA}" | jq --slurp '.[0].total_hashrate'`
      acc=`echo "${DATA}"  | jq --slurp '.[0].total_accepted'`
      rej=`echo "${DATA}"  | jq --slurp '.[0].total_rejected'`
      JSON=`echo "${JSON}" | jq ".hash=\"${hash}\"" | jq ".acc=\"${acc}\"" | jq ".rej=\"${rej}\""`
      gpuHash=(`echo "${DATA}" | jq --slurp '.[2][].hashrate' | sed 's/^$/n\/a/g' | awk '{ printf "%.2f\n", $1 }'`)
      for ((i=0; i<${#gpuHash[@]}; i++)); do
        JSON=`echo "${JSON}" | jq ".gpuHash[\"${i}\"]=\"${gpuHash[$i]}\""`
      done
    fi
  fi
  ### teamredminer
  if [[ $(echo "${MINER_PATH}" | grep -i "/teamredminer" | head -n 1 | wc -l) == 1 ]]; then
    DATA=`echo '{"command":"devs+summary+devs2+summary2"}' | timeout 5 nc -q 0 127.0.0.1 4028`
    if [[ -z ${DATA} ]]; then
      [[ ${minerApiWrn} ]] && CONSOLE+="\n<span style='color:red;'><b>Please add to miner options in order to see stats: --api_listen=127.0.0.1:4028 (or wait if miner is just starting)</b></span>"
    else
      hash=`echo "${DATA}" | jq -r 'try .summary.SUMMARY[]."KHS 30s" // 0' | awk '{ printf "%.2f", $1*1000 }'`
      acc=` echo "${DATA}" | jq -r 'try .summary.SUMMARY[].Accepted // 0'`
      rej=` echo "${DATA}" | jq -r 'try .summary.SUMMARY[].Rejected // 0'`
      JSON=`echo "${JSON}" | jq ".hash=\"${hash}\"" | jq ".acc=\"${acc}\"" | jq ".rej=\"${rej}\""`
      gpuHash=(`echo "${DATA}" | jq -r 'try .devs.DEVS[]."KHS 30s" // 0' | sed 's/^$/n\/a/g'`)
      for ((i=0; i<${#gpuHash[@]}; i++)); do
        igpuHash=`echo | awk "{ printf \"%.2f\", ${gpuHash[$i]}*1000 }"`
        JSON=`echo "${JSON}" | jq ".gpuHash[\"${i}\"]=\"${igpuHash}\""`
      done
      dualMine=`echo ${DATA} | jq -r 'try .summary2.SUMMARY // null'`
      if [[ ${dualMine} != "null" ]]; then
        hash2=`echo "${DATA}" | jq -r 'try .summary2.SUMMARY[]."KHS 30s" // 0' | awk '{ printf "%.2f", $1*1000 }'`
        acc2=` echo "${DATA}" | jq -r 'try .summary2.SUMMARY[].Accepted // 0'`
        rej2=` echo "${DATA}" | jq -r 'try .summary2.SUMMARY[].Rejected // 0'`
        JSON=`echo "${JSON}" | jq ".hash2=\"${hash2}\"" | jq ".acc2=\"${acc2}\"" | jq ".rej2=\"${rej2}\""`
        gpuHash2=(`echo "${DATA}" | jq -r 'try .devs2.DEVS[]."KHS 30s" // 0' | sed 's/^$/n\/a/g'`)
        for ((i=0; i<${#gpuHash2[@]}; i++)); do
          igpuHash2=`echo | awk "{ printf \"%.2f\", ${gpuHash2[$i]}*1000 }"`
          JSON=`echo "${JSON}" | jq ".gpuHash2[\"${i}\"]=\"${igpuHash2}\""`
        done
      fi

    fi
  fi
  ### tt-miner
  if [[ $(echo "${MINER_PATH}" | grep -i "/tt-miner" | head -n 1 | wc -l) == 1 ]]; then
    DATA=`echo '{"id":0,"jsonrpc":"2.0","method":"miner_getstat1"}' | timeout 5 nc -q 0 127.0.0.1 3333`
    [[ -z ${DATA} ]] && DATA=$(cat /var/tmp/miner_stats_tt-miner 2>/dev/null)
    if [[ -z ${DATA} ]]; then
      [[ ${minerApiWrn} ]] && CONSOLE+="\n<span style='color:red;'><b>Please add to miner options in order to see stats: --api-bind 127.0.0.1:3333 (or wait if miner is just starting)</b></span>"
    else
      echo "${DATA}" > /var/tmp/miner_stats_tt-miner
      hash=`echo "${DATA}"  | jq -r '.result[2]' | awk -F";" '{ print $1 }' | awk '{ printf "%.2f", $1 }'`
      share=`echo "${DATA}" | jq -r '.result[2]' | awk -F";" '{ print $2 }'`
      rej=`echo "${DATA}"   | jq -r '.result[2]' | awk -F";" '{ print $3 }'`
      acc=`echo | awk "{ printf \"%.2f\", ${share}-${rej} }"`
      JSON=`echo "${JSON}" | jq ".hash=\"${hash}\"" | jq ".acc=\"${acc}\"" | jq ".rej=\"${rej}\""`
      gpuHash=(`echo "${DATA}" | jq -r '.result[3]' | sed -e 's/;/\n/g' | sed 's/^$/n\/a/g'`)
      for ((i=0; i<${#gpuHash[@]}; i++)); do
        igpuHash=`echo | awk "{ printf \"%.2f\", ${gpuHash[$i]} }"`
        JSON=`echo "${JSON}" | jq ".gpuHash[\"${i}\"]=\"${igpuHash}\""`
      done
    fi
  fi
  ### wildrig-multi
  if [[ $(echo "${MINER_PATH}" | grep -i "/wildrig-multi" | head -n 1 | wc -l) == 1 ]]; then
    DATA=`timeout 5 curl -s http://127.0.0.1:3333/`
    if [[ -z ${DATA} ]]; then
      [[ ${minerApiWrn} ]] && CONSOLE+="\n<span style='color:red;'><b>Please add to miner options in order to see stats: --api-port=3333 (or wait if miner is just starting)</b></span>"
    else
      hash=`echo "${DATA}"  | jq -r '.hashrate.total[0]' | awk '{ printf "%.2f", $1 }'`
      share=`echo "${DATA}" | jq -r '.results.shares_total'`
      acc=`echo "${DATA}" | jq -r '.results.shares_good'`
      rej=`echo | awk "{ printf \"%.2f\", ${share}-${acc} }"`
      JSON=`echo "${JSON}" | jq ".hash=\"${hash}\"" | jq ".acc=\"${acc}\"" | jq ".rej=\"${rej}\""`
      gpuHash=(`echo "${DATA}" | jq -r '.hashrate.threads[][0]' | sed 's/^$/n\/a/g'`)
      for ((i=0; i<${#gpuHash[@]}; i++)); do
        JSON=`echo "${JSON}" | jq ".gpuHash[\"${i}\"]=\"${gpuHash[$i]}\""`
      done
    fi
  fi
  ### xmrig (xmrig-vX.XX-cudaX.XX)
  if [[ $(echo "${MINER_PATH}" | grep -i "/xmrig-v" | head -n 1 | wc -l) == 1 ]]; then
    DATA=`timeout 5 curl -s http://127.0.0.1:3333/1/summary`
    DATA2=`timeout 5 curl -s http://127.0.0.1:3333/2/backends`
    if [[ -z ${DATA} ]]; then
      [[ ${minerApiWrn} ]] && CONSOLE+="\n<span style='color:red;'><b>Please add to miner options in order to see stats: --http-port=3333 (or wait if miner is just starting)</b></span>"
    else
      hash=`echo "${DATA}"  | jq -r '.hashrate.total[0]' | awk '{ printf "%.2f", $1 }'`
      share=`echo "${DATA}" | jq -r '.results.shares_total'`
      acc=`echo "${DATA}" | jq -r '.results.shares_good'`
      rej=`echo | awk "{ printf \"%.2f\", ${share}-${acc} }"`
      JSON=`echo "${JSON}" | jq ".hash=\"${hash}\"" | jq ".acc=\"${acc}\"" | jq ".rej=\"${rej}\""`
      # relation thread-GPU
      # [1] - opencl results / [2] - cuda results
      thread2Index=(`(echo ${DATA2} | jq -r '.[1].threads[].index' 2> /dev/null) || (echo ${DATA2} | jq -r '.[2].threads[].index' 2> /dev/null)`)
      gpuHash=(`echo "${DATA}" | jq -r '.hashrate.threads[][0]' | sed 's/^$/n\/a/g'`)
      for ((i=0; i<${#gpuHash[@]}; i++)); do
        gpuIdx=${thread2Index[$i]}
        tmpGpuHash=`echo "${JSON}" | jq -r ".gpuHash[\"${gpuIdx}\"]"`
        tmpGpuHash=`echo "${tmpGpuHash} ${gpuHash[$i]}" | awk '{ printf "%.0f", $1+$2 }'`
        JSON=`echo "${JSON}" | jq ".gpuHash[\"${gpuIdx}\"]=\"${tmpGpuHash}\""`
      done
    fi
  fi
  ### xmrig-amd
  if [[ $(echo "${MINER_PATH}" | grep -i "/xmrig-amd" | head -n 1 | wc -l) == 1 ]]; then
    DATA=`timeout 5 curl -s http://127.0.0.1:3333/`
    if [[ -z ${DATA} ]]; then
      [[ ${minerApiWrn} ]] && CONSOLE+="\n<span style='color:red;'><b>Please add to miner options in order to see stats: --api-port=3333 (or wait if miner is just starting)</b></span>"
    else
      hash=`echo "${DATA}"  | jq -r '.hashrate.total[0]' | awk '{ printf "%.2f", $1 }'`
      share=`echo "${DATA}" | jq -r '.results.shares_total'`
      acc=`echo "${DATA}" | jq -r '.results.shares_good'`
      rej=`echo | awk "{ printf \"%.2f\", ${share}-${acc} }"`
      JSON=`echo "${JSON}" | jq ".hash=\"${hash}\"" | jq ".acc=\"${acc}\"" | jq ".rej=\"${rej}\""`
      gpuHash=(`echo "${DATA}" | jq -r '.hashrate.threads[][0]' | sed 's/^$/n\/a/g'`)
      for ((i=0; i<${#gpuHash[@]}; i++)); do
        JSON=`echo "${JSON}" | jq ".gpuHash[\"${i}\"]=\"${gpuHash[$i]}\""`
      done
    fi
  fi
  ### xmrig-nvidia
  if [[ $(echo "${MINER_PATH}" | grep -i "/xmrig-nvidia" | head -n 1 | wc -l) == 1 ]]; then
    DATA=`timeout 5 curl -s http://127.0.0.1:3333/`
    if [[ -z ${DATA} ]]; then
      [[ ${minerApiWrn} ]] && CONSOLE+="\n<span style='color:red;'><b>Please add to miner options in order to see stats: --api-port=3333 (or wait if miner is just starting)</b></span>"
    else
      hash=`echo "${DATA}"  | jq -r '.hashrate.total[0]' | awk '{ printf "%.2f", $1 }'`
      share=`echo "${DATA}" | jq -r '.results.shares_total'`
      acc=`echo "${DATA}" | jq -r '.results.shares_good'`
      rej=`echo | awk "{ printf \"%.2f\", ${share}-${acc} }"`
      JSON=`echo "${JSON}" | jq ".hash=\"${hash}\"" | jq ".acc=\"${acc}\"" | jq ".rej=\"${rej}\""`
      gpuHash=(`echo "${DATA}" | jq -r '.hashrate.threads[][0]' | sed 's/^$/n\/a/g'`)
      for ((i=0; i<${#gpuHash[@]}; i++)); do
        JSON=`echo "${JSON}" | jq ".gpuHash[\"${i}\"]=\"${gpuHash[$i]}\""`
      done
    fi
  fi
  ### xmr-stak
  if [[ $(echo "${MINER_PATH}" | grep -i "/xmr-stak" | head -n 1 | wc -l) == 1 ]]; then
    DATA=`timeout 5 curl -s http://127.0.0.1:3333/api.json`
    if [[ -z ${DATA} ]]; then
      [[ ${minerApiWrn} ]] && CONSOLE+="\n<span style='color:red;'><b>Please add to miner options in order to see stats: -i 3333 (or wait if miner is just starting)</b></span>"
    else
      hash=`echo "${DATA}"  | jq -r '.hashrate.total[0]' | awk '{ printf "%.2f", $1 }'`
      share=`echo "${DATA}" | jq -r '.results.shares_total'`
      acc=`echo "${DATA}" | jq -r '.results.shares_good'`
      rej=`echo | awk "{ printf \"%.2f\", ${share}-${acc} }"`
      JSON=`echo "${JSON}" | jq ".hash=\"${hash}\"" | jq ".acc=\"${acc}\"" | jq ".rej=\"${rej}\""`
      gpuHash=(`echo "${DATA}" | jq -r '.hashrate.threads[][0]' | sed 's/^$/n\/a/g'`)
      for ((i=0; i<${#gpuHash[@]}; i++)); do
        JSON=`echo "${JSON}" | jq ".gpuHash[\"${i}\"]=\"${gpuHash[$i]}\""`
      done
    fi
  fi
  ### z-enemy
  if [[ $(echo "${MINER_PATH}" | grep -i "/z-enemy" | head -n 1 | wc -l) == 1 ]]; then
    DATA=`echo "summary" | timeout 5 nc -q 0 127.0.0.1 4068 | sed -e 's/;/\n/g'`
    if [[ -z ${DATA} ]]; then
      [[ ${minerApiWrn} ]] && CONSOLE+="\n<span style='color:red;'><b>Please add to miner options in order to see stats: --api-bind=127.0.0.1:4068 (or wait if miner is just starting)</b></span>"
    else
      hash=`echo "${DATA}" | grep "^KHS=" | awk -F"=" '{ print $2 }' | awk '{ printf "%.2f", $1*1000 }'`
      acc=`echo "${DATA}"  | grep "^ACC=" | awk -F"=" '{ print $2 }'`
      rej=`echo "${DATA}"  | grep "^REJ=" | awk -F"=" '{ print $2 }'`
      JSON=`echo "${JSON}" | jq ".hash=\"${hash}\"" | jq ".acc=\"${acc}\"" | jq ".rej=\"${rej}\""`
    fi
  fi




  ##########################################
  # old versions without full json data - units are known

  ### cudaminer-microbitcoinorg
  if [[ $(echo "${MINER_PATH}" | grep -i "cudaminer-microbitcoinorg" | wc -l) ==  1 ]]; then
    DATA=`echo "summary" | timeout 5 nc -q 0 127.0.0.1 4068`
    if [[ -z ${DATA} ]]; then
      :
    else
      hash=`echo "${DATA}" | awk -F";" '{ print $6 }' | awk -F"=" '{ print $2 }'`
      hash=`echo | awk "{ printf \"%.2f\",${hash}*1000 }"`
      JSON=`echo "${JSON}" | jq ".hash=\"${hash}\""`
    fi
  fi
  ### danila-miner
  if [[ $(echo "${MINER_PATH}" | grep -i "danila-miner" | wc -l) ==  1 ]]; then
    DATA=`echo "${CONSOLE_SHORT_PRE}" | grep -ai "Total system hashrate" | tail -n 1 | awk '{ for (i=1;i<=NF;i++)if($i~/hashrate/) printf "%0.2f %s\n", $(i+1), $(i+2) }'`
    unit=`echo "${DATA}" | awk '{ print $2 }' | tr -d ','`
    unitMul=1
    [[ ${unit} == "Khash/s" ]] && unitMul=1000
    [[ ${unit} == "Mhash/s" ]] && unitMul=1000000
    [[ ${unit} == "Ghash/s" ]] && unitMul=1000000000
    hash=`echo "${DATA}" | awk '{ print $1 }'`
    hash=`echo | awk "{ printf \"%.2f\", ${hash}*${unitMul} }"`
    JSON=`echo "${JSON}" | jq ".hash=\"${hash}\""`
  fi
  ### gringoldminer-v2
  if [[ $(echo "${MINER_PATH}" | grep -i "gringoldminer-v2" | wc -l) ==  1 ]]; then
    DATA=(`echo "${CONSOLE_SHORT_PRE}" | grep "Statistics:" | tail -n 50 | awk '{ print $4$7}'`)
    DATA2=()
    hash=0
    for ione in "${DATA[@]}"; do
      ione2=(`echo "${ione}" | awk -F":" '{ print $1" "$2 }'`)
      DATA2[${ione2[0]}]=${ione2[1]}
    done
    for ione in "${DATA2[@]}"; do
      hash=`echo | awk "{ printf \"%.2f\", ${hash}+${ione} }"`
    done
    JSON=`echo "${JSON}" | jq ".hash=\"${hash}\""`
  fi
  ### grinpro
  if [[ $(echo "${MINER_PATH}" | grep -i "grinpro" | wc -l) ==  1 ]]; then
    DATA=`timeout 5 curl -s http://127.0.0.1:5777/api/status`
    if [[ -z ${DATA} ]]; then
      :
    else
      hash=`echo "${DATA}" | jq -r '.workers[].graphsPerSecond' | paste -s -d+ | bc`
      hash=`echo | awk "{ printf \"%.2f\",${hash} }"`
      JSON=`echo "${JSON}" | jq ".hash=\"${hash}\""`
    fi
  fi
  ### kbminer
  if [[ $(echo "${MINER_PATH}" | grep -i "/kbminer" | wc -l) ==  1 ]]; then
    DATA=`timeout 5 curl -s http://127.0.0.1:3333/`
    hash=`echo "${DATA}" | jq -r '.hashrates[]' | paste -s -d+ | bc`
    hash=`echo | awk "{ printf \"%.2f\",${hash} }"`
    JSON=`echo "${JSON}" | jq ".hash=\"${hash}\""`
  fi
  ### ProgPoWminer
  if [[ $(echo "${MINER_PATH}" | grep -i "progpowminer" | wc -l) ==  1 ]]; then
    CONSOLE_SHORT=`echo "${CONSOLE_SHORT_PRE}" | grep -a " Speed " | tail -n 1 | awk -F" Speed " '{ print $2 }' | awk '{ print $1" "$2 }'`
  fi
  ### rhminer
  if [[ $(echo "${MINER_PATH}" | grep -i "rhminer" | wc -l) ==  1 ]]; then
    DATA=`timeout 5 curl -s http://127.0.0.1:7111/`
    if [[ -z ${DATA} ]]; then
      :
    else
      hash=`echo "${DATA}" | jq -r '.speed'`
      hash=`echo | awk "{ printf \"%.2f\",${hash} }"`
      JSON=`echo "${JSON}" | jq ".hash=\"${hash}\""`
    fi
  fi
  ### serominer
  if [[ $(echo "${MINER_PATH}" | grep -i "/serominer" | wc -l) ==  1 ]]; then
    DATA=`echo '{"method": "miner_getstat1", "jsonrpc": "2.0", "id": 1 }' | timeout 5 nc -q 0 127.0.0.1 3333`
    if [[ -z ${DATA} ]]; then
      CONSOLE+="\n<span style='color:red;'><b>Please add to miner options in order to see stats: --api-port 3333 (or wait if miner is just starting)</b></span>"
    else
      hash=`echo "${DATA}" | jq -r '.result[2]' | awk -F";" '{ print $1 }'`
      hash=`echo | awk "{ printf \"%.2f\",${hash}*1000 }"`
      JSON=`echo "${JSON}" | jq ".hash=\"${hash}\""`
    fi
  fi
  ### suprminer-ocminer
  if [[ $(echo "${MINER_PATH}" | grep -i "suprminer-ocminer" | wc -l) ==  1 ]]; then
    DATA=`echo "summary" | timeout 5 nc -1 0 127.0.0.1 4068`
    if [[ -z ${DATA} ]]; then
      :
    else
      hash=`echo "${DATA}" | awk -F";" '{ print $6 }' | awk -F"=" '{ print $2 }'`
      hash=`echo | awk "{ printf \"%.2f\",${hash}*1000 }"`
      JSON=`echo "${JSON}" | jq ".hash=\"${hash}\""`
    fi
  fi
  ### ubqminer
  if [[ $(echo "${MINER_PATH}" | grep -i "ubqminer" | wc -l) ==  1 ]]; then
    DATA=`echo '{"method": "miner_getstat1", "jsonrpc": "2.0", "id": 1 }' | timeout 5 nc -q 0 127.0.0.1 33333`
    if [[ -z ${DATA} ]]; then
      [[ ${minerApiWrn} ]] && CONSOLE+="\n<span style='color:red;'><b>Please add to miner options in order to see stats: --api-bind 127.0.0.1:33333 (or wait if miner is just starting)</b></span>"
    else
      hash=`echo "${DATA}" | jq -r '.result[2]' | awk -F";" '{ print $1 }'`
      hash=`echo | awk "{ printf \"%.2f\",${hash}*1000 }"`
      JSON=`echo "${JSON}" | jq ".hash=\"${hash}\""`
    fi
  fi
  ### verthashminer
  if [[ $(echo "${MINER_PATH}" | grep -i "verthashminer" | wc -l) ==  1 ]]; then
    hash=`echo "${CONSOLE_SHORT_PRE}" | grep -a "total hashrate" | tail -n 1 | awk '{ for (i=1;i<=NF;i++)if($i~/hashrate/) printf $(i+1) }'`
    unit=`echo "${CONSOLE_SHORT_PRE}" | grep -a "total hashrate" | tail -n 1 | awk '{ for (i=1;i<=NF;i++)if($i~/hashrate/) printf $(i+2) }'`
    hash=`echo | awk "{ printf \"%.2f\",${hash} }"`
    [[ ${unit} == "kH/s" ]] && hash=`echo | awk "{ printf \"%.2f\",${hash}*1000 }"`
    JSON=`echo "${JSON}" | jq ".hash=\"${hash}\""`
  fi
  ### zjazz-cuda-miner
  if [[ $(echo "${MINER_PATH}" | grep -i "zjazz-cuda-miner" | wc -l) ==  1 ]]; then
    DATA=`timeout 5 curl -s http://127.0.0.1:4011/summary`
    if [[ -z ${DATA} ]]; then
      :
    else
      hash=`echo "${DATA}" | sed -e 's/;/\n/g' | grep -a ^HS= | awk -F"=" '{ print $2 }'`
      hash=`echo | awk "{ printf \"%.2f\",${hash}*1000 }"`
      JSON=`echo "${JSON}" | jq ".hash=\"${hash}\""`
    fi
  fi


  ##########################################
  # old versions without full json data - unknown units without parsing

  ### beam-opencl-miner
  # with multi GPUs:
  # Performance: 7.00 sol/s 8.40 sol/s 7.80 sol/s 8.73 sol/s 7.47 sol/s 9.33 sol/s | Total: 48.73 sol/s
  if [[ $(echo "${MINER_PATH}" | grep -i "beam-opencl-miner" | wc -l) ==  1 ]]; then
    # For multi GPUs
    CONSOLE_SHORT=`echo "${CONSOLE_SHORT_PRE}" | grep -ai "Performance" | tail -n 1 | awk '{ for (i=1;i<=NF;i++)if($i~/Total:/) print $(i+1)" "$(i+2) }'`
    # For one GPU
    [[ ${CONSOLE_SHORT} == "" ]] && CONSOLE_SHORT=`echo "${CONSOLE_SHORT_PRE}" | grep -ai "Performance" | tail -n 1 | awk '{ for (i=1;i<=NF;i++)if($i~/sol\/s/) print $(i-1)" "$i }'`
  fi
  ### ccminer-phi-anxmod-216k155 ????????
  if [[ $(echo "${MINER_PATH}" | grep -i "ccminer-phi-anxmod-216k155" | wc -l) ==  1 ]]; then
    CONSOLE_SHORT=`echo "${CONSOLE_SHORT_PRE}" | grep -a "[YES]" | tail -n 1 | awk '{ for (i=1;i<=NF;i++)if($i~/H\/s/) print $(i-1)" "$i }'`
  fi
  ### ccminer nevermore-brian | ccminer-skunk-krnlx (not used acctually)
  if [[ $(echo "${MINER_PATH}" | grep -i "nevermore\|ccminer-skunk-krnlx" | wc -l) ==  1 ]]; then
    CONSOLE_SHORT=`echo "${CONSOLE_SHORT_PRE}" | grep -a "H/s yes!" | tail -n 1 | awk '{ print $(NF-2)" "$(NF-1) }'`
  fi
  ### energiminer
  if [[ $(echo "${MINER_PATH}" | grep -i "energiminer" | wc -l) ==  1 ]]; then
    CONSOLE_SHORT=`echo "${CONSOLE_SHORT_PRE}" | grep -a " Speed " | tail -n 1 | awk '{ for (i=1;i<=NF;i++)if($i~/Speed/) printf $(i+1)" "$(i+2) }'`
  fi
  ### finminer
  # echo '{"id":0,"jsonrpc":"2.0","method":"miner_getstat1"}' | nc 127.0.0.1 3333
  if [[ $(echo "${MINER_PATH}" | grep -i "finminer" | wc -l) ==  1 ]]; then
    CONSOLE_SHORT=`echo "${CONSOLE_SHORT_PRE}" | grep -ai "total speed" | tail -n 1 | awk '{ for (i=1;i<=NF;i++)if($i~/H\/s/) print $(i-1)" "$i }' | sed 's/,//g'`
  fi
  ### grin-miner
  if [[ $(echo "${MINER_PATH}" | grep -i "grin-miner" | wc -l) ==  1 ]]; then
    CONSOLE_SHORT=`echo "${CONSOLE_SHORT_PRE}" | grep -ai "graphs per second" | tail -n 1 | awk '{ for (i=1;i<=NF;i++)if($i~/gps/) printf "%0.2f %s\n", $(i-1), $i }'`
  fi
  ### gringoldminer
  if [[ $(echo "${MINER_PATH}" | grep -i "gringoldminer" | wc -l) ==  1 ]]; then
    DATA=`echo "${CONSOLE_SHORT_PRE}" | grep "Total" | grep "gps" | tail -n 1`
    CONSOLE_SHORT=`echo "${DATA}" | awk '{ for (i=1;i<=NF;i++)if($i~/gps/) printf "%0.2f %s\n", $(i-1), $i }'`
  fi
  ### sgminer-brian112358
  if [[ $(echo "${MINER_PATH}" | grep -i "/sgminer-brian112358" | wc -l) ==  1 ]]; then
    CONSOLE_SHORT=`echo "${CONSOLE_SHORT_PRE}" | sed 's/\r/\n/g' | grep -a "(avg)" | tail -n 1 | awk '{ print $2 }' | sed 's/(avg)://g'`
  fi
  ### sushi-miner-cuda
  if [[ $(echo "${MINER_PATH}" | grep -i "/sushi-miner-cuda" | wc -l) ==  1 ]]; then
    CONSOLE_SHORT=`echo "${CONSOLE_SHORT_PRE}" | grep -ai "Hashrate:" | tail -n 1 | awk '{ for (i=1;i<=NF;i++)if($i~/Hashrate:/) print $(i+1)" "$(i+2) }'`
  fi
  ### sushi-miner-opencl
  if [[ $(echo "${MINER_PATH}" | grep -i "/sushi-miner-opencl" | wc -l) ==  1 ]]; then
    CONSOLE_SHORT=`echo "${CONSOLE_SHORT_PRE}" | grep -ai "Hashrate:" | tail -n 1 | awk '{ for (i=1;i<=NF;i++)if($i~/Hashrate:/) print $(i+1)" "$(i+2) }'`
  fi
  ### tdxminer
  if [[ $(echo "${MINER_PATH}" | grep -i "tdxminer" | wc -l) ==  1 ]]; then
    CONSOLE_SHORT=`echo "${CONSOLE_SHORT_PRE}" | sed 's/\r/\n/g' | grep -a "Stats Total" | tail -n 1 | awk '{ print $7 }' | sed 's/^[ \t]*//;s/[ \t]*$//'`
    if [ "${CONSOLE_SHORT}" == "" ]; then
      # brak sekcji Total, ktora wystepuje tylko dla count(GPU)>1
      CONSOLE_SHORT=`echo "${CONSOLE_SHORT_PRE}" | sed 's/\r/\n/g' | grep -a "Stats GPU" | tail -n 1 | awk '{ print $8 }'`
    fi
  fi
  ### wildrig
  if [[ $(echo "${MINER_PATH}" | grep -i "wildrig" | grep -v "wildrig-multi" | wc -l) ==  1 ]]; then
    CONSOLE_SHORT=`echo "${CONSOLE_SHORT_PRE}" | grep -a " speed " | tail -n 1 | awk '{ for (i=1;i<=NF;i++)if($i~/speed/) printf $(i+2)" "$(i+5) }'`
  fi

  ############################################################################
  # zeroing too big gpuhash values
  ifHashrateZeroed=0
  for iarr in "" 2; do
    # check if array exists
    [[ -z `echo "${JSON}" | jq -r ".gpuHash${iarr} // empty"` ]] && continue
    gpuHash=`echo "${JSON}" | jq -r ".gpuHash${iarr}[]" | tr -d "\"" | awk -F. '{ print $1 }'`
    gpuHashArr=(`echo "${gpuHash}"`)
    gpuHashSortArr=(`echo "${gpuHash}" | grep -v "^0$" | sort`) # filtered out zero hashrates
    n=${#gpuHashArr[@]}
    nSort=${#gpuHashSortArr[@]}
    # do not filter if only 3 or less elements
    [[ ${nSort} -le 2 ]] && continue
    mediana=0
    if [[ $(($n % 2)) == 1 ]]; then
      mediana=${gpuHashSortArr[$((${nSort}/2-1))]}
    else
      medianaN=$((n/2))
      medianaA=${gpuHashSortArr[$((medianaN-1))]} # -1 because start from 0
      medianaB=${gpuHashSortArr[$((medianaN+1-1))]}
      mediana=$(((medianaA+medianaB)/2))
    fi
    hashrateLimit=$((mediana*20))
    # zeroing too big values:
    ifRecalculateSum=0
    for ((i=0; i<${n}; i++)) do
      if [[ ${gpuHashArr[${i}]} -ge ${hashrateLimit} ]]; then
        JSON=`echo "${JSON}" | jq ".gpuHash${iarr}[\"${i}\"]=\"0.00\""`
        ifRecalculateSum=1 # please recalculate sum
        ifHashrateZeroed=1 # please add error msg in console
      fi
    done
    # recalculate sum
    if [[ ${ifRecalculateSum} == 1 ]]; then
      gpuHashSum=`echo "${JSON}" | jq -r ".gpuHash${iarr}[]" | tr -d "\"" | awk '{ sum+=$1 } END { printf "%.2f", sum }'`
      JSON=`echo "${JSON}" | jq ".hash${iarr}=\"${gpuHashSum}\""`
    fi
  done
  if [[ ${ifHashrateZeroed} == 1 ]]; then
    CONSOLE+="\n<span style='color:red;'><b>!!! Some GPU hashrates are zeroed due to very high values reported by miner. Please reload miner or use newer version of miner to fix this.</b></span>"
  fi
  ############################################################################

  # find errors:
  # CUDA9.1 error
  # z-enemy: Unable to query number of CUDA devices!
  # ?
  # ?
  # t-rex: unable to get number of CUDA devices
  # xmr-stak: wrong vendor driver
  if [[ $(echo "${CONSOLE}" | grep -ai "Unable to query number of CUDA devices\|does not support CUDA\|driver version is insufficient\|unable to get number of CUDA devices\|wrong vendor driver" | wc -l) == 1 ]]; then
    CONSOLE+="\n<span style='color:red;'><b>!!! Please download newest SimpleMiningOS image in order to use this miner !!!</b></span>"
  fi
fi




### CONSOLE_SHORT
# filter out special characters
CONSOLE_SHORT=`echo "${CONSOLE_SHORT}" | tr -d '\001'-'\011''\013''\014''\016'-'\037''\200'-'\377'`
# make sure lines are not too long
CONSOLE_SHORT=`echo "${CONSOLE_SHORT}" | awk '{ print substr($0, 1, 30) }'`
echo "${CONSOLE_SHORT}" > /var/tmp/screen.miner.log.short.to_send
JSON=`echo "${JSON}" | jq ".consoleShort=\"${CONSOLE_SHORT}\""`


### CONSOLE
# default = send CONSOLE evey update_status loop. But If report=slow (60 sec) then CONSOLE only every 2 minutes
# slow (defualt)=60sec / norm=20sec / fast=5sec / now=1sec
ifReportSlow=1
[[ -f /var/tmp/update_status_fast ]] && ifReportSlow=0
[[ -f /var/tmp/update_status_now  ]] && ifReportSlow=0
[[ `cat /var/tmp/update_status_report 2> /dev/null` == "fast" ]] && ifReportSlow=0
[[ `cat /var/tmp/update_status_report 2> /dev/null` == "norm" ]] && ifReportSlow=0
# final check
ifDoConsoleSend=1
[[ ${ifReportSlow} == 1 && -e /var/tmp/screen.miner.log.sent && `stat --format=%Y /var/tmp/screen.miner.log.sent` -gt $((`date +%s` - 120)) ]] && ifDoConsoleSend=0
if [[ ${ifDoConsoleSend} == 1 ]]; then
  # filter out special characters
  CONSOLE=`echo "${CONSOLE}" | tr -d '\001'-'\011''\013''\014''\016'-'\037''\200'-'\377'`
  # pack console
  CONSOLE=`echo -e "${CONSOLE}" | gzip -c | base64 -w 0`
  echo "${CONSOLE}" > /var/tmp/screen.miner.log.to_send
  ifConsoleSend=0
  # check if sent file is very old (beyond 1h)
  [[ -f /var/tmp/screen.miner.log.sent && `stat --format=%Y /var/tmp/screen.miner.log.sent` -lt $((`date +%s` - 3600)) ]] && sudo rm -f /var/tmp/screen.miner.log.sent
  # check if were sent after rig reboot
  [[ ! -f /var/tmp/screen.miner.log.sent ]] && ifConsoleSend=1
  # check if have newer data than last sent
  if [[ -f /var/tmp/screen.miner.log.sent && -f /var/tmp/screen.miner.log.to_send ]]; then
    md5Sent=`md5sum /var/tmp/screen.miner.log.sent | awk '{ print $1 }'`
    md5New=`md5sum /var/tmp/screen.miner.log.to_send | awk '{ print $1 }'`
    [[ ${md5Sent} != ${md5New} ]] && ifConsoleSend=1
  fi
  # get file content
  [[ ${ifConsoleSend} == 0 ]] && CONSOLE=
  [[ "${CONSOLE}" != "" ]] && JSON=`echo "${JSON}" | jq ".console=\"${CONSOLE}\""`
fi

StatFileAppendJson () {
  varName=$1; fileName=$2; type=$3; doForce=$4
  jsonTmp=
  doSend=0
  # check if force send
  [[ ${doForce} == 1 ]] && doSend=1

  # if failed(?) last sent (in update_status), then remove xxx.to_send and xxx.sent files and resend with fresh content
  [[ -f /var/tmp/${fileName}.to_send ]] && sudo rm -f /var/tmp/${fileName}.*

  # if last sent was long time ago, then resend
  [[ -f /var/tmp/${fileName}.sent && `stat --format=%Y /var/tmp/${fileName}.sent` -lt $((`date +%s` - 3600)) ]] && sudo rm -f /var/tmp/${fileName}.sent

  # if new data file has newer date then sent file (thats mean, that stats_periodic force us to resend data even if no differs)
  [[ -f /var/tmp/${fileName}.sent && `stat --format=%Y /var/tmp/${fileName}` -gt `stat --format=%Y /var/tmp/${fileName}.sent` ]] && sudo rm -f /var/tmp/${fileName}.sent

  # if was not sent earlier (or deleted file), then resend
  [[ ! -f /var/tmp/${fileName}.sent ]] && doSend=1

  # if new data differs from prev sent, then send
  if [[ -f /var/tmp/${fileName}.sent && -f /var/tmp/${fileName} ]]; then
    md5Cur=`md5sum /var/tmp/${fileName}.sent | awk '{ print $1 }'`
    md5New=`md5sum /var/tmp/${fileName}      | awk '{ print $1 }'`
    [[ ${md5Cur} != ${md5New} ]] && doSend=1
  fi

  # get file content
  [[ ${doSend} == 1 && ${type} == "array" ]] && jsonTmp=`cat /var/tmp/${fileName} 2> /dev/null | jq -r '.' 2> /dev/null`
  [[ ${doSend} == 1 && ${type} == "txt"   ]] && jsonTmp=`cat /var/tmp/${fileName} 2> /dev/null || echo ""`

  # append to main JSON if not empty
  if [[ ${jsonTmp} != "" ]]; then
    [[ ${type} == "array" ]] && JSON=`echo "${JSON}" | jq ".${varName}=${jsonTmp}"`
    [[ ${type} == "txt" ]]   && JSON=`echo "${JSON}" | jq ".${varName}=\"${jsonTmp}\""`
    # save what was sent to not duplicate in future if not needed
    echo "${jsonTmp}" > /var/tmp/${fileName}.to_send
  fi
}

# uptime here instead of stats_periodic to see changes every few sec (not 20 sec) in dashboard
uptimeSec=`cat /proc/uptime | awk '{ print int($1) }'`
uptimeStr=
[[ ${uptimeSec} -ge 86400 ]] && uptimeStr="${uptimeStr} "`echo "${uptimeSec}" | awk '{ print int($1/86400) }'`"d"
[[ ${uptimeSec} -ge 3600  ]] && uptimeStr="${uptimeStr} "`echo "${uptimeSec}" | awk '{ print int(($1%86400)/3600) }'`"h"
[[ ${uptimeSec} -ge 60    ]] && uptimeStr="${uptimeStr} "`echo "${uptimeSec}" | awk '{ print int(($1%3600)/60) }'`"m"
[[ ${uptimeSec} -lt 60    ]] && uptimeStr="${uptimeSec}s"
[[ ${uptimeStr} != `cat /var/tmp/stats_sys_uptime 2> /dev/null` ]] && echo "${uptimeStr}" > /var/tmp/stats_sys_uptime

# Fixed data
StatFileAppendJson gpuPciBus stats_gpu_pcibus_jq array 0
StatFileAppendJson gpuPciId stats_gpu_pciid_jq array 0
StatFileAppendJson gpuModel stats_gpu_model_jq array 0
StatFileAppendJson gpuManufacturer stats_gpu_manufacturer_jq array 0
StatFileAppendJson gpuVramSize stats_gpu_vram_size_jq array 0
StatFileAppendJson gpuVramType stats_gpu_vram_type_jq array 0
StatFileAppendJson gpuVramChip stats_gpu_vram_chip_jq array 0
StatFileAppendJson gpuBiosVer stats_gpu_bios_ver_jq array 0
StatFileAppendJson gpuPwrMin stats_gpu_pwr_min_jq array 0
StatFileAppendJson gpuPwrMax stats_gpu_pwr_max_jq array 0

# Dynamic data
StatFileAppendJson gpuCoreClk stats_gpu_core_clk_jq array 0
StatFileAppendJson gpuMemClk stats_gpu_mem_clk_jq array 0
StatFileAppendJson gpuPwrLimit stats_gpu_pwr_limit_jq array 0
StatFileAppendJson gpuPwrCur stats_gpu_pwr_cur_jq array 0
StatFileAppendJson gpuFan stats_gpu_fan_jq array 0
StatFileAppendJson gpuTemp stats_gpu_temp_jq array 0
StatFileAppendJson gpuAsicTemp stats_gpu_asic_temp_jq array 0
StatFileAppendJson gpuMemTemp stats_gpu_mem_temp_jq array 0
StatFileAppendJson gpuVddGfx stats_gpu_vdd_gfx_jq array 0
StatFileAppendJson gpuMvdd stats_gpu_mvdd_jq array 0
StatFileAppendJson gpuMvddci stats_gpu_mvddci_jq array 0

# Txt data
StatFileAppendJson gpuCount stats_gpu_count txt 1
StatFileAppendJson sysPwr stats_sys_pwr txt 0
StatFileAppendJson kernel stats_sys_kernel txt 0
StatFileAppendJson driver stats_sys_driver txt 0
StatFileAppendJson uptime stats_sys_uptime txt 0
StatFileAppendJson ipLAN stats_sys_ipLAN txt 0
StatFileAppendJson ipWAN4 stats_sys_ipWAN4 txt 0
StatFileAppendJson ipWAN6 stats_sys_ipWAN6 txt 0
StatFileAppendJson sysLoad5 stats_sys_sysLoad5 txt 0
StatFileAppendJson sysCpuModel stats_sys_cpuModel txt 0
StatFileAppendJson sysMbo stats_sys_mbo txt 0
StatFileAppendJson sysBios stats_sys_bios txt 0
StatFileAppendJson sysRamSize stats_sys_sysRamSize txt 0
StatFileAppendJson sysHdd stats_sys_hdd txt 0
StatFileAppendJson isWifiEnabled stats_is_wifi_enabled txt 0
StatFileAppendJson wifiRssiPercentage stats_wifi_rssi_percentage txt 0

# append err to JSON
errDir="/var/tmp/err"
for errFile in `ls -1 /var/tmp/err/ 2> /dev/null | grep -v ".tmp$\|.sent$\|.to_send$"`; do
  # if sent already, then ommit file
  [[ -f ${errDir}/${errFile}.sent ]] && continue
  iGpu=`echo ${errFile} | awk -F_ '{ print $2 }' 2> /dev/null`
  iCode=`echo ${errFile} | awk -F_ '{ print $3 }' 2> /dev/null`
  [[ -z ${iGpu} || -z ${iCode} ]] && continue # bad file name
  [[ ${iGpu} == sys ]] && iCat="sys" || iCat="gpu"
  iCodeJq=`echo -n ${iCode} | jq -aRs .`
  iGpuJq=`echo -n ${iGpu} | jq -aRs .`
  if [[ ${iCat} == sys ]]; then
    JSON=`echo "${JSON}" | jq ".err.${iCat} += [${iCodeJq}]"`
  else
    JSON=`echo "${JSON}" | jq ".err.${iCat}.${iGpuJq} += [${iCodeJq}]"`
  fi  
  # flag file ready in sending mode
  touch ${errDir}/${errFile}.to_send
done

# get dmesg.to_send file content
if [ -f /var/tmp/dmesg.to_send ]; then
  sudo chown miner:miner /var/tmp/dmesg.to_send
  CONSOLE_DMESG=`cat /var/tmp/dmesg.to_send | sed 's/\r/\n/g; s/\\\\/_/g' | grep -a . | tail -n 200 | aha --no-header`
  # remove some special characters from HTML code (after AHA)
  # replace [space & < > " ' '] with underscore
  CONSOLE_DMESG=`echo "${CONSOLE_DMESG}" | sed 's/&nbsp;/_/g; s/&amp;/_/g; s/&lt;/_/g; s/&gt;/_/g; s/&quot;/_/g; s/&ldquo;/_/g; s/&rdquo;/_/g'`
  # remove amp
  CONSOLE_DMESG=`echo "${CONSOLE_DMESG}" | sed 's/\&//g' | tr '"' "'"`
  # filter out special characters
  CONSOLE_DMESG=`echo "${CONSOLE_DMESG}" | tr -d '\001'-'\011''\013''\014''\016'-'\037''\200'-'\377'`
  CONSOLE_DMESG=`echo -e "${CONSOLE_DMESG}" | gzip -c | base64 -w 0`
  JSON=`echo "${JSON}" | jq ".consoleDmesg=\"${CONSOLE_DMESG}\""`

  # last 100 lines from console
  CONSOLE_DEBUG=`cat /var/tmp/screen.miner.log`
  ## add system messages
  CONSOLE_DEBUG+=`echo; cat /var/tmp/screen.miner.log.d-* 2> /dev/null`
  # if minerPause
  [[ -f /var/tmp/minerPause ]] && CONSOLE_DEBUG+=`echo -ne "\n${xNO}${xRED}${xBOLD}Paused${xNO}"`
  # convert some LIGHT colors to darken (aha drops LIGHT colors)
  #96 - lightcyan -> 36 - cyan
  #95 - lightmagenta -> 33 - yellow
  #92 - light -> 32 - green
  CONSOLE_DEBUG=`echo "${CONSOLE_DEBUG}" | sed -e 's/\[96m/\[36m/g' | sed -e 's/\[95m/\[33m/g' | sed -e 's/\[92m/\[32m/g'`
  # remove nbminer 49 (default background color), which gaves me black background in aha
  CONSOLE_DEBUG=`echo "${CONSOLE_DEBUG}" | sed -e 's/\[49;/\[/g'`
  # remove cryptodredge "default clearing" (ESC[39;49m) not supported on some terminals causing black text text on black background
  CONSOLE_DEBUG=`echo "${CONSOLE_DEBUG}" | sed -e 's/\x1B\[39m//g' -e 's/\x1B\[49m//g'`
  # remove "ATTR+one space" lines "[[96m ^M" (PhoenixMiner)
  CONSOLE_DEBUG=`echo "${CONSOLE_DEBUG}" | sed -e 's/^\x1B\[36m\ \r$//g'`
  # remove all single and multiple ^M characters (but only on end of lines)
  # replace ^M characters with our sign and delete those lines (progress bars without last occurrence)
  # replace linex with spaces only (!+) to empty line wign (and later remove those lines)
  # replace ^M with standard unix EOL
  # replace "\\" with "_"
  # remove empty lines (by greping lines with at least one character)
  # limit to X lines output
  # convert to HTML
  CONSOLE_DEBUG=`echo "${CONSOLE_DEBUG}" | sed 's/\r\{1,\}$//g' | sed -e 's/\r/XXXDELETEXXX\n/g' | sed -e 's/^[ ]*$/XXXDELETEXXX/g' | grep -av "XXXDELETEXXX" | sed 's/\r/\n/g; s/\\\\/_/g' | grep -a . | tail -n 200 | aha --no-header`
  # remove some special characters from HTML code (after AHA)
  # replace [space & < > " ' '] with underscore
  CONSOLE_DEBUG=`echo "${CONSOLE_DEBUG}" | sed 's/&nbsp;/_/g; s/&amp;/_/g; s/&lt;/_/g; s/&gt;/_/g; s/&quot;/_/g; s/&ldquo;/_/g; s/&rdquo;/_/g'`
  # remove amp
  CONSOLE_DEBUG=`echo "${CONSOLE_DEBUG}" | sed 's/\&//g' | tr '"' "'"`
  # filter out special characters
  CONSOLE_DEBUG=`echo "${CONSOLE_DEBUG}" | tr -d '\001'-'\011''\013''\014''\016'-'\037''\200'-'\377'`
  CONSOLE_DEBUG=`echo -e "${CONSOLE_DEBUG}" | gzip -c | base64 -w 0`
  JSON=`echo "${JSON}" | jq ".consoleDebug=\"${CONSOLE_DEBUG}\""`
fi

# Console System
ifile="/var/tmp/consoleSys.log"
cp -f ${ifile} ${ifile}.tmp
# if send 0: whole log file or 1: only changes (new lines/characters)
consoleSysFullInc=1
# if new log shorter than prev - force send full
consoleSysSize=`    cat ${ifile}.tmp  | wc -c`
consoleSysSizePrev=`cat ${ifile}.prev | wc -c`
[[ ${consoleSysSizePrev} -gt ${consoleSysSize} ]] && consoleSysFullInc=0
# if shared begining differ - force send full
if [[ ${consoleSysFullInc} == 1 ]]; then
  consoleSysShareMd5=`    cat ${ifile}.tmp  | head -c ${consoleSysSizePrev} 2> /dev/null | md5sum | awk '{ print $1 }'`
  consoleSysShareMd5Prev=`cat ${ifile}.prev | head -c ${consoleSysSizePrev} 2> /dev/null | md5sum | awk '{ print $1 }'`
  [[ ${consoleSysShareMd5} != ${consoleSysShareMd5Prev} ]] && consoleSysFullInc=0
fi
# if forced full - clear old file
[[ ${consoleSysFullInc} == 0 ]] && echo -n > ${ifile}.prev
# get fragment or whole file for sent
[[ ${consoleSysFullInc} == 0 ]] && consoleSysSkip=0 || consoleSysSkip=${consoleSysSizePrev}
cat ${ifile}.tmp | tail -c +$((consoleSysSkip+1)) 2> /dev/null > ${ifile}.to_send_new
cat ${ifile}.to_send_new >> ${ifile}.prev
cat ${ifile}.to_send_new >> ${ifile}.to_send
# clear tmp files
rm -f ${ifile}.to_send_new 2> /dev/null
rm -f ${ifile}.tmp 2> /dev/null
consoleSysToSendSize=`cat ${ifile}.to_send | wc -c`
CONSOLE_SYS=`cat ${ifile}.to_send | sed 's/\r\{1,\}$//g' | sed -e 's/\r/XXXDELETEXXX\n/g' | grep -av "XXXDELETEXXX" | sed 's/\r/\n/g; s/\\\\/_/g'`
if [[ ${consoleSysToSendSize} -gt 0 ]]; then
  CONSOLE_SYS_BASE64=`echo -e "${CONSOLE_SYS}" | gzip -c | base64 -w 0`
  # wait for dashboard ready for receiving ;-)
  #JSON=`echo "${JSON}" | jq ".consoleSys=\"${CONSOLE_SYS_BASE64}\""`
  # TEST
  #cat ${ifile}.to_send >> /tmp/consoleSys.plain
  #echo "${JSON}" | jq -r '.consoleSys' >> /tmp/xxx
fi
# truncate log file
if [[ -e ${ifile} ]]; then
  ifileLines=`cat ${ifile} | wc -l`
  if [[ ${ifileLines} -gt 500 ]]; then
    tail -n 100 ${ifile} > ${ifile}.tmptruncate 2> /dev/null
    mv -f ${ifile}.tmptruncate ${ifile} 1> /dev/null 2> /dev/null
  fi
fi

# New Console DmesgInc
ifile="/var/tmp/dmesg2"
cp -f /var/tmp/dmesg ${ifile}.tmp
# if send 0: whole log file or 1: only changes (new lines/characters)
consoleDmesg2FullInc=1
# if new log shorter than prev - force send full
consoleDmesg2Size=`    cat ${ifile}.tmp  2> /dev/null | wc -c`
consoleDmesg2SizePrev=`cat ${ifile}.prev 2> /dev/null | wc -c`
[[ ${consoleDmesg2SizePrev} -gt ${consoleDmesg2Size} ]] && consoleDmesg2FullInc=0
# if shared begining differ - force send full
if [[ ${consoleDmesg2FullInc} == 1 ]]; then
  consoleDmesg2ShareMd5=`    cat ${ifile}.tmp  | head -c ${consoleDmesg2SizePrev} 2> /dev/null | md5sum | awk '{ print $1 }'`
  consoleDmesg2ShareMd5Prev=`cat ${ifile}.prev | head -c ${consoleDmesg2SizePrev} 2> /dev/null | md5sum | awk '{ print $1 }'`
  [[ ${consoleDmesg2ShareMd5} != ${consoleDmesg2ShareMd5Prev} ]] && consoleDmesg2FullInc=0
fi
# if forced full - clear old file
[[ ${consoleDmesg2FullInc} == 0 ]] && echo -n > ${ifile}.prev
# get fragment or whole file for sent
[[ ${consoleDmesg2FullInc} == 0 ]] && consoleDmesg2Skip=0 || consoleDmesg2Skip=${consoleDmesg2SizePrev}
cat ${ifile}.tmp | tail -c +$((consoleDmesg2Skip+1)) 2> /dev/null > ${ifile}.to_send_new
cat ${ifile}.to_send_new >> ${ifile}.prev
cat ${ifile}.to_send_new >> ${ifile}.to_send
# clear tmp files
rm -f ${ifile}.to_send_new
rm -f ${ifile}.tmp
consoleDmesg2ToSendSize=`cat ${ifile}.to_send | wc -c`
CONSOLE_DMESG2=`cat ${ifile}.to_send | sed 's/\r\{1,\}$//g' | sed -e 's/\r/XXXDELETEXXX\n/g' | grep -av "XXXDELETEXXX" | sed 's/\r/\n/g; s/\\\\/_/g'`
if [[ ${consoleDmesg2ToSendSize} -gt 0 ]]; then
  CONSOLE_DMESG2_BASE64=`echo -e "${CONSOLE_DMESG2}" | gzip -c | base64 -w 0`
  JSON=`echo "${JSON}" | jq ".consoleDmesg2=\"${CONSOLE_DMESG2_BASE64}\""`

  # secure from flood
  consoleDmesg2ToSendLines=`cat ${ifile}.to_send | wc -l`
  # dmesg flood flag and counter
  consoleDmesg2FloodFlag=`date --date='5 minutes ago' +%Y%m%d%H%M`
  # check if dmesg2 sending in suspend mode
  consoleDmesg2FloodSuspend=`cat ${ifile}.sentCounter 2> /dev/null | awk -v consoleDmesg2FloodFlag=${consoleDmesg2FloodFlag} '{ if ($1>consoleDmesg2FloodFlag) print $2 }' | grep "flood" | head -n 1 | wc -l`
  if [[ ${consoleDmesg2FloodSuspend} == 1 ]]; then
    # suspend for few minutes...just remove variable and send nothing
    JSON=`echo "${JSON}" | jq 'del(.consoleDmesg2)'`
    #echo "suspended in progress" >> /tmp/consoleDmesg2.plain
  else
    consoleDmesg2FloodCount=`cat ${ifile}.sentCounter 2> /dev/null | awk -v consoleDmesg2FloodFlag=${consoleDmesg2FloodFlag} '{ if ($1>consoleDmesg2FloodFlag) print $2 }' | paste -s -d+ | bc | awk '{ printf "%.0f", $1 }'`
    if [[ ${consoleDmesg2FloodCount} -gt 100 ]]; then
      #echo "suspend" >> /tmp/consoleDmesg2.plain
      # in last minutes was sending too much logs - start suspend
      JSON=`echo "${JSON}" | jq 'del(.consoleDmesg2)'`
      echo "`date +%Y%m%d%H%M` flood" > ${ifile}.sentCounter
      #CONSOLE_DMESG2='Dmesg flood detected. Suspend sending dmesg log for 5 minutes'
      #CONSOLE_DMESG2_BASE64=`echo -e "${CONSOLE_DMESG2}" | gzip -c | base64 -w 0`
      #JSON=`echo "${JSON}" | jq ".consoleDmesg2=\"${CONSOLE_DMESG2_BASE64}\""`
      # TEST
      #echo "${CONSOLE_DMESG2}" >> /tmp/consoleDmesg2.plain
      #echo "${JSON}" | jq -r '.consoleDmesg2' >> /tmp/yyy
    else
      #echo "grant" >> /tmp/consoleDmesg2.plain
      # not flooded in last time. grant for sending
      # just append lines count
      echo "`date +%Y%m%d%H%M` ${consoleDmesg2ToSendLines}" >> ${ifile}.sentCounter
      # TEST
      #echo -e "${CONSOLE_DMESG2}" >> /tmp/consoleDmesg2.plain
      #echo "${JSON}" | jq -r '.consoleDmesg2' >> /tmp/yyy
    fi
  fi
fi
# truncate log file
# ...is managed by watchdog_system
ifile="/var/tmp/dmesg.sentCounter"
# truncate log counter file
if [[ -e ${ifile} ]]; then
  ifileLines=`cat ${ifile} | wc -l`
  if [[ ${ifileLines} -gt 500 ]]; then
    consoleDmesgCounterTruncateFlag=`date --date='6 minutes ago' +%Y%m%d%H%M`
    cat ${ifile}.sentCounter 2> /dev/null | awk -v consoleDmesgCounterTruncateFlag=${consoleDmesgCounterTruncateFlag} '{ if ($1>consoleDmesgCounterTruncateFlag) print $0 }' > ${ifile}.tmptruncate 2> /dev/null
    mv -f ${ifile}.tmptruncate ${ifile} 1> /dev/null 2> /dev/null
  fi
fi

# save hashrate to file
echo "${JSON}" | jq '.hash' 2> /dev/null | tr -d '\"' > /var/tmp/stats_hash
echo "${JSON}" | jq '.gpuHash // empty' 2> /dev/null > /var/tmp/stats_gpu_hash_jq

echo "${JSON}"
