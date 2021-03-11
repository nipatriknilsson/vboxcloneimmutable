#!/bin/bash

set -x
set -e

storageport=0
storagedevice=0
storagename="SATA"


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
            fi
            
            if [ "$poweredoff" == "1" ] ; then
                running=
                running=$(ps -A -o command | grep -v grep | grep 'VirtualBoxVM' | grep -E -c "${childvm}" || true)
                
                if [ "$running" == "0" ] ; then
                    break
                fi

    #            break
            fi

            sleep 10s
        done

        vboxmanage list vms | grep -q -E "\"${childvm}\"" && vboxmanage unregistervm "${childvm}" --delete || true
    done

    while true; do
        poweredoff=""

        if vboxmanage showvminfo "${parentvm}" 2>/dev/null 1>&2 ; then
            poweredoff=$(vboxmanage showvminfo "${parentvm}" | grep -E -c -i "State:[[:space:]]+powered off" || true)
        fi

        if [ "$poweredoff" == "1" ]; then
            break
        fi

        sleep 10s
    done

    while true ; do
        snapshotdelete=$(vboxmanage snapshot "${parentvm}" list --machinereadable | grep -o -P  '(?<=CurrentSnapshotUUID=")[0-9a-f\-]+' || echo "")
        if [ "$snapshotdelete" == "" ] ; then
            break
        fi

        vboxmanage snapshot "${parentvm}" delete "$snapshotdelete"
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
    done < <(vboxmanage showvminfo "${parentvm}" | grep -E "^(${storagename})" | grep -i '(UUID:')

    parentmedium=$(vboxmanage showvminfo "${parentvm}" | grep -o -P '^Config file:[[:space:]]+\K.*(\.vbox)' | sed 's/\.vbox$/\.vdi/')

    while true ; do
        childhduuid=$(vboxmanage showhdinfo "${parentmedium}" | grep -E '^Child UUIDs:' | grep -o -P '[0-9a-f\-]{36}' || echo "")
        
        if [ "$childhduuid" == "" ] ; then
            break
        fi

        vboxmanage closemedium disk "$childhduuid" --delete
    done

    echo "${parentmedium}" | sed "s/\.vdi\$/\_$(date +%Y%m%d-%H%M%S)\.vdi\.bak\.tmp/" | xargs -I '{}' -- cp -a "${parentmedium}" '{}'

    vboxmanage modifymedium "${parentmedium}" --type normal
    vboxmanage storageattach "${parentvm}" --storagectl "${storagename}" --port ${storageport} --device ${storagedevice} --type hdd --medium "${parentmedium}"

    vboxmanage startvm "${parentvm}"

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

        sleep 10s
    done

    sleep 10s
    
    vboxmanage modifymedium "$parentmedium" --compact && sleep 10s && touch -r "$parentmedium" "${parentmedium}.stamp"

    vboxmanage storageattach "${parentvm}" --storagectl "${storagename}" --port ${storageport} --device ${storagedevice} --type hdd --medium emptydrive && sleep 10s

    vboxmanage modifymedium "${parentmedium}" --type immutable && sleep 10s

    for childvm in "${childvms[@]}" ; do
        vboxmanage clonevm "${parentvm}" --name "${childvm}" --register

        vboxmanage storageattach "${childvm}" --storagectl "${storagename}" --port ${storageport} --device ${storagedevice} --type hdd --medium "${parentmedium}" && sleep 10s
        
        for option in "${options[@]}" ; do
            vboxmanage modifyvm "$childvm" $option && sleep 10s
        done
    done

    dirname "${parentmedium}" | xargs -I '{}' -- find '{}' -type f -maxdepth 1 -mindepth 1 -iname '*.vdi.bak.tmp' | LANG=C sort -r | awk '{if(NR>1) { print $0; } }' | xargs -I '{}' -- rm -f '{}'
    
    dirname "${parentmedium}" | xargs -I '{}' -- find '{}' -type f -maxdepth 1 -mindepth 1 -iname '*.vdi.bak.tmp' | sed "s/\.tmp\$//" | xargs -I '{}' -- mv -f "{}.tmp" '{}'

    dirname "${parentmedium}" | xargs -I '{}' -- find '{}' -type f -maxdepth 1 -mindepth 1 -iname '*.vdi.bak' | LANG=C sort -r | awk '{if(NR>3) { print $0; } }' | xargs -I '{}' -- rm -f '{}'

    exit 0
fi


