cryptusb
========

Boot disk with pivot for automatically decrypting and mounting encrypted harddisk with root pivot.

Bonus features, when no encrypted disk is detected it'll behave much like a rescue disk

setup
========

Basically you need a working gentoo install, ideally it'd be a fresh install (or chrooted environment) with a kernel install

1. fdisk your usb stick, you need 3 partitions (boot, root and vfat)
2. clone this repo
3. run setup.sh
4. go have coffee

example
--------

```bash
mkdir /foobar
wget http://some/stage3.tbz
tar -jxvpf stage3.tbz -C /foobar
mkdir -p /foobar/usr/portage
mount -o bind /usr/portage /foobar/usr/portage
mount -o bind /dev /foobar/dev
mount -t proc none /foobar/proc
chroot /foobar /bin/bash
USE="-blksha1 -gpg -iconv -nls -perl -python -pcre -threads -webdav" emerge git
git clone https://github.com/freman/cryptusb.git
cd cryptsetup
./setup.sh
```

optional boot parameters
========

* nocryptpivot=1
 > Boot and mount the encrypted disk but don't switch to it


* noautocrypt=1
 > Don't mount the encrypted disk at all.

booting
========

Boot from the stick, all the defaults should work
Your root password will be whatever you set while running setup.sh

commands
========

* net-setup {list|dhcp}
 > Set up the network interface, only supports wired connections atm

* initdisk {/dev/disk}
 > Create a new encrypted disk for booting off, will generate keys
 > encrypt the disk, set up the required lvm partitions and leave
 > the new root mounted in /mnt/cryptroot

* stagedisk {/path/to/root}
 > Will install a stage3 on the root chosen before adding extra packages
 > some required by encrypted filesystems, some just because they're
 > packages I always install on a system
 >
 > *nb: doesn't need to be an encrypted root, you could use this script
 > to stage any gentoo
