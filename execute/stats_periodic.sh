#!/bin/bash

[[ `id -u` -eq 0 ]] && echo "Please run NOT as root" && exit

[[ -z ${DEBUG} ]] && DEBUG=0

CONFIG_FILE="/root/config.txt"
source ${CONFIG_FILE}

uptimeSec=`cat /proc/uptime | awk '{ print int($1) }'`

# GPU Manufacturer database
gpuManufacturers[0x1002]="AMD"
gpuManufacturers[0x1022]="AMD" # AMD APU (BC-250 APU on AsRock)
gpuManufacturers[0x1043]="Asus"
gpuManufacturers[0x10b0]="Gainward"
gpuManufacturers[0x10de]="Nvidia"
gpuManufacturers[0x1458]="Gigabyte"
gpuManufacturers[0x1462]="Msi"
gpuManufacturers[0x148c]="Powercolor"
gpuManufacturers[0x1569]="Palit"
gpuManufacturers[0x1682]="Xfx" # XFX Pine Group Inc.
gpuManufacturers[0x1787]="His"
gpuManufacturers[0x1849]="Asrock"
gpuManufacturers[0x196e]="Pny"
gpuManufacturers[0x19da]="Zotac"
gpuManufacturers[0x174b]="Sapphire"
gpuManufacturers[0x1da2]="Sapphire"
gpuManufacturers[0x3842]="Evga"
gpuManufacturers[0x7377]="Colorful"
gpuManufacturers[0x1eae]="Xfx" # XFX Limited
getGpuManufacturerStr () {
  local out=${gpuManufacturers["0x"$1]}
  echo -n ${out}
}

JSSTAT='{}'
IFS='
'

doFixed=0   # fixed data - stat once per some time - in theory static data
doDynamic=1 # dynamic data - stat every time

# if one of these data are older than 10minutes (or not exist yet), refresh fixed data (and make it to be sent by update_status)
# this prevent to run slow utils every time stats_periodic is running
doFixedFiles=()
doFixedFiles+=("stats_gpu_bios_ver_jq")
doFixedFiles+=("stats_gpu_count")
[[ ${osSeries} == "NV" ]] && doFixedFiles+=("stats_gpu_fans_per_gpu")
doFixedFiles+=("stats_gpu_model_jq")
doFixedFiles+=("stats_gpu_manufacturer_jq")
doFixedFiles+=("stats_gpu_pcibus_jq")
doFixedFiles+=("stats_gpu_pwr_max_jq")
doFixedFiles+=("stats_gpu_pwr_min_jq")
doFixedFiles+=("stats_gpu_vram_chip_jq")
doFixedFiles+=("stats_gpu_vdd_gfx_jq")
doFixedFiles+=("stats_gpu_vram_size_jq")
doFixedFiles+=("stats_gpu_vram_type_jq")
for iFile in "${doFixedFiles[@]}"; do
  [[ ! -f /var/tmp/${iFile} || `stat --format=%Y /var/tmp/${iFile}` -lt $((`date +%s` - 600 )) ]] && doFixed=1 && break
  # check if array contains good count of elements with actual state of gpuCount
  [[ ${iFile} == "stats_gpu_count" ]] && continue
  if [[ -f /var/tmp/stats_gpu_count && -f /var/tmp/${iFile} ]]; then
    gpuCountSubCheck=`cat /var/tmp/stats_gpu_count`
    gpuCountSubArrayLen=`cat /var/tmp/${iFile} '. | length' 2> /dev/null`
    [[ ${gpuCountSubCheck} != ${gpuCountSubArrayLen} ]] && doFixed=1 && break
  fi
done

StatFileUpdate () {
  varName=$1; fileName=$2;
  doWrite=0
  # update if file not yet exist
  [[ ! -f /var/tmp/${fileName} ]] && doWrite=1
  # write to tmp file
  echo ${JSSTAT} | jq -r ".${varName}" > /var/tmp/${fileName}.tmp
  # write if data changed
  if [[ -f /var/tmp/${fileName}.tmp && -f /var/tmp/${fileName} ]]; then
    md5Tmp=`md5sum /var/tmp/${fileName}.tmp | awk '{ print $1 }'`
    md5Cur=`md5sum /var/tmp/${fileName}     | awk '{ print $1 }'`
    [[ ${md5Tmp} != ${md5Cur} ]] && doWrite=1
  fi
  # do write/update data
  [[ ${doWrite} == 1 ]] && cp -f /var/tmp/${fileName}.tmp /var/tmp/${fileName}
  # delete tmp file
  [[ -f /var/tmp/${fileName}.tmp ]] && rm -f /var/tmp/${fileName}.tmp
}


#### system variables (updated every time. but resending in stats_rig only if older than 1h)
# kernel version
kernel=`uname -r`
# append image verion (uniq number)
imageVer=`cat /root/imageVer 2> /dev/null || echo ""`
[[ ! -z ${imageVer} ]] && kernel+="#"${imageVer}
#distro=`(lsb_release -rs | grep "^18") 1> /dev/null 2> /dev/null && echo "-ub18" || echo ""`
#kernel+=$distro
kernelJq=`echo -n ${kernel} | jq -aRs .`
JSSTAT=`echo ${JSSTAT} | jq ".kernel=${kernelJq}"`
StatFileUpdate kernel stats_sys_kernel

driver="n/d"
if [[ ${osSeries} == "RX" ]]; then
  driverAmd=`dpkg -l | grep amdgpu | grep pro | head -n 1 | awk '{ print $3 }' | awk -F"-" '{ print $1 }'`
  driverRocm=`modinfo amdgpu 2>/dev/null | grep -i ^version | awk '{ print $2 }'`
  driver="amd${driverAmd}"
  [[ ! -z ${driverRocm} ]] && driver+="r${driverRocm}"
elif [[ ${osSeries} == "NV" ]]; then
  driverNv=`modinfo nvidia | grep ^version | awk '{ print $2 }'`
  [[ -z ${driverNv} ]] && driverNv="0.0"
  cudaCompatibility=()
  cudaCompatibility+=("346.46 7.0")
  cudaCompatibility+=("352.31 7.5")
  cudaCompatibility+=("375.26 8.0")
  cudaCompatibility+=("384.81 9.0")
  cudaCompatibility+=("390.46 9.1")
  cudaCompatibility+=("396.37 9.2")
  cudaCompatibility+=("410.48 10.0")
  cudaCompatibility+=("418.39 10.1")
  cudaCompatibility+=("440.33 10.2")
  cudaCompatibility+=("450.57 11.0")
  cudaCompatibility+=("455.23 11.1")
  cudaCompatibility+=("460.27 11.2")
  cudaCompatibility+=("465.19 11.3")
  cudaCompatibility+=("470.42 11.4")
  cudaCompatibility+=("495.29 11.5")
  cudaCompatibility+=("510.39 11.6")
  driverCuda="0.0" #default
  for iCuda in "${cudaCompatibility[@]}"; do
    driverNvTest=`echo ${driverNv} | awk -F"." '{ print $1"."$2 }'` # two first colons
    iDriverNv=`echo    ${iCuda}    | awk '{ print $1 }'`
    iDriverCuda=`echo  ${iCuda}    | awk '{ print $2 }'`
    [[ `echo "${driverNvTest} >= ${iDriverNv}" | bc` == 1 ]] && driverCuda=${iDriverCuda}
  done
  driver="nv${driverNv}c${driverCuda}"
fi
driverJq=`echo -n ${driver} | jq -aRs .`
JSSTAT=`echo ${JSSTAT} | jq ".driver=${driverJq}"`
StatFileUpdate driver stats_sys_driver

ipLAN=`hostname -I | awk '{ print $1 }'`
ipLANJq=`echo -n ${ipLAN} | jq -aRs .`
JSSTAT=`echo ${JSSTAT} | jq ".ipLAN=${ipLANJq}"`
StatFileUpdate ipLAN stats_sys_ipLAN

for ipv in 4 6; do
  # ipWAN renew every 1 hour. retry after 10min when failed
  iFile=stats_sys_ipWAN${ipv}
  [[ ${uptimeSec} -lt 180 ]] && failRetryTime=30 || failRetryTime=600 # retry more often just after reboot
  if ( [[ ! -f /var/tmp/${iFile}.fail   ]] || [[ -f /var/tmp/${iFile}.fail   && `stat --format=%Y /var/tmp/${iFile}.fail`   -lt $((`date +%s` - ${failRetryTime} )) ]] ) &&
     ( [[ ! -f /var/tmp/${iFile}        ]] || [[ -f /var/tmp/${iFile}        && `stat --format=%Y /var/tmp/${iFile}`        -lt $((`date +%s` - 3600 )) ]] ) &&
     ( [[ ! -f /var/tmp/${iFile}.lastok ]] || [[ -f /var/tmp/${iFile}.lastok && `stat --format=%Y /var/tmp/${iFile}.lastok` -lt $((`date +%s` - 3600 )) ]] ); then
     # file.lastok is necessery to save date of last success because StatFileUpdate will not update file timestamp if content not differ
    data=`curl -k -${ipv} --connect-timeout 10 --max-time 20 ${BASEURL}/rig/ip`
    [[ ${DEBUG} == 1 ]] && echo "`date +%Y%m%d_%H.%M.%S` curl data=${data}" >> /var/tmp/debug.ipWAN${ipv}
    if [[ `echo "${data}" | jq -r '.status // empty' 2> /dev/null` == "ok" ]]; then
      ipWAN=`echo "${data}" | jq -r '.ip // empty' 2> /dev/null`
      ipWANJq=`echo -n ${ipWAN} | jq -aRs .`
      JSSTAT=`echo ${JSSTAT} | jq ".ipWAN${ipv}=${ipWANJq}"`
      StatFileUpdate ipWAN${ipv} stats_sys_ipWAN${ipv}
      [[ ${DEBUG} == 1 ]] && echo "`date +%Y%m%d_%H.%M.%S` OK ipWAN${ipv}=${ipWAN}" >> /var/tmp/debug.ipWAN${ipv}
      touch /var/tmp/${iFile}.lastok 2> /dev/null
      [[ -f /var/tmp/${iFile}.fail ]] && sudo rm -f /var/tmp/${iFile}.fail 2> /dev/null
    else
      [[ ${DEBUG} == 1  ]] && echo "`date +%Y%m%d_%H.%M.%S` ERR data=${data}" >> /var/tmp/debug.ipWAN${ipv}
      touch /var/tmp/${iFile}.fail 2> /dev/null
      [[ -f /var/tmp/${iFile}.lastok ]] && sudo rm -f /var/tmp/${iFile}.lastok 2> /dev/null
    fi
  fi
done

sysLoad5=`cat /proc/loadavg | awk '{ print $2 }'`
sysLoad5Jq=`echo -n ${sysLoad5} | jq -aRs .`
JSSTAT=`echo ${JSSTAT} | jq ".sysLoad5=${sysLoad5Jq}"`
StatFileUpdate sysLoad5 stats_sys_sysLoad5

sysCpuModel=`cat /proc/cpuinfo | grep "model name" | awk -F: '{ $1=""; print $0 }' | head -n 1 | sed 's/^[ ]*//'`
sysCpuModelJq=`echo -n "${sysCpuModel}" | jq -aRs .`
JSSTAT=`echo ${JSSTAT} | jq ".sysCpuModel=${sysCpuModelJq}"`
StatFileUpdate sysCpuModel stats_sys_cpuModel

tmpVendor=`cat /sys/devices/virtual/dmi/id/board_vendor`
tmpName=`cat /sys/devices/virtual/dmi/id/board_name`
tmpVersion=`cat /sys/devices/virtual/dmi/id/board_version`
sysMboJq=`echo -n "${tmpVendor} ${tmpName} ${tmpVersion}" | jq -aRs .`
JSSTAT=`echo ${JSSTAT} | jq ".sysMbo=${sysMboJq}"`
StatFileUpdate sysMbo stats_sys_mbo

tmpDate=`cat /sys/devices/virtual/dmi/id/bios_date`
tmpVersion=`cat /sys/devices/virtual/dmi/id/bios_version`
sysBios=`echo -n "${tmpVersion} ${tmpDate}" | jq -aRs .`
JSSTAT=`echo ${JSSTAT} | jq ".sysBios=${sysBios}"`
StatFileUpdate sysBios stats_sys_bios

sysRamSizeMB=`sudo dmidecode -t 17 2> /dev/null | awk '( /Size/ && $2 ~ /^[0-9]+$/ ) { x+=$2 } END { print x }'`
sysRamSizeGB=`echo -n "${sysRamSizeMB}" | awk '{ printf "%.0f", $1/128 }' | awk '{ printf "%.1f\n", $1/8 }' | sed 's/\.0$//'`
# if problem with DMI reading, than second method
if [[ -z ${sysRamSizeGB} ]]; then
  sysRamSizeMB=`grep MemTotal /proc/meminfo | awk '{ printf "%.0f\n", $2/1024 }'`
  sysRamSizeGB=`echo -n "${sysRamSizeMB}" | awk '{ printf "%.0f", $1/128 }' | awk '{ printf "%.1f\n", $1/8 }' | sed 's/\.0$//'`
  # if still problem with reading
  [[ -z ${sysRamSizeGB} ]] && sysRamSizeGB=0
fi
sysRamSizeGBJq=`echo -n ${sysRamSizeGB} | jq -aRs .`
JSSTAT=`echo ${JSSTAT} | jq ".sysRamSize=${sysRamSizeGB}"`
StatFileUpdate sysRamSize stats_sys_sysRamSize

tmp=`sudo lshw -class disk 2> /dev/null`
tmpProduct=`echo "${tmp}" | grep "product: " | awk '{ $1=""; print $0 }' | head -n 1`
tmpVendor=`echo "${tmp}"  | grep "vendor: "  | awk '{ $1=""; print $0 }' | head -n 1`
tmpSize=`echo "${tmp}"    | grep "size: "    | awk '{ print $3 }'        | head -n 1 | tr -d '()'`
sysHddJq=`echo -n "${tmpProduct} ${tmpVendor} ${tmpSize}" | jq -aRs .` 
JSSTAT=`echo ${JSSTAT} | jq ".sysHdd=${sysHddJq}"`
StatFileUpdate sysHdd stats_sys_hdd

isWifiEnabled=0
isWifiEnabledTmp=`cat /mnt/user/config.txt | (grep "^WIFI_ENABLE=" || echo "WIFI_ENABLE=0") | head -n 1 | sed 's/^WIFI_ENABLE=//' | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'`
[[ ${isWifiEnabledTmp} == 1 ]] && isWifiEnabled=1
JSSTAT=`echo ${JSSTAT} | jq ".isWifiEnabled=${isWifiEnabled}"`
StatFileUpdate isWifiEnabled stats_is_wifi_enabled

wifiRssiPercentage=0
if [[ ${isWifiEnabled} == 1 ]]; then
  wifiRssiDbm=`cat /proc/net/wireless 2> /dev/null | awk 'FNR==3 { print $4 }' | awk -F. '{ print $1 }'`
  [[ ! ${wifiRssiDbm} =~ ^-?[0-9]+$ ]] && wifiRssiDbm=-100
  wifiRssiPercentage=$((2*(wifiRssiDbm+100)))
  [[ ${wifiRssiPercentage} -lt   0 ]] && wifiRssiPercentage=0
  [[ ${wifiRssiPercentage} -gt 100 ]] && wifiRssiPercentage=100
fi
JSSTAT=`echo ${JSSTAT} | jq ".wifiRssiPercentage=${wifiRssiPercentage}"`
StatFileUpdate wifiRssiPercentage stats_wifi_rssi_percentage


#### system variables end

# do not do GPU stats if rclocal not finished
# for safety use time limit max 3 minutes
# (this could cause empty all rig data in dashboard for new rig...but this should not be longer than 1minute)
[[ ! -f /var/tmp/rigStarted.run && ${uptimeSec} -lt 180 ]] && exit



gpuCount=0 # number of all GPUs
sysPwr=40 # start from Motherboard wattage (plus minus)

if [[ ${osSeries} == "RX" ]]; then
  # the most important - number of GPUs - do it fast before next slow operations
  gpuCount=`ls -1 /sys/class/drm/card*/device/pp_table 2> /dev/null | wc -l`
  echo ${gpuCount} > /var/tmp/stats_gpu_count

  [[ ${doFixed} == 1 ]] && amdmeminfoData=`sudo /root/utils/amdmeminfo -q -s -n --use-stderr`
  #GPU3:04.00.0:Radeon RX 570:113-2E366AU-X5T:Micron MT51J256M32:GDDR5:Polaris10
  #GPU2:06.00.0:Radeon RX 570:xxx-xxx-xxx:Elpida EDW4032BABG:GDDR5:Polaris10

  gpuIdxRaw=0 # /sys/class/ numeration. May be 0,2,3,...
  gpuIdx=0 # our numeration. Must be continuous 0,1,2,3...
  while [[ true ]]; do
    [[ ! -e /sys/class/drm/card${gpuIdxRaw} ]] && break # no more cards
    if [[ -e /sys/class/drm/card${gpuIdxRaw}/device/power_dpm_force_performance_level ]]; then # if AMD mining card
      gpuIdxJq=`echo -n ${gpuIdx} | jq -aRs .`

      # link to /sys/devices/pci0000:00/0000:00:1c.2/0000:02:00.0
      linkdst=`readlink -f /sys/class/drm/card${gpuIdxRaw}/device 2> /dev/null`
      # parse for PCI BUS
      pciBus=`echo ${linkdst}]} | sed -n 's/.*\([0-9a-f]\{2\}:[0-9a-f]\{2\}[\.:][0-9a-f]\).*/\1/pi'`
      # get previous readings if parser failed (GPU crash?)
      [[ -z ${pciBus} ]] && pciBus=`(cat /var/tmp/stats_gpu_pcibus_jq 2> /dev/null || echo "null") | jq -r ".[${gpuIdxJq}] // \"n/a\""`
      pciBusJq=`echo -n ${pciBus} | jq -aRs .`

      # pci id
      pciId=`lspci -n -s "${pciBus}" 2> /dev/null | sed -n 's/.*\([0-9a-f]\{4\}\):\([0-9a-f]\{4\}\).*(rev \([0-9a-f]\{2\}\)).*/\1:\2:\3/pi'`
      [[ -z ${pciId} ]] && pciId=`lspci -n -s "${pciBus}" 2> /dev/null | sed -n 's/.*\([0-9a-f]\{4\}\):\([0-9a-f]\{4\}\).*/\1:\2:00/pi'`
      pciIdJq=`echo -n ${pciId} | jq -aRs .`

      # some Vega/navi checks
      isVega10=`lspci -n -s "${pciBus}" 2> /dev/null | egrep -i "${pciids_vega10}" | head -n 1 | wc -l`
      isVega20=`lspci -n -s "${pciBus}" 2> /dev/null | egrep -i "${pciids_vega20}" | head -n 1 | wc -l`
      isNavi10=`lspci -n -s "${pciBus}" 2> /dev/null | egrep -i "${pciids_navi10}" | head -n 1 | wc -l`
      isNavi12=`lspci -n -s "${pciBus}" 2> /dev/null | egrep -i "${pciids_navi12}" | head -n 1 | wc -l`
      isNavi21=`lspci -n -s "${pciBus}" 2> /dev/null | egrep -i "${pciids_navi21}" | head -n 1 | wc -l`
      isNavi22=`lspci -n -s "${pciBus}" 2> /dev/null | egrep -i "${pciids_navi22}" | head -n 1 | wc -l`
      isNavi23=`lspci -n -s "${pciBus}" 2> /dev/null | egrep -i "${pciids_navi23}" | head -n 1 | wc -l`
      isNavi24=`lspci -n -s "${pciBus}" 2> /dev/null | egrep -i "${pciids_navi24}" | head -n 1 | wc -l`

      # get VRAM size always, but not always put in JSON and output files
      # VRAM size in GB
      gpuVramSize=`sudo stat -c %s -- /sys/kernel/debug/dri/${gpuIdxRaw}/amdgpu_vram`
      gpuVramSizeMB=$((gpuVramSize / 1024 / 1024))
      gpuVramSizeGB=`echo ${gpuVramSizeMB} | awk '{ printf "%.0f", $1/512 }' | awk '{ printf "%.1f\n", $1/2 }' | sed 's/\.0$//'`

      if [[ ${doFixed} == 1 ]]; then
        pciBusAmdmeminfo=`echo ${pciBus} | sed -e 's/:/\./'` # changed ":" with ".", because ":" is delimeter char

        JSSTAT=`echo ${JSSTAT} | jq ".gpuPciBus[${gpuIdxJq}]=${pciBusJq}"`

        JSSTAT=`echo ${JSSTAT} | jq ".gpuPciId[${gpuIdxJq}]=${pciIdJq}"`

        gpuModel=`echo "${amdmeminfoData}" | grep ":${pciBusAmdmeminfo}:" | awk -F":" '{ print $3 }' | sed 's/Radeon //g' | sed 's/ Anniversary//g'`
        gpuModelJq=`echo -n ${gpuModel} | jq -aRs .`
        JSSTAT=`echo ${JSSTAT} | jq ".gpuModel[${gpuIdxJq}]=${gpuModelJq}"`

        gpuManufacturer=`lspci -n -k -s "${pciBus}" 2>/dev/null | grep -i Subsystem | awk -F: '{ print $2 }' | tr -d ' ' | head -n 1`
        gpuManufacturerStr=$(getGpuManufacturerStr ${gpuManufacturer})
        gpuManufacturerStrJq=`echo -n ${gpuManufacturerStr} | jq -aRs .`
        JSSTAT=`echo ${JSSTAT} | jq ".gpuManufacturer[${gpuIdxJq}]=${gpuManufacturerStrJq}"`

        gpuVramSizeBGJq=`echo -n ${gpuVramSizeGB} | jq -aRs .`
        JSSTAT=`echo ${JSSTAT} | jq ".gpuVramSize[${gpuIdxJq}]=${gpuVramSizeBGJq}"`

        gpuVramType=`echo "${amdmeminfoData}" | grep ":${pciBusAmdmeminfo}:" | awk -F":" '{ print $6 }'`
        gpuVramTypeJq=`echo -n ${gpuVramType} | jq -aRs .`
        JSSTAT=`echo ${JSSTAT} | jq ".gpuVramType[${gpuIdxJq}]=${gpuVramTypeJq}"`

        gpuVramChip=`(cat /sys/class/drm/card${gpuIdxRaw}/device/mem_info_vram_vendor 2> /dev/null || echo "unknown") | sed 's/./\u&/'`
        [[ ${gpuVramChip} == "Unknown" ]] && gpuVramChip=`echo "${amdmeminfoData}" | grep ":${pciBusAmdmeminfo}:" | awk -F: '{ print $5 }'`
        gpuVramChipJq=`echo -n ${gpuVramChip} | jq -aRs .`
        JSSTAT=`echo ${JSSTAT} | jq ".gpuVramChip[${gpuIdxJq}]=${gpuVramChipJq}"`

        gpuBiosVer=`echo "${amdmeminfoData}" | grep ":${pciBusAmdmeminfo}:" | awk -F":" '{ print $4 }'`
        gpuBiosVerJq=`echo -n ${gpuBiosVer} | jq -aRs .`
        JSSTAT=`echo ${JSSTAT} | jq ".gpuBiosVer[${gpuIdxJq}]=${gpuBiosVerJq}"`

        JSSTAT=`echo ${JSSTAT} | jq ".gpuPwrMin[${gpuIdxJq}]=\"\""`
        JSSTAT=`echo ${JSSTAT} | jq ".gpuPwrMax[${gpuIdxJq}]=\"\""`
      fi # fixed data

      if [[ ${doDynamic} == 1 ]]; then
        if [[ ${isNavi10} == 1 || ${isNavi12} == 1 ]]; then
          # get last (of always(?) two) state
          gpuCoreClk=`(cat /sys/class/drm/card${gpuIdxRaw}/device/pp_od_clk_voltage 2> /dev/null || echo 0) | sed -ne '/OD_SCLK:/,/.*:$/p' | grep -av ":$" | tail -n 1 | awk '{ print $2 }' | tr '[:upper:]' '[:lower:]' | tr -d 'mhz'`
        else
          gpuCoreClk=`(cat /sys/class/drm/card${gpuIdxRaw}/device/pp_dpm_sclk 2> /dev/null || echo 0) | grep "*" | awk '{ print $2 }' | tr '[:upper:]' '[:lower:]' | tr -d 'mhz'`
        fi
        gpuCoreClkJq=`echo -n ${gpuCoreClk} | jq -aRs .`
        JSSTAT=`echo ${JSSTAT} | jq ".gpuCoreClk[${gpuIdxJq}]=${gpuCoreClkJq}"`

        if [[ ${isNavi10} == 1 || ${isNavi12} == 1 ]]; then
          # get last (of always(?) one) state
          gpuMemClk=`(cat /sys/class/drm/card${gpuIdxRaw}/device/pp_od_clk_voltage 2> /dev/null || echo 0) | sed -ne '/OD_MCLK:/,/.*:$/p' | grep -av ":$" | tail -n 1 | awk '{ print $2 }' | tr '[:upper:]' '[:lower:]' | tr -d 'mhz'`
        else
          gpuMemClk=`(cat /sys/class/drm/card${gpuIdxRaw}/device/pp_dpm_mclk 2> /dev/null || echo 0) | grep "*" | awk '{ print $2 }' | tr '[:upper:]' '[:lower:]' | tr -d 'mhz'`
        fi
        gpuMemClkJq=`echo -n ${gpuMemClk} | jq -aRs .`
        JSSTAT=`echo ${JSSTAT} | jq ".gpuMemClk[${gpuIdxJq}]=${gpuMemClkJq}"`

        JSSTAT=`echo ${JSSTAT} | jq ".gpuPwrLimit[${gpuIdxJq}]=\"\""`

        gpuPwrCur=` (cat /sys/class/drm/card${gpuIdxRaw}/device/hwmon/hwmon*/power1_average 2> /dev/null || echo 0) | awk '{ printf "%.0f", $1/1000000 }'`
        gpuPwrCurJq=`echo -n ${gpuPwrCur} | jq -aRs .`
        JSSTAT=`echo ${JSSTAT} | jq ".gpuPwrCur[${gpuIdxJq}]=${gpuPwrCurJq}"`
        if [[ ${isVega10} == 1 ]]; then
          gpuMemPwr=40 # Vega
        elif [[ ${isVega20} == 1 ]]; then
          gpuMemPwr=55 # R VII
        elif [[ ${isNavi10} == 1 ]]; then
          gpuMemPwr=20 # RX 5500/5600/5700
        elif [[ ${isNavi21} == 1 || ${isNavi22} == 1 || ${isNavi23} == 1 || ${isNavi24} == 1 ]]; then
          gpuMemPwr=10 # RX 6800/6900 / 6700 / 6600 / 6500/6400
        else
          # Polaris
          gpuMemPwr=40 # 4GB - use as default
          [[ ${gpuVramSizeGB} == 8 ]] && gpuMemPwr=44 # 8GB
        fi
        sysPwr=$((sysPwr+gpuPwrCur+gpuMemPwr))

        gpuTemp=`(cat /sys/class/drm/card${gpuIdxRaw}/device/hwmon/hwmon*/temp1_input 2> /dev/null || echo 0) | awk '{ printf "%.0f", $1/1000 }'`
        gpuTempJq=`echo -n ${gpuTemp} | jq -aRs .`
        JSSTAT=`echo ${JSSTAT} | jq ".gpuTemp[${gpuIdxJq}]=${gpuTempJq}"`

        gpuAsicTemp=`(cat /sys/class/drm/card${gpuIdxRaw}/device/hwmon/hwmon*/temp2_input 2> /dev/null || echo 0) | awk '{ printf "%.0f", $1/1000 }' | sed -e 's/^0$//g'`
        gpuAsicTempJq=`echo -n ${gpuAsicTemp} | jq -aRs .`
        JSSTAT=`echo ${JSSTAT} | jq ".gpuAsicTemp[${gpuIdxJq}]=${gpuAsicTempJq}"`

        gpuMemTemp=`(cat /sys/class/drm/card${gpuIdxRaw}/device/hwmon/hwmon*/temp3_input 2> /dev/null || echo 0) | awk '{ printf "%.0f", $1/1000 }' | sed -e 's/^0$//g'`
        gpuMemTempJq=`echo -n ${gpuMemTemp} | jq -aRs .`
        JSSTAT=`echo ${JSSTAT} | jq ".gpuMemTemp[${gpuIdxJq}]=${gpuMemTempJq}"`

        gpuFan=`(cat /sys/class/drm/card${gpuIdxRaw}/device/hwmon/hwmon*/pwm1 2> /dev/null || echo 0) | awk '{ printf "%.0f", $1/255*100 }'`
        [[ ${gpuFan} -gt 100 ]] && gpuFan=100
        gpuFanJq=`echo -n ${gpuFan} | jq -aRs .`
        JSSTAT=`echo ${JSSTAT} | jq ".gpuFan[${gpuIdxJq}]=${gpuFanJq}"`

        gpuVddgfx=`(cat /sys/class/drm/card${gpuIdxRaw}/device/hwmon/hwmon*/in0_input 2> /dev/null || echo 0)` #VDDGFX
        gpuVddgfxJq=`echo -n ${gpuVddgfx} | jq -aRs .`
        JSSTAT=`echo ${JSSTAT} | jq ".gpuVddGfx[${gpuIdxJq}]=${gpuVddgfxJq}"`

        gpuMvdd=
        [[ ${isNavi10} == 1 || ${isNavi12} == 1 || ${isNavi21} == 1 || ${isNavi22} == 1 || ${isNavi23} == 1 || ${isNavi24} == 1 ]] && gpuMvdd=`timeout 5 sudo /root/utils/navitool -i ${gpuIdxRaw} --show-mvdd 2> /dev/null | grep "Memory voltage" | awk '{ print $NF }'`
        gpuMvddJq=`echo -n ${gpuMvdd} | jq -aRs .`
        JSSTAT=`echo ${JSSTAT} | jq ".gpuMvdd[${gpuIdxJq}]=${gpuMvddJq}"`

        gpuMvddci=
        [[ ${isNavi10} == 1 || ${isNavi12} == 1 || ${isNavi21} == 1 || ${isNavi22} == 1 || ${isNavi23} == 1 || ${isNavi24} == 1 ]] && gpuMvddci=`timeout 5 sudo /root/utils/navitool -i ${gpuIdxRaw} --show-mvddci 2> /dev/null | grep "Memory controller voltage" | awk '{ print $NF }'`
        gpuMvddciJq=`echo -n ${gpuMvddci} | jq -aRs .`
        JSSTAT=`echo ${JSSTAT} | jq ".gpuMvddci[${gpuIdxJq}]=${gpuMvddciJq}"`
      fi # cur
      gpuIdx=$((gpuIdx+1))
    fi
    gpuIdxRaw=$((gpuIdxRaw+1))
  done
fi

if [[ $osSeries == "NV" ]]; then
  # speedy gpu count because of slow nvidia-smi (only if zero or null file because search by word may be not accurate for all NV cards)
  gpuCountPrev=`cat /var/tmp/stats_gpu_count 2> /dev/null || echo 0`
  gpuCount=${gpuCountPrev}
  [[ ${gpuCountPrev} == 0 ]] && gpuCount=`lspci | grep -i "VGA\|3D Con" | grep -i "NVIDIA" | wc -l` && echo ${gpuCount} > /var/tmp/stats_gpu_count

  # get fan/gpu ratio
  ifGetFansPerGpu=0
  # if there is no file with fan/gpu ratio
  [[ ! -f /var/tmp/stats_gpu_fans_per_gpu ]] && ifGetFansPerGpu=1
  # if file is old
  [[ -f /var/tmp/stats_gpu_fans_per_gpu && `stat --format=%Y /var/tmp/stats_gpu_fans_per_gpu` -lt $((`date +%s` - 3600)) ]] && ifGetFansPerGpu=1
  if [[ ${ifGetFansPerGpu} == 1 ]]; then
    # get fan/gpu ratio
    fanCount=`DISPLAY=:0 sudo nvidia-settings -q fans 2> /dev/null | grep "\[fan" | wc -l`
    fansPerGpu=`echo | awk "{ printf \"%.2f\", ${fanCount}/${gpuCount} }"`
    [[ ${fansPerGpu} != "0.00" ]] && echo ${fansPerGpu} > /var/tmp/stats_gpu_fans_per_gpu
  fi

  # get some data from nvsmi
  nvsmiData=`DISPLAY=:0 nvidia-smi --format=csv,noheader --query-gpu=index,count,name,pci.bus_id,vbios_version,memory.total,power.min_limit,power.max_limit,power.limit,power.draw,clocks.sm,clocks.mem,temperature.gpu,fan.speed --format=csv,noheader`
  #12, 13, P104-100, 00000000:0F:00.0, 86.04.7A.00.20, 4042 MiB, 90.00 W, 217.00 W, 128.36 W, 130.00 W, 180.00 W
  nvsmiCount=`echo "${nvsmiData}" | awk -F',' '{ print $2 }' | sed 's/[^0-9]*//g'  | head -n 1 | sed 's/^$/0/g' || echo 0`
  # if [not supported] or other error (not value), than make "n/a" string
  nvsmiGpuPcibus=(`echo   "${nvsmiData}" | awk -F',' '{ print $4  }' | sed 's/^[[:space:]]*//g' | sed 's/[[:space:]]*$//g' | sed -e 's/\./:/g' | mawk -F : '{ printf("%s:%s.%s\n", $2, $3, $4) }' | sed 's/^$/n\/a/g'`)
  nvsmiGpuModel=(`echo    "${nvsmiData}" | awk -F',' '{ print $3  }' | sed 's/^[[:space:]]*//g' | sed 's/[[:space:]]*$//g' | sed 's/GeForce //g' | sed 's/^$/n\/a/g'`)
  nvsmiGpuVramSize=(`echo "${nvsmiData}" | awk -F',' '{ print $6  }' | sed 's/^[[:space:]]*//g' | sed 's/[[:space:]]*$//g' | tr -d -c '\n[:digit:]\.' | sed 's/^$/n\/a/g'`)
  nvsmiGpuBiosVer=(`echo  "${nvsmiData}" | awk -F',' '{ print $5  }' | sed 's/^[[:space:]]*//g' | sed 's/[[:space:]]*$//g' | sed 's/^$/n\/a/g'`)
  nvsmiGpuPwrMin=(`echo   "${nvsmiData}" | awk -F',' '{ print $7  }' | sed 's/^[[:space:]]*//g' | sed 's/[[:space:]]*$//g' | tr -d -c '\n[:digit:]\.'| awk -F"." '{ print $1 }' | sed 's/^$/n\/a/g'`)
  nvsmiGpuPwrMax=(`echo   "${nvsmiData}" | awk -F',' '{ print $8  }' | sed 's/^[[:space:]]*//g' | sed 's/[[:space:]]*$//g' | tr -d -c '\n[:digit:]\.'| awk -F"." '{ print $1 }' | sed 's/^$/n\/a/g'`)
  nvsmiGpuPwrLimit=(`echo "${nvsmiData}" | awk -F',' '{ print $9  }' | sed 's/^[[:space:]]*//g' | sed 's/[[:space:]]*$//g' | tr -d -c '\n[:digit:]\.'| awk -F"." '{ print $1 }' | sed 's/^$/n\/a/g'`)
  nvsmiGpuPwrCur=(`echo   "${nvsmiData}" | awk -F',' '{ print $10 }' | sed 's/^[[:space:]]*//g' | sed 's/[[:space:]]*$//g' | tr -d -c '\n[:digit:]\.'| awk -F"." '{ print $1 }' | sed 's/^$/n\/a/g'`)
  nvsmiGpuCoreClk=(`echo  "${nvsmiData}" | awk -F',' '{ print $11 }' | sed 's/^[[:space:]]*//g' | sed 's/[[:space:]]*$//g' | tr -d -c '\n[:digit:]\.' | sed 's/^$/n\/a/g'`)
  nvsmiGpuMemClk=(`echo   "${nvsmiData}" | awk -F',' '{ print $12 }' | sed 's/^[[:space:]]*//g' | sed 's/[[:space:]]*$//g' | tr -d -c '\n[:digit:]\.' | sed 's/^$/n\/a/g'`)
  nvsmiGpuTemp=(`echo     "${nvsmiData}" | awk -F',' '{ print $13 }' | sed 's/^[[:space:]]*//g' | sed 's/[[:space:]]*$//g' | tr -d -c '\n[:digit:]\.' | sed 's/^$/n\/a/g'`)
  nvsmiGpuFan=(`echo      "${nvsmiData}" | awk -F',' '{ print $14 }' | sed 's/^[[:space:]]*//g' | sed 's/[[:space:]]*$//g' | tr -d -c '\n[:digit:]\.' | sed 's/^$/n\/a/g'`)

  [[ ${nvsmiCount} -gt 0 ]] && echo ${nvsmiCount} > /var/tmp/stats_gpu_count

  gpuIdx=0
  for ((gpuIdx=0; gpuIdx<${nvsmiCount}; gpuIdx++)); do
    gpuIdxJq=`echo -n ${gpuIdx} | jq -aRs .`
    if [[ ${doFixed} == 1 ]]; then
      # get last reading if now error data
      [[ ${nvsmiGpuPcibus[${gpuIdx}]} == "n/a" ]] && nvsmiGpuPcibus[${gpuIdx}]=`(cat /var/tmp/stats_gpu_pcibus_jq 2> /dev/null || echo "null") | jq -r ".[${gpuIdxJq}] // \"n/a\""`
      # validate format XX:XX.X
      nvsmiGpuPcibus[${gpuIdx}]=`echo ${nvsmiGpuPcibus[${gpuIdx}]} | sed -n 's/.*\([0-9a-f]\{2\}:[0-9a-f]\{2\}[\.:][0-9a-f]\).*/\1/pi'`
      [[ -z ${nvsmiGpuPcibus[${gpuIdx}]} ]] && nvsmiGpuPcibus[${gpuIdx}]="n/a"
      pciBusJq=`echo -n ${nvsmiGpuPcibus[${gpuIdx}]} | jq -aRs .`
      JSSTAT=`echo ${JSSTAT} | jq ".gpuPciBus[${gpuIdxJq}]=${pciBusJq}"`

      # pci id
      pciId=`lspci -n -s "${nvsmiGpuPcibus[${gpuIdx}]}" 2> /dev/null | sed -n 's/.*\([0-9a-f]\{4\}\):\([0-9a-f]\{4\}\).*(rev \([0-9a-f]\{2\}\)).*/\1:\2:\3/pi'`
      [[ -z ${pciId} ]] && pciId=`lspci -n -s "${nvsmiGpuPcibus[${gpuIdx}]}" 2> /dev/null | sed -n 's/.*\([0-9a-f]\{4\}\):\([0-9a-f]\{4\}\).*/\1:\2:00/pi'`
      pciIdJq=`echo -n ${pciId} | jq -aRs .`
      JSSTAT=`echo ${JSSTAT} | jq ".gpuPciId[${gpuIdxJq}]=${pciIdJq}"`

      [[ ${nvsmiGpuModel[${gpuIdx}]} == "n/a" ]] && nvsmiGpuModel[${gpuIdx}]=`(cat /var/tmp/stats_gpu_model_jq 2> /dev/null || echo "null") | jq -r ".[${gpuIdxJq}]" // \"n/a\"`
      # some GPUs has VRAM size in ModelName :) ...clean up this
      gpuModel=`echo ${nvsmiGpuModel[${gpuIdx}]} | sed 's/ [[:digit:]]\{1,\}GB$//'`
      gpuModelJq=`echo -n ${gpuModel} | jq -aRs .`
      JSSTAT=`echo ${JSSTAT} | jq ".gpuModel[${gpuIdxJq}]=${gpuModelJq}"`

      # GPU manufacturer
      gpuManufacturer=`lspci -n -k -s "${nvsmiGpuPcibus[${gpuIdx}]}" 2> /dev/null | grep -i Subsystem | awk -F: '{ print $2 }' | tr -d ' ' | head -n 1`
      gpuManufacturerStr=$(getGpuManufacturerStr ${gpuManufacturer})
      gpuManufacturerStrJq=`echo -n ${gpuManufacturerStr} | jq -aRs .`
      JSSTAT=`echo ${JSSTAT} | jq ".gpuManufacturer[${gpuIdxJq}]=${gpuManufacturerStrJq}"`

      [[ ${nvsmiGpuVramSize[${gpuIdx}]} == "n/a" ]] && nvsmiGpuVramSize[${gpuIdx}]=`(cat /var/tmp/stats_gpu_vram_size_jq 2> /dev/null || echo "null") | jq -r ".[${gpuIdxJq}] // \"n/a\""`
      gpuVramSizeGB=${nvsmiGpuVramSize[${gpuIdx}]}
      [[ ${gpuVramSizeGB} != "n/a" ]] && gpuVramSizeGB=`echo ${nvsmiGpuVramSize[${gpuIdx}]} | awk '{ printf "%.0f", $1/512 }' | awk '{ printf "%.1f\n", $1/2 }' | sed 's/\.0$//'`
      gpuVramSizeGBJq=`echo -n ${gpuVramSizeGB} | jq -aRs .`
      JSSTAT=`echo ${JSSTAT} | jq ".gpuVramSize[${gpuIdxJq}]=${gpuVramSizeGBJq}"`

      gpuVramType=`DISPLAY=:0 sudo /root/utils/nvtool -i ${gpuIdx} --get-metrics2 2> /dev/null | awk '{ print $2 }'`
      gpuVramTypeJq=`echo -n ${gpuVramType} | jq -aRs .`
      JSSTAT=`echo ${JSSTAT} | jq ".gpuVramType[${gpuIdxJq}]=${gpuVramTypeJq}"`

      gpuVramChip=`DISPLAY=:0 sudo /root/utils/nvtool -i ${gpuIdx} --get-metrics2 2> /dev/null | awk '{ print $1 }'`
      gpuVramChipJq=`echo -n ${gpuVramChip} | jq -aRs .`
      JSSTAT=`echo ${JSSTAT} | jq ".gpuVramChip[${gpuIdxJq}]=${gpuVramChipJq}"`

      [[ ${nvsmiGpuBiosVer[${gpuIdx}]} == "n/a" ]] && nvsmiGpuBiosVer[${gpuIdx}]=`(cat /var/tmp/stats_gpu_bios_ver_jq 2> /dev/null || echo "null") | jq -r ".[${gpuIdxJq}] // \"n/a\""`
      invsmiGpuBiosVerJq=`echo -n ${nvsmiGpuBiosVer[${gpuIdx}]} | jq -aRs .`

      JSSTAT=`echo ${JSSTAT} | jq ".gpuBiosVer[${gpuIdxJq}]=${invsmiGpuBiosVerJq}"`
      [[ ${nvsmiGpuPwrMin[${gpuIdx}]} == "n/a" ]] && nvsmiGpuPwrMin[${gpuIdx}]=`(cat /var/tmp/stats_gpu_pwr_min_jq 2> /dev/null || echo "null") | jq -r ".[${gpuIdxJq}] // \"n/a\""`
      invsmiGpuPwrMinJq=`echo -n ${nvsmiGpuPwrMin[${gpuIdx}]} | jq -aRs .`
      JSSTAT=`echo ${JSSTAT} | jq ".gpuPwrMin[${gpuIdxJq}]=${invsmiGpuPwrMinJq}"`

      [[ ${nvsmiGpuPwrMax[${gpuIdx}]} == "n/a" ]] && nvsmiGpuPwrMax[${gpuIdx}]=`(cat /var/tmp/stats_gpu_pwr_max_jq 2> /dev/null || echo "null") | jq -r ".[${gpuIdxJq}] // \"n/a\""`
      invsmiGpuPwrMaxJq=`echo -n ${nvsmiGpuPwrMax[${gpuIdx}]} | jq -aRs .`
      JSSTAT=`echo ${JSSTAT} | jq ".gpuPwrMax[${gpuIdxJq}]=${invsmiGpuPwrMaxJq}"`
    fi
    if [[ ${doDynamic} == 1 ]]; then
      [[ ${nvsmiGpuCoreClk[${gpuIdx}]} == "n/a" ]] && nvsmiGpuCoreClk[${gpuIdx}]=`(cat /var/tmp/stats_gpu_core_clk_jq 2> /dev/null || echo "null") | jq -r ".[${gpuIdxJq}] // \"n/a\""`
      gpuVramSizeGBJq=`echo -n ${nvsmiGpuCoreClk[${gpuIdx}]} | jq -aRs .`
      JSSTAT=`echo ${JSSTAT} | jq ".gpuCoreClk[${gpuIdxJq}]=${gpuVramSizeGBJq}"`

      [[ ${nvsmiGpuMemClk[${gpuIdx}]} == "n/a" ]] && nvsmiGpuMemClk[${gpuIdx}]=`(cat /var/tmp/stats_gpu_mem_clk_jq 2> /dev/null || echo "null") | jq -r ".[${gpuIdxJq}] // \"n/a\""`
      invsmiGpuMemClkJq=`echo -n ${nvsmiGpuMemClk[${gpuIdx}]} | jq -aRs .`
      JSSTAT=`echo ${JSSTAT} | jq ".gpuMemClk[${gpuIdxJq}]=${invsmiGpuMemClkJq}"`

      [[ ${nvsmiGpuPwrLimit[${gpuIdx}]} == "n/a" ]] && nvsmiGpuPwrLimit[${gpuIdx}]=`(cat /var/tmp/stats_gpu_pwr_limit_jq 2> /dev/null || echo "null") | jq -r ".[${gpuIdxJq}] // \"n/a\""`
      invsmiGpuPwrLimitJq=`echo -n ${nvsmiGpuPwrLimit[${gpuIdx}]} | jq -aRs .`
      JSSTAT=`echo ${JSSTAT} | jq ".gpuPwrLimit[${gpuIdxJq}]=${invsmiGpuPwrLimitJq}"`

      [[ ${nvsmiGpuPwrCur[${gpuIdx}]} == "n/a" ]] && nvsmiGpuPwrCur[${gpuIdx}]=`(cat /var/tmp/stats_gpu_pwr_cur_jq 2> /dev/null || echo "null") | jq -r ".[${gpuIdxJq}] // \"0\""`
      invsmiGpuPwrCurJq=`echo -n ${nvsmiGpuPwrCur[${gpuIdx}]} | jq -aRs .`
      JSSTAT=`echo ${JSSTAT} | jq ".gpuPwrCur[${gpuIdxJq}]=${invsmiGpuPwrCurJq}"`
      gpuPwrCur=`echo "${nvsmiGpuPwrCur[${gpuIdx}]}" | tr -d -c '\n[:digit:]' | sed 's/^$/0/'` #get only values and if empty then zero
      sysPwr=$((sysPwr+gpuPwrCur))

      [[ ${nvsmiGpuTemp[${gpuIdx}]} == "n/a" ]] && nvsmiGpuTemp[${gpuIdx}]=`(cat /var/tmp/stats_gpu_temp_jq 2> /dev/null || echo "null") | jq -r ".[${gpuIdxJq}] // \"n/a\""`
      JSSTAT=`echo ${JSSTAT} | jq ".gpuTemp[${gpuIdxJq}]=\"${nvsmiGpuTemp[${gpuIdx}]}\""`

      JSSTAT=`echo ${JSSTAT} | jq ".gpuAsicTemp[${gpuIdxJq}]=\"\""`

      gpuMemTemp=`DISPLAY=:0 sudo /root/utils/nvtool -i ${gpuIdx} --get-metrics 2> /dev/null`
      gpuMemTempJq=`echo -n ${gpuMemTemp} | jq -aRs .`
      JSSTAT=`echo ${JSSTAT} | jq ".gpuMemTemp[${gpuIdxJq}]=${gpuMemTempJq}"`

      [[ ${nvsmiGpuFan[${gpuIdx}]} == "n/a" ]] && nvsmiGpuFan[${gpuIdx}]=`(cat /var/tmp/stats_gpu_fan_jq 2> /dev/null || echo "null") | jq -r ".[${gpuIdxJq}] // \"n/a\""`
      [[ ${nvsmiGpuFan[${gpuIdx}]} -gt 100 ]] && nvsmiGpuFan[${gpuIdx}]=100
      JSSTAT=`echo ${JSSTAT} | jq ".gpuFan[${gpuIdxJq}]=\"${nvsmiGpuFan[${gpuIdx}]}\""`
#      New pending method (more accurate)
#      gpuFan=`DISPLAY=:0 sudo /root/utils/nvtool -i ${gpuIdx} --show-fan 2> /dev/null`
#      [[ ${nvsmiGpuFan[${gpuIdx}]} == "n/a" ]] && nvsmiGpuFan[${gpuIdx}]=`(cat /var/tmp/stats_gpu_fan_jq 2> /dev/null || echo "null") | jq -r ".[${gpuIdxJq}] // \"n/a\""`
#      [[ ${gpuFan} -gt 100 ]] && gpuFan=100
#      gpuFanJq=`echo -n ${gpuFan} | jq -aRs .`
#      JSSTAT=`echo ${JSSTAT} | jq ".gpuFan[${gpuIdxJq}]=\"${gpuFan}\""`

      JSSTAT=`echo ${JSSTAT} | jq ".gpuVddGfx[${gpuIdxJq}]=\"\""`

      JSSTAT=`echo ${JSSTAT} | jq ".gpuMvdd[${gpuIdxJq}]=\"\""`

      JSSTAT=`echo ${JSSTAT} | jq ".gpuMvddci[${gpuIdxJq}]=\"\""`
    fi
  done
fi
# end of NV

if [[ ${osSeries} == "R" ]]; then
  gpuCount=`DISPLAY=:0 aticonfig --list-adapters | grep -v Default | grep -v '^$' | wc -l`
  echo ${gpuCount} > /var/tmp/stats_gpu_count
  ATICONFIG_GPU_TEMP=(`DISPLAY=:0 aticonfig --adapter=all --od-gettemperature  | grep -o [0-9][0-9].[0-9][0-9] | sed 's/\..*$//'`)
  ATICONFIG_GPU_FAN=(`/root/utils/atitweak/atitweak -s | grep "fan speed" | awk -F  " " '{ print $3 }' | tr -d '%'`)
  ATICONFIG_GPU_CORE_CLK=(`DISPLAY=:0 aticonfig --od-getclocks --adapter=all | grep "Current Clocks" | awk -F  " " '{ print $4 }'`)
  ATICONFIG_GPU_MEM_CLK=(`DISPLAY=:0 aticonfig --od-getclocks --adapter=all | grep "Current Clocks" | awk -F  " " '{ print $5 }'`)
  ATICONFIG_GPU_PCIBUS=(`DISPLAY=:0 aticonfig --list-adapters | grep -v Default | grep -v '^$' | sed -e 's/*//' | awk '{ print $2 }'`)
  ATICONFIG_GPU_MODEL=(`DISPLAY=:0 aticonfig --list-adapters | grep -v Default | grep -v '^$' | sed -e 's/*//' | awk '{ $1=$2=""; print $0 }' | sed -e 's/^ \{1,\}//g' \
| sed 's/AMD Radeon (TM) //g' | sed 's/ Series//g'`)

  gpuIdx=0
  for ((gpuIdx=0; gpuIdx<${gpuCount}; gpuIdx++)); do
    if [[ ${doFixed} == 1 ]]; then
      JSSTAT=`echo ${JSSTAT} | jq ".gpuPciBus[${gpuIdxJq}]=\"${ATICONFIG_GPU_PCIBUS[${gpuIdx}]}\""`
      JSSTAT=`echo ${JSSTAT} | jq ".gpuPciId[${gpuIdxJq}]=\"\""`
      JSSTAT=`echo ${JSSTAT} | jq ".gpuModel[${gpuIdxJq}]=\"${ATICONFIG_GPU_MODEL[${gpuIdx}]}\""`

      # GPU manufacturer
      GPU_MANUFACTURER=`lspci -n -k -s "${ATICONFIG_GPU_PCIBUS[${gpuIdx}]}" 2> /dev/null | grep -i Subsystem | awk -F: '{ print $2 }' | tr -d ' ' | head -n 1`
      GPU_MANUFACTURER_STR=$(getGpuManufacturerStr ${GPU_MANUFACTURER})
      JSSTAT=`echo ${JSSTAT} | jq ".gpuManufacturer[${gpuIdxJq}]=\"${GPU_MANUFACTURER_STR}\""`
      JSSTAT=`echo ${JSSTAT} | jq ".gpuVramSize[${gpuIdxJq}]=\"\""`
      JSSTAT=`echo ${JSSTAT} | jq ".gpuVramType[${gpuIdxJq}]=\"\""`
      JSSTAT=`echo ${JSSTAT} | jq ".gpuVramChip[${gpuIdxJq}]=\"\""`
      JSSTAT=`echo ${JSSTAT} | jq ".gpuBiosVer[${gpuIdxJq}]=\"\""`
      JSSTAT=`echo ${JSSTAT} | jq ".gpuPwrMin[${gpuIdxJq}]=\"\""`
      JSSTAT=`echo ${JSSTAT} | jq ".gpuPwrMax[${gpuIdxJq}]=\"\""`
    fi
    if [[ ${doDynamic} == 1 ]]; then
      JSSTAT=`echo ${JSSTAT} | jq ".gpuCoreClk[${gpuIdxJq}]=\"${ATICONFIG_GPU_CORE_CLK[${gpuIdx}]}\""`
      JSSTAT=`echo ${JSSTAT} | jq ".gpuMemClk[${gpuIdxJq}]=\"${ATICONFIG_GPU_MEM_CLK[${gpuIdx}]}\""`
      JSSTAT=`echo ${JSSTAT} | jq ".gpuPwrLimit[${gpuIdxJq}]=\"\""`
      JSSTAT=`echo ${JSSTAT} | jq ".gpuPwrCur[${gpuIdxJq}]=\"\""`
      JSSTAT=`echo ${JSSTAT} | jq ".gpuTemp[${gpuIdxJq}]=\"${ATICONFIG_GPU_TEMP[${gpuIdx}]}\""`
      JSSTAT=`echo ${JSSTAT} | jq ".gpuAsicTemp[${gpuIdxJq}]=\"\""`
      JSSTAT=`echo ${JSSTAT} | jq ".gpuMemTemp[${gpuIdxJq}]=\"\""`
      JSSTAT=`echo ${JSSTAT} | jq ".gpuFan[${gpuIdxJq}]=\"${ATICONFIG_GPU_FAN[${gpuIdx}]}\""`
      JSSTAT=`echo ${JSSTAT} | jq ".gpuVddGfx[${gpuIdxJq}]=\"\""`
      JSSTAT=`echo ${JSSTAT} | jq ".gpuMvdd[${gpuIdxJq}]=\"\""`
      JSSTAT=`echo ${JSSTAT} | jq ".gpuMvddci[${gpuIdxJq}]=\"\""`
    fi
  done
fi
# end of NV

if [[ ${osSeries} == "none" ]]; then
  echo 0 > /var/tmp/stats_gpu_count
fi

sysPwrJq=`echo -n ${sysPwr} | jq -aRs .`
JSSTAT=`echo ${JSSTAT} | jq ".sysPwr=${sysPwrJq}"`
StatFileUpdate sysPwr stats_sys_pwr

# write all retrieved data to files
if [[ ${doFixed} == 1 ]]; then
  StatFileUpdate gpuPciBus stats_gpu_pcibus_jq
  StatFileUpdate gpuPciId stats_gpu_pciid_jq
  StatFileUpdate gpuModel stats_gpu_model_jq
  StatFileUpdate gpuManufacturer stats_gpu_manufacturer_jq
  StatFileUpdate gpuVramSize stats_gpu_vram_size_jq
  StatFileUpdate gpuVramType stats_gpu_vram_type_jq
  StatFileUpdate gpuVramChip stats_gpu_vram_chip_jq
  StatFileUpdate gpuBiosVer stats_gpu_bios_ver_jq
  StatFileUpdate gpuPwrMin stats_gpu_pwr_min_jq
  StatFileUpdate gpuPwrMax stats_gpu_pwr_max_jq
fi
if [[ ${doDynamic} == 1 ]]; then
  # StatFileUpdate gpuCoreClk stats_gpu_core_clk_jq
  # StatFileUpdate gpuMemClk stats_gpu_mem_clk_jq
  # StatFileUpdate gpuPwrLimit stats_gpu_pwr_limit_jq
  # StatFileUpdate gpuPwrCur stats_gpu_pwr_cur_jq
  # StatFileUpdate gpuFan stats_gpu_fan_jq
  # #StatFileUpdate gpuTemp stats_gpu_temp_jq
  # StatFileUpdate gpuAsicTemp stats_gpu_asic_temp_jq
  # StatFileUpdate gpuMemTemp stats_gpu_mem_temp_jq
  # StatFileUpdate gpuVddGfx stats_gpu_vdd_gfx_jq
  # StatFileUpdate gpuMvdd stats_gpu_mvdd_jq
  # StatFileUpdate gpuMvddci stats_gpu_mvddci_jq
fi
