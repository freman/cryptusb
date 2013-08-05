#!/bin/bash
DISK=$1

CWD="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
FILES="${CWD}/files"

if [ -z "${DISK}" ]; then
	echo "Please pass /dev/sdx"
	exit 1
else
	echo "Warning, this will destroy the disk ${DISK}"
	echo ""
	echo "Please enter 'YES' in uppercase to continue"
	read CONFIRM
	if [ "${CONFIRM}" != "YES" ]; then
		echo "No then...."
		exit 1;
	fi
fi

if [ ! -e "${DISK}3" ]]
	echo "Please make 3 partitions on ${DISK}"
	echo " - Small partition for /boot (128m should be enough)"
	echo " - Smallish partition for / (4gb should be enough)"
	echo " - Whatever is left over for vfat"
	exit 1
fi

if [ ! -e /sbin/lvm.static ]; then
	USE="static" emerge lvm2
fi
if ! ( ldd /sbin/cryptsetup &> /dev/null ); then
	USE="static" emerge cryptsetup
fi
if [ ! -e /sbin/mke2fs ]; then
	emerge e2fsprogs
fi

echo "Formatting"

mkfs.ext2 -L GENTOO_USB_BOOT "${DISK}1"
mkfs.ext2 -L GENTOO_USB_ROOT "${DISK}2"
mkfs.vfat "${DISK}3"

echo "Mounting /"
mount "${DISK}2 /mnt

echo "Grabbing a stage3"
LINK=$(wget -q -O - http://mirror.internode.on.net/pub/gentoo/releases/amd64/current-stage3/* | grep 'stage3-amd64.*.tar.bz2"' | cut -d '"' -f 2)
wget -q -O - "${LINK}" | tar -jxvp -C /mnt/

echo "Mounting /boot"
mount "${DISK}1 /mnt/boot

echo "Generating a kernel - go get a coffee"
genkernel --e2fsprogs --firmware --busybox --disklabel --bootdir=/mnt/boot --no-symlink --all-ramdisk-modules --lukes --lvm --install all

echo "Patching INIT"

VERSION=$(ls /mnt/boot/kernel* | tail -n1 | cut -d "-" -f 3-)
INITRD="initramfs-genkernel-${VERSION}"
KERNEL="kernel-genkernel-${VERSION}"

mkdir inittmp
pushd inittmp
xzcat /mnt/boot/${INITRD} | cpio -i

patch -p0 < "${FILES}/crypt_init.patch"

for i in awk df tail; do
	ln -s busybox bin/$i;
done

cp -L /bin/tr bin/
cp -ar lib/modules /mnt/lib/ 

ln -s ../bin/lvm sbin/

find | cpio -H newc -o | xz --check=crc32 -v9 > "/mnt/boot/${INITRD}"

popd

rm -fr inittmp

echo "Setting up syslinux"

if [ ! -e /usr/bin/syslinux ]; then
	emerge sys-boot/syslinux
fi

dd bs=404 count=1 conv=notrunc if=/usr/share/syslinux/mbr.bin of=/dev/sdx &>/dev/null

mkdir /mnt/boot/syslinux

cat > /mnt/boot/syslinux.cfg <<"EOF"
PROMPT 1
TIMEOUT 10
DEFAULT gentoo
 
LABEL gentoo
        LINUX ../${KERNEL}
        APPEND root=LABEL=GENTOO_USB_ROOT scandelay=3 ro
        INITRD ../${INITRD}
EOF

extlinux --device="${DISK}1" --install /mnt/boot/syslinux

emerge --root /mnt net-misc/ntp net-dns/bind-tools dev-libs/libusb sys-apps/usbutils sys-apps/pciutils net-misc/curl www-client/links sys-fs/lvm2 sys-fs/cryptsetup app-misc/mc app-editors/vim sys-block/parted

cp "${FILES}"/{initdisk,stagedisk,net-setup} /mnt/usr/sbin/
cp "${FILES}"/{motd,issue,resolv.conf} /mnt/etc

cp /mnt/usr/share/zoneinfo/UTC /mnt/etc/localtime
echo UTC > /mnt/etc/timezone

sed -i 's/localhost/usbboot/' /mnt/etc/conf.d/hostname

patch -p0 < "${FILES}/bashrc.patch"
chroot /mnt /bin/passwd

# init supports
# nocryptpivot=1
# 	Boot and mount the encrypted disk but don't switch to it
# noautocrypt=1
# 	Don't mount the encrypted disk at all.
