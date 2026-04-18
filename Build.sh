#!/bin/bash
#Build.sh 17.0 for netbootcd-neo - BIOS + UEFI support (x86_64)
## Copyright (C) 2022 Isaac Schemm <isaacschemm@gmail.com>
## Edited by Jonathan A. Wingo <spcwingo1@gmail.com> to support
## only x86_64 in either BIOS or UEFI mode.
##
## This program is free software; you can redistribute it and/or
## modify it under the terms of the GNU General Public License
## as published by the Free Software Foundation; either version 2
## of the License, or (at your option) any later version.
##
## This program is distributed in the hope that it will be useful,
## but WITHOUT ANY WARRANTY; without even the implied warranty of
## MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
## GNU General Public License for more details.
##
## You should have received a copy of the GNU General Public License
## along with this program; if not, write to the Free Software
## Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
##
## The full text of the GNU GPL, versions 2 or 3, can be found at
## <http://www.gnu.org/copyleft/gpl.html> or on the CD itself.

set -e
PATH=$PATH:/sbin
WORK=$(pwd)/work
DONE=$(pwd)/done
NBINIT=${WORK}/nbinit

# Always clean up the intermediate build tree, even if the script exits early
# due to a set -e failure.  DONE (the output directory) is intentionally kept.
cleanup() {
    rm -rf "${WORK:-}" squashfs-root opt
    rm -f "vmlinuz64-${COREVER}" "corepure64-${COREVER}.gz" \
          "kexec-tools-${KEXEC_VER}.tar.xz" \
          "dialog-x86_64.tcz" "ncursesw-x86_64.tcz" "openssl-x86_64.tcz"
    for _pkg in ${WIFI_PKGS_ALL:-}; do
        rm -f "${_pkg}-x86_64.tcz"
    done
}
trap cleanup EXIT

NBCDVER=17.0
COREVER=17.0
KEXEC_VER=2.0.29
TCX64="http://tinycorelinux.net/${COREVER%.*}.x/x86_64"

# --- Locate GRUB EFI modules directory ---
GRUB_MODULES_DIR=""
for dir in /usr/lib/grub/x86_64-efi \
           /usr/lib/grub2/x86_64-efi \
           /boot/grub2/x86_64-efi \
           /usr/share/grub2/x86_64-efi; do
    if [ -d "$dir" ] && [ -f "$dir/linux.mod" ]; then
        GRUB_MODULES_DIR="$dir"
        break
    fi
done
if [ -z "$GRUB_MODULES_DIR" ]; then
    echo "ERROR: GRUB EFI modules not found."
    echo "Install with: sudo apt install grub-efi-amd64-bin"
    exit 1
fi

# --- Download TinyCore x86_64 kernel and rootfs ---
# We use TinyCore x86_64 (not i386) because the i386 kexec binary hardcodes
# bzImage_support_efi_boot=0, making UEFI kexec handoff impossible.  The
# x86_64 kexec binary sets it to 1 and properly fills boot_params.efi_info.
if [ ! -f "vmlinuz64-${COREVER}" ]; then
    wget "$TCX64/release/distribution_files/vmlinuz64" \
         -O "vmlinuz64-${COREVER}"
fi
if [ ! -f "corepure64-${COREVER}.gz" ]; then
    wget "$TCX64/release/distribution_files/corepure64.gz" \
         -O "corepure64-${COREVER}.gz"
fi

# x86_64 TCZ packages (downloaded once, cached locally)
for pkg in dialog ncursesw openssl; do
    if [ ! -f "${pkg}-x86_64.tcz" ]; then
        wget "$TCX64/tcz/${pkg}.tcz" -O "${pkg}-x86_64.tcz"
    fi
done

# Detect the kernel version shipped in corepure64 so we can request the
# matching wireless kernel module package (wireless-<kver>.tcz).
# TinyCore ships zero wireless drivers in corepure64 itself; they live in a
# separate version-stamped package that installs into /usr/local/lib/modules/.
KVER=$(gzip -cd "corepure64-${COREVER}.gz" | cpio -t 2>/dev/null \
    | grep '^lib/modules/[^/]*$' | head -1 | sed 's|lib/modules/||')
if [ -z "$KVER" ]; then
    echo "ERROR: Could not detect kernel version from corepure64-${COREVER}.gz"
    exit 1
fi
echo "Detected kernel version: $KVER"

WIFI_PKGS="wifi wpa_supplicant-dbus iw wireless-${KVER} wireless-regdb wireless_tools \
    firmware-atheros \
    firmware-broadcom_bcm43xx firmware-broadcom_bnx2 firmware-broadcom_bnx2x \
    firmware-cavium_nic firmware-chelsio \
    firmware-ipw2100 firmware-ipw2200 firmware-iwimax \
    firmware-iwl8000 firmware-iwl9000 firmware-iwlax20x firmware-iwlwifi \
    firmware-lan firmware-marvel firmware-mediatek firmware-mellanox \
    firmware-myri10ge firmware-netronome firmware-netxen \
    firmware-openfwwf firmware-qca firmware-qed \
    firmware-ralinkwifi firmware-rtl_nic firmware-rtlwifi \
    firmware-ti-connectivity firmware-tigon \
    firmware-vxge firmware-wlan firmware-zd1211"
# Download a TCZ package plus all of its transitive dependencies by reading
# the .tcz.dep file that TinyCore publishes alongside each package.
# Discovered names accumulate in WIFI_PKGS_ALL for extraction and cleanup.
fetch_tcz() {
    local pkg="$1"
    if [ -z "$pkg" ]; then return 0; fi
    case " ${WIFI_PKGS_ALL} " in *" ${pkg} "*) return 0 ;; esac
    WIFI_PKGS_ALL="${WIFI_PKGS_ALL} ${pkg}"
    printf '  [wifi dep] %s\n' "$pkg"

    if [ ! -f "${pkg}-x86_64.tcz" ]; then
        if ! wget -q -T 15 "$TCX64/tcz/${pkg}.tcz" -O "${pkg}-x86_64.tcz"; then
            rm -f "${pkg}-x86_64.tcz"
            echo "WARNING: Could not download ${pkg}.tcz — skipping"
            return 0
        fi
    fi

    local depfile
    depfile=$(mktemp)
    wget -q -T 15 "$TCX64/tcz/${pkg}.tcz.dep" -O "$depfile" 2>/dev/null || true
    if [ -s "$depfile" ]; then
        # plain read (no IFS=) trims leading/trailing whitespace, so blank
        # lines and whitespace-only lines become empty strings and are skipped
        while read -r dep; do
            dep="${dep%.tcz}"
            dep="${dep//KERNEL/$KVER}"   # TinyCore uses KERNEL as a placeholder
            if [ -n "$dep" ]; then
                fetch_tcz "$dep"
            fi
        done < "$depfile"
    fi
    rm -f "$depfile"
    return 0
}

WIFI_PKGS_ALL=""
echo "Resolving WiFi package dependencies..."
for pkg in $WIFI_PKGS; do
    fetch_tcz "$pkg"
done
echo "WiFi packages to install: ${WIFI_PKGS_ALL}"

# kexec-tools source (for 64-bit static build)
if [ ! -f "kexec-tools-${KEXEC_VER}.tar.xz" ]; then
    wget "https://mirrors.edge.kernel.org/pub/linux/utils/kernel/kexec/kexec-tools-${KEXEC_VER}.tar.xz"
fi

# --- Dependency checks ---
NO=0
for i in nbscript.sh tc-config.diff; do
    if [ ! -e "$i" ]; then
        echo "Couldn't find $i!"
        NO=1
    fi
done
for i in mkfs.vfat unsquashfs grub-mkstandalone mcopy \
          xorriso gcc make; do
    if ! which "$i" > /dev/null 2>&1; then
        echo "Please install $i!"
        NO=1
    fi
done
if [ $NO = 1 ]; then exit 1; fi

if [ "$(whoami)" != "root" ]; then
    echo "Please run as root."
    exit 1
fi

# --- Clean slate ---
rm -rf "${WORK}" "${DONE}"
mkdir -p "${WORK}" "${DONE}" "${NBINIT}"

FDIR=$(pwd)

# --- Copy x86_64 kernel ---
cp "vmlinuz64-${COREVER}" "${DONE}/vmlinuz"
chmod +w "${DONE}/vmlinuz"

# --- Build nbinit4.gz from TinyCore x86_64 rootfs ---
if [ -d "${NBINIT}" ]; then rm -r "${NBINIT}"; fi
mkdir "${NBINIT}"

cd "${NBINIT}"
echo "Extracting corepure64..."
gzip -cd "${FDIR}/corepure64-${COREVER}.gz" | cpio -id
cd -

# Wrapper script
cat > "${NBINIT}/usr/bin/netboot" << "EOF"
#!/bin/sh
if [ $(whoami) != "root" ]; then
	exec sudo $0 $*
fi

if [ ! -f /tmp/internet-is-up ]; then
	# Quick check: do we already have internet?
	if wget --no-check-certificate --tries=1 -T 5 --spider \
		http://www.example.com >/dev/null 2>&1; then
		echo > /tmp/internet-is-up
	elif command -v wpa_supplicant >/dev/null 2>&1; then
		# WiFi ISO: let the user configure wireless from the menu
		echo "No internet connection detected."
		echo "Use the 'wifi' option in the menu to connect to a wireless network."
	else
		# Wired-only ISO: wait until a link comes up
		echo "Waiting for internet connection (will keep trying indefinitely)"
		echo -n "Testing example.com"
		while ! wget --no-check-certificate --tries=1 -T 5 --spider \
			http://www.example.com >/dev/null 2>&1; do
			sleep 1
			echo -n "."
		done
		echo ""
		echo > /tmp/internet-is-up
	fi
fi

if [ -x /tmp/nbscript.sh ]; then
	/tmp/nbscript.sh
else
	/usr/bin/nbscript.sh
fi
echo "Type \"netboot\" to return to the menu."
EOF
chmod +x "${NBINIT}/usr/bin/netboot"

# Patch tc-config (disable swap in NetbootCD-Neo)
cd "${NBINIT}/etc/init.d"
patch -p0 < "${FDIR}/tc-config.diff" || {
    echo "WARNING: tc-config.diff did not apply cleanly."
    echo "The swap-disable patch may need updating for TinyCore x86_64."
    echo "Continuing anyway - swap will not be disabled."
}
cd -

cp -v nbscript.sh "${NBINIT}/usr/bin"

# x86_64 TCZ packages
if [ -e squashfs-root ]; then rm -r squashfs-root; fi
for pkg in dialog ncursesw openssl; do
    unsquashfs "${pkg}-x86_64.tcz"
    cp -a squashfs-root/* "${NBINIT}"
    rm -r squashfs-root
done

# --- Build 64-bit static kexec-tools ---
# A 64-bit kexec binary is required for UEFI kexec handoff:
# the i386 bzImage loader sets bzImage_support_efi_boot=0 unconditionally,
# so it never fills boot_params.efi_info.  The x86_64 loader sets it to 1.
KEXEC_BUILD="${WORK}/kexec-build"
rm -rf "${KEXEC_BUILD}"
mkdir -p "${KEXEC_BUILD}"
tar -C "${KEXEC_BUILD}" --strip-components=1 -xf "kexec-tools-${KEXEC_VER}.tar.xz"
(
    cd "${KEXEC_BUILD}"
    LDFLAGS='-static' ./configure --sbindir=/sbin > /dev/null
    make -j"$(nproc)"
)
KEXEC_BIN="${KEXEC_BUILD}/build/sbin/kexec"
if ! "${KEXEC_BIN}" --help 2>&1 | grep -q -- '-s'; then
    echo "ERROR: kexec built without kexec_file_load (-s) support."
    echo "Check that linux/kexec.h is present on the build host."
    exit 1
fi
install -D -m 0755 "${KEXEC_BIN}" "${NBINIT}/sbin/kexec"
strip "${NBINIT}/sbin/kexec"
echo "Installed kexec-tools ${KEXEC_VER} (64-bit static, -s supported)"
rm -rf "${KEXEC_BUILD}"

echo "if ! which startx;then netboot;else sleep 5;echo '** Type netboot to start **';fi" \
    >> "${NBINIT}/etc/skel/.profile"

cd "${NBINIT}"
find . | cpio -o -H 'newc' | gzip -c > "${DONE}/nbinit4.gz"
cd -
echo "Made initrd: $(wc -c < "${DONE}/nbinit4.gz") bytes"

# --- Prepare ISO tree ---
rm -rf "${WORK}/iso"
mkdir -p "${WORK}/iso/boot/isolinux"

# Get isolinux from system package (architecture-independent BIOS bootloader)
ISOLINUX_BIN=""
for f in /usr/lib/ISOLINUX/isolinux.bin \
          /usr/share/syslinux/isolinux.bin \
          /usr/lib/syslinux/modules/bios/isolinux.bin; do
    [ -f "$f" ] && { ISOLINUX_BIN="$f"; break; }
done
if [ -z "$ISOLINUX_BIN" ]; then
    echo "ERROR: isolinux.bin not found. Install: sudo apt install isolinux"
    exit 1
fi
cp "$ISOLINUX_BIN" "${WORK}/iso/boot/isolinux/"

SYSLINUX_BIOS_DIR=""
for d in /usr/lib/syslinux/modules/bios \
          /usr/share/syslinux \
          /usr/lib/ISOLINUX; do
    [ -f "$d/menu.c32" ] && { SYSLINUX_BIOS_DIR="$d"; break; }
done
if [ -z "$SYSLINUX_BIOS_DIR" ]; then
    echo "ERROR: syslinux modules not found. Install: sudo apt install syslinux-common"
    exit 1
fi
# Syslinux 5+ requires ldlinux.c32, libcom32.c32, and libutil.c32 alongside
# menu.c32; copy whichever ones exist (older versions don't have them).
for mod in menu.c32 ldlinux.c32 libcom32.c32 libutil.c32; do
    [ -f "$SYSLINUX_BIOS_DIR/$mod" ] && \
        cp "$SYSLINUX_BIOS_DIR/$mod" "${WORK}/iso/boot/isolinux/"
done

cp "${DONE}/vmlinuz" "${DONE}/nbinit4.gz" "${WORK}/iso/boot/"

# BIOS boot menu
cat > "${WORK}/iso/boot/isolinux/isolinux.cfg" << EOF
DEFAULT menu.c32
PROMPT 0
TIMEOUT 100
ONTIMEOUT nbcd

LABEL hd
MENU LABEL Boot from hard disk
localboot 0x80

LABEL nbcd
menu label Start ^NetbootCD-Neo $NBCDVER
menu default
kernel /boot/vmlinuz
initrd /boot/nbinit4.gz
append quiet

EOF

# --- Build UEFI EFI boot image ---
echo "Building self-contained UEFI binary with grub-mkstandalone..."
mkdir -p "${WORK}/efifiles/EFI/BOOT"

cat > "${WORK}/grub-full.cfg" << EOF
set default=0
set timeout=5

insmod all_video
insmod gfxterm
insmod font

search --no-floppy --file --set=root /boot/vmlinuz

menuentry "Start NetbootCD-Neo $NBCDVER" {
    linux  /boot/vmlinuz quiet
    initrd /boot/nbinit4.gz
}

menuentry "Boot from hard disk" {
    exit
}
EOF

grub-mkstandalone \
    -O x86_64-efi \
    -d "$GRUB_MODULES_DIR" \
    --modules="iso9660 linux search search_fs_file normal configfile \
               fat part_gpt part_msdos all_video gfxterm font \
               boot echo halt reboot ls cat" \
    --locales="" \
    --themes="" \
    -o "${WORK}/efifiles/EFI/BOOT/BOOTx64.EFI" \
    "boot/grub/grub.cfg=${WORK}/grub-full.cfg"

# Size the FAT image from the actual EFI binary with headroom
EFI_SIZE=$(du -m "${WORK}/efifiles/EFI/BOOT/BOOTx64.EFI" | cut -f1)
IMG_SIZE=$(( EFI_SIZE + 8 ))
[ "$IMG_SIZE" -lt 16 ] && IMG_SIZE=16
dd if=/dev/zero of="${WORK}/efiboot.img" bs=1M count="${IMG_SIZE}"
mkfs.vfat -F 16 "${WORK}/efiboot.img"
mcopy -i "${WORK}/efiboot.img" -s "${WORK}/efifiles/EFI" ::/EFI
cp "${WORK}/efiboot.img" "${WORK}/iso/efiboot.img"
# Also copy the EFI tree into the ISO filesystem so that Windows-based USB
# preparation tools (which copy the filesystem rather than writing a raw image)
# end up with a UEFI-bootable stick.
cp -r "${WORK}/efifiles/EFI" "${WORK}/iso/"

# --- Build hybrid ISO (BIOS El Torito + UEFI El Torito) ---
# xorriso marks the alt-boot entry as EFI automatically and writes a proper
# GPT EFI System Partition entry; genisoimage/mkisofs do not set platform
# ID 0xEF, so UEFI firmware skips those entries.
xorriso -as mkisofs \
    -r -J -l \
    -b boot/isolinux/isolinux.bin \
    -c boot/isolinux/boot.cat \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
    -eltorito-alt-boot \
    -e efiboot.img \
    -no-emul-boot \
    -isohybrid-gpt-basdat \
    -o "${DONE}/NetbootCD-Neo-$NBCDVER.iso" \
    "${WORK}/iso"


# --- Build wireless initrd ---
echo "Building wireless initrd..."
cp -a "${NBINIT}" "${WORK}/nbinit-wifi"
# lib/firmware in corepure64 is a symlink: lib/firmware -> ../usr/local/lib/firmware
# That target directory does not exist in the base image, so the symlink is
# dangling.  Create the target so the symlink resolves; firmware TCZ packages
# install to usr/local/lib/firmware/ and will then be reachable at lib/firmware/
# where the kernel firmware loader expects them.
mkdir -p "${WORK}/nbinit-wifi/usr/local/lib/firmware"
if [ -e squashfs-root ]; then rm -r squashfs-root; fi
for pkg in $WIFI_PKGS_ALL; do
    if [ -s "${pkg}-x86_64.tcz" ]; then
        unsquashfs "${pkg}-x86_64.tcz"
        tar -C squashfs-root -c . | tar -C "${WORK}/nbinit-wifi" -x
        rm -r squashfs-root
    fi
done

# --- Fix wireless module visibility and regulatory database ---
# wireless-regdb installs regulatory.db to /usr/local/share/wireless-regdb/files/
# but cfg80211 loads it via the kernel firmware API, which searches /lib/firmware/.
REGDB="${WORK}/nbinit-wifi/usr/local/share/wireless-regdb/files/regulatory.db"
[ -f "$REGDB" ] && cp "$REGDB" "${WORK}/nbinit-wifi/lib/firmware/regulatory.db"

# Build-time depmod cannot follow kernel.tclocal because that symlink has an
# absolute target (/usr/local/lib/modules/…) that doesn't exist on the build
# host.  Instead we run depmod -a inside bootsync.sh, which executes
# synchronously during the TinyCore boot, where the symlink resolves correctly
# to the wireless TCZ content at /usr/local/lib/modules/.
#
# After depmod rebuilds modules.alias we replay hardware events with
# "udevadm trigger" so udev's MODALIAS rule (modprobe -bv $MODALIAS) picks up
# the newly indexed drivers, then "udevadm settle" blocks until every queued
# event — including driver loads — has finished.  All interfaces are therefore
# present before the user reaches the netboot menu.
cat > "${WORK}/nbinit-wifi/opt/bootsync.sh" << 'BOOTSYNC'
#!/bin/sh
/usr/bin/sethostname box
depmod -a 2>/dev/null || true
# TCZ packages install libraries to /usr/local/lib which ldconfig doesn't
# search by default.  Register it so every TCZ binary can find its libs.
mkdir -p /etc/ld.so.conf.d
echo '/usr/local/lib' > /etc/ld.so.conf.d/usrlocal.conf
ldconfig 2>/dev/null || true
udevadm trigger --action=add 2>/dev/null
udevadm settle --timeout=15 2>/dev/null || true
/opt/bootlocal.sh &
BOOTSYNC
chmod +x "${WORK}/nbinit-wifi/opt/bootsync.sh"

cd "${WORK}/nbinit-wifi"
find . | cpio -o -H 'newc' | gzip -c > "${DONE}/nbinit4-wifi.gz"
cd -
echo "Made wireless initrd: $(wc -c < "${DONE}/nbinit4-wifi.gz") bytes"

# Swap initrd in the ISO tree and rebuild for the wireless variant.
# The EFI binary is reused as-is since grub.cfg references /boot/nbinit4.gz
# by the same path in both ISOs.
cp "${DONE}/nbinit4-wifi.gz" "${WORK}/iso/boot/nbinit4.gz"
xorriso -as mkisofs \
    -r -J -l \
    -b boot/isolinux/isolinux.bin \
    -c boot/isolinux/boot.cat \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
    -eltorito-alt-boot \
    -e efiboot.img \
    -no-emul-boot \
    -isohybrid-gpt-basdat \
    -o "${DONE}/NetbootCD-Neo-$NBCDVER-wifi.iso" \
    "${WORK}/iso"

chown -R 1000:1000 "${DONE}"

echo ""
echo "Build complete!"
echo "  Base ISO:     ${DONE}/NetbootCD-Neo-$NBCDVER.iso"
echo "  Wireless ISO: ${DONE}/NetbootCD-Neo-$NBCDVER-wifi.iso"
