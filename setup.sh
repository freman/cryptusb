#!/bin/bash
DISK=$1

FTP_MIRROR="ftp://mirror.internode.on.net/pub/gentoo"

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

if [ ! -e "${DISK}3" ]; then
	echo "Please make 3 partitions on ${DISK}"
	echo " - Small partition for /boot (128m should be enough)"
	echo " - Smallish partition for / (4gb should be enough)"
	echo " - Whatever is left over for vfat"
	exit 1
fi

# These emerges need special USEs for genkernel
EMERGE=""
if [ ! -e /sbin/lvm.static ]; then
	EMERGE="${EMERGE} sys-fs/lvm2"
fi
ldd /sbin/cryptsetup &> /dev/null
RESULT=$?
if [ $RESULT -eq 0 ]; then
	EMERGE="${EMERGE} sys-fs/cryptsetup"
fi
if [ ! -e /usr/bin/genkernel ] || [ "$(qlist -IU sys-kernel/genkernel | grep cryptsetup)x" == "x" ]; then
	EMERGE="${EMERGE} sys-kernel/genkernel"
fi
if [ -n "${EMERGE}" ]; then
	USE="static static-libs cryptsetup -udev" emerge ${EMERGE}
fi

# These emerges just need to exist
EMERGE=""
if [ ! -e /sbin/mke2fs ]; then
	EMERGE="${EMERGE} sys-fs/e2fsprogs"
fi
if [ ! -e /usr/sbin/mkfs.vfat ]; then
	EMERGE="${EMERGE} sys-fs/dosfstools"
fi
if [ ! -e /usr/bin/syslinux ]; then
	EMERGE="${EMERGE} sys-boot/syslinux"
fi
if [ ! -e /usr/src/linux/Makefile ]; then
	EMERGE="${EMERGE} gentoo-sources"
fi
if [ -n "${EMERGE}" ]; then
	emerge ${EMERGE}
fi

echo "Formatting"

mkfs.ext2 -L GENTOO_USB_BOOT "${DISK}1"
mkfs.ext2 -L GENTOO_USB_ROOT "${DISK}2"
mkfs.vfat "${DISK}3"

echo "Mounting /"
mount "${DISK}2" /mnt

echo "Grabbing a stage3"

FTP_MIRROR_DIR=$(wget -q -O - ${FTP_MIRROR}/releases/amd64/current-stage3/default/ | grep -e 'a href' | tail -n 1 | cut -d '"' -f 2)
LINK=$(wget -q -O - ${FTP_MIRROR_DIR} | grep 'stage3-amd64.*.tar.bz2"' | cut -d '"' -f 2)
wget -q -O - "${LINK}" | tar -jxvp -C /mnt/

echo "Mounting /boot"
mount "${DISK}1" /mnt/boot

echo "Generating a kernel - go get a coffee"
genkernel --e2fsprogs --firmware --busybox --disklabel --bootdir=/mnt/boot --no-symlink --all-ramdisk-modules --luks --lvm --install all

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

dd bs=404 count=1 conv=notrunc if=/usr/share/syslinux/mbr.bin of=/dev/${DISK} &>/dev/null

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

emerge --root /mnt net-misc/ntp net-dns/bind-tools dev-libs/libusb sys-apps/usbutils sys-apps/pciutils \
       net-misc/curl www-client/links sys-fs/lvm2 sys-fs/cryptsetup app-misc/mc app-editors/vim \
       sys-block/parted sys-fs/ntfs3g

cp "${FILES}"/{initdisk,stagedisk,net-setup} /mnt/usr/sbin/
cp "${FILES}"/{motd,issue,resolv.conf} /mnt/etc

mkdir -p /mnt/usr/share/udhcpc
cp "${FILES}"/default.script /mnt/usr/share/udhcpc/default.script

cp /mnt/usr/share/zoneinfo/UTC /mnt/etc/localtime
echo UTC > /mnt/etc/timezone

sed -i 's/localhost/usbboot/' /mnt/etc/conf.d/hostname

patch -p0 < "${FILES}/bashrc.patch"
chroot /mnt /bin/passwd &> /dev/null << 'EOF'
password
password
EOF

umount /mnt/boot
umount /mnt

echo "All done!"
