#!/bin/bash

set -x
set -e

storageport=0
storagedevice=0
storagectl="IDE"

#vboxbugdelay=10s

declare -a childvms
declare -a options

while [ "$1" != "" ] ; do
    if [ "${1::1}" == "-" ] ; then
        options+=( "${1:1}" )
        echo "option vbox: ${1:1}"
    elif [ "${1::1}" == "+" ] ; then
        case "${1:1}" in
            storageport=*)
                storageport="${1:1}"
                storageport=${storageport:$(expr index "$storageport" "=")}
                ;;
                
            storagedevice=*)
                storagedevice="${1:1}"
                storagedevice=${storagedevice:$(expr index "$storagedevice" "=")}
                ;;
                
            storagectl=*)
                storagectl="${1:1}"
                storagectl=${storagectl:$(expr index "$storagectl" "=")}
                ;;
                
            *)
                echo "No such option!"
                exit 255
        esac
        echo "option internal: $1"
    elif [ "$parentvm" == "" ] ; then
        parentvm="$1"
        echo "parent: $1"
    else
        childvms+=( "$1" )
        echo "child: $1"
    fi
    
    shift
done

function sleepbuggyvboxdelay()
{
    while true ; do
        killall VirtualBox 2>/dev/null || true
        
        sleep 1s
        
        if [ "$(ps -A -o wchan,command | grep -v grep | grep -i -E '/VirtualBoxVM' | awk '{print $1}' | grep -v -E '^-' | wc -l)" != "0" ]; then
            continue
        fi
        
        if [ "$(ps -A -o wchan,command | grep -v grep | grep -i -E '/VirtualBox[[:blank:]]*$' | wc -l)" != "0" ] ; then
            if [ "$(ps -A -o wchan,command | grep -v grep | grep -i -E '/VirtualBox[[:blank:]]*$' | awk '{print $1}' | grep -v -E 'do_pol' | wc -l)" != "0" ] ; then
                continue
            fi
        fi
        
        break
    done
}

if [ "${parentvm}" != "" ] ; then
    flagfile=$(mktemp)
    
    # Wait for parentvm
    while [ -f $flagfile ] ; do
        (
            flock 200
            
            sleepbuggyvboxdelay
            
            statepoweredoff=""
            stateaborted=""
            statesaved=""
            running=$(ps -A -o command | grep -v grep | grep 'VirtualBoxVM' | grep -E -c "${parentvm}" || true)
            
            if vboxmanage showvminfo "${parentvm}" 2>/dev/null 1>&2 ; then
                statepoweredoff=$(vboxmanage showvminfo "${parentvm}" | grep -E -c -i "State:[[:space:]]+powered off" || true)
                stateaborted=$(vboxmanage showvminfo "${parentvm}" | grep -E -c -i "State:[[:space:]]+aborted" || true)
                statesaved=$(vboxmanage showvminfo "${parentvm}" | grep -E -c -i "State:[[:space:]]+saved" || true)
            fi
            
            if [ "$statesaved" == "1" ] ; then
                vboxmanage discardstate "$parentvm"
            elif [ "$running" == "0" ] ; then
                rm -f $flagfile
            fi
        ) 200>/var/lock/vboxcloneimmutable
        
        if [ -f $flagfile ] ; then
            sleep 10s
        fi
    done
    
    # Wait for childvm
    for childvm in "${childvms[@]}" ; do
        flagfile=$(mktemp)
        
        while [ -f $flagfile ] ; do
            (
                flock 200
                
                sleepbuggyvboxdelay
                
                statepoweredoff=""
                stateaborted=""
                statesaved=""
                running=$(ps -A -o command | grep -v grep | grep 'VirtualBoxVM' | grep -E -c "${childvm}" || true)
                
                if vboxmanage showvminfo "${childvm}" 2>/dev/null 1>&2 ; then
                    statepoweredoff=$(vboxmanage showvminfo "${childvm}" | grep -E -c -i "State:[[:space:]]+powered off" || true)
                    stateaborted=$(vboxmanage showvminfo "${childvm}" | grep -E -c -i "State:[[:space:]]+aborted" || true)
                    statesaved=$(vboxmanage showvminfo "${childvm}" | grep -E -c -i "State:[[:space:]]+saved" || true)
                fi
                
                if [ "$statesaved" == "1" ] ; then
                    vboxmanage discardstate "$childvm"
                elif [ "$running" == "0" ] ; then
                    rm -f $flagfile
                fi
            ) 200>/var/lock/vboxcloneimmutable
            
            if [ -f $flagfile ] ; then
                sleep 10s
            fi
        done
    done
    
    # delete parent snapshot
    (
        flock 200
        
        while true ; do
            sleepbuggyvboxdelay
            
            snapshotdelete=$(vboxmanage snapshot "${parentvm}" list --machinereadable | grep -o -P  '(?<=CurrentSnapshotUUID=")[0-9a-f\-]+' || echo "")
            if [ "$snapshotdelete" == "" ] ; then
                break
            fi
            
            vboxmanage snapshot "${parentvm}" delete "$snapshotdelete"
        done
    ) 200>/var/lock/vboxcloneimmutable
    
    # delete all childvms
    (
        flock 200
        
        for childvm in "${childvms[@]}" ; do
            sleepbuggyvboxdelay
            
            vboxmanage list vms | grep -q -E "\"${childvm}\"" && vboxmanage unregistervm "${childvm}" --delete || true
        done
    ) 200>/var/lock/vboxcloneimmutable
    
    # Remove parent's state aborted flag
    (
        flock 200
        sleepbuggyvboxdelay
        
        stateaborted=$(vboxmanage showvminfo "${parentvm}" | grep -E -c -i "State:[[:space:]]+aborted" || true)
        
        if [ "$stateaborted" == "1" ]; then
            configfile="$(vboxmanage showvminfo "${parentvm}" | grep -o -P '^Config file:[[:space:]]+\K.*(\.vbox)')"
            sed '/<Machine/s/aborted="true"/aborted="false"/' "$configfile" > "${configfile}.newstate"
            mv -f "${configfile}.newstate" "${configfile}"
        fi
    ) 200>/var/lock/vboxcloneimmutable
    
    # remove children's state aborted flag
    (
        flock 200
        
        while true; do
            sleepbuggyvboxdelay
            
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
        done
    ) 200>/var/lock/vboxcloneimmutable
    
    # detach hard disk from parent
    (
        flock 200
        sleepbuggyvboxdelay
        
        while IFS= read f ; do
            vartype="$(echo "$f" | grep -o -E "^(${storagectl})")"
            echo $vartype
            varportdevice="$(echo "$f" | grep -o -i -E '\(.*\):' | tr -c '0123456789' ' ')"
            echo $varportdevice
            varport=$(echo "$varportdevice" | awk '{print $1}')
            echo $varport
            vardevice=$(echo "$varportdevice" | awk '{print $2}')
            echo $vardevice
            
            vboxmanage storageattach "${parentvm}" --storagectl "${vartype}" --port ${varport} --device ${vardevice} --type hdd --medium emptydrive
            sleepbuggyvboxdelay
        done < <(vboxmanage showvminfo "${parentvm}" | grep -E "^(${storagectl})" | grep -i '(UUID:')
    ) 200>/var/lock/vboxcloneimmutable
    
    parentmedium="$(vboxmanage showvminfo "${parentvm}" | grep -o -P '^Config file:[[:space:]]+\K.*(\.vbox)' | sed 's/\.vbox$/\.vdi/')"
    
    if [ "$parentmedium" == "" ] ; then
        echo "Couldn't get parent medium"
        exit 255
    fi
    
    if [ ! -f "$parentmedium" ] ; then
        echo "No parent medium"
        exit 255
    fi
    
    # close and delete all children's harddisks
    (
        flock 200
        
        while true ; do
            sleepbuggyvboxdelay
            childhduuid=$(vboxmanage showhdinfo "${parentmedium}" | grep -E '^Child UUIDs:' | grep -o -P '[0-9a-f\-]{36}' || echo "")
            
            if [ "$childhduuid" == "" ] ; then
                break
            fi
            
            vboxmanage closemedium disk "$childhduuid" --delete
        done
    ) 200>/var/lock/vboxcloneimmutable
    
    # make a backup of parent's harddisk
    (
        flock 200
        
        sleepbuggyvboxdelay
        echo "${parentmedium}" | sed "s/\.vdi\$/\_$(date +%Y%m%d-%H%M%S)\.vdi\.bak\.tmp/" | xargs -I '{}' -- ionice -c 3 -- rsync -a --progress "${parentmedium}" '{}'
        
        sleepbuggyvboxdelay
        vboxmanage modifymedium "${parentmedium}" --type normal
        
        sleepbuggyvboxdelay
        vboxmanage storageattach "${parentvm}" --storagectl "${storagectl}" --port ${storageport} --device ${storagedevice} --medium emptydrive
        
        sleepbuggyvboxdelay
        vboxmanage storageattach "${parentvm}" --storagectl "${storagectl}" --port ${storageport} --device ${storagedevice} --type hdd --medium "${parentmedium}"
        
    ) 200>/var/lock/vboxcloneimmutable
    
    set +x
    
    echo "Waiting for VM \"${parentvm}\" to be assigned a memory share..."
    
    ( # A Virtualbox VM does not allocate all memory immediately
        while : ; do
            if flock -w 0 200 ; then
                memoryguestmb=$(vboxmanage showvminfo "$parentvm" | grep -E "^Memory size(:)*[[:space:]]" | tr -d -c '[0-9]')
                
                if [ "$memoryguestmb" == "" ] ; then
                    memoryguestmb=$((1024*1024*1024))
                fi
                
                memoryguestmb=$(echo "(2048+$memoryguestmb*1.1)/1" | bc)
                
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
            
            sleepbuggyvboxdelay
            sleep 10s
        done
        
        vboxmanage startvm "${parentvm}"
        sleepbuggyvboxdelay
        
        flock -u 200
    ) 200>/var/lock/vboxcloneimmutable
    
    echo "Waiting for VM \"${parentvm}\" to power off..."
    
    while true ; do
        statepoweredoff=""
        stateaborted=""
        
        if vboxmanage showvminfo "${parentvm}" 2>/dev/null 1>&2 ; then
            statepoweredoff=$(vboxmanage showvminfo "${parentvm}" | grep -E -c -i "State:[[:space:]]+powered off" || true)
            stateaborted=$(vboxmanage showvminfo "${parentvm}" | grep -E -c -i "State:[[:space:]]+aborted" || true)
        fi
        
        if [ "$stateaborted" == "1" ]; then
            echo "${parentvm} was aborted."
            exit 255
        fi
        
        if [ "$statepoweredoff" == "1" ] ; then
            running=
            running=$(ps -A -o command | grep -v grep | grep 'VirtualBoxVM' | grep -E -c "${parentvm}" || true)
            
            if [ "$running" == "0" ] ; then
                break
            fi
            
#            break
        fi
        
        sleepbuggyvboxdelay
    done
    
    set -x
    
    # compact parent's hard disk, attach an immutable copy to each created child and apply all options on the command line for the childvm
    (
        flock 200
        
        sleepbuggyvboxdelay
        vboxmanage modifymedium "$parentmedium" --compact && touch -r "$parentmedium" "${parentmedium}.stamp"
        
        sleepbuggyvboxdelay
        vboxmanage storageattach "${parentvm}" --storagectl "${storagectl}" --port ${storageport} --device ${storagedevice} --type hdd --medium emptydrive
        
        sleepbuggyvboxdelay
        vboxmanage modifymedium "${parentmedium}" --type immutable
        
        for childvm in "${childvms[@]}" ; do
            sleepbuggyvboxdelay
            vboxmanage clonevm "${parentvm}" --options=KeepAllMACs,KeepHwUUIDs --name "${childvm}" --register
            
            sleepbuggyvboxdelay
            vboxmanage storageattach "${childvm}" --storagectl "${storagectl}" --port ${storageport} --device ${storagedevice} --type hdd --medium "${parentmedium}"
            
            for (( i=0 ; i<10 ; i++ )) ; do
                sleepbuggyvboxdelay
                diskfile="$(vboxmanage showvminfo "${childvm}" --machinereadable | grep -E "\"${storagectl}-${storageport}-${storagedevice}\"" | grep -o -P '(?<==")[^"]+')"
                
                if [ "$diskfile" != "" ] ; then
                    break
                fi
            done
            
            if [ "$diskfile" == "" ] ; then
                echo "vboxmanage showvminfo failed"
                exit 255
            fi
            
            diskdir="$(dirname "$diskfile")"
            rm -f "${diskdir}/"*".vdi.bak"
            cp -a "${diskfile}" "${diskfile}.bak"
            
            for option in "${options[@]}" ; do
                sleepbuggyvboxdelay
                
                if echo "$option" | grep -q '{}' ; then
                    s="$(echo "$option" | sed "s/{}/${childvm}/")"
                    eval vboxmanage "$s"
                else
                    vboxmanage modifyvm "$childvm" $option
                fi
            done
        done
    ) 200>/var/lock/vboxcloneimmutable
    
    # We save maximum three copies parentvm hard disk. Temp files are removed.
    dirname "${parentmedium}" | xargs -I '{}' -- find '{}' -maxdepth 1 -mindepth 1  -type f -iname '*.vdi.bak.tmp' | LANG=C sort -r | awk '{if(NR>1) { print $0; } }' | xargs -I '{}' -- rm -f '{}'
    
    dirname "${parentmedium}" | xargs -I '{}' -- find '{}' -maxdepth 1 -mindepth 1  -type f -iname '*.vdi.bak.tmp' | sed "s/\.tmp\$//" | xargs -I '{}' -- mv -f "{}.tmp" '{}'
    
    dirname "${parentmedium}" | xargs -I '{}' -- find '{}' -maxdepth 1 -mindepth 1  -type f -iname '*.vdi.bak' | LANG=C sort -r | awk '{if(NR>3) { print $0; } }' | xargs -I '{}' -- rm -f '{}'
fi

exit 0

