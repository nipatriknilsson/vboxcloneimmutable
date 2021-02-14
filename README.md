# vboxcloneimmutable.sh

The vboxcloneimmutable.sh script is made to simplify creation of VirtualBox child VMs from a parent VM. Nothing is saved when you power off a child VMs. Modifications to be used by the child VMs can only be done from the parent VM when it is running and then cloned.

Syntax of calling vboxcloneimmutable.sh is
```
vboxcloneimmutable.sh <parent vm> <child vm_1> <child vm_2> 
```

The disk's interface is named SCSI.

In sequence the script does the following:
1) Wait for child VMs and delete them when they are not running.
2) Set the parent's disk to vbox path with extension vdi.
3) Run parent VM and wait for it to finish.
4) Compact parent VM's disk. Saves space if you have zeroed out unused sectors of the virtual disk.
5) Set the parent disk to immutable.
6) Clone the parent into the child VMs.
7) Set the parent's disk to NONE, so it is not accidently run.

Tested on Ubuntu Mate 20.04 (Focal).

# Examples
```
vboxcloneimmutable.sh "Ubuntu Mate Focal" "Ubuntu Mate Focal #1" "Ubuntu Mate Focal #2" "Ubuntu Mate Focal #3"
```

```
vboxcloneimmutable.sh "Kali Linux" "Kali Linux #1" "Kali Linux #2" "Kali Linux #3"
```

```
vboxcloneimmutable.sh "Shellter" "Shellter #1"
```

