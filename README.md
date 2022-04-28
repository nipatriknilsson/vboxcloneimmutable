# vboxcloneimmutable.sh

The vboxcloneimmutable.sh script is made to simplify creation of VirtualBox child VMs from a parent VM. Nothing is saved when you power off a child VMs. Modifications to be used by the child VMs can only be done from the parent VM when it is running and then cloned.

Syntax of calling vboxcloneimmutable.sh is
```
vboxcloneimmutable.sh {parent vm} [child vm_1] [child vm_2] [-optionstovbox] [+optionstoscript]
```

These are optionstoscript options
+storageport=<number> # example: +storageport=0
+storagedevice=<number> # example: +storagedevice=1
+storagectl=<name> # example: +storagectl=SATA

The disk's interface is named IDE by default and disk attached to storageport 0 and storagedevice 0:

In sequence the script does the following:
1) Wait for child VMs and delete them when they are not running.
2) Set the parent's disk to vbox path with extension vdi.
3) Run parent VM and wait for it to finish.
4) Compact parent VM's disk. Saves space if you have zeroed out unused sectors of the virtual disk.
5) Set the parent disk to immutable.
6) Clone the parent into the child VMs. No limits of the number imposed by the script.
7) Set the parent VM's disk to NONE, so it is not accidentally run. It is not removed from the host's file system.

Tested on Ubuntu Mate 20.04 (Focal).

# Examples
Remove child VMs named "Ubuntu Mate Focal #1", "Ubuntu Mate Focal #2", "Ubuntu Mate Focal #3" and run "Ubuntu Mate Focal". When parent finished running the child VMs are created again, Mac address 1 is randomized. Parent can't be run to avoid accidental run. The children's disks are set immutable.
```
vboxcloneimmutable.sh "Ubuntu Mate Focal" "Ubuntu Mate Focal #1" "Ubuntu Mate Focal #2" "Ubuntu Mate Focal #3" "---macaddress1 auto"
```

Another example with three child VMs.
```
vboxcloneimmutable.sh "Kali Linux" "Kali Linux #1" "Kali Linux #2" "Kali Linux #3"
```

Example with storage naming control.
```
vboxcloneimmutable.sh +storageport=0 +storagedevice=0 +storagectl="SATA" "Kali Linux" "Kali Linux #1" "Kali Linux #2" "Kali Linux #3"
```

Example with one child VM.
```
vboxcloneimmutable.sh "Shellter" "Shellter #1"
```

(This version can't take quotes in the option.) Example with options. The options are run with "vboxmanage modifyvm "$childvm" $option". All child VMs (in this case one) get all options on the command line. This translates to ```vboxmanage modifyvm "Shellter #1" --nic1 none```,  ```vboxmanage modifyvm "Shellter #1" -nic2 hostonly```, etc.
```
vboxcloneimmutable.sh "Shellter" "Shellter #1" "---nic1 none" "---nic2 hostonly" "---hostonlyadapter2 vboxnet0" "---nic3 hostonly" "---hostonlyadapter3 vboxnet1"
```

You can have the "{}" option to insert the cloned childvm's name. This translates to ```vboxmanage sharedfolder add 'Shellter #1' --name R: --hostpath / --readonly --automount```
```
vboxcloneimmutable.sh "Shellter" "Shellter #1" -"sharedfolder add \"{}\" --name \"root\" --hostpath / --readonly --automount --auto-mount-point=R:" 
```

