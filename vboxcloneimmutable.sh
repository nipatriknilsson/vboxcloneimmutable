#!/bin/bash

set -x
set -e

storageport=0
storagedevice=0
storagename="SATA"

vboxbugdelay=20s

declare -a childvms
declare -a options

while [ "$1" != "" ] ; do
    if [ "${1::1}" == "-" ] ; then
        options+=( "${1:1}" )
        echo "option: ${1:1}"
    elif [ "$parentvm" == "" ] ; then
        parentvm="$1"
        echo "parent: $1"
    else
        childvms+=( "$1" )
        echo "child: $1"
    fi
    
    shift
done

if [ "${parentvm}" != "" ] ; then
    for childvm in "${childvms[@]}" ; do
        while true; do
            if ! vboxmanage list vms | grep -q -E "\"${childvm}\"" ; then
                break
            fi
            
            poweredoff=""
            
            if vboxmanage showvminfo "${childvm}" 2>/dev/null 1>&2 ; then
                poweredoff=$(vboxmanage showvminfo "${childvm}" | grep -E -c -i "State:[[:space:]]+powered off" || true)
                stateaborted=$(vboxmanage showvminfo "${parentvm}" | grep -E -c -i "State:[[:space:]]+aborted" || true)
            fi
            
            if [ "$poweredoff" == "1" ] || [ "$stateaborted" == "1" ] ; then
                running=
                running=$(ps -A -o command | grep -v grep | grep 'VirtualBoxVM' | grep -E -c "${childvm}" || true)
                
                if [ "$running" == "0" ] ; then
                    break
                fi
                
    #            break
            fi
            
            sleep ${vboxbugdelay}
        done
        
        ( # removal of /var/lock/vboxcloneimmutable unlocks lock
            while : ; do
                if flock -w 0 200 ; then 
                    vboxmanage list vms | grep -q -E "\"${childvm}\"" && vboxmanage unregistervm "${childvm}" --delete || true
                    sleep ${vboxbugdelay}
                    
                    flock -u 200
                    
                    break
                fi
                
                sleep ${vboxbugdelay}
            done
        ) 200>/var/lock/vboxcloneimmutable
    done
    
    stateaborted=$(vboxmanage showvminfo "${parentvm}" | grep -E -c -i "State:[[:space:]]+aborted" || true)
    
    if [ "$stateaborted" == "1" ]; then
        configfile="$(vboxmanage showvminfo "${parentvm}" | grep -o -P '^Config file:[[:space:]]+\K.*(\.vbox)')"
        sed '/<Machine/s/aborted="true"/aborted="false"/' "$configfile" > "${configfile}.newstate"
        mv -f "${configfile}.newstate" "${configfile}"
        
        break
    fi
    
    while true; do
        statepoweredoff=""
        stateaborted=""
        
        if vboxmanage showvminfo "${parentvm}" 2>/dev/null 1>&2 ; then
            statepoweredoff=$(vboxmanage showvminfo "${parentvm}" | grep -E -c -i "State:[[:space:]]+powered off" || true)
            stateaborted=$(vboxmanage showvminfo "${parentvm}" | grep -E -c -i "State:[[:space:]]+aborted" || true)
        fi
        
        if [ "$statepoweredoff" == "1" ]; then
            break
        fi
        
        if [ "$stateaborted" == "1" ]; then
            configfile="$(vboxmanage showvminfo "${parentvm}" | grep -o -P '^Config file:[[:space:]]+\K.*(\.vbox)')"
            sed '/<Machine/s/aborted="true"/aborted="false"/' "$configfile" > "${configfile}.newstate"
            mv -f "${configfile}.newstate" "${configfile}"
            break
        fi
        
        sleep ${vboxbugdelay}
    done
    
    while true ; do
        snapshotdelete=$(vboxmanage snapshot "${parentvm}" list --machinereadable | grep -o -P  '(?<=CurrentSnapshotUUID=")[0-9a-f\-]+' || echo "")
        if [ "$snapshotdelete" == "" ] ; then
            break
        fi
        
        vboxmanage snapshot "${parentvm}" delete "$snapshotdelete"
        sleep ${vboxbugdelay}
    done
    
    while IFS= read f ; do
        vartype="$(echo "$f" | grep -o -E "^(${storagename})")"
        echo $vartype
        varportdevice="$(echo "$f" | grep -o -i -E '\(.*\):' | tr -c '0123456789' ' ')"
        echo $varportdevice
        varport=$(echo "$varportdevice" | awk '{print $1}')
        echo $varport
        vardevice=$(echo "$varportdevice" | awk '{print $2}')
        echo $vardevice
        
        vboxmanage storageattach "${parentvm}" --storagectl "${vartype}" --port ${varport} --device ${vardevice} --type hdd --medium emptydrive
        sleep ${vboxbugdelay}
    done < <(vboxmanage showvminfo "${parentvm}" | grep -E "^(${storagename})" | grep -i '(UUID:')
    
    parentmedium="$(vboxmanage showvminfo "${parentvm}" | grep -o -P '^Config file:[[:space:]]+\K.*(\.vbox)' | sed 's/\.vbox$/\.vdi/')"
    
    if [ "$parentmedium" == "" ] ; then
        echo "Couldn't get parent medium"
        exit 255
    fi
    
    while true ; do
        childhduuid=$(vboxmanage showhdinfo "${parentmedium}" | grep -E '^Child UUIDs:' | grep -o -P '[0-9a-f\-]{36}' || echo "")
        
        if [ "$childhduuid" == "" ] ; then
            break
        fi
        
        vboxmanage closemedium disk "$childhduuid" --delete
        sleep ${vboxbugdelay}
    done
    
    ( # removal of /var/lock/vboxcloneimmutable unlocks lock
        while : ; do
            if flock -w 0 200 ; then 
                echo "${parentmedium}" | sed "s/\.vdi\$/\_$(date +%Y%m%d-%H%M%S)\.vdi\.bak\.tmp/" | xargs -I '{}' -- cp -a "${parentmedium}" '{}'
                
                flock -u 200
                
                break
            fi
            
            sleep ${vboxbugdelay}
        done
    ) 200>/var/lock/vboxcloneimmutable
    
    ( # removal of /var/lock/vboxcloneimmutable unlocks lock
        while : ; do
            if flock -w 0 200 ; then 
                vboxmanage modifymedium "${parentmedium}" --type normal
                sleep ${vboxbugdelay}
                
                flock -u 200
                
                break
            fi
            
            sleep ${vboxbugdelay}
        done
    ) 200>/var/lock/vboxcloneimmutable
    
    ( # removal of /var/lock/vboxcloneimmutable unlocks lock
        while : ; do
            if flock -w 0 200 ; then 
                vboxmanage storageattach "${parentvm}" --storagectl "${storagename}" --port ${storageport} --device ${storagedevice} --type hdd --medium "${parentmedium}"
                sleep ${vboxbugdelay}
                
                flock -u 200
                
                break
            fi
            
            sleep ${vboxbugdelay}
        done
    ) 200>/var/lock/vboxcloneimmutable
    
    ( # A Virtualbox VM does not allocate all memory immediately
        while : ; do
            if flock -w 0 200 ; then
                memoryguestmb=$(vboxmanage showvminfo "$parentvm" | grep -E "^Memory size(:)*[[:space:]]" | tr -d -c '[0-9]')
                
                if [ "$memoryguestmb" == "" ] ; then
                    memoryguestmb=$((1024*1024*1024))
                fi
                
                memoryguestmb=$(echo "(1024+$memoryguestmb*1.1)/1" | bc)
                
                memoryhostfree=$(free -m | grep -E '^Mem:' | awk '{print $7}')
                
                if [ "$memoryguestmb" -lt "$memoryhostfree" ] ; then
                    l=$(ps -A -o time,command | grep -i VirtualBoxVM | grep -- "--startvm" | awk '{print $1}' | awk -F: '{ print ($1 * 3600) + ($2 * 60) + $3 }' | sort -V | head -1)
                    
                    if [ "$l" == "" ] ; then
                        break
                    fi
                    
                    if [ "$l" -gt "120" ] ; then
                        break
                    fi
                fi
                
                flock -u 200
            fi
            
            sleep ${vboxbugdelay}
        done
        
        vboxmanage startvm "${parentvm}"
        sleep ${vboxbugdelay}
        
        flock -u 200
    ) 200>/var/lock/vboxcloneimmutable
    
    echo "Waiting for \"${parentvm}\" to power off..."
    
    while true ; do
        poweredoff=""
        
        if vboxmanage showvminfo "${parentvm}" 2>/dev/null 1>&2 ; then
            poweredoff=$(vboxmanage showvminfo "${parentvm}" | grep -E -c -i "State:[[:space:]]+powered off" || true)
        fi
        
        if [ "$poweredoff" == "1" ] ; then
            running=
            running=$(ps -A -o command | grep -v grep | grep 'VirtualBoxVM' | grep -E -c "${parentvm}" || true)
            
            if [ "$running" == "0" ] ; then
                break
            fi
            
#            break
        fi
        
        sleep ${vboxbugdelay}
    done
    
    ( # removal of /var/lock/vboxcloneimmutable unlocks lock
        while : ; do
            if flock -w 0 200 ; then 
                vboxmanage modifymedium "$parentmedium" --compact && touch -r "$parentmedium" "${parentmedium}.stamp"
                sleep ${vboxbugdelay}
                
                vboxmanage storageattach "${parentvm}" --storagectl "${storagename}" --port ${storageport} --device ${storagedevice} --type hdd --medium emptydrive
                sleep ${vboxbugdelay}
                
                vboxmanage modifymedium "${parentmedium}" --type immutable
                sleep ${vboxbugdelay}
                
                for childvm in "${childvms[@]}" ; do
                    vboxmanage clonevm "${parentvm}" --options=KeepAllMACs,KeepHwUUIDs --name "${childvm}" --register
                    sleep ${vboxbugdelay}
                    
                    vboxmanage storageattach "${childvm}" --storagectl "${storagename}" --port ${storageport} --device ${storagedevice} --type hdd --medium "${parentmedium}"
                    sleep ${vboxbugdelay}
                    
                    diskfile="$(vboxmanage showvminfo "${childvm}" --machinereadable | grep -E "\"${storagename}-${storageport}-${storagedevice}\"" | grep -o -P '(?<==")[^"]+')"
                    diskdir="$(dirname "$diskfile")"
                    rm -f "${diskdir}/"*".vdi.bak"
                    cp -a "${diskfile}" "${diskfile}.bak"
                    
                    for option in "${options[@]}" ; do
                        if echo "$option" | grep -q '{}' ; then
                            s="$(echo "$option" | sed "s/{}/${childvm}/")"
                            eval vboxmanage "$s"
                            sleep ${vboxbugdelay}
                        else
                            vboxmanage modifyvm "$childvm" $option
                            sleep ${vboxbugdelay}
                        fi
                    done
                done
                
                flock -u 200
                
                break
            fi
            
            sleep ${vboxbugdelay}
        done
    ) 200>/var/lock/vboxcloneimmutable
    
    dirname "${parentmedium}" | xargs -I '{}' -- find '{}' -maxdepth 1 -mindepth 1  -type f -iname '*.vdi.bak.tmp' | LANG=C sort -r | awk '{if(NR>1) { print $0; } }' | xargs -I '{}' -- rm -f '{}'
    
    dirname "${parentmedium}" | xargs -I '{}' -- find '{}' -maxdepth 1 -mindepth 1  -type f -iname '*.vdi.bak.tmp' | sed "s/\.tmp\$//" | xargs -I '{}' -- mv -f "{}.tmp" '{}'
    
    dirname "${parentmedium}" | xargs -I '{}' -- find '{}' -maxdepth 1 -mindepth 1  -type f -iname '*.vdi.bak' | LANG=C sort -r | awk '{if(NR>3) { print $0; } }' | xargs -I '{}' -- rm -f '{}'
fi

exit 0

