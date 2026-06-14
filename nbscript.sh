#!/bin/sh
set -e
## nbscript.sh - Download netboot images and launch them with kexec
## Copyright (C) 2022-2025 Isaac Schemm <isaacschemm@gmail.com>
## Devuan and Arch added by Jonathan A. Wingo Oct 2022 <spcwingo1@gmail.com>
## Edited by Jonathan A. Wingo to support x86_64 only in both
## BIOS or UEFI mode.
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
## <http://www.gnu.org/copyleft/gpl.html>, on the NetbootCD site at
## <http://netbootcd.tuxfamily.org>, or on the CD itself.

PATH=/usr/local/sbin:/usr/local/bin:$PATH
export PATH
export LD_LIBRARY_PATH=/usr/local/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}

TITLE="NetbootCD-Neo Script 17.2 - June 10, 2026"

EFIMODE=0
[ -d /sys/firmware/efi ] && EFIMODE=1

# TinyCore has no CA store; retry transient TLS/download failures.
WGET="wget --no-check-certificate --tries=3"
NBSCRIPT_UPDATE_URL="https://raw.githubusercontent.com/spcwingo/netbootcd-neo/refs/heads/main/nbscript.sh"

getversion ()
{
	VERSION=$(cat /tmp/nb-version)
	if [ "$VERSION" = "Manual" ]; then
		printf 'Version (codename for Debian/Ubuntu, number for others): '
		read -r VERSION
		if [ -z "$VERSION" ]; then rm -f /tmp/nb-version; return 1; fi
	fi
	rm /tmp/nb-version
}

getisourl ()
{
	ISODEFAULT="$1"
	ISOLABEL="${2:-Ubuntu live ISO}"
	ISOURL=

	if dialog --backtitle "$TITLE" --yesno \
		"Use this $ISOLABEL?\n\n$ISODEFAULT" 10 70; then
		ISOURL="$ISODEFAULT"
	else
		_rc=$?
		[ "$_rc" -eq 1 ] || return 1
		printf 'URL for the %s [%s]: ' "$ISOLABEL" "$ISODEFAULT"
		read -r ISOURL
		ISOURL="${ISOURL:-$ISODEFAULT}"
	fi

	[ -n "$ISOURL" ]
}

ubuntu_live_iso ()
{
	KERNELURL="$1"
	INITRDURL="$2"
	getisourl "$3" "$4" || return 1
	printf '%s' "root=/dev/ram0 ramdisk_size=3500000 ip=dhcp url=$ISOURL cloud-config-url=/dev/null ---" >>/tmp/nb-options
}

ubuntu_live_server ()
{
	ubuntu_live_iso "$1" "$2" "$3" "Ubuntu live-server ISO"
}

ubuntu_casper_iso_setup ()
{
	DEBIAN_LIVE_LABEL="$1"
	DEBIAN_LIVE_ISO_URL="$2"
	DEBIAN_LIVE_BOOT_URL="${4:-$2}"
	DEBIAN_LIVE_MODE=casper-url
	DEBIAN_LIVE_KERNEL_PATHS="casper/vmlinuz casper/vmlinuz.efi live/vmlinuz boot/vmlinuz boot/vmlinuz-*"
	DEBIAN_LIVE_INITRD_PATHS="casper/initrd casper/initrd.lz casper/initrd.img casper/initrd.gz casper/initrd.zst casper/initrd.zstd live/initrd live/initrd.lz live/initrd.img live/initrd.gz live/initrd.zst live/initrd.zstd boot/initrd boot/initrd.lz boot/initrd.img boot/initrd.gz boot/initrd.zst boot/initrd.zstd"
	DEBIAN_LIVE_EMBED_ROOTFS_ALIAS_PATH=
	DEBIAN_LIVE_EXTRA_ROOTFS_PATHS=
	printf '%s' "ip=dhcp boot=casper netboot=url url=$DEBIAN_LIVE_BOOT_URL iso-url=$DEBIAN_LIVE_BOOT_URL noprompt noeject $3 " >>/tmp/nb-options
}

dracut_live_iso_setup ()
{
	DEBIAN_LIVE_LABEL="$1"
	DEBIAN_LIVE_ISO_URL="$2"
	DEBIAN_LIVE_BOOT_URL="$2"
	DEBIAN_LIVE_MODE=embed
	DEBIAN_LIVE_KERNEL_PATHS="images/pxeboot/vmlinuz boot/x86_64/loader/linux isolinux/vmlinuz isolinux/vmlinuz0 boot/kernel boot/vmlinuz boot/vmlinuz-*"
	DEBIAN_LIVE_INITRD_PATHS="images/pxeboot/initrd.img boot/x86_64/loader/initrd isolinux/initrd.img isolinux/initrd0.img boot/initramfs.img boot/initrd.img boot/initrd boot/initrd-*"
	DEBIAN_LIVE_ROOTFS_PATHS="LiveOS/squashfs.img"
	DEBIAN_LIVE_EMBED_ROOTFS_PATH="LiveOS/squashfs.img"
	DEBIAN_LIVE_EMBED_ROOTFS_ALIAS_PATH=
	DEBIAN_LIVE_EXTRA_ROOTFS_PATHS=
	printf '%s' "root=live:/LiveOS/squashfs.img ro rd.live.image rd.live.overlay.overlayfs=1 rd.luks=0 rd.md=0 rd.dm=0 $3 " >>/tmp/nb-options
}

gobolinux_iso_setup ()
{
	DEBIAN_LIVE_LABEL="GoboLinux 017.01"
	DEBIAN_LIVE_ISO_URL="https://gobolinux.neonsys.org/017.01-ISO/GoboLinux-017.01-x86_64.iso"
	DEBIAN_LIVE_BOOT_URL="$DEBIAN_LIVE_ISO_URL"
	DEBIAN_LIVE_MODE=embed
	DEBIAN_LIVE_KERNEL_PATHS="isolinux/kernel"
	DEBIAN_LIVE_INITRD_PATHS="isolinux/initramfs"
	DEBIAN_LIVE_ROOTFS_PATHS="gobolinux-live.squashfs"
	DEBIAN_LIVE_EMBED_ROOTFS_PATH="gobolinux-live.img"
	DEBIAN_LIVE_EMBED_ROOTFS_ALIAS_PATH=
	DEBIAN_LIVE_EXTRA_ROOTFS_PATHS=
	printf '%s' "root=live:/gobolinux-live.img Boot=LiveCD vt.default_utf8=1 audit=0 rd.live.image rd.live.dir=/ rd.live.squashimg=gobolinux-live.img rd.live.overlay.overlayfs rd.luks=0 rd.lvm=0 rd.md=0 rd.dm=0 rd.live.ram=0 " >>/tmp/nb-options
}

adelie_iso_setup ()
{
	DEBIAN_LIVE_LABEL="Adelie Linux 1.0-beta6 Installer"
	DEBIAN_LIVE_ISO_URL="https://distfiles.adelielinux.org/adelie/1.0-beta6/iso/adelie-inst-x86_64-1.0-beta6-20241223.iso"
	DEBIAN_LIVE_BOOT_URL="$DEBIAN_LIVE_ISO_URL"
	DEBIAN_LIVE_MODE=embed
	DEBIAN_LIVE_KERNEL_PATHS="kernel-x86_64"
	DEBIAN_LIVE_INITRD_PATHS="initrd-x86_64"
	DEBIAN_LIVE_ROOTFS_PATHS="x86_64.squashfs"
	DEBIAN_LIVE_EMBED_ROOTFS_PATH="x86_64.img"
	DEBIAN_LIVE_EMBED_ROOTFS_ALIAS_PATH=
	DEBIAN_LIVE_EXTRA_ROOTFS_PATHS=
	printf '%s' "root=live:/x86_64.img ro rd.live.overlay.overlayfs=1 softlevel=graphical " >>/tmp/nb-options
}

pika_iso_setup ()
{
	PIKA_LABEL="$1"
	PIKA_ISO_URL="$2"
	PIKA_ISO_FILE="$3"
	PIKA_ISO_VOLUME="$4"
	printf '%s' "VTOY_ISO_NAME=$PIKA_ISO_FILE ISO_LABEL_NAME=\"$PIKA_ISO_VOLUME\" boot=live booster.loadcdrom booster.skiproot " >>/tmp/nb-options
}

porteux_iso_setup ()
{
	PORTEUX_LABEL="$1"
	PORTEUX_ISO_URL="$2"
	PORTEUX_KERNEL_PATH="$3"
	PORTEUX_INITRD_PATH="$4"
	printf '%s' "$5 " >>/tmp/nb-options
}

porteus_iso_setup ()
{
	PORTEUS_LABEL="$1"
	PORTEUS_ISO_URL="$2"
	PORTEUS_KERNEL_PATH="$3"
	PORTEUS_INITRD_PATH="$4"
	printf '%s' "$5 " >>/tmp/nb-options
}

nemesis_iso_setup ()
{
	NEMESIS_LABEL="$1"
	NEMESIS_ISO_URL="$2"
	NEMESIS_KERNEL_PATH="$3"
	NEMESIS_INITRD_PATH="$4"
	printf '%s' "$5 " >>/tmp/nb-options
}

chimera_iso_setup ()
{
	CHIMERA_LABEL="$1"
	CHIMERA_ISO_URL="$2"
	CHIMERA_KERNEL_PATH="$3"
	CHIMERA_INITRD_PATH="$4"
	printf '%s' "boot=live live-media=CHIMERA_LIVE fromiso=/.netbootcd/chimera.iso dinit_skip_volumes init=/usr/bin/init loglevel=4 " >>/tmp/nb-options
}

coyote_iso_setup ()
{
	COYOTE_LABEL="$1"
	COYOTE_ISO_URL="$2"
	COYOTE_KERNEL_PATH="$3"
	COYOTE_INITRD_PATH="$4"
	printf '%s' "console=tty0 quiet installer " >>/tmp/nb-options
}

nutyx_iso_setup ()
{
	NUTYX_LABEL="$1"
	NUTYX_ISO_URL="$2"
	NUTYX_KERNEL_PATH="$3"
	NUTYX_INITRD_PATH="$4"
	NUTYX_ROOTFS_PATH="$5"
	printf '%s' "ro quiet rootdelay=5 live " >>/tmp/nb-options
}

salix_iso_setup ()
{
	SALIX_LABEL="$1"
	SALIX_ISO_URL="$2"
	SALIX_KERNEL_PATH="$3"
	SALIX_INITRD_PATH="$4"
	printf '%s' "$5 " >>/tmp/nb-options
}

venom_iso_setup ()
{
	VENOM_LABEL="$1"
	VENOM_ISO_URL="$2"
	VENOM_KERNEL_PATH="$3"
	VENOM_INITRD_PATH="$4"
	printf '%s' "ro quiet wait=15 " >>/tmp/nb-options
}

daphile_iso_setup ()
{
	DAPHILE_LABEL="$1"
	DAPHILE_ISO_URL="$2"
	DAPHILE_KERNEL_PATH="$3"
	DAPHILE_INITRD_PATH="$4"
	DAPHILE_ROOTFS_PATH="$5"
	DAPHILE_VERSION_DIR="$6"
	printf '%s' "daphile=$DAPHILE_VERSION_DIR vga=788 splash quiet panic=1 console=tty2 vt.global_cursor_default=0 i915.enable_fbc=0 threadirqs live " >>/tmp/nb-options
}

berry_iso_setup ()
{
	BERRY_LABEL="Berry Linux 1.42"
	BERRY_ISO_URL="http://master.dl.sourceforge.net/project/berryos/Berry%20Linux/1.42/berry-1.42.iso?viasf=1"
	BERRY_KERNEL_PATH="Setup/vmlinuz"
	BERRY_INITRD_PATH="Setup/initrd.gz"
	BERRY_ROOTFS_PATH="BERRY/BERRY"
	printf '%s' "quiet console=tty2 audit=0 rootwait ro noresume noswap boot=cdrom berry_dir=/BERRY/BERRY overlay=ram lang=us autologin clocksource=tsc nopti noibrs noibpb nospectre_v2 nospec_store_bypass_disable " >>/tmp/nb-options
}

berry_extract_boot_file ()
{
	_berry_iso="$1"
	_berry_out="$2"
	_berry_desc="$3"
	_berry_path="$4"
	_berry_extract_dir="${_berry_out%/*}/nb-berry-extract"

	rm -rf "$_berry_extract_dir"
	mkdir -p "$_berry_extract_dir"
	if ! "$BERRY_7Z" e -y -o"$_berry_extract_dir" "$_berry_iso" "$_berry_path" >/tmp/nb-berry-7z.log 2>&1; then
		nb_error "Could not extract $_berry_desc from the $BERRY_LABEL ISO.\nSee /tmp/nb-berry-7z.log for details."
		rm -rf "$_berry_extract_dir"
		return 1
	fi
	_berry_found=
	for _berry_candidate in "$_berry_extract_dir"/*; do
		[ -f "$_berry_candidate" ] || continue
		[ -s "$_berry_candidate" ] || continue
		_berry_found="$_berry_candidate"
		break
	done
	if [ -z "$_berry_found" ]; then
		nb_error "Could not extract $_berry_desc from the $BERRY_LABEL ISO.\nSee /tmp/nb-berry-7z.log for details."
		rm -rf "$_berry_extract_dir"
		return 1
	fi
	mv "$_berry_found" "$_berry_out"
	rm -rf "$_berry_extract_dir"
	return 0
}

community_live_iso_setup ()
{
	_community_live_tag="$1"

	case "$_community_live_tag" in
		adelie-inst-beta6)
			adelie_iso_setup || return
			;;
		acreetionos-cinnamon-10)
			archiso_live_iso_setup \
				"AcreetionOS 1.0 Cinnamon" \
				"https://ftp2.osuosl.org/pub/acreetionos/AcreetionOS-1.0-x86_64.iso" \
				"arch/boot/x86_64/vmlinuz-linux" \
				"arch/boot/x86_64/initramfs-linux.img" \
				"arch/x86_64/airootfs.sfs" \
				"arch/x86_64/airootfs.sha512" \
				"archisobasedir=arch arch=x86_64 copytoram=n checksum=n cow_spacesize=10G module_blacklist=pcspkr nvme_load=yes" || return
			;;
		bredos-20251027)
			archiso_live_iso_setup \
				"BredOS 2025.10.27" \
				"https://github.com/BredOS/BredOS-iso/releases/download/2025-10-27/BredOS-2025.10.27-x86_64.iso" \
				"arch/boot/x86_64/vmlinuz-linux" \
				"arch/boot/x86_64/initramfs-linux.img" \
				"arch/x86_64/airootfs.sfs" \
				"arch/x86_64/airootfs.sha512" \
				"archisobasedir=arch arch=x86_64 copytoram=n checksum=n cow_spacesize=10G nvme_load=yes i915.modeset=1 radeon.modeset=1 nouveau.modeset=1 nvidia-drm.modeset=0 module_blacklist=pcspkr,nvidia,nvidia_uvm,nvidia_drm,nvidia_modeset" || return
			;;
		berry-142)
			berry_iso_setup || return
			;;
		ditana-09-beta)
			archiso_live_iso_setup \
				"Ditana GNU/Linux 0.9 Beta" \
				"https://ditana.org/downloads/Ditana-0.9.0-Beta-x86_64.iso" \
				"ditana/boot/x86_64/vmlinuz-linux" \
				"ditana/boot/x86_64/initramfs-linux.img" \
				"ditana/x86_64/airootfs.sfs" \
				"ditana/x86_64/airootfs.sha512" \
				"archisobasedir=ditana arch=x86_64 copytoram=n checksum=n cow_spacesize=10G module_blacklist=pcspkr nvme_load=yes" || return
			;;
		endeavouros-titan-neo-20260427)
			archiso_live_iso_setup \
				"EndeavourOS Titan Neo 2026.04.27" \
				"https://mirrors.gigenet.com/endeavouros/iso/EndeavourOS_Titan-Neo-2026.04.27.iso" \
				"arch/boot/x86_64/vmlinuz-linux" \
				"arch/boot/x86_64/initramfs-linux.img" \
				"arch/x86_64/airootfs.sfs" \
				"arch/x86_64/airootfs.sha512" \
				"archisobasedir=arch arch=x86_64 copytoram=n checksum=n cow_spacesize=10G module_blacklist=pcspkr nvme_load=yes" || return
			;;
		garuda-kde-lite-latest)
			garuda_iso_setup \
				"Garuda KDE Lite latest" \
				"https://iso.builds.garudalinux.org/iso/latest/garuda/kde-lite/latest.iso" \
				"boot/vmlinuz-x86_64" \
				"boot/initramfs-x86_64.img" \
				"garuda" \
				"x86_64" || return
			;;
		fatdog64-903)
			iso_boot_setup \
				"https://distro.ibiblio.org/fatdog/iso/Fatdog64-903.iso" \
				"Fatdog64 903" \
				"vmlinuz" \
				"initrd"
			printf '%s' "rootfstype=ramfs savefile=none " >>/tmp/nb-options
			;;
		cachyos-desktop-260426)
			archiso_live_iso_setup \
				"CachyOS Desktop 260426" \
				"https://build.cachyos.org/ISO/desktop/260426/cachyos-desktop-linux-260426.iso" \
				"arch/boot/x86_64/vmlinuz-linux-cachyos" \
				"arch/boot/x86_64/initramfs-linux-cachyos.img" \
				"arch/x86_64/airootfs.sfs" \
				"arch/x86_64/airootfs.sha512" \
				"archisobasedir=arch arch=x86_64 copytoram=n checksum=n cow_spacesize=10G module_blacklist=pcspkr nvme_load=yes" || return
			;;
		keskos-layer-v3)
			archiso_live_iso_setup \
				"KeskOS Layer v3" \
				"https://downloads.keskos.org/release/layer-v3/keskos-layer-v3.iso" \
				"keskos/boot/x86_64/vmlinuz-linux" \
				"keskos/boot/x86_64/initramfs-linux.img" \
				"keskos/x86_64/airootfs.erofs" \
				"keskos/x86_64/airootfs.sha512" \
				"archisobasedir=keskos arch=x86_64 copytoram=n checksum=n cow_spacesize=10G" || return
			;;
		pikaos-gnome)
			pika_iso_setup \
				"PikaOS GNOME 4.0" \
				"https://iso.pika-os.com/PikaOS-Nest-GNOME-4.0-amd64-v3-26.04.04-1.iso" \
				"PikaOS-Nest-GNOME-4.0-amd64-v3-26.04.04-1.iso" \
				"PGN 26.04.04 1" || return
			;;
		pikaos-kde)
			pika_iso_setup \
				"PikaOS KDE 4.0" \
				"https://iso.pika-os.com/PikaOS-Nest-KDE-4.0-amd64-v3-26.04.04-1.iso" \
				"PikaOS-Nest-KDE-4.0-amd64-v3-26.04.04-1.iso" \
				"PKD 26.04.04 1" || return
			;;
		pikaos-hyprland)
			pika_iso_setup \
				"PikaOS Hyprland 4.0" \
				"https://iso.pika-os.com/PikaOS-Nest-Hyprland-4.0-amd64-v3-26.04.04-1.iso" \
				"PikaOS-Nest-Hyprland-4.0-amd64-v3-26.04.04-1.iso" \
				"PHL 26.04.04 1" || return
			;;
		pikaos-niri)
			pika_iso_setup \
				"PikaOS Niri 4.0" \
				"https://iso.pika-os.com/PikaOS-Nest-Niri-4.0-amd64-v3-26.04.04-1.iso" \
				"PikaOS-Nest-Niri-4.0-amd64-v3-26.04.04-1.iso" \
				"PNI 26.04.04 1" || return
			;;
		pikaos-cosmic)
			pika_iso_setup \
				"PikaOS COSMIC 4.0" \
				"https://iso.pika-os.com/PikaOS-Nest-COSMIC-4.0-amd64-v3-26.04.04-1.iso" \
				"PikaOS-Nest-COSMIC-4.0-amd64-v3-26.04.04-1.iso" \
				"PSC 26.04.04 1" || return
			;;
		prismlinux-20260505)
			archiso_live_iso_setup \
				"PrismLinux 2026.05.05" \
				"https://repository.prismlinux.org/ISO/2026.05.05/PrismLinux-Desktop-2026.05.05-x86_64.iso" \
				"prismlinux/boot/x86_64/vmlinuz-linux-lts" \
				"prismlinux/boot/x86_64/initramfs-linux-lts.img" \
				"prismlinux/x86_64/airootfs.sfs" \
				"prismlinux/x86_64/airootfs.sha512" \
				"archisobasedir=prismlinux arch=x86_64 copytoram=n checksum=n cow_spacesize=10G module_blacklist=pcspkr nvme_load=yes nvidia-drm.modeset=1" || return
			;;
		rebornos-20260122)
			archiso_live_iso_setup \
				"RebornOS 2026.01.22" \
				"https://cdn.soulharsh007.dev/RebornOS-ISO/rebornos_iso-2026.01.22-x86_64.iso" \
				"arch/boot/x86_64/vmlinuz-linux" \
				"arch/boot/x86_64/initramfs-linux.img" \
				"arch/x86_64/airootfs.sfs" \
				"arch/x86_64/airootfs.sha512" \
				"archisobasedir=arch arch=x86_64 copytoram=n checksum=n cow_spacesize=10G module_blacklist=pcspkr nvme_load=yes" || return
			;;
		solus-xfce)
			dracut_live_iso_setup \
				"Solus Xfce 2026-04-18" \
				"https://downloads.getsol.us/isos/2026-04-18/Solus-Xfce-Release-2026-04-18.iso" \
				"quiet splash" || return
			;;
		mocaccino-kde-20260505)
			mocaccino_live_iso_setup \
				"MocaccinoOS KDE 0.20260505" \
				"http://downloads.sourceforge.net/project/mocaccino/v26.05/MocaccinoOS-KDE-0.20260505.iso" \
				"boot/kernel.xz" \
				"boot/rootfs.xz" \
				"rootfs.squashfs" || return
			;;
		puppy-bookwormpup64)
			puppy_iso_setup \
				"BookwormPup64 10.0.12" \
				"https://distro.ibiblio.org/puppylinux/puppy-bookwormpup/BookwormPup64/10.0.12/BookwormPup64_10.0.12.iso" \
				"vmlinuz" \
				"initrd.gz" \
				"puppy_dpupbw64_10.0.12.sfs" \
				"zdrv_dpupbw64_10.0.12.sfs" \
				"fdrv_dpupbw64_10.0.12.sfs" \
				"adrv_dpupbw64_10.0.12.sfs" \
				"bdrv_dpupbw64_10.0.12.sfs" || return
			;;
		puppy-trixiepup64-legacy-114)
			puppy_iso_setup \
				"TrixiePup64 Legacy 11.4" \
				"https://distro.ibiblio.org/puppylinux/puppy-trixie/TrixiePup64/11.4/legacy/Trixiepup64_Legacy-11.4.iso" \
				"vmlinuz" \
				"initrd.gz" \
				"puppy_trixiepup64_11.4.sfs" \
				"zdrv_trixiepup64_11.4.sfs" \
				"fdrv_trixiepup64_11.4.sfs" \
				"adrv_trixiepup64_11.4.sfs" \
				"bdrv_trixiepup64_11.4.sfs" || return
			;;
		easyos-excalibur)
			easyos_img_setup \
				"EasyOS Excalibur 7.3.8" \
				"https://distro.ibiblio.org/easyos/amd64/releases/excalibur/2026/7.3.8/easy-7.3.8-amd64.img" \
				"easyos/vmlinuz" \
				"easyos/initrd" \
				"1.img" \
				"af274dcb-219b-4746-ba5d-78e6bf358770" \
				"easyos/" \
				"easyos2" || return
			;;
		gobolinux-01701)
			gobolinux_iso_setup || return
			;;
		hyperbola-milky-way-044)
			hyperbola_iso_setup \
				"Hyperbola GNU/Linux-libre Milky Way 0.4.4" \
				"https://repo.hyperbola.info:50000/other/live_images/gnu-plus-linux-libre/hyperbola-milky-way-v0.4.4/hyperbola-milky-way-v0.4.4-dual.iso" \
				"hyperbola/boot/x86_64/vmlinuz" \
				"hyperbola/boot/x86_64/initramfs-hyperiso.img" \
				"hyperbola/x86_64/root-image.fs.sfs" \
				"hyperbola/aitab" \
				"hyperisobasedir=hyperbola hyperisolabel=HYPER_v044 arch=x86_64 copytoram=n checksum=n cowspace_size=50%" || return
			;;
		libreelec-generic)
			libreelec_img_setup \
				"LibreELEC Generic x86_64 12.2.1" \
				"https://releases.libreelec.tv/LibreELEC-Generic.x86_64-12.2.1.img.gz" \
				"https://raw.githubusercontent.com/LibreELEC/LibreELEC.tv/12.2.1/packages/sysutils/busybox/scripts/init" || return
			;;
		nutyx-xfce-260403)
			nutyx_iso_setup \
				"NuTyX 26.04.3 Xfce" \
				"http://downloads.sourceforge.net/project/nutyx/ISOs/NuTyX_x86_64-26.04.3-XFCE4.iso" \
				"boot/kernel-618" \
				"boot/initrd-618" \
				"boot/NuTyX.squashfs" || return
			;;
		obarun-minimal-20260430)
			archiso_live_iso_setup \
				"Obarun Minimal 2026.04.30" \
				"https://cloud.server.obarun.org/iso/2026.04.30/obarun-2026.04.30-x86_64.iso" \
				"arch/boot/x86_64/vmlinuz" \
				"arch/boot/x86_64/archiso.img" \
				"arch/x86_64/airootfs.sfs" \
				"arch/x86_64/airootfs.md5" \
				"archisobasedir=arch arch=x86_64 copytoram=n checksum=n cow_spacesize=4G" || return
			;;
		parabola-cli-202204)
			parabola_iso_setup \
				"Parabola GNU/Linux-libre 2022.04 CLI netinstall" \
				"http://mirror.math.princeton.edu/pub/parabola/iso/x86_64-systemd-cli-2022.04/parabola-x86_64-systemd-cli-2022.04-netinstall.iso" \
				"parabola/boot/x86_64/vmlinuz" \
				"parabola/boot/x86_64/parabolaiso.img" \
				"parabola/x86_64/root-image.fs.sfs" \
				"parabola/aitab" \
				"parabolaisobasedir=parabola parabolaisolabel=PARA_202205 arch=x86_64 copytoram=n checksum=n cowspace_size=50%" || return
			;;
		salixlive-xfce-150)
			salix_iso_setup \
				"SalixLive64 Xfce 15.0" \
				"http://phoenixnap.dl.sourceforge.net/project/salix/15.0/salixlive64-xfce-15.0.iso" \
				"boot/vmlinuz" \
				"boot/initrd.gz" \
				"max_loop=255 vga=791 locale=en_US.utf8 keymap=us useswap=no copy2ram=no tz=Etc/GMT hwc=localtime runlevel=4" || return
			;;
		slackel-openbox-80)
			salix_iso_setup \
				"Slackel 8.0 Openbox" \
				"https://downloads.sourceforge.net/project/slackel/openbox/slackellive64-openbox-8.0.iso" \
				"boot/vmlinuz" \
				"boot/initrd.gz" \
				"max_loop=255 vga=791 locale=en_US.utf8 keymap=us useswap=no copy2ram=no tz=Etc/GMT hwc=localtime runlevel=4" || return
			;;
		sdesk-quartz-202510)
			archiso_live_iso_setup \
				"SDesk Quartz 2025.10" \
				"https://stevestudios.net/wp-content/uploads/2025/10/sdesk-2025.10.17-quartz-x86_64.iso" \
				"sdesk/boot/x86_64/vmlinuz-linux" \
				"sdesk/boot/x86_64/initramfs-linux.img" \
				"sdesk/x86_64/airootfs.sfs" \
				"sdesk/x86_64/airootfs.sha512" \
				"archisobasedir=sdesk arch=x86_64 copytoram=n checksum=n cow_spacesize=10G module_blacklist=pcspkr nvme_load=yes" || return
			;;
		venom-base-sysv-20260320)
			venom_iso_setup \
				"Venom Linux Base SysV 2026-03-20" \
				"http://master.dl.sourceforge.net/project/venomlinux/ISO/venomlinux-base-sysv-x86_64-20260320.iso?viasf=1" \
				"boot/vmlinuz" \
				"boot/initrd" || return
			;;
		porteux-lxde)
			porteux_iso_setup \
				"PorteuX 2.4 LXDE" \
				"https://github.com/porteux/porteux/releases/download/v2.4/porteux-2.4-current-lxde-0.11.1-x86_64.iso" \
				"boot/syslinux/vmlinuz" \
				"boot/syslinux/initrd.zst" \
				"kvm.enable_virt_at_load=0" || return
			;;
		porteus-xfce-501)
			porteus_iso_setup \
				"Porteus 5.01 Xfce" \
				"https://ftp.nluug.nl/os/Linux/distr/porteus/x86_64/current/Porteus-XFCE-v5.01-x86_64.iso" \
				"boot/syslinux/vmlinuz" \
				"boot/syslinux/initrd.xz" \
				"nomagic base_only norootcopy" || return
			;;
		nemesis-lxde-2510)
			nemesis_iso_setup \
				"Nemesis Linux 25.10 LXDE" \
				"https://phoenixnap.dl.sourceforge.net/project/nemesis-linux/ISO/25.10/Nemesis-v25.10-LXDE-x86_64.iso" \
				"boot/syslinux/vmlinuz" \
				"boot/syslinux/initrd.xz" \
				"nomagic base_only norootcopy" || return
			;;
		chimera-base)
			chimera_iso_setup \
				"Chimera Linux Base 2025-12-20" \
				"https://repo.chimera-linux.org/live/latest/chimera-linux-x86_64-LIVE-20251220-base.iso" \
				"live/vmlinuz" \
				"live/initrd" || return
			;;
		coyote-installer-40192)
			coyote_iso_setup \
				"Coyote Linux 4.0.192 Technology Preview" \
				"https://www.coyotelinux.com/files/coyote/coyote-installer-4.0.192.iso" \
				"boot/vmlinuz" \
				"boot/initramfs.gz" || return
			;;
		daphile-2505)
			daphile_iso_setup \
				"Daphile 25.05 x86_64" \
				"https://www.daphile.com/firmware/stable/daphile-25.05-x86_64.iso" \
				"boot/fw2505251549/kernel" \
				"boot/fw2505251549/initrd" \
				"boot/fw2505251549/rootfs" \
				"fw2505251549" || return
			;;
		*)
			nb_error "Unknown community live ISO entry: $_community_live_tag"
			return 1
			;;
	esac
}

nb_error ()
{
	dialog --backtitle "$TITLE" --msgbox "$1" 8 70 || true
}

downloadandrun ()
{
	_nbscript_url="$1"
	_nbscript_new="/tmp/nbscript-new.sh"
	rm -f "$_nbscript_new"
	if $WGET -O "$_nbscript_new" "$_nbscript_url"; then
		if [ ! -s "$_nbscript_new" ]; then
			rm -f "$_nbscript_new"
			nb_error "The downloaded NetbootCD-Neo script was empty.\n\nURL:\n$_nbscript_url"
			return 1
		fi
		if ! sh -n "$_nbscript_new" 2>/tmp/nbscript-new.err; then
			rm -f "$_nbscript_new"
			nb_error "The downloaded NetbootCD-Neo script did not pass a shell syntax check.\n\nURL:\n$_nbscript_url"
			return 1
		fi
		chmod 755 "$_nbscript_new"
		exec "$_nbscript_new"
	fi
	_nbscript_rc=$?
	rm -f "$_nbscript_new"
	nb_error "Downloading the newest NetbootCD-Neo script was not successful.\n\nURL:\n$_nbscript_url"
	return "$_nbscript_rc"
}


# --- POSIX initramfs helper functions ---

# Verify the decompressor for the given initramfs format is available.
# Args: format label
nb_initrd_need_tool ()
{
	_nb_nt_format="$1"
	_nb_nt_label="$2"
	case "$_nb_nt_format" in
		zstd)
			if ! command -v zstd >/dev/null 2>&1; then
				nb_error "$_nb_nt_label initramfs uses zstd compression, but zstd is not available."
				return 1
			fi
			;;
		xz)
			if ! command -v xz >/dev/null 2>&1; then
				nb_error "$_nb_nt_label initramfs uses xz compression, but xz is not available."
				return 1
			fi
			;;
	esac
}

# Unpack the main compressed archive from an initramfs image.
# Args: input_file work_dir format offset [cpio_flags] [log_file]
nb_initrd_unpack ()
{
	_nb_u_input="$1"
	_nb_u_work="$2"
	_nb_u_format="$3"
	_nb_u_offset="$4"
	_nb_u_cpio="${5:--idm}"
	_nb_u_log="${6:-/dev/null}"

	case "$_nb_u_format" in
		gzip)
			tail -c +"$(( _nb_u_offset + 1 ))" "$_nb_u_input" | gzip -cd | ( cd "$_nb_u_work" && cpio "$_nb_u_cpio" ) 2>"$_nb_u_log"
			;;
		zstd)
			tail -c +"$(( _nb_u_offset + 1 ))" "$_nb_u_input" | zstd -dc | ( cd "$_nb_u_work" && cpio "$_nb_u_cpio" ) 2>"$_nb_u_log"
			;;
		xz)
			tail -c +"$(( _nb_u_offset + 1 ))" "$_nb_u_input" | xz -dc | ( cd "$_nb_u_work" && cpio "$_nb_u_cpio" ) 2>"$_nb_u_log"
			;;
		cpio)
			tail -c +"$(( _nb_u_offset + 1 ))" "$_nb_u_input" | ( cd "$_nb_u_work" && cpio "$_nb_u_cpio" ) 2>"$_nb_u_log"
			;;
		*)
			return 1
			;;
	esac
}

# Repack an initramfs working directory into a compressed image.
# Args: work_dir output_file format [mode]
# Modes: standard (default), artix (gzip -c), fastxz (xz -0 -C crc32), nutyx (zstd -q -1 -c)
nb_initrd_repack ()
{
	_nb_r_work="$1"
	_nb_r_output="$2"
	_nb_r_format="$3"
	_nb_r_mode="${4:-standard}"

	case "$_nb_r_format" in
		gzip)
			case "$_nb_r_mode" in
				artix)
					( cd "$_nb_r_work" && find . | cpio -o -H newc | gzip -c >"$_nb_r_output" )
					;;
				*)
					( cd "$_nb_r_work" && find . | cpio -o -H newc | gzip -1 -c >"$_nb_r_output" )
					;;
			esac
			;;
		zstd)
			case "$_nb_r_mode" in
				nutyx)
					( cd "$_nb_r_work" && find . | cpio -o -H newc | zstd -q -1 -c >"$_nb_r_output" )
					;;
				*)
					( cd "$_nb_r_work" && find . | cpio -o -H newc | zstd -q -c >"$_nb_r_output" )
					;;
			esac
			;;
		xz)
			case "$_nb_r_mode" in
				fastxz)
					( cd "$_nb_r_work" && find . | cpio -o -H newc | xz -0 -C crc32 -c >"$_nb_r_output" )
					;;
				*)
					( cd "$_nb_r_work" && find . | cpio -o -H newc | xz --check=crc32 --lzma2=dict=1MiB -c >"$_nb_r_output" )
					;;
			esac
			;;
		cpio)
			( cd "$_nb_r_work" && find . | cpio -o -H newc >"$_nb_r_output" )
			;;
		*)
			return 1
			;;
	esac
}

# Preserve an early uncompressed initramfs prefix and append the repacked payload.
# Args: output_file input_file offset repacked_file
nb_initrd_prefix_append ()
{
	_nb_pa_output="$1"
	_nb_pa_input="$2"
	_nb_pa_offset="$3"
	_nb_pa_repacked="$4"

	: >"$_nb_pa_output"
	if [ "$_nb_pa_offset" -gt 0 ]; then
		if ! head -c "$_nb_pa_offset" "$_nb_pa_input" >>"$_nb_pa_output"; then
			return 1
		fi
	fi
	cat "$_nb_pa_repacked" >>"$_nb_pa_output"
}

debian_live_iso_setup ()
{
	_debian_live_tag="$1"
	DEBIAN_LIVE_ISO_URL=
	DEBIAN_LIVE_BOOT_URL=
	DEBIAN_LIVE_LABEL=
	DEBIAN_LIVE_MODE=fetch
	DEBIAN_LIVE_OPTIONS=
	DEBIAN_LIVE_KERNEL_PATHS="live/vmlinuz live/vmlinuz-* boot/vmlinuz boot/vmlinuz-*"
	DEBIAN_LIVE_INITRD_PATHS="live/initrd.img live/initrd live/initrd.gz live/initrd.lz live/initrd.xz live/initrd.zst live/initrd.zstd live/initrd.img-* live/initrd-* boot/initrd.img boot/initrd boot/initrd.gz boot/initrd.lz boot/initrd.xz boot/initrd.zst boot/initrd.zstd boot/initrd.img-* boot/initrd-*"
	DEBIAN_LIVE_ROOTFS_PATHS="live/filesystem.squashfs live/filesystem.squashfs-* live/*.squashfs"
	DEBIAN_LIVE_EMBED_ROOTFS_PATH="live/filesystem.squashfs"
	DEBIAN_LIVE_EMBED_ROOTFS_ALIAS_PATH=
	DEBIAN_LIVE_EXTRA_ROOTFS_PATHS=

	case "$_debian_live_tag" in
		butterbian-xfce)
			DEBIAN_LIVE_LABEL="Butterbian Xfce 0.2.1"
			DEBIAN_LIVE_ISO_URL="https://get.butterbian.org/butterbian-xfce-0.2.1-trixie-20260504.iso"
			DEBIAN_LIVE_OPTIONS="username=user hostname=butterbian"
			;;
		butterknife)
			DEBIAN_LIVE_LABEL="Butterknife 0.1.11"
			DEBIAN_LIVE_ISO_URL="https://get.butterbian.org/butterknife-0.1.11-trixie-20260504.iso"
			DEBIAN_LIVE_OPTIONS="username=user hostname=butterknife"
			;;
		bunsenlabs-carbon)
			DEBIAN_LIVE_LABEL="BunsenLabs Carbon 1"
			DEBIAN_LIVE_ISO_URL="http://ddl.bunsenlabs.org/ddl/carbon-1-260211-amd64.hybrid.iso"
			DEBIAN_LIVE_OPTIONS="username=user hostname=bunsenlabs"
			;;
		crunchbangplusplus-120)
			DEBIAN_LIVE_LABEL="CrunchBang++ 12.0"
			DEBIAN_LIVE_ISO_URL="https://github.com/CBPP/cbpp/releases/download/v12.0/cbpp-12.0-amd64-20230611.iso"
			DEBIAN_LIVE_OPTIONS="username=live hostname=crunchbangplusplus"
			;;
		crowz-openbox)
			DEBIAN_LIVE_LABEL="CROWZ 5.0.1 Openbox"
			DEBIAN_LIVE_ISO_URL="http://netactuate.dl.sourceforge.net/project/crowz/crowz-5.0.1-daedalus_2024.02-ob-amd64.iso?viasf=1&fid=c2b2d7d6505e5406"
			DEBIAN_LIVE_OPTIONS="username=user hostname=crowz"
			;;
		crowz-fluxbox)
			DEBIAN_LIVE_LABEL="CROWZ 5.0.1 Fluxbox"
			DEBIAN_LIVE_ISO_URL="http://cytranet.dl.sourceforge.net/project/crowz/crowz-5.0.1-daedalus_2024.02-fb-amd64.iso?viasf=1"
			DEBIAN_LIVE_OPTIONS="username=user hostname=crowz"
			;;
		crowz-jwm)
			DEBIAN_LIVE_LABEL="CROWZ 5.0.1 JWM"
			DEBIAN_LIVE_ISO_URL="http://cytranet.dl.sourceforge.net/project/crowz/crowz-5.0.1-daedalus_2024.02-jwm-amd64.iso?viasf=1&fid=9a1c076617cbd21c"
			DEBIAN_LIVE_OPTIONS="username=user hostname=crowz"
			;;
		besgnulinux-jwm)
			DEBIAN_LIVE_LABEL="Besgnulinux JWM 3.3"
			DEBIAN_LIVE_ISO_URL="http://downloads.sourceforge.net/project/besgnulinux/besgnulinux-jwm-3-3.iso"
			DEBIAN_LIVE_OPTIONS="username=besgnulinux hostname=besgnulinux"
			;;
		emmabuntus-de6-core)
			DEBIAN_LIVE_LABEL="Emmabuntus DE6 Core"
			DEBIAN_LIVE_ISO_URL="http://cfhcable.dl.sourceforge.net/project/emmabuntus/Emmabuntus_DE6/Images/1.01/emmabuntus-de6-core-amd64-13.4-1.01.iso?viasf=1&fid=d15787c9fd137e59"
			DEBIAN_LIVE_BOOT_URL="http://downloads.sourceforge.net/project/emmabuntus/Emmabuntus_DE6/Images/1.01/emmabuntus-de6-core-amd64-13.4-1.01.iso"
			DEBIAN_LIVE_OPTIONS="username=user hostname=emmabuntus"
			;;
		enux-533)
			DEBIAN_LIVE_LABEL="ENux 5.3.3 Xfce"
			DEBIAN_LIVE_ISO_URL="http://master.dl.sourceforge.net/project/enux/ENux-5.3.3/ENux-5.3.3.iso?viasf=1"
			DEBIAN_LIVE_OPTIONS="quiet nosplash"
			;;
		exegnu-daedalus)
			DEBIAN_LIVE_LABEL="Exe GNU/Linux Daedalus Trinity"
			DEBIAN_LIVE_ISO_URL="http://master.dl.sourceforge.net/project/exegnulinux/iso/daedalus/exegnu64_daedalus-20250511.iso?viasf=1"
			DEBIAN_LIVE_OPTIONS="username=user hostname=exegnu nocomponents=xinit locales=en_US.UTF-8"
			;;
		kanotix-towelfire-lxde)
			DEBIAN_LIVE_LABEL="KANOTIX Towelfire LXDE"
			DEBIAN_LIVE_ISO_URL="https://iso.kanotix.com/kanotix64-towelfire-nightly-LXDE.iso"
			DEBIAN_LIVE_OPTIONS="username=kanotix hostname=kanotix"
			;;
		lmde-7-cinnamon)
			DEBIAN_LIVE_LABEL="LMDE 7 Cinnamon"
			DEBIAN_LIVE_ISO_URL="http://mirrors.edge.kernel.org/linuxmint/debian/lmde-7-cinnamon-64bit.iso"
			DEBIAN_LIVE_OPTIONS="username=mint hostname=lmde"
			;;
		locos-24)
			DEBIAN_LIVE_LABEL="Loc-OS 24"
			DEBIAN_LIVE_ISO_URL="http://downloads.sourceforge.net/project/loc-os/Loc-OS%2024/Loc-OS-24-current_amd64.iso"
			DEBIAN_LIVE_OPTIONS="username=user hostname=loc-os"
			;;
		mauna-christian)
			DEBIAN_LIVE_LABEL="Mauna Linux 25.2 Christian Edition"
			DEBIAN_LIVE_ISO_URL="http://downloads.sourceforge.net/project/maunalinux/ISO/25.2/MaunaLinux-25.2-Christian-Edition-amd64.iso"
			DEBIAN_LIVE_OPTIONS="username=user hostname=mauna"
			;;
		minios-standard)
			DEBIAN_LIVE_LABEL="MiniOS 5.1.1 Standard"
			DEBIAN_LIVE_ISO_URL="https://github.com/minios-linux/minios-live/releases/download/v5.1.1/minios-trixie-xfce-standard-amd64-5.1.1.iso"
			DEBIAN_LIVE_MODE=minios-embed
			DEBIAN_LIVE_KERNEL_PATHS="minios/boot/vmlinuz minios/boot/vmlinuz-* boot/vmlinuz boot/vmlinuz-*"
			DEBIAN_LIVE_INITRD_PATHS="minios/boot/initrfs.img minios/boot/initrfs-*.img minios/boot/initrd.img minios/boot/initrd.img-* boot/initrd.img boot/initrd.img-*"
			DEBIAN_LIVE_OPTIONS="username=user hostname=minios"
			;;
		nakedeb-16)
			DEBIAN_LIVE_LABEL="nakeDeb 1.6"
			DEBIAN_LIVE_ISO_URL="https://nakedeb.arpinux.org/download/nakedeb-1.6-202603-amd64.iso"
			DEBIAN_LIVE_OPTIONS="username=human hostname=nakedeb"
			;;
		neptune-91)
			DEBIAN_LIVE_LABEL="Neptune 9.1"
			DEBIAN_LIVE_ISO_URL="https://download.neptuneos.com/download/Neptune9-20260314.iso"
			DEBIAN_LIVE_OPTIONS="username=user hostname=neptune"
			;;
		peppermint-trixie)
			DEBIAN_LIVE_LABEL="Peppermint OS Debian 64"
			DEBIAN_LIVE_ISO_URL="http://downloads.sourceforge.net/project/peppermintos/isos/XFCE/PeppermintOS-Debian-64.iso"
			DEBIAN_LIVE_OPTIONS="username=user hostname=peppermint"
			;;
		pureos-11-gnome)
			DEBIAN_LIVE_LABEL="PureOS 11 GNOME"
			DEBIAN_LIVE_ISO_URL="https://storage.puri.sm/pureos/images/crimson/2026.05/gnome/pureos-11-gnome-live-20260515_amd64.iso"
			DEBIAN_LIVE_MODE=casper-embed
			DEBIAN_LIVE_KERNEL_PATHS="casper/vmlinuz casper/vmlinuz.efi"
			DEBIAN_LIVE_INITRD_PATHS="casper/initrd.img casper/initrd casper/initrd.gz casper/initrd.lz casper/initrd.zst casper/initrd.zstd"
			DEBIAN_LIVE_ROOTFS_PATHS="casper/filesystem.squashfs"
			DEBIAN_LIVE_EMBED_ROOTFS_PATH="casper/filesystem.squashfs"
			DEBIAN_LIVE_OPTIONS="quiet splash username=pureos hostname=pureos"
			;;
		refracta-xfce)
			DEBIAN_LIVE_LABEL="Refracta 13.3 Xfce"
			DEBIAN_LIVE_ISO_URL="https://get.refracta.org/files/stable/refracta_13.3_xfce_amd64-20260501_1208.iso"
			DEBIAN_LIVE_OPTIONS="username=user hostname=refracta"
			;;
		refracta-nox)
			DEBIAN_LIVE_LABEL="Refracta 13.3 noX"
			DEBIAN_LIVE_ISO_URL="https://get.refracta.org/files/stable/refracta_13.3_nox_amd64-20260501_1521.iso"
			DEBIAN_LIVE_OPTIONS="username=user hostname=refracta"
			;;
		solydx-13)
			DEBIAN_LIVE_LABEL="SolydX 13"
			DEBIAN_LIVE_ISO_URL="http://ftp.nluug.nl/os/Linux/distr/solydxk/downloads/solydx_13_64_202512.iso"
			DEBIAN_LIVE_OPTIONS="username=solydxk hostname=solydx"
			;;
		sparky-lxqt-83)
			DEBIAN_LIVE_LABEL="SparkyLinux 8.3 LXQt"
			DEBIAN_LIVE_ISO_URL="http://downloads.sourceforge.net/project/sparkylinux/lxqt/sparkylinux-8.3-x86_64-lxqt.iso"
			DEBIAN_LIVE_OPTIONS="username=live hostname=sparky"
			;;
		sparky-xfce-831)
			DEBIAN_LIVE_LABEL="SparkyLinux 8.3.1 Xfce"
			DEBIAN_LIVE_ISO_URL="http://downloads.sourceforge.net/project/sparkylinux/xfce/sparkylinux-8.3.1-x86_64-xfce.iso"
			DEBIAN_LIVE_OPTIONS="username=live hostname=sparky"
			;;
		synex-icewm)
			DEBIAN_LIVE_LABEL="Synex 13 IceWM"
			DEBIAN_LIVE_ISO_URL="http://downloads.sourceforge.net/project/synex/Stable/ICEWM/synex-icewm-13-u8-amd64.hybrid.iso"
			DEBIAN_LIVE_OPTIONS="username=user hostname=synex"
			;;
		synex-lxde)
			DEBIAN_LIVE_LABEL="Synex 13 LXDE"
			DEBIAN_LIVE_ISO_URL="http://downloads.sourceforge.net/project/synex/Stable/LXDE/synex-lxde-13-u8-amd64.hybrid.iso"
			DEBIAN_LIVE_OPTIONS="username=user hostname=synex"
			;;
		synex-xfce)
			DEBIAN_LIVE_LABEL="Synex 13 Xfce"
			DEBIAN_LIVE_ISO_URL="http://downloads.sourceforge.net/project/synex/Stable/XFCE/synex-xfce-13-u8-amd64.hybrid.iso"
			DEBIAN_LIVE_OPTIONS="username=user hostname=synex"
			;;
		voyager-debian-133)
			DEBIAN_LIVE_LABEL="Voyager 13.3 Debian"
			DEBIAN_LIVE_ISO_URL="http://downloads.sourceforge.net/project/voyagerlive/Voyager-13.3-debian-amd64.iso"
			DEBIAN_LIVE_OPTIONS="username=user hostname=voyager"
			;;
		wattos-r13)
			DEBIAN_LIVE_LABEL="wattOS R13"
			DEBIAN_LIVE_ISO_URL="http://extantpc.com/iso/wattOS-R13.iso"
			DEBIAN_LIVE_OPTIONS="username=user hostname=wattos"
			;;
		*)
			nb_error "Unknown Debian-based live ISO entry: $_debian_live_tag"
			return 1
			;;
	esac

	[ -n "$DEBIAN_LIVE_BOOT_URL" ] || DEBIAN_LIVE_BOOT_URL="$DEBIAN_LIVE_ISO_URL"
	case "$_debian_live_tag" in
		crowz-*)
			DEBIAN_LIVE_MODE=embed
			if [ "$EFIMODE" = 1 ]; then
				DEBIAN_LIVE_OPTIONS="$DEBIAN_LIVE_OPTIONS modprobe.blacklist=video module_blacklist=video"
			fi
			;;
		crunchbangplusplus-*|enux-*|exegnu-*)
			DEBIAN_LIVE_MODE=embed
			;;
		refracta-*)
			DEBIAN_LIVE_MODE=embed
			;;
	esac

	if [ "$DEBIAN_LIVE_MODE" = "embed" ]; then
		printf '%s' "boot=live config components live-media=/ noeject noprompt $DEBIAN_LIVE_OPTIONS " >>/tmp/nb-options
	elif [ "$DEBIAN_LIVE_MODE" = "casper-embed" ]; then
		printf '%s' "boot=casper live-media=/ noeject noprompt $DEBIAN_LIVE_OPTIONS " >>/tmp/nb-options
	elif [ "$DEBIAN_LIVE_MODE" = "minios-embed" ]; then
		printf '%s' "boot=live $DEBIAN_LIVE_OPTIONS " >>/tmp/nb-options
	elif [ "$DEBIAN_LIVE_MODE" = "casper-url" ]; then
		printf '%s' "ip=dhcp boot=casper netboot=url url=$DEBIAN_LIVE_BOOT_URL iso-url=$DEBIAN_LIVE_BOOT_URL noprompt noeject $DEBIAN_LIVE_OPTIONS " >>/tmp/nb-options
	else
		printf '%s' "ip=dhcp boot=live config components fetch=$DEBIAN_LIVE_BOOT_URL ramdisk-size=85% noeject noprompt $DEBIAN_LIVE_OPTIONS " >>/tmp/nb-options
	fi
}

debian_live_extract_boot_file ()
{
	_debian_live_iso="$1"
	_debian_live_out="$2"
	_debian_live_desc="$3"
	shift 3
	_debian_live_out_dir="${_debian_live_out%/*}"
	if [ "$_debian_live_out_dir" = "$_debian_live_out" ] || [ ! -d "$_debian_live_out_dir" ]; then
		_debian_live_extract_dir="/tmp/nb-debian-live-extract"
	else
		_debian_live_extract_dir="$_debian_live_out_dir/nb-debian-live-extract"
	fi

	while [ "$#" -gt 0 ]; do
		_debian_live_path="$1"
		shift

		rm -rf "$_debian_live_extract_dir"
		mkdir -p "$_debian_live_extract_dir"
		if "$DEBIAN_LIVE_7Z" e -y -o"$_debian_live_extract_dir" "$_debian_live_iso" "$_debian_live_path" >/tmp/nb-debian-live-7z.log 2>&1; then
			_debian_live_found=
			for _debian_live_candidate in "$_debian_live_extract_dir"/*; do
				[ -f "$_debian_live_candidate" ] || continue
				[ -s "$_debian_live_candidate" ] || continue
				_debian_live_found="$_debian_live_candidate"
				break
			done
			if [ -n "$_debian_live_found" ]; then
				mv "$_debian_live_found" "$_debian_live_out"
				rm -rf "$_debian_live_extract_dir"
				return 0
			fi
		fi
	done

	nb_error "Could not extract $_debian_live_desc from the $DEBIAN_LIVE_LABEL ISO.\nSee /tmp/nb-debian-live-7z.log for details."
	rm -rf "$_debian_live_extract_dir"
	return 1
}

debian_live_repack_initrd_with_rootfs ()
{
	_debian_live_rootfs="$1"
	_debian_live_parent="${_debian_live_rootfs%/*}"
	_debian_live_work="$_debian_live_parent/initrd-work"
	_debian_live_repacked="$_debian_live_parent/nb-initrd.repacked"
	_debian_live_new="$_debian_live_parent/nb-initrd.new"
	_debian_live_final="$_debian_live_parent/nb-initrd"

	if ! _debian_live_main_info=$(artix_find_main_initrd /tmp/nb-initrd); then
		nb_error "Could not determine the $DEBIAN_LIVE_LABEL initramfs compression format."
		return 1
	fi
	_debian_live_format="${_debian_live_main_info%% *}"
	_debian_live_main_offset="${_debian_live_main_info#* }"

	if ! nb_initrd_need_tool "$_debian_live_format" "$DEBIAN_LIVE_LABEL"; then
		return 1
	fi

	rm -rf "$_debian_live_work" "$_debian_live_repacked" "$_debian_live_new" "$_debian_live_final"
	mkdir -p "$_debian_live_work"

	if ! nb_initrd_unpack /tmp/nb-initrd "$_debian_live_work" "$_debian_live_format" "$_debian_live_main_offset" "-idm" "/dev/null"; then
		nb_error "Could not unpack the $DEBIAN_LIVE_LABEL $_debian_live_format initramfs."
		rm -rf "$_debian_live_work"
		return 1
	fi

	_debian_live_embed_rootfs="$_debian_live_work/$DEBIAN_LIVE_EMBED_ROOTFS_PATH"
	_debian_live_embed_rootfs_dir="${_debian_live_embed_rootfs%/*}"
	mkdir -p "$_debian_live_embed_rootfs_dir"
	if ! mv "$_debian_live_rootfs" "$_debian_live_embed_rootfs"; then
		nb_error "Could not add the $DEBIAN_LIVE_LABEL live filesystem to the initramfs."
		rm -rf "$_debian_live_work"
		return 1
	fi
	if [ -n "${DEBIAN_LIVE_EMBED_ROOTFS_ALIAS_PATH:-}" ]; then
		_debian_live_alias="$_debian_live_work/$DEBIAN_LIVE_EMBED_ROOTFS_ALIAS_PATH"
		_debian_live_alias_dir="${_debian_live_alias%/*}"
		_debian_live_alias_target="../$DEBIAN_LIVE_EMBED_ROOTFS_PATH"
		mkdir -p "$_debian_live_alias_dir"
		if ! ln -s "$_debian_live_alias_target" "$_debian_live_alias"; then
			nb_error "Could not add the $DEBIAN_LIVE_LABEL live filesystem alias to the initramfs."
			rm -rf "$_debian_live_work"
			return 1
		fi
	fi
	for _debian_live_extra_path in ${DEBIAN_LIVE_EXTRA_ROOTFS_PATHS:-}; do
		_debian_live_extra_src="$_debian_live_parent/$_debian_live_extra_path"
		_debian_live_extra_dest="$_debian_live_work/$_debian_live_extra_path"
		_debian_live_extra_dest_dir="${_debian_live_extra_dest%/*}"
		mkdir -p "$_debian_live_extra_dest_dir"
		if ! mv "$_debian_live_extra_src" "$_debian_live_extra_dest"; then
			nb_error "Could not add $_debian_live_extra_path from the $DEBIAN_LIVE_LABEL ISO to the initramfs."
			rm -rf "$_debian_live_work"
			return 1
		fi
	done
	if ! nb_initrd_repack "$_debian_live_work" "$_debian_live_repacked" "$_debian_live_format" "standard"; then
		nb_error "Could not repack the $DEBIAN_LIVE_LABEL $_debian_live_format initramfs."
		rm -rf "$_debian_live_work"
		return 1
	fi

	rm -rf "$_debian_live_work"

	if ! nb_initrd_prefix_append "$_debian_live_new" /tmp/nb-initrd "$_debian_live_main_offset" "$_debian_live_repacked"; then
		nb_error "Could not preserve or write the DEBIAN_LIVE_LABEL initramfs."
		rm -rf "$_debian_live_work" "$_debian_live_repacked" "$_debian_live_new"
		return 1
	fi
	mv "$_debian_live_new" "$_debian_live_final"
	rm -rf "$_debian_live_work" "$_debian_live_repacked"
	rm -f /tmp/nb-initrd
	ln -s "$_debian_live_final" /tmp/nb-initrd
	return 0
}

debian_live_repack_initrd_with_minios_data ()
{
	_debian_live_iso="$1"
	_debian_live_parent="${_debian_live_iso%/*}"
	_debian_live_work="$_debian_live_parent/initrd-work"
	_debian_live_repacked="$_debian_live_parent/nb-initrd.repacked"
	_debian_live_new="$_debian_live_parent/nb-initrd.new"
	_debian_live_final="$_debian_live_parent/nb-initrd"

	if ! _debian_live_7z=$(artix_7z_cmd); then
		nb_error "7zip is required to extract the $DEBIAN_LIVE_LABEL MiniOS data."
		return 1
	fi
	if ! _debian_live_main_info=$(artix_find_main_initrd /tmp/nb-initrd); then
		nb_error "Could not determine the $DEBIAN_LIVE_LABEL initramfs compression format."
		return 1
	fi
	_debian_live_format="${_debian_live_main_info%% *}"
	_debian_live_main_offset="${_debian_live_main_info#* }"

	if ! nb_initrd_need_tool "$_debian_live_format" "$DEBIAN_LIVE_LABEL"; then
		return 1
	fi

	rm -rf "$_debian_live_work" "$_debian_live_repacked" "$_debian_live_new" "$_debian_live_final"
	mkdir -p "$_debian_live_work"

	if ! nb_initrd_unpack /tmp/nb-initrd "$_debian_live_work" "$_debian_live_format" "$_debian_live_main_offset" "-idm" "/dev/null"; then
		nb_error "Could not unpack the $DEBIAN_LIVE_LABEL $_debian_live_format initramfs."
		rm -rf "$_debian_live_work"
		return 1
	fi

	if ! "$_debian_live_7z" x -y -o"$_debian_live_work" "$_debian_live_iso" "minios/*" >/tmp/nb-debian-live-7z.log 2>&1; then
		nb_error "Could not extract MiniOS data from the $DEBIAN_LIVE_LABEL ISO.\nSee /tmp/nb-debian-live-7z.log for details."
		rm -rf "$_debian_live_work"
		return 1
	fi
	rm -f "$_debian_live_iso"

	if [ ! -d "$_debian_live_work/minios" ]; then
		nb_error "The $DEBIAN_LIVE_LABEL ISO did not contain a minios data directory."
		rm -rf "$_debian_live_work"
		return 1
	fi
	_debian_live_has_sb=$(find "$_debian_live_work/minios" -name "*.sb" | head -1)
	if [ -z "$_debian_live_has_sb" ]; then
		nb_error "The $DEBIAN_LIVE_LABEL ISO did not contain MiniOS bundle files."
		rm -rf "$_debian_live_work"
		return 1
	fi

	_debian_live_minios_init="$_debian_live_work/minios-init"
	if [ ! -f "$_debian_live_minios_init" ]; then
		_debian_live_minios_init=$(find "$_debian_live_work" -type f -name minios-init | head -1)
	fi
	if [ -z "$_debian_live_minios_init" ] || [ ! -f "$_debian_live_minios_init" ]; then
		nb_error "Could not find the $DEBIAN_LIVE_LABEL minios-init script to patch."
		rm -rf "$_debian_live_work"
		return 1
	fi
	if ! awk '
		$0 == "DATA=\"$(find_data 45 \"$DATAMNT\")\"" {
			print "if [ -d \"/minios\" ]; then"
			print "   echo_white_star >&2"
			print "   echo \"Using embedded MiniOS data\" >&2 >/dev/tty1"
			print "   DATA=\"/minios\""
			print "else"
			print "   DATA=\"$(find_data 45 \"$DATAMNT\")\""
			print "fi"
			found=1
			next
		}
		{ print }
		END { if (!found) exit 1 }
	' "$_debian_live_minios_init" >"$_debian_live_minios_init.tmp"; then
		nb_error "Could not patch the $DEBIAN_LIVE_LABEL minios-init script."
		rm -rf "$_debian_live_work"
		return 1
	fi
	if ! mv "$_debian_live_minios_init.tmp" "$_debian_live_minios_init"; then
		nb_error "Could not write the patched $DEBIAN_LIVE_LABEL minios-init script."
		rm -rf "$_debian_live_work"
		return 1
	fi
	chmod 755 "$_debian_live_minios_init"

	if ! nb_initrd_repack "$_debian_live_work" "$_debian_live_repacked" "$_debian_live_format" "standard"; then
		nb_error "Could not repack the $DEBIAN_LIVE_LABEL $_debian_live_format initramfs."
		rm -rf "$_debian_live_work"
		return 1
	fi

	if ! nb_initrd_prefix_append "$_debian_live_new" /tmp/nb-initrd "$_debian_live_main_offset" "$_debian_live_repacked"; then
		nb_error "Could not preserve or write the DEBIAN_LIVE_LABEL initramfs."
		rm -rf "$_debian_live_work" "$_debian_live_repacked" "$_debian_live_new"
		return 1
	fi
	mv "$_debian_live_new" "$_debian_live_final"
	rm -rf "$_debian_live_work" "$_debian_live_repacked"
	rm -f /tmp/nb-initrd
	ln -s "$_debian_live_final" /tmp/nb-initrd
	return 0
}

debian_live_prepare_from_iso ()
{
	_debian_live_iso_url="$1"
	_debian_live_work="/tmp/nb-debian-live-work"
	_debian_live_mount_dir="$_debian_live_work"
	_debian_live_iso="$_debian_live_mount_dir/nb-debian-live.iso"
	_debian_live_rootfs="$_debian_live_mount_dir/filesystem.squashfs"

	if ! DEBIAN_LIVE_7Z=$(artix_7z_cmd); then
		nb_error "7zip is required to extract Debian-based live ISO boot files. Rebuild NetbootCD-Neo with 7zip included."
		return 1
	fi

	if grep -q " $_debian_live_mount_dir " /proc/mounts 2>/dev/null; then
		umount "$_debian_live_mount_dir" 2>/dev/null || true
	fi
	rm -f /tmp/nb-linux /tmp/nb-initrd
	rm -rf "$_debian_live_mount_dir" /tmp/nb-debian-live-extract
	mkdir -p "$_debian_live_mount_dir"
	_debian_live_mounted=
	if mount -t tmpfs -o size=85%,mode=0755 tmpfs "$_debian_live_mount_dir" 2>/tmp/nb-debian-live-mount.log; then
		_debian_live_mounted=1
	fi

	if ! wgetgauge "$_debian_live_iso_url" "$_debian_live_iso" "Downloading $DEBIAN_LIVE_LABEL ISO"; then
		nb_error "Could not download $DEBIAN_LIVE_LABEL ISO from:\n\n$_debian_live_iso_url\n\nThis entry needs enough RAM to hold the ISO before kexec."
		[ -n "$_debian_live_mounted" ] && umount "$_debian_live_mount_dir" 2>/dev/null || true
		rm -rf "$_debian_live_mount_dir"
		return 1
	fi

	if ! debian_live_extract_boot_file "$_debian_live_iso" /tmp/nb-linux "kernel" $DEBIAN_LIVE_KERNEL_PATHS; then
		[ -n "$_debian_live_mounted" ] && umount "$_debian_live_mount_dir" 2>/dev/null || true
		rm -rf "$_debian_live_mount_dir"
		rm -f /tmp/nb-linux /tmp/nb-initrd
		return 1
	fi
	if ! debian_live_extract_boot_file "$_debian_live_iso" /tmp/nb-initrd "initrd" $DEBIAN_LIVE_INITRD_PATHS; then
		[ -n "$_debian_live_mounted" ] && umount "$_debian_live_mount_dir" 2>/dev/null || true
		rm -rf "$_debian_live_mount_dir"
		rm -f /tmp/nb-linux /tmp/nb-initrd
		return 1
	fi
	if [ "$DEBIAN_LIVE_MODE" = "minios-embed" ]; then
		dialog --backtitle "$TITLE" --infobox \
			"Embedding the $DEBIAN_LIVE_LABEL data directory into the initrd.\n\nThis can take a while for large ISOs." 7 70 || true
		if ! debian_live_repack_initrd_with_minios_data "$_debian_live_iso"; then
			[ -n "$_debian_live_mounted" ] && umount "$_debian_live_mount_dir" 2>/dev/null || true
			rm -rf "$_debian_live_mount_dir"
			rm -f /tmp/nb-linux /tmp/nb-initrd
			return 1
		fi
		rm -f "$_debian_live_iso" /tmp/nb-debian-live-7z.log /tmp/nb-debian-live-mount.log
		return 0
	fi
	case "$DEBIAN_LIVE_MODE" in
		embed|casper-embed) ;;
		*)
		rm -f "$_debian_live_iso" /tmp/nb-debian-live-7z.log /tmp/nb-debian-live-mount.log
		[ -n "$_debian_live_mounted" ] && umount "$_debian_live_mount_dir" 2>/dev/null || true
		rm -rf "$_debian_live_mount_dir"
		return 0
			;;
	esac
	if ! debian_live_extract_boot_file "$_debian_live_iso" "$_debian_live_rootfs" "live filesystem" $DEBIAN_LIVE_ROOTFS_PATHS; then
		[ -n "$_debian_live_mounted" ] && umount "$_debian_live_mount_dir" 2>/dev/null || true
		rm -rf "$_debian_live_mount_dir"
		rm -f /tmp/nb-linux /tmp/nb-initrd
		return 1
	fi
	for _debian_live_extra_path in ${DEBIAN_LIVE_EXTRA_ROOTFS_PATHS:-}; do
		_debian_live_extra_out="$_debian_live_mount_dir/$_debian_live_extra_path"
		_debian_live_extra_out_dir="${_debian_live_extra_out%/*}"
		mkdir -p "$_debian_live_extra_out_dir"
		if ! debian_live_extract_boot_file "$_debian_live_iso" "$_debian_live_extra_out" "live filesystem layer $_debian_live_extra_path" "$_debian_live_extra_path"; then
			[ -n "$_debian_live_mounted" ] && umount "$_debian_live_mount_dir" 2>/dev/null || true
			rm -rf "$_debian_live_mount_dir"
			rm -f /tmp/nb-linux /tmp/nb-initrd
			return 1
		fi
	done
	rm -f "$_debian_live_iso"

	dialog --backtitle "$TITLE" --infobox \
		"Embedding the $DEBIAN_LIVE_LABEL live filesystem into the initrd.\n\nThis can take a while for large ISOs." 7 70 || true
	if ! debian_live_repack_initrd_with_rootfs "$_debian_live_rootfs"; then
		[ -n "$_debian_live_mounted" ] && umount "$_debian_live_mount_dir" 2>/dev/null || true
		rm -rf "$_debian_live_mount_dir"
		rm -f /tmp/nb-linux /tmp/nb-initrd
		return 1
	fi

	rm -f "$_debian_live_iso" "$_debian_live_rootfs" /tmp/nb-debian-live-7z.log /tmp/nb-debian-live-mount.log
	return 0
}

berry_repack_initrd_with_rootfs ()
{
	_berry_rootfs="$1"
	_berry_parent="${_berry_rootfs%/*}"
	_berry_work="$_berry_parent/initrd-work"
	_berry_repacked="$_berry_parent/nb-initrd.repacked"
	_berry_new="$_berry_parent/nb-initrd.new"
	_berry_final="$_berry_parent/nb-initrd"

	if ! _berry_main_info=$(artix_find_main_initrd /tmp/nb-initrd); then
		nb_error "Could not determine the $BERRY_LABEL initramfs compression format."
		return 1
	fi
	_berry_format="${_berry_main_info%% *}"
	_berry_main_offset="${_berry_main_info#* }"

	if ! nb_initrd_need_tool "$_berry_format" "$BERRY_LABEL"; then
		return 1
	fi

	rm -rf "$_berry_work" "$_berry_repacked" "$_berry_new" "$_berry_final"
	mkdir -p "$_berry_work"
	_berry_unpack_failed=

	case "$_berry_format" in
		gzip)
			if ! ( tail -c +"$(( _berry_main_offset + 1 ))" /tmp/nb-initrd | gzip -cd | ( cd "$_berry_work" && cpio -idmu ) ) 2>/tmp/nb-berry-cpio.log; then
				_berry_unpack_failed=1
			fi
			;;
		zstd)
			if ! ( tail -c +"$(( _berry_main_offset + 1 ))" /tmp/nb-initrd | zstd -dc | ( cd "$_berry_work" && cpio -idmu ) ) 2>/tmp/nb-berry-cpio.log; then
				_berry_unpack_failed=1
			fi
			;;
		xz)
			if ! ( tail -c +"$(( _berry_main_offset + 1 ))" /tmp/nb-initrd | xz -dc | ( cd "$_berry_work" && cpio -idmu ) ) 2>/tmp/nb-berry-cpio.log; then
				_berry_unpack_failed=1
			fi
			;;
		cpio)
			if ! ( tail -c +"$(( _berry_main_offset + 1 ))" /tmp/nb-initrd | ( cd "$_berry_work" && cpio -idmu ) ) 2>/tmp/nb-berry-cpio.log; then
				_berry_unpack_failed=1
			fi
			;;
	esac

	if [ -n "$_berry_unpack_failed" ] && [ ! -s "$_berry_work/init" ]; then
		nb_error "Could not unpack the $BERRY_LABEL $_berry_format initramfs.\nSee /tmp/nb-berry-cpio.log for details."
		rm -rf "$_berry_work"
		return 1
	fi
	if [ ! -s "$_berry_work/init" ]; then
		nb_error "Could not find the $BERRY_LABEL init script."
		rm -rf "$_berry_work"
		return 1
	fi

	mkdir -p "$_berry_work/BERRY"
	if ! mv "$_berry_rootfs" "$_berry_work/BERRY/BERRY"; then
		nb_error "Could not embed the $BERRY_LABEL live filesystem."
		rm -rf "$_berry_work"
		return 1
	fi

	if ! awk '
		$0 == "case \"$CMDLINE\" in *\\ memboot*) memboot=y; ;; esac" {
			print
			print ""
			print "if [ -r ${looproot} ]; then"
			print "\t[ -e /dev/loop0 ] || mknod /dev/loop0 b 7 0 2>/dev/null || true"
			print "\tlosetup /dev/loop0 ${looproot} >/dev/null 2>&1 || failed"
			print "\tfs=squashfs"
			print "\tmount -t squashfs -o ro /dev/loop0 ${sysdir} >/dev/null 2>&1 || (fs=ext2; pmount /dev/loop0 ${sysdir} \"-o ro\") || failed"
			print "\tFOUND_BERRY=netbootcd"
			print "\trinit ${sysdir} ${sysdir}/initrd"
			print "fi"
			found=1
			next
		}
		{ print }
		END { if (!found) exit 1 }
	' "$_berry_work/init" >"$_berry_work/init.new"; then
		nb_error "Could not patch the $BERRY_LABEL init script."
		rm -rf "$_berry_work"
		return 1
	fi
	mv "$_berry_work/init.new" "$_berry_work/init"
	chmod 755 "$_berry_work/init"

	if ! nb_initrd_repack "$_berry_work" "$_berry_repacked" "$_berry_format" "standard"; then
		nb_error "Could not repack the $BERRY_LABEL $_berry_format initramfs."
		rm -rf "$_berry_work"
		return 1
	fi

	if ! nb_initrd_prefix_append "$_berry_new" /tmp/nb-initrd "$_berry_main_offset" "$_berry_repacked"; then
		nb_error "Could not preserve or write the BERRY_LABEL initramfs."
		rm -rf "$_berry_work" "$_berry_repacked" "$_berry_new"
		return 1
	fi
	mv "$_berry_new" "$_berry_final"
	rm -rf "$_berry_work" "$_berry_repacked"
	rm -f /tmp/nb-initrd
	ln -s "$_berry_final" /tmp/nb-initrd
	return 0
}

berry_prepare_from_iso ()
{
	_berry_work="/tmp/nb-berry-work"
	_berry_iso="$_berry_work/nb-berry.iso"
	_berry_rootfs="$_berry_work/berry.squashfs"

	if ! BERRY_7Z=$(artix_7z_cmd); then
		nb_error "7zip is required to extract $BERRY_LABEL boot files. Rebuild NetbootCD-Neo with 7zip included."
		return 1
	fi

	if grep -q " $_berry_work " /proc/mounts 2>/dev/null; then
		umount "$_berry_work" 2>/dev/null || true
	fi
	rm -f /tmp/nb-linux /tmp/nb-initrd
	rm -rf "$_berry_work"
	mkdir -p "$_berry_work"
	_berry_mounted=
	if mount -t tmpfs -o size=85%,mode=0755 tmpfs "$_berry_work" 2>/tmp/nb-berry-mount.log; then
		_berry_mounted=1
	fi

	if ! wgetgauge "$BERRY_ISO_URL" "$_berry_iso" "Downloading $BERRY_LABEL ISO"; then
		nb_error "Could not download $BERRY_LABEL ISO from:\n\n$BERRY_ISO_URL\n\nThis entry needs enough RAM to hold the ISO before kexec."
		[ -n "$_berry_mounted" ] && umount "$_berry_work" 2>/dev/null || true
		rm -rf "$_berry_work"
		return 1
	fi
	if ! berry_extract_boot_file "$_berry_iso" /tmp/nb-linux "kernel" "$BERRY_KERNEL_PATH"; then
		[ -n "$_berry_mounted" ] && umount "$_berry_work" 2>/dev/null || true
		rm -rf "$_berry_work"
		return 1
	fi
	if ! berry_extract_boot_file "$_berry_iso" /tmp/nb-initrd "initrd" "$BERRY_INITRD_PATH"; then
		[ -n "$_berry_mounted" ] && umount "$_berry_work" 2>/dev/null || true
		rm -rf "$_berry_work"
		rm -f /tmp/nb-linux /tmp/nb-initrd
		return 1
	fi
	if ! berry_extract_boot_file "$_berry_iso" "$_berry_rootfs" "live filesystem" "$BERRY_ROOTFS_PATH"; then
		[ -n "$_berry_mounted" ] && umount "$_berry_work" 2>/dev/null || true
		rm -rf "$_berry_work"
		rm -f /tmp/nb-linux /tmp/nb-initrd
		return 1
	fi
	rm -f "$_berry_iso"

	dialog --backtitle "$TITLE" --infobox \
		"Embedding the $BERRY_LABEL live filesystem into the initrd.\n\nThis can take a while." 7 70 || true
	if ! berry_repack_initrd_with_rootfs "$_berry_rootfs"; then
		[ -n "$_berry_mounted" ] && umount "$_berry_work" 2>/dev/null || true
		rm -rf "$_berry_work"
		rm -f /tmp/nb-linux /tmp/nb-initrd
		return 1
	fi

	rm -f /tmp/nb-berry-7z.log /tmp/nb-berry-cpio.log /tmp/nb-berry-mount.log
	return 0
}

pika_repack_initrd_with_iso ()
{
	_pika_iso="$1"
	_pika_parent="${_pika_iso%/*}"
	_pika_work="$_pika_parent/initrd-work"
	_pika_repacked="$_pika_parent/nb-initrd.repacked"
	_pika_new="$_pika_parent/nb-initrd.new"
	_pika_final="$_pika_parent/nb-initrd"

	if ! _pika_main_info=$(artix_find_main_initrd /tmp/nb-initrd); then
		nb_error "Could not determine the $PIKA_LABEL initramfs compression format."
		return 1
	fi
	_pika_format="${_pika_main_info%% *}"
	_pika_main_offset="${_pika_main_info#* }"

	if ! nb_initrd_need_tool "$_pika_format" "$PIKA_LABEL"; then
		return 1
	fi

	rm -rf "$_pika_work" "$_pika_repacked" "$_pika_new" "$_pika_final"
	mkdir -p "$_pika_work"
	_pika_unpack_failed=

	case "$_pika_format" in
		gzip)
			if ! ( tail -c +"$(( _pika_main_offset + 1 ))" /tmp/nb-initrd | gzip -cd | ( cd "$_pika_work" && cpio -idmu ) ) 2>/tmp/nb-pika-cpio.log; then
				_pika_unpack_failed=1
			fi
			;;
		zstd)
			if ! ( tail -c +"$(( _pika_main_offset + 1 ))" /tmp/nb-initrd | zstd -dc | ( cd "$_pika_work" && cpio -idmu ) ) 2>/tmp/nb-pika-cpio.log; then
				_pika_unpack_failed=1
			fi
			;;
		xz)
			if ! ( tail -c +"$(( _pika_main_offset + 1 ))" /tmp/nb-initrd | xz -dc | ( cd "$_pika_work" && cpio -idmu ) ) 2>/tmp/nb-pika-cpio.log; then
				_pika_unpack_failed=1
			fi
			;;
		cpio)
			if ! ( tail -c +"$(( _pika_main_offset + 1 ))" /tmp/nb-initrd | ( cd "$_pika_work" && cpio -idmu ) ) 2>/tmp/nb-pika-cpio.log; then
				_pika_unpack_failed=1
			fi
			;;
	esac

	if [ -n "$_pika_unpack_failed" ] && { [ ! -s "$_pika_work/init" ] || [ ! -s "$_pika_work/usr/bin/busybox" ]; }; then
		nb_error "Could not unpack the $PIKA_LABEL $_pika_format initramfs.\nSee /tmp/nb-pika-cpio.log for details."
		rm -rf "$_pika_work"
		return 1
	fi
	if [ ! -s "$_pika_work/init" ]; then
		nb_error "Could not find the $PIKA_LABEL booster init binary."
		rm -rf "$_pika_work"
		return 1
	fi

	mkdir -p "$_pika_work/.netbootcd"
	if ! mv "$_pika_iso" "$_pika_work/.netbootcd/pika.iso"; then
		nb_error "Could not embed the $PIKA_LABEL ISO into the initramfs."
		rm -rf "$_pika_work"
		return 1
	fi

	_pika_hooks_dir="$_pika_work/usr/share/booster/hooks-early"
	if [ ! -d "$_pika_hooks_dir" ]; then
		nb_error "Could not find the $PIKA_LABEL booster hooks directory."
		rm -rf "$_pika_work"
		return 1
	fi
	_pika_hook="$_pika_hooks_dir/00_netbootcd_pika_iso.sh"
	cat >"$_pika_hook" <<'EOF'
#!/usr/bin/busybox sh
PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH

BB=/usr/bin/busybox
ISO=/.netbootcd/pika.iso

netbootcd_pika_log()
{
	$BB echo "NetbootCD-Neo: $*" >/dev/console 2>/dev/null || true
}

$BB mkdir -p /proc /sys /dev 2>/dev/null || true
$BB mount -t proc proc /proc 2>/dev/null || true
$BB mount -t sysfs sysfs /sys 2>/dev/null || true
$BB mount -t devtmpfs devtmpfs /dev 2>/dev/null || true

case " $($BB cat /proc/cmdline 2>/dev/null) " in
	*" boot=live "*) ;;
	*) exit 0 ;;
esac

[ -e /dev/loop-control ] || $BB mknod /dev/loop-control c 10 237 2>/dev/null || true
for PIKA_LOOP in 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
	[ -e "/dev/loop$PIKA_LOOP" ] || $BB mknod "/dev/loop$PIKA_LOOP" b 7 "$PIKA_LOOP" 2>/dev/null || true
done

for PIKA_MODULE in loop cdrom isofs squashfs overlay; do
	if ! $BB modprobe "$PIKA_MODULE" 2>/dev/null; then
		[ -f "/usr/lib/modules/$PIKA_MODULE.ko" ] && $BB insmod "/usr/lib/modules/$PIKA_MODULE.ko" 2>/dev/null || true
	fi
done

if [ ! -f "$ISO" ]; then
	netbootcd_pika_log "embedded PikaOS ISO is missing"
	exit 0
fi

PIKA_LOOP_DEVICE="$($BB losetup -f 2>/dev/null)"
if [ -n "$PIKA_LOOP_DEVICE" ] && $BB losetup -r "$PIKA_LOOP_DEVICE" "$ISO" 2>/dev/null; then
	netbootcd_pika_log "attached embedded PikaOS ISO to $PIKA_LOOP_DEVICE"
	$BB blkid "$PIKA_LOOP_DEVICE" >/dev/console 2>/dev/null || true
	exit 0
fi

for PIKA_LOOP in /dev/loop0 /dev/loop1 /dev/loop2 /dev/loop3 /dev/loop4 /dev/loop5 /dev/loop6 /dev/loop7 /dev/loop8 /dev/loop9 /dev/loop10 /dev/loop11 /dev/loop12 /dev/loop13 /dev/loop14 /dev/loop15; do
	if $BB losetup -r "$PIKA_LOOP" "$ISO" 2>/dev/null; then
		netbootcd_pika_log "attached embedded PikaOS ISO to $PIKA_LOOP"
		$BB blkid "$PIKA_LOOP" >/dev/console 2>/dev/null || true
		exit 0
	fi
done

netbootcd_pika_log "could not attach embedded PikaOS ISO to a loop device"
exit 0
EOF
	chmod 755 "$_pika_hook"
	if [ ! -e "$_pika_work/usr/bin/sh" ]; then
		( cd "$_pika_work/usr/bin" && ln -s busybox sh ) 2>/dev/null || true
	fi

	if ! nb_initrd_repack "$_pika_work" "$_pika_repacked" "$_pika_format" "standard"; then
		nb_error "Could not repack the $PIKA_LABEL $_pika_format initramfs."
		rm -rf "$_pika_work"
		return 1
	fi

	rm -rf "$_pika_work"

	: >"$_pika_new"
	if [ "$_pika_main_offset" -gt 0 ]; then
		if ! head -c "$_pika_main_offset" /tmp/nb-initrd >>"$_pika_new"; then
			nb_error "Could not preserve the $PIKA_LABEL early initramfs prefix."
			rm -f "$_pika_repacked" "$_pika_new"
			return 1
		fi
	fi
	if ! cat "$_pika_repacked" >>"$_pika_new"; then
		nb_error "Could not write the repacked $PIKA_LABEL initramfs."
		rm -f "$_pika_repacked" "$_pika_new"
		return 1
	fi
	mv "$_pika_new" "$_pika_final"
	rm -f "$_pika_repacked" /tmp/nb-initrd
	ln -s "$_pika_final" /tmp/nb-initrd
	return 0
}

pika_prepare_from_iso ()
{
	_pika_iso_url="$1"
	_pika_work="/tmp/nb-pika-work"
	_pika_iso="$_pika_work/nb-pika.iso"
	_pika_boot="$_pika_work/boot"
	_pika_boot_image="$_pika_boot/Boot-NoEmul.img"

	if ! PIKA_7Z=$(artix_7z_cmd); then
		nb_error "7zip is required to extract PikaOS ISO boot files. Rebuild NetbootCD-Neo with 7zip included."
		return 1
	fi

	if grep -q " $_pika_work " /proc/mounts 2>/dev/null; then
		umount "$_pika_work" 2>/dev/null || true
	fi
	rm -f /tmp/nb-linux /tmp/nb-initrd
	rm -rf "$_pika_work" /tmp/nb-pika-initrd-work
	mkdir -p "$_pika_boot"
	_pika_mounted=
	if mount -t tmpfs -o size=85%,mode=0755 tmpfs "$_pika_work" 2>/tmp/nb-pika-mount.log; then
		_pika_mounted=1
		mkdir -p "$_pika_boot"
	fi

	if ! wgetgauge "$_pika_iso_url" "$_pika_iso" "Downloading $PIKA_LABEL ISO"; then
		nb_error "Could not download $PIKA_LABEL ISO from:\n\n$_pika_iso_url\n\nThis entry needs enough RAM to hold the ISO and the repacked initrd."
		[ -n "$_pika_mounted" ] && umount "$_pika_work" 2>/dev/null || true
		rm -rf "$_pika_work"
		return 1
	fi

	if ! "$PIKA_7Z" e -y -o"$_pika_boot" "$_pika_iso" "[BOOT]/Boot-NoEmul.img" >/tmp/nb-pika-7z.log 2>&1; then
		nb_error "Could not extract the $PIKA_LABEL EFI boot image.\nSee /tmp/nb-pika-7z.log for details."
		[ -n "$_pika_mounted" ] && umount "$_pika_work" 2>/dev/null || true
		rm -rf "$_pika_work"
		return 1
	fi
	if [ ! -s "$_pika_boot_image" ]; then
		nb_error "The $PIKA_LABEL ISO did not contain [BOOT]/Boot-NoEmul.img."
		[ -n "$_pika_mounted" ] && umount "$_pika_work" 2>/dev/null || true
		rm -rf "$_pika_work"
		return 1
	fi
	if ! "$PIKA_7Z" e -y -o"$_pika_boot" "$_pika_boot_image" EFI/VMLINUZ EFI/INITRD >>/tmp/nb-pika-7z.log 2>&1; then
		nb_error "Could not extract kernel and initrd from the $PIKA_LABEL EFI boot image.\nSee /tmp/nb-pika-7z.log for details."
		[ -n "$_pika_mounted" ] && umount "$_pika_work" 2>/dev/null || true
		rm -rf "$_pika_work"
		return 1
	fi
	if [ ! -s "$_pika_boot/VMLINUZ" ] || [ ! -s "$_pika_boot/INITRD" ]; then
		nb_error "The $PIKA_LABEL EFI boot image did not contain EFI/VMLINUZ and EFI/INITRD."
		[ -n "$_pika_mounted" ] && umount "$_pika_work" 2>/dev/null || true
		rm -rf "$_pika_work"
		return 1
	fi

	mv "$_pika_boot/VMLINUZ" /tmp/nb-linux
	mv "$_pika_boot/INITRD" /tmp/nb-initrd
	rm -rf "$_pika_boot"

	dialog --backtitle "$TITLE" --infobox \
		"Embedding the $PIKA_LABEL ISO into the initrd.\n\nThis can take a while for large ISOs." 7 70 || true
	if ! pika_repack_initrd_with_iso "$_pika_iso"; then
		[ -n "$_pika_mounted" ] && umount "$_pika_work" 2>/dev/null || true
		rm -rf "$_pika_work"
		rm -f /tmp/nb-linux /tmp/nb-initrd
		return 1
	fi

	rm -f "$_pika_boot_image" /tmp/nb-pika-7z.log /tmp/nb-pika-mount.log
	return 0
}

porteux_repack_initrd_with_iso ()
{
	_porteux_iso="$1"
	_porteux_parent="${_porteux_iso%/*}"
	_porteux_tree="$_porteux_parent/initrd-work"
	_porteux_repacked="$_porteux_parent/nb-initrd.repacked"
	_porteux_final="$_porteux_parent/nb-initrd"

	if ! command -v zstd >/dev/null 2>&1; then
		nb_error "$PORTEUX_LABEL initramfs uses zstd compression, but zstd is not available."
		return 1
	fi

	rm -rf "$_porteux_tree" "$_porteux_repacked" "$_porteux_final"
	mkdir -p "$_porteux_tree"
	if ! ( zstd -dc /tmp/nb-initrd | ( cd "$_porteux_tree" && cpio -idmu ) ) 2>/tmp/nb-porteux-cpio.log; then
		nb_error "Could not unpack the $PORTEUX_LABEL initramfs.\nSee /tmp/nb-porteux-cpio.log for details."
		rm -rf "$_porteux_tree"
		return 1
	fi
	if [ ! -L "$_porteux_tree/init" ] || [ ! -s "$_porteux_tree/linuxrc" ]; then
		nb_error "Could not find the $PORTEUX_LABEL initramfs startup scripts."
		rm -rf "$_porteux_tree"
		return 1
	fi

	mkdir -p "$_porteux_tree/netbootcd"
	if ! mv "$_porteux_iso" "$_porteux_tree/netbootcd/porteux.iso"; then
		nb_error "Could not embed the $PORTEUX_LABEL ISO into the initramfs."
		rm -rf "$_porteux_tree"
		return 1
	fi

	if ! awk '
		$0 == "if [ $ISO ]; then" && !patched {
			print "if [ -f /netbootcd/porteux.iso ]; then"
			print "\tCFGDEV=/mnt/isoloop"
			print "\tISOSRC=/netbootcd/porteux.iso"
			print "\tmkdir -p \"$CFGDEV\""
			print "\tmount -o loop \"$ISOSRC\" \"$CFGDEV\""
			print "elif [ $ISO ]; then"
			patched=1
			next
		}
		{ print }
		END { if (!patched) exit 1 }
	' "$_porteux_tree/linuxrc" >"$_porteux_tree/linuxrc.new"; then
		nb_error "Could not patch the $PORTEUX_LABEL initramfs media search."
		rm -rf "$_porteux_tree"
		return 1
	fi
	mv "$_porteux_tree/linuxrc.new" "$_porteux_tree/linuxrc"
	chmod 755 "$_porteux_tree/linuxrc"

	if ! ( cd "$_porteux_tree" && find . | cpio -o -H newc | zstd -q -c >"$_porteux_repacked" ); then
		nb_error "Could not repack the $PORTEUX_LABEL zstd initramfs."
		rm -rf "$_porteux_tree"
		return 1
	fi

	rm -rf "$_porteux_tree"
	mv "$_porteux_repacked" "$_porteux_final"
	rm -f /tmp/nb-initrd
	ln -s "$_porteux_final" /tmp/nb-initrd
	return 0
}

porteus_family_prepare_from_iso ()
{
	_porteus_family_label="$1"
	_porteus_family_iso_url="$2"
	_porteus_family_kernel_path="$3"
	_porteus_family_initrd_path="$4"
	_porteus_family_tag="$5"
	_porteus_family_repack="$6"
	_porteus_family_work="/tmp/nb-$_porteus_family_tag-work"
	_porteus_family_iso="$_porteus_family_work/nb-$_porteus_family_tag.iso"
	_porteus_family_boot="$_porteus_family_work/boot"
	_porteus_family_log="/tmp/nb-$_porteus_family_tag"

	if ! _porteus_family_7z=$(artix_7z_cmd); then
		nb_error "7zip is required to extract $_porteus_family_label ISO boot files. Rebuild NetbootCD-Neo with 7zip included."
		return 1
	fi

	if grep -q " $_porteus_family_work " /proc/mounts 2>/dev/null; then
		umount "$_porteus_family_work" 2>/dev/null || true
	fi
	rm -f /tmp/nb-linux /tmp/nb-initrd
	rm -rf "$_porteus_family_work"
	mkdir -p "$_porteus_family_boot"
	_porteus_family_mounted=
	if mount -t tmpfs -o size=85%,mode=0755 tmpfs "$_porteus_family_work" 2>"$_porteus_family_log-mount.log"; then
		_porteus_family_mounted=1
		mkdir -p "$_porteus_family_boot"
	fi

	if ! wgetgauge "$_porteus_family_iso_url" "$_porteus_family_iso" "Downloading $_porteus_family_label ISO"; then
		nb_error "Could not download $_porteus_family_label ISO from:\n\n$_porteus_family_iso_url\n\nThis entry needs enough RAM to hold the ISO and the repacked initrd."
		[ -n "$_porteus_family_mounted" ] && umount "$_porteus_family_work" 2>/dev/null || true
		rm -rf "$_porteus_family_work"
		return 1
	fi

	if ! "$_porteus_family_7z" e -y -o"$_porteus_family_boot" "$_porteus_family_iso" "$_porteus_family_kernel_path" "$_porteus_family_initrd_path" >"$_porteus_family_log-7z.log" 2>&1; then
		nb_error "Could not extract $_porteus_family_label boot files from the ISO.\nSee $_porteus_family_log-7z.log for details."
		[ -n "$_porteus_family_mounted" ] && umount "$_porteus_family_work" 2>/dev/null || true
		rm -rf "$_porteus_family_work"
		return 1
	fi
	_porteus_family_kernel_file="${_porteus_family_kernel_path##*/}"
	_porteus_family_initrd_file="${_porteus_family_initrd_path##*/}"
	if [ ! -s "$_porteus_family_boot/$_porteus_family_kernel_file" ] || [ ! -s "$_porteus_family_boot/$_porteus_family_initrd_file" ]; then
		nb_error "The $_porteus_family_label ISO did not contain its expected kernel and initramfs."
		[ -n "$_porteus_family_mounted" ] && umount "$_porteus_family_work" 2>/dev/null || true
		rm -rf "$_porteus_family_work"
		return 1
	fi

	mv "$_porteus_family_boot/$_porteus_family_kernel_file" /tmp/nb-linux
	mv "$_porteus_family_boot/$_porteus_family_initrd_file" /tmp/nb-initrd
	rm -rf "$_porteus_family_boot"

	dialog --backtitle "$TITLE" --infobox \
		"Embedding the $_porteus_family_label ISO into the initrd.\n\nThis can take a while." 7 70 || true
	if ! "$_porteus_family_repack" "$_porteus_family_iso"; then
		[ -n "$_porteus_family_mounted" ] && umount "$_porteus_family_work" 2>/dev/null || true
		rm -rf "$_porteus_family_work"
		rm -f /tmp/nb-linux /tmp/nb-initrd
		return 1
	fi

	rm -f "$_porteus_family_log-7z.log" "$_porteus_family_log-mount.log" "$_porteus_family_log-cpio.log"
	return 0
}

porteux_prepare_from_iso ()
{
	porteus_family_prepare_from_iso "$PORTEUX_LABEL" "$1" "$PORTEUX_KERNEL_PATH" "$PORTEUX_INITRD_PATH" porteux porteux_repack_initrd_with_iso
}

porteus_repack_initrd_with_iso ()
{
	_porteus_iso="$1"
	_porteus_parent="${_porteus_iso%/*}"
	_porteus_tree="$_porteus_parent/initrd-work"
	_porteus_repacked="$_porteus_parent/nb-initrd.repacked"
	_porteus_final="$_porteus_parent/nb-initrd"

	if ! command -v xz >/dev/null 2>&1; then
		nb_error "$PORTEUS_LABEL initramfs uses xz compression, but xz is not available."
		return 1
	fi

	rm -rf "$_porteus_tree" "$_porteus_repacked" "$_porteus_final"
	mkdir -p "$_porteus_tree"
	if ! ( xz -dc /tmp/nb-initrd | ( cd "$_porteus_tree" && cpio -idmu ) ) 2>/tmp/nb-porteus-cpio.log; then
		nb_error "Could not unpack the $PORTEUS_LABEL initramfs.\nSee /tmp/nb-porteus-cpio.log for details."
		rm -rf "$_porteus_tree"
		return 1
	fi
	if [ ! -s "$_porteus_tree/linuxrc" ]; then
		nb_error "Could not find the $PORTEUS_LABEL initramfs startup script."
		rm -rf "$_porteus_tree"
		return 1
	fi

	mkdir -p "$_porteus_tree/netbootcd"
	if ! mv "$_porteus_iso" "$_porteus_tree/netbootcd/porteus.iso"; then
		nb_error "Could not embed the $PORTEUS_LABEL ISO into the initramfs."
		rm -rf "$_porteus_tree"
		return 1
	fi

	if ! awk '
		$0 == "elif [ $ISO ]; then CFGDEV=/mnt/isoloop" && !patched {
			print "elif [ -f /netbootcd/porteus.iso ]; then CFGDEV=/mnt/isoloop"
			print "\tmkdir -p /mnt/isoloop"
			print "\tmount -o loop /netbootcd/porteus.iso /mnt/isoloop"
			print "\tISOSRC=/netbootcd/porteus.iso"
			print "\tISO=/netbootcd/porteus.iso"
			print "elif [ $ISO ]; then CFGDEV=/mnt/isoloop"
			patched=1
			next
		}
		{ print }
		END { if (!patched) exit 1 }
	' "$_porteus_tree/linuxrc" >"$_porteus_tree/linuxrc.new"; then
		nb_error "Could not patch the $PORTEUS_LABEL initramfs media search."
		rm -rf "$_porteus_tree"
		return 1
	fi
	mv "$_porteus_tree/linuxrc.new" "$_porteus_tree/linuxrc"
	chmod 755 "$_porteus_tree/linuxrc"

	if ! ( cd "$_porteus_tree" && find . | cpio -o -H newc | xz -0 -C crc32 -c >"$_porteus_repacked" ); then
		nb_error "Could not repack the $PORTEUS_LABEL xz initramfs."
		rm -rf "$_porteus_tree"
		return 1
	fi

	rm -rf "$_porteus_tree"
	mv "$_porteus_repacked" "$_porteus_final"
	rm -f /tmp/nb-initrd
	ln -s "$_porteus_final" /tmp/nb-initrd
	return 0
}

porteus_prepare_from_iso ()
{
	porteus_family_prepare_from_iso "$PORTEUS_LABEL" "$1" "$PORTEUS_KERNEL_PATH" "$PORTEUS_INITRD_PATH" porteus porteus_repack_initrd_with_iso
}

nemesis_repack_initrd_with_iso ()
{
	_nemesis_iso="$1"
	_nemesis_parent="${_nemesis_iso%/*}"
	_nemesis_tree="$_nemesis_parent/initrd-work"
	_nemesis_repacked="$_nemesis_parent/nb-initrd.repacked"
	_nemesis_final="$_nemesis_parent/nb-initrd"

	if ! command -v xz >/dev/null 2>&1; then
		nb_error "$NEMESIS_LABEL initramfs uses xz compression, but xz is not available."
		return 1
	fi

	rm -rf "$_nemesis_tree" "$_nemesis_repacked" "$_nemesis_final"
	mkdir -p "$_nemesis_tree"
	if ! ( xz -dc /tmp/nb-initrd | ( cd "$_nemesis_tree" && cpio -idmu ) ) 2>/tmp/nb-nemesis-cpio.log; then
		nb_error "Could not unpack the $NEMESIS_LABEL initramfs.\nSee /tmp/nb-nemesis-cpio.log for details."
		rm -rf "$_nemesis_tree"
		return 1
	fi
	if [ ! -s "$_nemesis_tree/linuxrc" ]; then
		nb_error "Could not find the $NEMESIS_LABEL initramfs startup script."
		rm -rf "$_nemesis_tree"
		return 1
	fi

	mkdir -p "$_nemesis_tree/netbootcd"
	if ! mv "$_nemesis_iso" "$_nemesis_tree/netbootcd/nemesis.iso"; then
		nb_error "Could not embed the $NEMESIS_LABEL ISO into the initramfs."
		rm -rf "$_nemesis_tree"
		return 1
	fi

	if ! awk '
		$0 == "elif [ $ISO ]; then SGNDEV=/mnt/isoloop" && !patched {
			print "elif [ -f /netbootcd/nemesis.iso ]; then SGNDEV=/mnt/isoloop"
			print "\tmkdir -p /mnt/isoloop"
			print "\tmount -o loop /netbootcd/nemesis.iso /mnt/isoloop"
			print "\tISO=/netbootcd/nemesis.iso"
			print "elif [ $ISO ]; then SGNDEV=/mnt/isoloop"
			patched=1
			next
		}
		{ print }
		END { if (!patched) exit 1 }
	' "$_nemesis_tree/linuxrc" >"$_nemesis_tree/linuxrc.new"; then
		nb_error "Could not patch the $NEMESIS_LABEL initramfs media search."
		rm -rf "$_nemesis_tree"
		return 1
	fi
	mv "$_nemesis_tree/linuxrc.new" "$_nemesis_tree/linuxrc"
	chmod 755 "$_nemesis_tree/linuxrc"

	if ! ( cd "$_nemesis_tree" && find . | cpio -o -H newc | xz -0 -C crc32 -c >"$_nemesis_repacked" ); then
		nb_error "Could not repack the $NEMESIS_LABEL xz initramfs."
		rm -rf "$_nemesis_tree"
		return 1
	fi

	rm -rf "$_nemesis_tree"
	mv "$_nemesis_repacked" "$_nemesis_final"
	rm -f /tmp/nb-initrd
	ln -s "$_nemesis_final" /tmp/nb-initrd
	return 0
}

nemesis_prepare_from_iso ()
{
	porteus_family_prepare_from_iso "$NEMESIS_LABEL" "$1" "$NEMESIS_KERNEL_PATH" "$NEMESIS_INITRD_PATH" nemesis nemesis_repack_initrd_with_iso
}

chimera_repack_initrd_with_iso ()
{
	_chimera_iso="$1"
	_chimera_parent="${_chimera_iso%/*}"
	_chimera_tree="$_chimera_parent/initrd-work"
	_chimera_repacked="$_chimera_parent/nb-initrd.repacked"
	_chimera_new="$_chimera_parent/nb-initrd.new"
	_chimera_final="$_chimera_parent/nb-initrd"

	if ! _chimera_main_info=$(artix_find_main_initrd /tmp/nb-initrd); then
		nb_error "Could not determine the $CHIMERA_LABEL initramfs compression format."
		return 1
	fi
	_chimera_format="${_chimera_main_info%% *}"
	_chimera_main_offset="${_chimera_main_info#* }"

	if ! nb_initrd_need_tool "$_chimera_format" "$CHIMERA_LABEL"; then
		return 1
	fi

	rm -rf "$_chimera_tree" "$_chimera_repacked" "$_chimera_new" "$_chimera_final"
	mkdir -p "$_chimera_tree"
	case "$_chimera_format" in
		gzip)
			if ! ( tail -c +"$(( _chimera_main_offset + 1 ))" /tmp/nb-initrd | gzip -cd | ( cd "$_chimera_tree" && cpio -idmu ) ) 2>/tmp/nb-chimera-cpio.log; then
				nb_error "Could not unpack the $CHIMERA_LABEL gzip initramfs."
				return 1
			fi
			;;
		zstd)
			if ! ( tail -c +"$(( _chimera_main_offset + 1 ))" /tmp/nb-initrd | zstd -dc | ( cd "$_chimera_tree" && cpio -idmu ) ) 2>/tmp/nb-chimera-cpio.log; then
				nb_error "Could not unpack the $CHIMERA_LABEL zstd initramfs."
				return 1
			fi
			;;
		xz)
			if ! ( tail -c +"$(( _chimera_main_offset + 1 ))" /tmp/nb-initrd | xz -dc | ( cd "$_chimera_tree" && cpio -idmu ) ) 2>/tmp/nb-chimera-cpio.log; then
				nb_error "Could not unpack the $CHIMERA_LABEL xz initramfs."
				return 1
			fi
			;;
		cpio)
			if ! ( tail -c +"$(( _chimera_main_offset + 1 ))" /tmp/nb-initrd | ( cd "$_chimera_tree" && cpio -idmu ) ) 2>/tmp/nb-chimera-cpio.log; then
				nb_error "Could not unpack the $CHIMERA_LABEL cpio initramfs."
				return 1
			fi
			;;
	esac
	if [ ! -s "$_chimera_tree/usr/sbin/live-boot" ]; then
		nb_error "Could not find the $CHIMERA_LABEL live-boot initramfs files."
		rm -rf "$_chimera_tree"
		return 1
	fi
	_chimera_helpers="$_chimera_tree/usr/lib/live/boot/9990-misc-helpers.sh"
	if [ ! -s "$_chimera_helpers" ]; then
		nb_error "Could not find the $CHIMERA_LABEL live media helper script."
		rm -rf "$_chimera_tree"
		return 1
	fi
	if ! awk '
		$0 == "\t\t\t\t\tmount -t $fs_type \"${FROMISO}\" /run/live/fromiso" && !patched {
			print "\t\t\t\t\tmodprobe -q -b loop 1>/dev/null"
			print "\t\t\t\t\tudevadm settle"
			print
			patched=1
			next
		}
		{ print }
		END { if (!patched) exit 1 }
	' "$_chimera_helpers" >"$_chimera_helpers.new"; then
		nb_error "Could not patch the $CHIMERA_LABEL embedded ISO mount path."
		rm -rf "$_chimera_tree"
		return 1
	fi
	mv "$_chimera_helpers.new" "$_chimera_helpers"

	mkdir -p "$_chimera_tree/.netbootcd"
	if ! mv "$_chimera_iso" "$_chimera_tree/.netbootcd/chimera.iso"; then
		nb_error "Could not embed the $CHIMERA_LABEL ISO into the initramfs."
		rm -rf "$_chimera_tree"
		return 1
	fi

	if ! nb_initrd_repack "$_chimera_tree" "$_chimera_repacked" "$_chimera_format" "standard"; then
		nb_error "Could not repack the $CHIMERA_LABEL $_chimera_format initramfs."
		rm -rf "$_chimera_tree"
		return 1
	fi

	rm -rf "$_chimera_tree"
	: >"$_chimera_new"
	if [ "$_chimera_main_offset" -gt 0 ]; then
		if ! head -c "$_chimera_main_offset" /tmp/nb-initrd >>"$_chimera_new"; then
			nb_error "Could not preserve the $CHIMERA_LABEL early initramfs prefix."
			return 1
		fi
	fi
	if ! cat "$_chimera_repacked" >>"$_chimera_new"; then
		nb_error "Could not write the repacked $CHIMERA_LABEL initramfs."
		return 1
	fi
	mv "$_chimera_new" "$_chimera_final"
	rm -f "$_chimera_repacked" /tmp/nb-initrd
	ln -s "$_chimera_final" /tmp/nb-initrd
	return 0
}

chimera_prepare_from_iso ()
{
	_chimera_iso_url="$1"
	_chimera_work="/tmp/nb-chimera-work"
	_chimera_iso="$_chimera_work/nb-chimera.iso"
	_chimera_boot="$_chimera_work/boot"

	if ! _chimera_7z=$(artix_7z_cmd); then
		nb_error "7zip is required to extract $CHIMERA_LABEL ISO boot files. Rebuild NetbootCD-Neo with 7zip included."
		return 1
	fi

	if grep -q " $_chimera_work " /proc/mounts 2>/dev/null; then
		umount "$_chimera_work" 2>/dev/null || true
	fi
	rm -f /tmp/nb-linux /tmp/nb-initrd
	rm -rf "$_chimera_work"
	mkdir -p "$_chimera_boot"
	_chimera_mounted=
	if mount -t tmpfs -o size=85%,mode=0755 tmpfs "$_chimera_work" 2>/tmp/nb-chimera-mount.log; then
		_chimera_mounted=1
		mkdir -p "$_chimera_boot"
	fi

	if ! wgetgauge "$_chimera_iso_url" "$_chimera_iso" "Downloading $CHIMERA_LABEL ISO"; then
		nb_error "Could not download $CHIMERA_LABEL ISO from:\n\n$_chimera_iso_url\n\nThis entry needs enough RAM to hold the ISO and the repacked initrd."
		[ -n "$_chimera_mounted" ] && umount "$_chimera_work" 2>/dev/null || true
		rm -rf "$_chimera_work"
		return 1
	fi

	if ! "$_chimera_7z" e -y -o"$_chimera_boot" "$_chimera_iso" "$CHIMERA_KERNEL_PATH" "$CHIMERA_INITRD_PATH" >/tmp/nb-chimera-7z.log 2>&1; then
		nb_error "Could not extract $CHIMERA_LABEL boot files from the ISO.\nSee /tmp/nb-chimera-7z.log for details."
		[ -n "$_chimera_mounted" ] && umount "$_chimera_work" 2>/dev/null || true
		rm -rf "$_chimera_work"
		return 1
	fi
	_chimera_kernel_file="${CHIMERA_KERNEL_PATH##*/}"
	_chimera_initrd_file="${CHIMERA_INITRD_PATH##*/}"
	if [ ! -s "$_chimera_boot/$_chimera_kernel_file" ] || [ ! -s "$_chimera_boot/$_chimera_initrd_file" ]; then
		nb_error "The $CHIMERA_LABEL ISO did not contain its expected kernel and initramfs."
		[ -n "$_chimera_mounted" ] && umount "$_chimera_work" 2>/dev/null || true
		rm -rf "$_chimera_work"
		return 1
	fi

	mv "$_chimera_boot/$_chimera_kernel_file" /tmp/nb-linux
	mv "$_chimera_boot/$_chimera_initrd_file" /tmp/nb-initrd
	rm -rf "$_chimera_boot"

	dialog --backtitle "$TITLE" --infobox \
		"Embedding the $CHIMERA_LABEL ISO into the initrd.\n\nThis can take a while." 7 70 || true
	if ! chimera_repack_initrd_with_iso "$_chimera_iso"; then
		[ -n "$_chimera_mounted" ] && umount "$_chimera_work" 2>/dev/null || true
		rm -rf "$_chimera_work"
		rm -f /tmp/nb-linux /tmp/nb-initrd
		return 1
	fi

	rm -f /tmp/nb-chimera-7z.log /tmp/nb-chimera-mount.log /tmp/nb-chimera-cpio.log
	return 0
}

coyote_repack_initrd_with_iso ()
{
	_coyote_iso="$1"
	_coyote_parent="${_coyote_iso%/*}"
	_coyote_tree="$_coyote_parent/initrd-work"
	_coyote_repacked="$_coyote_parent/nb-initrd.repacked"
	_coyote_final="$_coyote_parent/nb-initrd"
	_coyote_media_script="$_coyote_tree/init.d/03-find-installer.sh"

	rm -rf "$_coyote_tree" "$_coyote_repacked" "$_coyote_final"
	mkdir -p "$_coyote_tree"
	if ! ( gzip -cd /tmp/nb-initrd | ( cd "$_coyote_tree" && cpio -idmu ) ) 2>/tmp/nb-coyote-cpio.log; then
		nb_error "Could not unpack the $COYOTE_LABEL initramfs.\nSee /tmp/nb-coyote-cpio.log for details."
		rm -rf "$_coyote_tree"
		return 1
	fi
	if [ ! -s "$_coyote_media_script" ]; then
		nb_error "Could not find the $COYOTE_LABEL installer media search script."
		rm -rf "$_coyote_tree"
		return 1
	fi

	mkdir -p "$_coyote_tree/netbootcd"
	if ! mv "$_coyote_iso" "$_coyote_tree/netbootcd/coyote.iso"; then
		nb_error "Could not embed the $COYOTE_LABEL ISO into the initramfs."
		rm -rf "$_coyote_tree"
		return 1
	fi

	if ! awk '
		/^# Function to check CD-ROM devices for installer$/ && !added_function {
			print "# Function to check the installer ISO embedded by NetbootCD-Neo"
			print "check_netbootcd_media() {"
			print "    [ -f /netbootcd/coyote.iso ] || return 1"
			print ""
			print "    log \"  Checking embedded installer ISO\""
			print "    [ -b /dev/loop0 ] || mknod /dev/loop0 b 7 0 2>/dev/null || true"
			print "    /bin/busybox losetup /dev/loop0 /netbootcd/coyote.iso 2>/dev/null || return 1"
			print "    if ! mount -o ro /dev/loop0 \"$MEDIA_MNT\" 2>/dev/null; then"
			print "        /bin/busybox losetup -d /dev/loop0 2>/dev/null || true"
			print "        return 1"
			print "    fi"
			print ""
			print "    if [ -f \"${MEDIA_MNT}/coyote.marker\" ]; then"
			print "        marker=$(cat \"${MEDIA_MNT}/coyote.marker\" 2>/dev/null)"
			print "        if [ \"$marker\" = \"COYOTE_INSTALLER\" ]; then"
			print "            INSTALLER_MEDIA=/dev/loop0"
			print "            INSTALLER_MEDIA_TYPE=embedded"
			print "            log \"  Found embedded installer ISO\""
			print "            return 0"
			print "        fi"
			print "    fi"
			print "    umount \"$MEDIA_MNT\" 2>/dev/null"
			print "    /bin/busybox losetup -d /dev/loop0 2>/dev/null || true"
			print "    return 1"
			print "}"
			print ""
			added_function=1
		}
		/^if ! check_cdrom_devices && ! check_disk_devices; then$/ {
			print "if ! check_netbootcd_media && ! check_cdrom_devices && ! check_disk_devices; then"
			changed_search=1
			next
		}
		{ print }
		END { if (!added_function || !changed_search) exit 1 }
	' "$_coyote_media_script" >"$_coyote_media_script.new"; then
		nb_error "Could not patch the $COYOTE_LABEL installer media search."
		rm -rf "$_coyote_tree"
		return 1
	fi
	mv "$_coyote_media_script.new" "$_coyote_media_script"
	chmod 755 "$_coyote_media_script"

	if ! ( cd "$_coyote_tree" && find . | cpio -o -H newc | gzip -1 -c >"$_coyote_repacked" ); then
		nb_error "Could not repack the $COYOTE_LABEL gzip initramfs."
		rm -rf "$_coyote_tree"
		return 1
	fi

	rm -rf "$_coyote_tree"
	mv "$_coyote_repacked" "$_coyote_final"
	rm -f /tmp/nb-initrd
	ln -s "$_coyote_final" /tmp/nb-initrd
	return 0
}

coyote_prepare_from_iso ()
{
	_coyote_iso_url="$1"
	_coyote_work="/tmp/nb-coyote-work"
	_coyote_iso="$_coyote_work/nb-coyote.iso"
	_coyote_boot="$_coyote_work/boot"

	if ! _coyote_7z=$(artix_7z_cmd); then
		nb_error "7zip is required to extract $COYOTE_LABEL ISO boot files. Rebuild NetbootCD-Neo with 7zip included."
		return 1
	fi

	if grep -q " $_coyote_work " /proc/mounts 2>/dev/null; then
		umount "$_coyote_work" 2>/dev/null || true
	fi
	rm -f /tmp/nb-linux /tmp/nb-initrd
	rm -rf "$_coyote_work"
	mkdir -p "$_coyote_boot"
	_coyote_mounted=
	if mount -t tmpfs -o size=85%,mode=0755 tmpfs "$_coyote_work" 2>/tmp/nb-coyote-mount.log; then
		_coyote_mounted=1
		mkdir -p "$_coyote_boot"
	fi

	if ! wgetgauge "$_coyote_iso_url" "$_coyote_iso" "Downloading $COYOTE_LABEL ISO"; then
		nb_error "Could not download $COYOTE_LABEL ISO from:\n\n$_coyote_iso_url\n\nThis entry needs enough RAM to hold the ISO and the repacked initrd."
		[ -n "$_coyote_mounted" ] && umount "$_coyote_work" 2>/dev/null || true
		rm -rf "$_coyote_work"
		return 1
	fi

	if ! "$_coyote_7z" e -y -o"$_coyote_boot" "$_coyote_iso" "$COYOTE_KERNEL_PATH" "$COYOTE_INITRD_PATH" >/tmp/nb-coyote-7z.log 2>&1; then
		nb_error "Could not extract $COYOTE_LABEL boot files from the ISO.\nSee /tmp/nb-coyote-7z.log for details."
		[ -n "$_coyote_mounted" ] && umount "$_coyote_work" 2>/dev/null || true
		rm -rf "$_coyote_work"
		return 1
	fi
	_coyote_kernel_file="${COYOTE_KERNEL_PATH##*/}"
	_coyote_initrd_file="${COYOTE_INITRD_PATH##*/}"
	if [ ! -s "$_coyote_boot/$_coyote_kernel_file" ] || [ ! -s "$_coyote_boot/$_coyote_initrd_file" ]; then
		nb_error "The $COYOTE_LABEL ISO did not contain its expected kernel and initramfs."
		[ -n "$_coyote_mounted" ] && umount "$_coyote_work" 2>/dev/null || true
		rm -rf "$_coyote_work"
		return 1
	fi

	mv "$_coyote_boot/$_coyote_kernel_file" /tmp/nb-linux
	mv "$_coyote_boot/$_coyote_initrd_file" /tmp/nb-initrd
	rm -rf "$_coyote_boot"

	dialog --backtitle "$TITLE" --infobox \
		"Embedding the $COYOTE_LABEL ISO into the initrd.\n\nThis can take a while." 7 70 || true
	if ! coyote_repack_initrd_with_iso "$_coyote_iso"; then
		[ -n "$_coyote_mounted" ] && umount "$_coyote_work" 2>/dev/null || true
		rm -rf "$_coyote_work"
		rm -f /tmp/nb-linux /tmp/nb-initrd
		return 1
	fi

	rm -f /tmp/nb-coyote-7z.log /tmp/nb-coyote-mount.log /tmp/nb-coyote-cpio.log
	return 0
}

nutyx_repack_initrd_with_rootfs ()
{
	_nutyx_rootfs="$1"
	_nutyx_work="/tmp/nb-nutyx-initrd-work"
	_nutyx_repacked="/tmp/nb-initrd.nutyx"

	if ! command -v zstd >/dev/null 2>&1; then
		nb_error "zstd is required to prepare the $NUTYX_LABEL initramfs. Rebuild NetbootCD-Neo with zstd included."
		return 1
	fi

	rm -rf "$_nutyx_work" "$_nutyx_repacked"
	mkdir -p "$_nutyx_work"
	if ! ( zstd -dc /tmp/nb-initrd | ( cd "$_nutyx_work" && cpio -idmu ) ) 2>/tmp/nb-nutyx-cpio.log; then
		nb_error "Could not unpack the $NUTYX_LABEL zstd initramfs.\nSee /tmp/nb-nutyx-cpio.log for details."
		rm -rf "$_nutyx_work"
		return 1
	fi
	if [ ! -s "$_nutyx_work/init" ]; then
		nb_error "Could not find the $NUTYX_LABEL initramfs media search logic."
		rm -rf "$_nutyx_work"
		return 1
	fi

	mkdir -p "$_nutyx_work/media/cdrom/boot"
	if ! mv "$_nutyx_rootfs" "$_nutyx_work/media/cdrom/boot/NuTyX.squashfs"; then
		nb_error "Could not embed the $NUTYX_LABEL live filesystem."
		rm -rf "$_nutyx_work"
		return 1
	fi

	if ! awk '
		/^find_media\(\) \{$/ {
			print
			print "\tif [ -s /media/cdrom/boot/NuTyX.squashfs ]; then"
			print "\t\tprintf \"Using embedded NetbootCD-Neo NuTyX media\\n\""
			print "\t\treturn"
			print "\tfi"
			inserted=1
			next
		}
		{ print }
		END { if (!inserted) exit 1 }
	' "$_nutyx_work/init" >"$_nutyx_work/init.new"; then
		nb_error "Could not patch the $NUTYX_LABEL media search."
		rm -rf "$_nutyx_work"
		return 1
	fi
	mv "$_nutyx_work/init.new" "$_nutyx_work/init"
	chmod 755 "$_nutyx_work/init"

	if ! ( cd "$_nutyx_work" && find . | cpio -o -H newc | zstd -q -1 -c >"$_nutyx_repacked" ); then
		nb_error "Could not repack the $NUTYX_LABEL zstd initramfs."
		rm -rf "$_nutyx_work"
		return 1
	fi

	rm -rf "$_nutyx_work"
	mv "$_nutyx_repacked" /tmp/nb-initrd
	return 0
}

nutyx_prepare_from_iso ()
{
	_nutyx_iso_url="$1"
	_nutyx_work="/tmp/nb-nutyx-work"
	_nutyx_iso="$_nutyx_work/nb-nutyx.iso"
	_nutyx_extract="$_nutyx_work/extract"

	if ! _nutyx_7z=$(artix_7z_cmd); then
		nb_error "7zip is required to extract $NUTYX_LABEL boot files. Rebuild NetbootCD-Neo with 7zip included."
		return 1
	fi

	if grep -q " $_nutyx_work " /proc/mounts 2>/dev/null; then
		umount "$_nutyx_work" 2>/dev/null || true
	fi
	rm -f /tmp/nb-linux /tmp/nb-initrd
	rm -rf "$_nutyx_work" /tmp/nb-nutyx-initrd-work /tmp/nb-initrd.nutyx
	mkdir -p "$_nutyx_extract"
	_nutyx_mounted=
	if mount -t tmpfs -o size=85%,mode=0755 tmpfs "$_nutyx_work" 2>/tmp/nb-nutyx-mount.log; then
		_nutyx_mounted=1
		mkdir -p "$_nutyx_extract"
	fi

	if ! wgetgauge "$_nutyx_iso_url" "$_nutyx_iso" "Downloading $NUTYX_LABEL ISO"; then
		nb_error "Could not download $NUTYX_LABEL ISO from:\n\n$_nutyx_iso_url\n\nThis entry needs enough RAM to hold and prepare the installable live system."
		[ -n "$_nutyx_mounted" ] && umount "$_nutyx_work" 2>/dev/null || true
		rm -rf "$_nutyx_work"
		return 1
	fi

	if ! "$_nutyx_7z" e -y -o"$_nutyx_extract" "$_nutyx_iso" "$NUTYX_KERNEL_PATH" "$NUTYX_INITRD_PATH" "$NUTYX_ROOTFS_PATH" >/tmp/nb-nutyx-7z.log 2>&1; then
		nb_error "Could not extract $NUTYX_LABEL live files from the ISO.\nSee /tmp/nb-nutyx-7z.log for details."
		[ -n "$_nutyx_mounted" ] && umount "$_nutyx_work" 2>/dev/null || true
		rm -rf "$_nutyx_work"
		return 1
	fi
	_nutyx_kernel_file="${NUTYX_KERNEL_PATH##*/}"
	_nutyx_initrd_file="${NUTYX_INITRD_PATH##*/}"
	_nutyx_rootfs_file="${NUTYX_ROOTFS_PATH##*/}"
	if [ ! -s "$_nutyx_extract/$_nutyx_kernel_file" ] || [ ! -s "$_nutyx_extract/$_nutyx_initrd_file" ] || [ ! -s "$_nutyx_extract/$_nutyx_rootfs_file" ]; then
		nb_error "The $NUTYX_LABEL ISO did not contain its expected live files."
		[ -n "$_nutyx_mounted" ] && umount "$_nutyx_work" 2>/dev/null || true
		rm -rf "$_nutyx_work"
		return 1
	fi

	mv "$_nutyx_extract/$_nutyx_kernel_file" /tmp/nb-linux
	mv "$_nutyx_extract/$_nutyx_initrd_file" /tmp/nb-initrd
	rm -f "$_nutyx_iso"

	dialog --backtitle "$TITLE" --infobox \
		"Embedding the $NUTYX_LABEL live filesystem into the initrd.\n\nThis can take a while." 7 70 || true
	if ! nutyx_repack_initrd_with_rootfs "$_nutyx_extract/$_nutyx_rootfs_file"; then
		[ -n "$_nutyx_mounted" ] && umount "$_nutyx_work" 2>/dev/null || true
		rm -rf "$_nutyx_work"
		rm -f /tmp/nb-linux /tmp/nb-initrd
		return 1
	fi

	rm -f /tmp/nb-nutyx-7z.log /tmp/nb-nutyx-mount.log /tmp/nb-nutyx-cpio.log
	[ -n "$_nutyx_mounted" ] && umount "$_nutyx_work" 2>/dev/null || true
	rm -rf "$_nutyx_work"
	return 0
}

salix_repack_initrd_with_iso ()
{
	_salix_iso="$1"
	_salix_work="/tmp/nb-salix-initrd-work"
	_salix_repacked="/tmp/nb-initrd.salix"

	rm -rf "$_salix_work" "$_salix_repacked"
	mkdir -p "$_salix_work"
	if ! ( gzip -cd /tmp/nb-initrd | ( cd "$_salix_work" && cpio -idmu ) ) 2>/tmp/nb-salix-cpio.log; then
		nb_error "Could not unpack the $SALIX_LABEL gzip initramfs.\nSee /tmp/nb-salix-cpio.log for details."
		rm -rf "$_salix_work"
		return 1
	fi
	if [ ! -s "$_salix_work/init" ]; then
		nb_error "Could not find the $SALIX_LABEL initramfs media search logic."
		rm -rf "$_salix_work"
		return 1
	fi

	if ! mv "$_salix_iso" "$_salix_work/netbootcd-salix.iso"; then
		nb_error "Could not embed the $SALIX_LABEL ISO into the initramfs."
		rm -rf "$_salix_work"
		return 1
	fi
	if ! awk '
		{ print }
		$0 == "mdev -s" {
			print ""
			print "# Attach the NetbootCD-Neo ISO before Salix searches for LIVE media."
			print "if [ -f /netbootcd-salix.iso ]; then"
			print "\tfor NETBOOTCD_LOOP_NUMBER in 0 1 2 3 4 5 6 7; do"
			print "\t\tNETBOOTCD_LOOP_DEVICE=\"/dev/loop$NETBOOTCD_LOOP_NUMBER\""
			print "\t\t[ -b \"$NETBOOTCD_LOOP_DEVICE\" ] || mknod \"$NETBOOTCD_LOOP_DEVICE\" b 7 \"$NETBOOTCD_LOOP_NUMBER\" 2>/dev/null"
			print "\t\tif losetup \"$NETBOOTCD_LOOP_DEVICE\" /netbootcd-salix.iso 2>/dev/null; then"
			print "\t\t\techo \"NetbootCD-Neo: attached embedded SalixLive ISO to $NETBOOTCD_LOOP_DEVICE\""
			print "\t\t\tbreak"
			print "\t\tfi"
			print "\tdone"
			print "fi"
			inserted=1
		}
		END { if (!inserted) exit 1 }
	' "$_salix_work/init" >"$_salix_work/init.new"; then
		nb_error "Could not patch the $SALIX_LABEL media search."
		rm -rf "$_salix_work"
		return 1
	fi
	mv "$_salix_work/init.new" "$_salix_work/init"
	chmod 755 "$_salix_work/init"

	if ! ( cd "$_salix_work" && find . | cpio -o -H newc | gzip -1 -c >"$_salix_repacked" ); then
		nb_error "Could not repack the $SALIX_LABEL gzip initramfs."
		rm -rf "$_salix_work"
		return 1
	fi

	rm -rf "$_salix_work"
	mv "$_salix_repacked" /tmp/nb-initrd
	return 0
}

salix_prepare_from_iso ()
{
	_salix_iso_url="$1"
	_salix_work="/tmp/nb-salix-work"
	_salix_iso="$_salix_work/nb-salix.iso"
	_salix_extract="$_salix_work/extract"

	if ! _salix_7z=$(artix_7z_cmd); then
		nb_error "7zip is required to extract $SALIX_LABEL boot files. Rebuild NetbootCD-Neo with 7zip included."
		return 1
	fi

	if grep -q " $_salix_work " /proc/mounts 2>/dev/null; then
		umount "$_salix_work" 2>/dev/null || true
	fi
	rm -f /tmp/nb-linux /tmp/nb-initrd
	rm -rf "$_salix_work" /tmp/nb-salix-initrd-work /tmp/nb-initrd.salix
	mkdir -p "$_salix_extract"
	_salix_mounted=
	if mount -t tmpfs -o size=85%,mode=0755 tmpfs "$_salix_work" 2>/tmp/nb-salix-mount.log; then
		_salix_mounted=1
		mkdir -p "$_salix_extract"
	fi

	if ! wgetgauge "$_salix_iso_url" "$_salix_iso" "Downloading $SALIX_LABEL ISO"; then
		nb_error "Could not download $SALIX_LABEL ISO from:\n\n$_salix_iso_url\n\nThis entry needs enough RAM to hold and prepare the installable live system."
		[ -n "$_salix_mounted" ] && umount "$_salix_work" 2>/dev/null || true
		rm -rf "$_salix_work"
		return 1
	fi

	if ! "$_salix_7z" e -y -o"$_salix_extract" "$_salix_iso" "$SALIX_KERNEL_PATH" "$SALIX_INITRD_PATH" >/tmp/nb-salix-7z.log 2>&1; then
		nb_error "Could not extract $SALIX_LABEL boot files from the ISO.\nSee /tmp/nb-salix-7z.log for details."
		[ -n "$_salix_mounted" ] && umount "$_salix_work" 2>/dev/null || true
		rm -rf "$_salix_work"
		return 1
	fi
	_salix_kernel_file="${SALIX_KERNEL_PATH##*/}"
	_salix_initrd_file="${SALIX_INITRD_PATH##*/}"
	if [ ! -s "$_salix_extract/$_salix_kernel_file" ] || [ ! -s "$_salix_extract/$_salix_initrd_file" ]; then
		nb_error "The $SALIX_LABEL ISO did not contain its expected boot files."
		[ -n "$_salix_mounted" ] && umount "$_salix_work" 2>/dev/null || true
		rm -rf "$_salix_work"
		return 1
	fi

	mv "$_salix_extract/$_salix_kernel_file" /tmp/nb-linux
	mv "$_salix_extract/$_salix_initrd_file" /tmp/nb-initrd

	dialog --backtitle "$TITLE" --infobox \
		"Embedding the $SALIX_LABEL ISO into the initrd.\n\nThis can take a while." 7 70 || true
	if ! salix_repack_initrd_with_iso "$_salix_iso"; then
		[ -n "$_salix_mounted" ] && umount "$_salix_work" 2>/dev/null || true
		rm -rf "$_salix_work"
		rm -f /tmp/nb-linux /tmp/nb-initrd
		return 1
	fi

	rm -f /tmp/nb-salix-7z.log /tmp/nb-salix-mount.log /tmp/nb-salix-cpio.log
	[ -n "$_salix_mounted" ] && umount "$_salix_work" 2>/dev/null || true
	rm -rf "$_salix_work"
	return 0
}

venom_repack_initrd_with_iso ()
{
	_venom_iso="$1"
	_venom_work="/tmp/nb-venom-initrd-work"
	_venom_repacked="/tmp/nb-initrd.venom"
	_venom_liveiso="$_venom_work/hook/liveiso"

	rm -rf "$_venom_work" "$_venom_repacked"
	mkdir -p "$_venom_work"
	if ! ( gzip -cd /tmp/nb-initrd | ( cd "$_venom_work" && cpio -idmu ) ) 2>/tmp/nb-venom-cpio.log; then
		nb_error "Could not unpack the $VENOM_LABEL gzip initramfs.\nSee /tmp/nb-venom-cpio.log for details."
		rm -rf "$_venom_work"
		return 1
	fi
	if [ ! -s "$_venom_liveiso" ]; then
		nb_error "Could not find the $VENOM_LABEL live media hook."
		rm -rf "$_venom_work"
		return 1
	fi

	mkdir -p "$_venom_work/.netbootcd"
	if ! mv "$_venom_iso" "$_venom_work/.netbootcd/venom.iso"; then
		nb_error "Could not embed the $VENOM_LABEL ISO into the initramfs."
		rm -rf "$_venom_work"
		return 1
	fi
	if ! awk '
		$0 == "\tMEDIA=/dev/disk/by-label/LIVEISO" && !media {
			print "\tif [ -f /.netbootcd/venom.iso ]; then"
			print "\t\tMEDIA=/.netbootcd/venom.iso"
			print "\t\tMEDIA_MOUNT_OPTS=\"-o loop,ro\""
			print "\telse"
			print "\t\tMEDIA=/dev/disk/by-label/LIVEISO"
			print "\t\tMEDIA_MOUNT_OPTS=\"-o ro\""
			print "\tfi"
			media=1
			next
		}
		$0 == "\tmount -o ro $MEDIA $MEDIUM || problem" && !mount_media {
			print "\tmount $MEDIA_MOUNT_OPTS $MEDIA $MEDIUM || problem"
			mount_media=1
			next
		}
		{ print }
		END { if (!media || !mount_media) exit 1 }
	' "$_venom_liveiso" >"$_venom_liveiso.new"; then
		nb_error "Could not patch the $VENOM_LABEL live media hook."
		rm -rf "$_venom_work"
		return 1
	fi
	mv "$_venom_liveiso.new" "$_venom_liveiso"
	chmod 755 "$_venom_liveiso"

	if ! ( cd "$_venom_work" && find . | cpio -o -H newc | gzip -1 -c >"$_venom_repacked" ); then
		nb_error "Could not repack the $VENOM_LABEL gzip initramfs."
		rm -rf "$_venom_work"
		return 1
	fi

	rm -rf "$_venom_work"
	mv "$_venom_repacked" /tmp/nb-initrd
	return 0
}

venom_prepare_from_iso ()
{
	_venom_iso_url="$1"
	_venom_work="/tmp/nb-venom-work"
	_venom_iso="$_venom_work/nb-venom.iso"
	_venom_extract="$_venom_work/extract"

	if ! _venom_7z=$(artix_7z_cmd); then
		nb_error "7zip is required to extract $VENOM_LABEL boot files. Rebuild NetbootCD-Neo with 7zip included."
		return 1
	fi

	if grep -q " $_venom_work " /proc/mounts 2>/dev/null; then
		umount "$_venom_work" 2>/dev/null || true
	fi
	rm -f /tmp/nb-linux /tmp/nb-initrd
	rm -rf "$_venom_work" /tmp/nb-venom-initrd-work /tmp/nb-initrd.venom
	mkdir -p "$_venom_extract"
	_venom_mounted=
	if mount -t tmpfs -o size=85%,mode=0755 tmpfs "$_venom_work" 2>/tmp/nb-venom-mount.log; then
		_venom_mounted=1
		mkdir -p "$_venom_extract"
	fi

	if ! wgetgauge "$_venom_iso_url" "$_venom_iso" "Downloading $VENOM_LABEL ISO"; then
		nb_error "Could not download $VENOM_LABEL ISO from:\n\n$_venom_iso_url\n\nThis entry needs enough RAM to hold and prepare the installable live system."
		[ -n "$_venom_mounted" ] && umount "$_venom_work" 2>/dev/null || true
		rm -rf "$_venom_work"
		return 1
	fi

	if ! "$_venom_7z" e -y -o"$_venom_extract" "$_venom_iso" "$VENOM_KERNEL_PATH" "$VENOM_INITRD_PATH" >/tmp/nb-venom-7z.log 2>&1; then
		nb_error "Could not extract $VENOM_LABEL boot files from the ISO.\nSee /tmp/nb-venom-7z.log for details."
		[ -n "$_venom_mounted" ] && umount "$_venom_work" 2>/dev/null || true
		rm -rf "$_venom_work"
		return 1
	fi
	_venom_kernel_file="${VENOM_KERNEL_PATH##*/}"
	_venom_initrd_file="${VENOM_INITRD_PATH##*/}"
	if [ ! -s "$_venom_extract/$_venom_kernel_file" ] || [ ! -s "$_venom_extract/$_venom_initrd_file" ]; then
		nb_error "The $VENOM_LABEL ISO did not contain its expected boot files."
		[ -n "$_venom_mounted" ] && umount "$_venom_work" 2>/dev/null || true
		rm -rf "$_venom_work"
		return 1
	fi

	mv "$_venom_extract/$_venom_kernel_file" /tmp/nb-linux
	mv "$_venom_extract/$_venom_initrd_file" /tmp/nb-initrd

	dialog --backtitle "$TITLE" --infobox \
		"Embedding the $VENOM_LABEL ISO into the initrd.\n\nThis can take a while." 7 70 || true
	if ! venom_repack_initrd_with_iso "$_venom_iso"; then
		[ -n "$_venom_mounted" ] && umount "$_venom_work" 2>/dev/null || true
		rm -rf "$_venom_work"
		rm -f /tmp/nb-linux /tmp/nb-initrd
		return 1
	fi

	rm -f /tmp/nb-venom-7z.log /tmp/nb-venom-mount.log /tmp/nb-venom-cpio.log
	[ -n "$_venom_mounted" ] && umount "$_venom_work" 2>/dev/null || true
	rm -rf "$_venom_work"
	return 0
}

archiso_live_iso_setup ()
{
	ARCHISO_LABEL="$1"
	ARCHISO_ISO_URL="$2"
	ARCHISO_KERNEL_PATH="$3"
	ARCHISO_INITRD_PATH="$4"
	ARCHISO_ROOTFS_PATH="$5"
	ARCHISO_CHECKSUM_PATH="$6"
	printf '%s' "$7 " >>/tmp/nb-options
}

archiso_repack_initrd_with_rootfs ()
{
	_archiso_rootfs="$1"
	_archiso_checksum="$2"
	_archiso_work="/tmp/nb-archiso-initrd-work"
	_archiso_repacked="/tmp/nb-initrd.archiso"

	if ! _archiso_main_info=$(artix_find_main_initrd /tmp/nb-initrd); then
		nb_error "Could not determine the $ARCHISO_LABEL initramfs compression format."
		return 1
	fi
	_archiso_format="${_archiso_main_info%% *}"
	_archiso_main_offset="${_archiso_main_info#* }"

	if ! nb_initrd_need_tool "$_archiso_format" "$ARCHISO_LABEL"; then
		return 1
	fi

	rm -rf "$_archiso_work" "$_archiso_repacked" /tmp/nb-initrd.new
	mkdir -p "$_archiso_work"

	if ! nb_initrd_unpack /tmp/nb-initrd "$_archiso_work" "$_archiso_format" "$_archiso_main_offset" "-idmu" "/dev/null"; then
		nb_error "Could not unpack the $ARCHISO_LABEL $_archiso_format initramfs."
		rm -rf "$_archiso_work"
		return 1
	fi

	_archiso_rootfs_dest="$_archiso_work/$ARCHISO_ROOTFS_PATH"
	_archiso_rootfs_dir="${_archiso_rootfs_dest%/*}"
	mkdir -p "$_archiso_rootfs_dir" "$_archiso_work/hooks"
	if ! mv "$_archiso_rootfs" "$_archiso_rootfs_dest"; then
		nb_error "Could not embed the $ARCHISO_LABEL root filesystem."
		rm -rf "$_archiso_work"
		return 1
	fi
	if [ -n "$_archiso_checksum" ] && [ -f "$_archiso_checksum" ]; then
		mv "$_archiso_checksum" "$_archiso_rootfs_dir/${ARCHISO_CHECKSUM_PATH##*/}" || true
	fi

	cat >"$_archiso_work/hooks/netbootcd_archiso" <<'EOFA'
#!/usr/bin/ash

run_hook() {
    if [ -f "/${archisobasedir}/${arch}/airootfs.sfs" ] || [ -f "/${archisobasedir}/${arch}/airootfs.erofs" ]; then
        copytoram=n
        export mount_handler="netbootcd_archiso_mount_handler"
    fi
}

netbootcd_archiso_mount_handler() {
    newroot="${1}"

    msg ":: Using NetbootCD embedded archiso root filesystem"
    mkdir -p /run/archiso/bootmnt
    if ! mountpoint -q /run/archiso/bootmnt; then
        mount --bind / /run/archiso/bootmnt || {
            echo "ERROR: could not bind initramfs for embedded archiso root"
            launch_interactive_shell
        }
    fi

    archisodevice=/
    copytoram=n
    archiso_mount_handler "$newroot"
}
EOFA
	chmod 755 "$_archiso_work/hooks/netbootcd_archiso"

	if [ -f "$_archiso_work/config" ] && ! grep -q 'netbootcd_archiso' "$_archiso_work/config"; then
		if grep -q '^HOOKS="' "$_archiso_work/config"; then
			if ! sed 's/^HOOKS="\([^"]*\)"/HOOKS="\1 netbootcd_archiso"/' "$_archiso_work/config" >"$_archiso_work/config.new"; then
				nb_error "Could not update the $ARCHISO_LABEL initramfs hook list."
				rm -rf "$_archiso_work" "$_archiso_repacked" "$_archiso_work/config.new"
				return 1
			fi
			mv "$_archiso_work/config.new" "$_archiso_work/config"
		else
			printf '\nHOOKS="${HOOKS} netbootcd_archiso"\n' >>"$_archiso_work/config"
		fi
	fi

	if ! nb_initrd_repack "$_archiso_work" "$_archiso_repacked" "$_archiso_format" "standard"; then
		nb_error "Could not repack the $ARCHISO_LABEL $_archiso_format initramfs."
		rm -rf "$_archiso_work"
		return 1
	fi

	: >/tmp/nb-initrd.new
	if [ "$_archiso_main_offset" -gt 0 ]; then
		if ! head -c "$_archiso_main_offset" /tmp/nb-initrd >>/tmp/nb-initrd.new; then
			nb_error "Could not preserve the $ARCHISO_LABEL early initramfs prefix."
			rm -rf "$_archiso_work" "$_archiso_repacked" /tmp/nb-initrd.new
			return 1
		fi
	fi
	if ! cat "$_archiso_repacked" >>/tmp/nb-initrd.new; then
		nb_error "Could not write the repacked $ARCHISO_LABEL initramfs."
		rm -rf "$_archiso_work" "$_archiso_repacked" /tmp/nb-initrd.new
		return 1
	fi
	mv /tmp/nb-initrd.new /tmp/nb-initrd
	rm -rf "$_archiso_work" "$_archiso_repacked"
	return 0
}

archiso_prepare_from_iso ()
{
	_archiso_iso_url="$1"
	_archiso_work="/tmp/nb-archiso-work"
	_archiso_iso="$_archiso_work/nb-archiso.iso"
	_archiso_boot="$_archiso_work/boot"
	_archiso_rootfs="$_archiso_work/airootfs.sfs"
	_archiso_checksum="$_archiso_work/airootfs.sha512"

	if ! _archiso_7z=$(artix_7z_cmd); then
		nb_error "7zip is required to extract $ARCHISO_LABEL boot files. Rebuild NetbootCD-Neo with 7zip included."
		return 1
	fi

	if grep -q " $_archiso_work " /proc/mounts 2>/dev/null; then
		umount "$_archiso_work" 2>/dev/null || true
	fi
	rm -f /tmp/nb-linux /tmp/nb-initrd
	rm -rf "$_archiso_work" /tmp/nb-archiso-initrd-work /tmp/nb-initrd.archiso /tmp/nb-initrd.new
	mkdir -p "$_archiso_boot"
	_archiso_mounted=
	if mount -t tmpfs -o size=85%,mode=0755 tmpfs "$_archiso_work" 2>/tmp/nb-archiso-mount.log; then
		_archiso_mounted=1
		mkdir -p "$_archiso_boot"
	fi

	if ! wgetgauge "$_archiso_iso_url" "$_archiso_iso" "Downloading $ARCHISO_LABEL ISO"; then
		nb_error "Could not download $ARCHISO_LABEL ISO from:\n\n$_archiso_iso_url\n\nThis entry needs enough RAM to hold the ISO before kexec."
		[ -n "$_archiso_mounted" ] && umount "$_archiso_work" 2>/dev/null || true
		rm -rf "$_archiso_work"
		return 1
	fi

	if ! "$_archiso_7z" e -y -o"$_archiso_boot" "$_archiso_iso" "$ARCHISO_KERNEL_PATH" "$ARCHISO_INITRD_PATH" >/tmp/nb-archiso-7z.log 2>&1; then
		nb_error "Could not extract $ARCHISO_LABEL boot files from the ISO.\nSee /tmp/nb-archiso-7z.log for details."
		[ -n "$_archiso_mounted" ] && umount "$_archiso_work" 2>/dev/null || true
		rm -rf "$_archiso_work"
		return 1
	fi
	_archiso_kernel_file="${ARCHISO_KERNEL_PATH##*/}"
	_archiso_initrd_file="${ARCHISO_INITRD_PATH##*/}"
	if [ ! -s "$_archiso_boot/$_archiso_kernel_file" ] || [ ! -s "$_archiso_boot/$_archiso_initrd_file" ]; then
		nb_error "The $ARCHISO_LABEL ISO did not contain its expected kernel and initramfs."
		[ -n "$_archiso_mounted" ] && umount "$_archiso_work" 2>/dev/null || true
		rm -rf "$_archiso_work"
		return 1
	fi
	mv "$_archiso_boot/$_archiso_kernel_file" /tmp/nb-linux
	mv "$_archiso_boot/$_archiso_initrd_file" /tmp/nb-initrd
	rm -rf "$_archiso_boot"

	if ! "$_archiso_7z" e -y -o"$_archiso_work" "$_archiso_iso" "$ARCHISO_ROOTFS_PATH" >>/tmp/nb-archiso-7z.log 2>&1; then
		nb_error "Could not extract $ARCHISO_LABEL root filesystem from the ISO.\nSee /tmp/nb-archiso-7z.log for details."
		[ -n "$_archiso_mounted" ] && umount "$_archiso_work" 2>/dev/null || true
		rm -rf "$_archiso_work"
		rm -f /tmp/nb-linux /tmp/nb-initrd
		return 1
	fi
	_archiso_rootfs_file="${ARCHISO_ROOTFS_PATH##*/}"
	if [ ! -s "$_archiso_work/$_archiso_rootfs_file" ]; then
		nb_error "The $ARCHISO_LABEL ISO did not contain $ARCHISO_ROOTFS_PATH."
		[ -n "$_archiso_mounted" ] && umount "$_archiso_work" 2>/dev/null || true
		rm -rf "$_archiso_work"
		rm -f /tmp/nb-linux /tmp/nb-initrd
		return 1
	fi
	mv "$_archiso_work/$_archiso_rootfs_file" "$_archiso_rootfs"

	if [ -n "$ARCHISO_CHECKSUM_PATH" ]; then
		"$_archiso_7z" e -y -o"$_archiso_work" "$_archiso_iso" "$ARCHISO_CHECKSUM_PATH" >>/tmp/nb-archiso-7z.log 2>&1 || true
		_archiso_checksum_file="${ARCHISO_CHECKSUM_PATH##*/}"
		[ -s "$_archiso_work/$_archiso_checksum_file" ] && mv "$_archiso_work/$_archiso_checksum_file" "$_archiso_checksum"
	fi
	rm -f "$_archiso_iso"

	dialog --backtitle "$TITLE" --infobox \
		"Embedding the $ARCHISO_LABEL root filesystem into the initrd.\n\nThis can take a while for large ISOs." 7 70 || true
	if ! archiso_repack_initrd_with_rootfs "$_archiso_rootfs" "$_archiso_checksum"; then
		[ -n "$_archiso_mounted" ] && umount "$_archiso_work" 2>/dev/null || true
		rm -rf "$_archiso_work"
		rm -f /tmp/nb-linux /tmp/nb-initrd /tmp/nb-initrd.new /tmp/nb-initrd.archiso
		return 1
	fi

	rm -f "$_archiso_iso" "$_archiso_rootfs" "$_archiso_checksum" /tmp/nb-archiso-7z.log /tmp/nb-archiso-mount.log
	[ -n "$_archiso_mounted" ] && umount "$_archiso_work" 2>/dev/null || true
	rm -rf "$_archiso_work"
	return 0
}

garuda_iso_setup ()
{
	GARUDA_LABEL="$1"
	GARUDA_ISO_URL="$2"
	GARUDA_KERNEL_PATH="$3"
	GARUDA_INITRD_PATH="$4"
	GARUDA_BASEDIR="$5"
	GARUDA_ARCH="$6"
	printf '%s' "misobasedir=$GARUDA_BASEDIR root=miso:/dev/null checksum=n copytoram=n overlay_root_size=75% netbootcd_garuda=1 systemd.show_status=1 " >>/tmp/nb-options
}

garuda_patch_miso_scripts ()
{
	_garuda_initrd_work="$1"
	_garuda_miso_script=
	_garuda_parse_script=

	_garuda_miso_script=$(find "$_garuda_initrd_work" -type f -name '*miso*.sh' -exec grep -l 'miso_mount_root' {} + 2>/dev/null | head -n 1)
	_garuda_parse_script=$(find "$_garuda_initrd_work" -type f -name '*miso*.sh' -exec grep -l 'root#miso' {} + 2>/dev/null | head -n 1)

	if [ -z "$_garuda_miso_script" ]; then
		nb_error "Could not find the $GARUDA_LABEL miso mount script in the initramfs."
		return 1
	fi

	if ! awk '
		/^miso_mount_root\(\)/ {
			in_miso_mount_root = 1
		}
		in_miso_mount_root && /^[[:space:]]*if ! mountpoint -q "\/run\/miso\/bootmnt"; then/ && ! inserted {
			print "    if [[ -f \"/${misobasedir}/${arch}/rootfs.sfs\" ]]; then"
			print "        echo \":: Using NetbootCD embedded Garuda live media\""
			print "        mkdir -p /run/miso/bootmnt"
			print "        if [[ ! -d \"/run/miso/bootmnt/${misobasedir}/${arch}\" ]]; then"
			print "            mkdir -p \"/run/miso/bootmnt/${misobasedir}\""
			print "            mv \"/${misobasedir}/${arch}\" \"/run/miso/bootmnt/${misobasedir}/\" || die \"Failed to stage embedded Garuda live media\""
			print "        fi"
			print "    elif ! mountpoint -q \"/run/miso/bootmnt\"; then"
			inserted = 1
			next
		}
		{
			print
		}
		END {
			if (!inserted)
				exit 1
		}
	' "$_garuda_miso_script" >"$_garuda_miso_script.new"; then
		nb_error "Could not patch the $GARUDA_LABEL miso mount script."
		rm -f "$_garuda_miso_script.new"
		return 1
	fi
	mv "$_garuda_miso_script.new" "$_garuda_miso_script"
	chmod 755 "$_garuda_miso_script"

	if ! grep -q 'NetbootCD embedded Garuda root trigger' "$_garuda_miso_script" 2>/dev/null; then
		if ! awk '
			/^if \[ -n "\$root" -a -z "\$\{root%%miso:\*\}" \]; then$/ && ! inserted {
				print "# NetbootCD embedded Garuda root trigger"
				print "if [[ \"$(getarg netbootcd_garuda=)\" == \"1\" ]]; then"
				print "    root=\"miso:/dev/null\""
				print "    miso_mount_root"
				print "elif [ -n \"$root\" -a -z \"${root%%miso:*}\" ]; then"
				inserted = 1
				next
			}
			{
				print
			}
			END {
				if (!inserted)
					exit 1
			}
		' "$_garuda_miso_script" >"$_garuda_miso_script.new"; then
			nb_error "Could not patch the $GARUDA_LABEL miso root trigger."
			rm -f "$_garuda_miso_script.new"
			return 1
		fi
		mv "$_garuda_miso_script.new" "$_garuda_miso_script"
		chmod 755 "$_garuda_miso_script"
	fi

	if [ -n "$_garuda_parse_script" ] && ! grep -q 'netbootcd_garuda' "$_garuda_parse_script" 2>/dev/null; then
		if ! awk '
			NR == 1 {
				print
				next
			}
			NR == 2 && ! inserted {
				print ""
				print "if [ \"$(getarg netbootcd_garuda=)\" = \"1\" ]; then"
				print "    root=\"miso:/dev/null\""
				print "    rootok=1"
				print "    return 0 2>/dev/null || exit 0"
				print "fi"
				print ""
				inserted = 1
			}
			{
				print
			}
			END {
				if (!inserted)
					exit 1
			}
		' "$_garuda_parse_script" >"$_garuda_parse_script.new"; then
			nb_error "Could not patch the $GARUDA_LABEL miso command-line parser."
			rm -f "$_garuda_parse_script.new"
			return 1
		fi
		mv "$_garuda_parse_script.new" "$_garuda_parse_script"
		chmod 755 "$_garuda_parse_script"
	fi

	return 0
}

garuda_repack_initrd_with_layers ()
{
	_garuda_layers="$1"
	_garuda_work="/tmp/nb-garuda-initrd-work"
	_garuda_repacked="/tmp/nb-initrd.garuda"

	if ! _garuda_main_info=$(artix_find_main_initrd /tmp/nb-initrd); then
		nb_error "Could not determine the $GARUDA_LABEL initramfs compression format."
		return 1
	fi
	_garuda_format="${_garuda_main_info%% *}"
	_garuda_main_offset="${_garuda_main_info#* }"

	if ! nb_initrd_need_tool "$_garuda_format" "$GARUDA_LABEL"; then
		return 1
	fi

	rm -rf "$_garuda_work" "$_garuda_repacked" /tmp/nb-initrd.new
	mkdir -p "$_garuda_work"

	if ! nb_initrd_unpack /tmp/nb-initrd "$_garuda_work" "$_garuda_format" "$_garuda_main_offset" "-idmu" "/dev/null"; then
		nb_error "Could not unpack the $GARUDA_LABEL $_garuda_format initramfs."
		rm -rf "$_garuda_work"
		return 1
	fi

	mkdir -p "$_garuda_work/$GARUDA_BASEDIR/$GARUDA_ARCH"
	for _garuda_sfs in "$_garuda_layers"/*.sfs; do
		[ -f "$_garuda_sfs" ] || continue
		mv "$_garuda_sfs" "$_garuda_work/$GARUDA_BASEDIR/$GARUDA_ARCH/${_garuda_sfs##*/}" || {
			nb_error "Could not embed the $GARUDA_LABEL live layer ${_garuda_sfs##*/}."
			rm -rf "$_garuda_work"
			return 1
		}
	done

	if ! garuda_patch_miso_scripts "$_garuda_work"; then
		rm -rf "$_garuda_work" "$_garuda_repacked" /tmp/nb-initrd.new
		return 1
	fi

	if ! nb_initrd_repack "$_garuda_work" "$_garuda_repacked" "$_garuda_format" "standard"; then
		nb_error "Could not repack the $GARUDA_LABEL $_garuda_format initramfs."
		rm -rf "$_garuda_work"
		return 1
	fi

	: >/tmp/nb-initrd.new
	if [ "$_garuda_main_offset" -gt 0 ]; then
		if ! head -c "$_garuda_main_offset" /tmp/nb-initrd >>/tmp/nb-initrd.new; then
			nb_error "Could not preserve the $GARUDA_LABEL early initramfs prefix."
			rm -rf "$_garuda_work" "$_garuda_repacked" /tmp/nb-initrd.new
			return 1
		fi
	fi
	if ! cat "$_garuda_repacked" >>/tmp/nb-initrd.new; then
		nb_error "Could not write the repacked $GARUDA_LABEL initramfs."
		rm -rf "$_garuda_work" "$_garuda_repacked" /tmp/nb-initrd.new
		return 1
	fi
	mv /tmp/nb-initrd.new /tmp/nb-initrd
	rm -rf "$_garuda_work" "$_garuda_repacked"
	return 0
}

garuda_prepare_from_iso ()
{
	_garuda_iso_url="$1"
	_garuda_work="/tmp/nb-garuda-work"
	_garuda_iso="$_garuda_work/nb-garuda.iso"
	_garuda_boot="$_garuda_work/boot"
	_garuda_layers="$_garuda_work/layers"

	if ! _garuda_7z=$(artix_7z_cmd); then
		nb_error "7zip is required to extract $GARUDA_LABEL boot files. Rebuild NetbootCD-Neo with 7zip included."
		return 1
	fi

	if grep -q " $_garuda_work " /proc/mounts 2>/dev/null; then
		umount "$_garuda_work" 2>/dev/null || true
	fi
	rm -f /tmp/nb-linux /tmp/nb-initrd
	rm -rf "$_garuda_work" /tmp/nb-garuda-initrd-work /tmp/nb-initrd.garuda /tmp/nb-initrd.new
	mkdir -p "$_garuda_boot" "$_garuda_layers"
	_garuda_mounted=
	if mount -t tmpfs -o size=85%,mode=0755 tmpfs "$_garuda_work" 2>/tmp/nb-garuda-mount.log; then
		_garuda_mounted=1
		mkdir -p "$_garuda_boot" "$_garuda_layers"
	fi

	if ! wgetgauge "$_garuda_iso_url" "$_garuda_iso" "Downloading $GARUDA_LABEL ISO"; then
		nb_error "Could not download $GARUDA_LABEL ISO from:\n\n$_garuda_iso_url\n\nThis entry needs enough RAM to hold the ISO before kexec."
		[ -n "$_garuda_mounted" ] && umount "$_garuda_work" 2>/dev/null || true
		rm -rf "$_garuda_work"
		return 1
	fi

	if ! "$_garuda_7z" e -y -o"$_garuda_boot" "$_garuda_iso" "$GARUDA_KERNEL_PATH" "$GARUDA_INITRD_PATH" >/tmp/nb-garuda-7z.log 2>&1; then
		nb_error "Could not extract $GARUDA_LABEL boot files from the ISO.\nSee /tmp/nb-garuda-7z.log for details."
		[ -n "$_garuda_mounted" ] && umount "$_garuda_work" 2>/dev/null || true
		rm -rf "$_garuda_work"
		return 1
	fi
	_garuda_kernel_file="${GARUDA_KERNEL_PATH##*/}"
	_garuda_initrd_file="${GARUDA_INITRD_PATH##*/}"
	if [ ! -s "$_garuda_boot/$_garuda_kernel_file" ] || [ ! -s "$_garuda_boot/$_garuda_initrd_file" ]; then
		nb_error "The $GARUDA_LABEL ISO did not contain its expected kernel and initramfs."
		[ -n "$_garuda_mounted" ] && umount "$_garuda_work" 2>/dev/null || true
		rm -rf "$_garuda_work"
		return 1
	fi
	mv "$_garuda_boot/$_garuda_kernel_file" /tmp/nb-linux
	mv "$_garuda_boot/$_garuda_initrd_file" /tmp/nb-initrd
	rm -rf "$_garuda_boot"

	for _garuda_layer in rootfs desktopfs livefs ghtfs; do
		_garuda_layer_path="$GARUDA_BASEDIR/$GARUDA_ARCH/$_garuda_layer.sfs"
		if "$_garuda_7z" e -y -o"$_garuda_layers" "$_garuda_iso" "$_garuda_layer_path" >>/tmp/nb-garuda-7z.log 2>&1; then
			[ -s "$_garuda_layers/$_garuda_layer.sfs" ] && continue
		fi
		if [ "$_garuda_layer" = "ghtfs" ]; then
			continue
		fi
		nb_error "Could not extract $_garuda_layer.sfs from the $GARUDA_LABEL ISO.\nSee /tmp/nb-garuda-7z.log for details."
		[ -n "$_garuda_mounted" ] && umount "$_garuda_work" 2>/dev/null || true
		rm -rf "$_garuda_work"
		rm -f /tmp/nb-linux /tmp/nb-initrd
		return 1
	done
	rm -f "$_garuda_iso"

	dialog --backtitle "$TITLE" --infobox \
		"Embedding the $GARUDA_LABEL live layers into the initrd.\n\nThis can take a while for large ISOs." 7 70 || true
	if ! garuda_repack_initrd_with_layers "$_garuda_layers"; then
		[ -n "$_garuda_mounted" ] && umount "$_garuda_work" 2>/dev/null || true
		rm -rf "$_garuda_work"
		rm -f /tmp/nb-linux /tmp/nb-initrd /tmp/nb-initrd.new /tmp/nb-initrd.garuda
		return 1
	fi

	rm -f "$_garuda_iso" /tmp/nb-garuda-7z.log /tmp/nb-garuda-mount.log
	[ -n "$_garuda_mounted" ] && umount "$_garuda_work" 2>/dev/null || true
	rm -rf "$_garuda_work"
	return 0
}

parabola_iso_setup ()
{
	PARABOLA_LABEL="$1"
	PARABOLA_ISO_URL="$2"
	PARABOLA_KERNEL_PATH="$3"
	PARABOLA_INITRD_PATH="$4"
	PARABOLA_ROOTFS_PATH="$5"
	PARABOLA_AITAB_PATH="$6"
	printf '%s' "$7 " >>/tmp/nb-options
}

parabola_repack_initrd_with_rootfs ()
{
	_parabola_rootfs="$1"
	_parabola_aitab="$2"
	_parabola_work="/tmp/nb-parabola-initrd-work"
	_parabola_repacked="/tmp/nb-initrd.parabola"

	if ! _parabola_main_info=$(artix_find_main_initrd /tmp/nb-initrd); then
		nb_error "Could not determine the $PARABOLA_LABEL initramfs compression format."
		return 1
	fi
	_parabola_format="${_parabola_main_info%% *}"
	_parabola_main_offset="${_parabola_main_info#* }"

	if ! nb_initrd_need_tool "$_parabola_format" "$PARABOLA_LABEL"; then
		return 1
	fi

	rm -rf "$_parabola_work" "$_parabola_repacked" /tmp/nb-initrd.new
	mkdir -p "$_parabola_work"

	if ! nb_initrd_unpack /tmp/nb-initrd "$_parabola_work" "$_parabola_format" "$_parabola_main_offset" "-idmu" "/dev/null"; then
		nb_error "Could not unpack the $PARABOLA_LABEL $_parabola_format initramfs."
		rm -rf "$_parabola_work"
		return 1
	fi

	mkdir -p "$_parabola_work/parabola/x86_64" "$_parabola_work/hooks"
	if ! mv "$_parabola_rootfs" "$_parabola_work/parabola/x86_64/root-image.fs.sfs"; then
		nb_error "Could not embed the $PARABOLA_LABEL root filesystem."
		rm -rf "$_parabola_work"
		return 1
	fi
	if ! mv "$_parabola_aitab" "$_parabola_work/parabola/aitab"; then
		nb_error "Could not embed the $PARABOLA_LABEL aitab file."
		rm -rf "$_parabola_work"
		return 1
	fi

	cat >"$_parabola_work/hooks/netbootcd_parabola" <<'EOFP'
#!/usr/bin/ash

run_hook() {
    _netbootcd_basedir="${parabolaisobasedir:-parabola}"
    if [ -f "/${_netbootcd_basedir}/aitab" ] && [ -f "/${_netbootcd_basedir}/x86_64/root-image.fs.sfs" ]; then
        copytoram=n
        mount_handler="netbootcd_parabola_mount_handler"
    fi
}

netbootcd_parabola_mount_handler() {
    newroot="${1}"

    msg ":: Using NetbootCD embedded Parabola root filesystem"
    mkdir -p /run/parabolaiso/bootmnt
    if ! mountpoint -q /run/parabolaiso/bootmnt; then
        mount -o bind / /run/parabolaiso/bootmnt || {
            echo "ERROR: could not bind initramfs for embedded Parabola root"
            launch_interactive_shell
        }
    fi

    parabolaisodevice=/
    copytoram=n
    parabolaiso_mount_handler "$newroot"
}
EOFP
	chmod 755 "$_parabola_work/hooks/netbootcd_parabola"

	if [ -f "$_parabola_work/config" ] && ! grep -q 'netbootcd_parabola' "$_parabola_work/config"; then
		if grep -q '^HOOKS="' "$_parabola_work/config"; then
			if ! sed 's/^HOOKS="\([^"]*\)"/HOOKS="\1 netbootcd_parabola"/' "$_parabola_work/config" >"$_parabola_work/config.new"; then
				nb_error "Could not update the $PARABOLA_LABEL initramfs hook list."
				rm -rf "$_parabola_work" "$_parabola_repacked" "$_parabola_work/config.new"
				return 1
			fi
			mv "$_parabola_work/config.new" "$_parabola_work/config"
		else
			printf '\nHOOKS="${HOOKS} netbootcd_parabola"\n' >>"$_parabola_work/config"
		fi
	fi

	if ! nb_initrd_repack "$_parabola_work" "$_parabola_repacked" "$_parabola_format" "standard"; then
		nb_error "Could not repack the $PARABOLA_LABEL $_parabola_format initramfs."
		rm -rf "$_parabola_work"
		return 1
	fi

	: >/tmp/nb-initrd.new
	if [ "$_parabola_main_offset" -gt 0 ]; then
		if ! head -c "$_parabola_main_offset" /tmp/nb-initrd >>/tmp/nb-initrd.new; then
			nb_error "Could not preserve the $PARABOLA_LABEL early initramfs prefix."
			rm -rf "$_parabola_work" "$_parabola_repacked" /tmp/nb-initrd.new
			return 1
		fi
	fi
	if ! cat "$_parabola_repacked" >>/tmp/nb-initrd.new; then
		nb_error "Could not write the repacked $PARABOLA_LABEL initramfs."
		rm -rf "$_parabola_work" "$_parabola_repacked" /tmp/nb-initrd.new
		return 1
	fi
	mv /tmp/nb-initrd.new /tmp/nb-initrd
	rm -rf "$_parabola_work" "$_parabola_repacked"
	return 0
}

parabola_prepare_from_iso ()
{
	_parabola_iso_url="$1"
	_parabola_work="/tmp/nb-parabola-work"
	_parabola_iso="$_parabola_work/nb-parabola.iso"
	_parabola_boot="$_parabola_work/boot"
	_parabola_rootfs="$_parabola_work/root-image.fs.sfs"
	_parabola_aitab="$_parabola_work/aitab"

	if ! _parabola_7z=$(artix_7z_cmd); then
		nb_error "7zip is required to extract $PARABOLA_LABEL boot files. Rebuild NetbootCD-Neo with 7zip included."
		return 1
	fi

	if grep -q " $_parabola_work " /proc/mounts 2>/dev/null; then
		umount "$_parabola_work" 2>/dev/null || true
	fi
	rm -f /tmp/nb-linux /tmp/nb-initrd
	rm -rf "$_parabola_work" /tmp/nb-parabola-initrd-work /tmp/nb-initrd.parabola /tmp/nb-initrd.new
	mkdir -p "$_parabola_boot"
	_parabola_mounted=
	if mount -t tmpfs -o size=85%,mode=0755 tmpfs "$_parabola_work" 2>/tmp/nb-parabola-mount.log; then
		_parabola_mounted=1
		mkdir -p "$_parabola_boot"
	fi

	if ! wgetgauge "$_parabola_iso_url" "$_parabola_iso" "Downloading $PARABOLA_LABEL ISO"; then
		nb_error "Could not download $PARABOLA_LABEL ISO from:\n\n$_parabola_iso_url\n\nThis entry needs enough RAM to hold the ISO before kexec."
		[ -n "$_parabola_mounted" ] && umount "$_parabola_work" 2>/dev/null || true
		rm -rf "$_parabola_work"
		return 1
	fi

	if ! "$_parabola_7z" e -y -o"$_parabola_boot" "$_parabola_iso" "$PARABOLA_KERNEL_PATH" "$PARABOLA_INITRD_PATH" >/tmp/nb-parabola-7z.log 2>&1; then
		nb_error "Could not extract $PARABOLA_LABEL boot files from the ISO.\nSee /tmp/nb-parabola-7z.log for details."
		[ -n "$_parabola_mounted" ] && umount "$_parabola_work" 2>/dev/null || true
		rm -rf "$_parabola_work"
		return 1
	fi
	_parabola_kernel_file="${PARABOLA_KERNEL_PATH##*/}"
	_parabola_initrd_file="${PARABOLA_INITRD_PATH##*/}"
	if [ ! -s "$_parabola_boot/$_parabola_kernel_file" ] || [ ! -s "$_parabola_boot/$_parabola_initrd_file" ]; then
		nb_error "The $PARABOLA_LABEL ISO did not contain its expected kernel and initramfs."
		[ -n "$_parabola_mounted" ] && umount "$_parabola_work" 2>/dev/null || true
		rm -rf "$_parabola_work"
		return 1
	fi
	mv "$_parabola_boot/$_parabola_kernel_file" /tmp/nb-linux
	mv "$_parabola_boot/$_parabola_initrd_file" /tmp/nb-initrd
	rm -rf "$_parabola_boot"

	if ! "$_parabola_7z" e -y -o"$_parabola_work" "$_parabola_iso" "$PARABOLA_ROOTFS_PATH" "$PARABOLA_AITAB_PATH" >>/tmp/nb-parabola-7z.log 2>&1; then
		nb_error "Could not extract $PARABOLA_LABEL live filesystem from the ISO.\nSee /tmp/nb-parabola-7z.log for details."
		[ -n "$_parabola_mounted" ] && umount "$_parabola_work" 2>/dev/null || true
		rm -rf "$_parabola_work"
		rm -f /tmp/nb-linux /tmp/nb-initrd
		return 1
	fi
	_parabola_rootfs_file="${PARABOLA_ROOTFS_PATH##*/}"
	_parabola_aitab_file="${PARABOLA_AITAB_PATH##*/}"
	if [ ! -s "$_parabola_work/$_parabola_rootfs_file" ] || [ ! -s "$_parabola_work/$_parabola_aitab_file" ]; then
		nb_error "The $PARABOLA_LABEL ISO did not contain its expected live filesystem files."
		[ -n "$_parabola_mounted" ] && umount "$_parabola_work" 2>/dev/null || true
		rm -rf "$_parabola_work"
		rm -f /tmp/nb-linux /tmp/nb-initrd
		return 1
	fi
	mv "$_parabola_work/$_parabola_rootfs_file" "$_parabola_rootfs"
	mv "$_parabola_work/$_parabola_aitab_file" "$_parabola_aitab"
	rm -f "$_parabola_iso"

	dialog --backtitle "$TITLE" --infobox \
		"Embedding the $PARABOLA_LABEL root filesystem into the initrd.\n\nThis can take a while." 7 70 || true
	if ! parabola_repack_initrd_with_rootfs "$_parabola_rootfs" "$_parabola_aitab"; then
		[ -n "$_parabola_mounted" ] && umount "$_parabola_work" 2>/dev/null || true
		rm -rf "$_parabola_work"
		rm -f /tmp/nb-linux /tmp/nb-initrd /tmp/nb-initrd.new /tmp/nb-initrd.parabola
		return 1
	fi

	rm -f "$_parabola_iso" "$_parabola_rootfs" "$_parabola_aitab" /tmp/nb-parabola-7z.log /tmp/nb-parabola-mount.log
	[ -n "$_parabola_mounted" ] && umount "$_parabola_work" 2>/dev/null || true
	rm -rf "$_parabola_work"
	return 0
}

hyperbola_iso_setup ()
{
	HYPERBOLA_LABEL="$1"
	HYPERBOLA_ISO_URL="$2"
	HYPERBOLA_KERNEL_PATH="$3"
	HYPERBOLA_INITRD_PATH="$4"
	HYPERBOLA_ROOTFS_PATH="$5"
	HYPERBOLA_AITAB_PATH="$6"
	printf '%s' "$7 " >>/tmp/nb-options
}

hyperbola_repack_initrd_with_rootfs ()
{
	_hyperbola_rootfs="$1"
	_hyperbola_aitab="$2"
	_hyperbola_work="/tmp/nb-hyperbola-initrd-work"
	_hyperbola_repacked="/tmp/nb-initrd.hyperbola"

	if ! _hyperbola_main_info=$(artix_find_main_initrd /tmp/nb-initrd); then
		nb_error "Could not determine the $HYPERBOLA_LABEL initramfs compression format."
		return 1
	fi
	_hyperbola_format="${_hyperbola_main_info%% *}"
	_hyperbola_main_offset="${_hyperbola_main_info#* }"

	if ! nb_initrd_need_tool "$_hyperbola_format" "$HYPERBOLA_LABEL"; then
		return 1
	fi

	rm -rf "$_hyperbola_work" "$_hyperbola_repacked" /tmp/nb-initrd.new
	mkdir -p "$_hyperbola_work"

	if ! nb_initrd_unpack /tmp/nb-initrd "$_hyperbola_work" "$_hyperbola_format" "$_hyperbola_main_offset" "-idmu" "/dev/null"; then
		nb_error "Could not unpack the $HYPERBOLA_LABEL $_hyperbola_format initramfs."
		rm -rf "$_hyperbola_work"
		return 1
	fi

	mkdir -p "$_hyperbola_work/hyperbola/x86_64" "$_hyperbola_work/hooks"
	if ! mv "$_hyperbola_rootfs" "$_hyperbola_work/hyperbola/x86_64/root-image.fs.sfs"; then
		nb_error "Could not embed the $HYPERBOLA_LABEL root filesystem."
		rm -rf "$_hyperbola_work"
		return 1
	fi
	if ! mv "$_hyperbola_aitab" "$_hyperbola_work/hyperbola/aitab"; then
		nb_error "Could not embed the $HYPERBOLA_LABEL aitab file."
		rm -rf "$_hyperbola_work"
		return 1
	fi

	cat >"$_hyperbola_work/hooks/netbootcd_hyperbola" <<'EOFP'
#!/usr/bin/ash

run_hook() {
    _netbootcd_basedir="${hyperisobasedir:-hyperbola}"
    if [ -f "/${_netbootcd_basedir}/aitab" ] && [ -f "/${_netbootcd_basedir}/x86_64/root-image.fs.sfs" ]; then
        copytoram=n
        mount_handler="netbootcd_hyperbola_mount_handler"
    fi
}

netbootcd_hyperbola_mount_handler() {
    newroot="${1}"

    msg ":: Using NetbootCD embedded Hyperbola root filesystem"
    mkdir -p /run/hyperiso/bootmnt
    if ! mountpoint -q /run/hyperiso/bootmnt; then
        mount -o bind / /run/hyperiso/bootmnt || {
            echo "ERROR: could not bind initramfs for embedded Hyperbola root"
            launch_interactive_shell
        }
    fi

    hyperisodevice=/
    copytoram=n
    hyperiso_mount_handler "$newroot"
}
EOFP
	chmod 755 "$_hyperbola_work/hooks/netbootcd_hyperbola"

	if [ -f "$_hyperbola_work/config" ] && ! grep -q 'netbootcd_hyperbola' "$_hyperbola_work/config"; then
		if grep -q '^HOOKS="' "$_hyperbola_work/config"; then
			if ! sed 's/^HOOKS="\([^"]*\)"/HOOKS="\1 netbootcd_hyperbola"/' "$_hyperbola_work/config" >"$_hyperbola_work/config.new"; then
				nb_error "Could not update the $HYPERBOLA_LABEL initramfs hook list."
				rm -rf "$_hyperbola_work" "$_hyperbola_repacked" "$_hyperbola_work/config.new"
				return 1
			fi
			mv "$_hyperbola_work/config.new" "$_hyperbola_work/config"
		else
			printf '\nHOOKS="${HOOKS} netbootcd_hyperbola"\n' >>"$_hyperbola_work/config"
		fi
	fi

	if ! nb_initrd_repack "$_hyperbola_work" "$_hyperbola_repacked" "$_hyperbola_format" "standard"; then
		nb_error "Could not repack the $HYPERBOLA_LABEL $_hyperbola_format initramfs."
		rm -rf "$_hyperbola_work"
		return 1
	fi

	: >/tmp/nb-initrd.new
	if [ "$_hyperbola_main_offset" -gt 0 ]; then
		if ! head -c "$_hyperbola_main_offset" /tmp/nb-initrd >>/tmp/nb-initrd.new; then
			nb_error "Could not preserve the $HYPERBOLA_LABEL early initramfs prefix."
			rm -rf "$_hyperbola_work" "$_hyperbola_repacked" /tmp/nb-initrd.new
			return 1
		fi
	fi
	if ! cat "$_hyperbola_repacked" >>/tmp/nb-initrd.new; then
		nb_error "Could not write the repacked $HYPERBOLA_LABEL initramfs."
		rm -rf "$_hyperbola_work" "$_hyperbola_repacked" /tmp/nb-initrd.new
		return 1
	fi
	mv /tmp/nb-initrd.new /tmp/nb-initrd
	rm -rf "$_hyperbola_work" "$_hyperbola_repacked"
	return 0
}

hyperbola_prepare_from_iso ()
{
	_hyperbola_iso_url="$1"
	_hyperbola_work="/tmp/nb-hyperbola-work"
	_hyperbola_iso="$_hyperbola_work/nb-hyperbola.iso"
	_hyperbola_boot="$_hyperbola_work/boot"
	_hyperbola_rootfs="$_hyperbola_work/root-image.fs.sfs"
	_hyperbola_aitab="$_hyperbola_work/aitab"

	if ! _hyperbola_7z=$(artix_7z_cmd); then
		nb_error "7zip is required to extract $HYPERBOLA_LABEL boot files. Rebuild NetbootCD-Neo with 7zip included."
		return 1
	fi

	if grep -q " $_hyperbola_work " /proc/mounts 2>/dev/null; then
		umount "$_hyperbola_work" 2>/dev/null || true
	fi
	rm -f /tmp/nb-linux /tmp/nb-initrd
	rm -rf "$_hyperbola_work" /tmp/nb-hyperbola-initrd-work /tmp/nb-initrd.hyperbola /tmp/nb-initrd.new
	mkdir -p "$_hyperbola_boot"
	_hyperbola_mounted=
	if mount -t tmpfs -o size=85%,mode=0755 tmpfs "$_hyperbola_work" 2>/tmp/nb-hyperbola-mount.log; then
		_hyperbola_mounted=1
		mkdir -p "$_hyperbola_boot"
	fi

	if ! wgetgauge "$_hyperbola_iso_url" "$_hyperbola_iso" "Downloading $HYPERBOLA_LABEL ISO"; then
		nb_error "Could not download $HYPERBOLA_LABEL ISO from:\n\n$_hyperbola_iso_url\n\nThis entry needs enough RAM to hold the ISO before kexec."
		[ -n "$_hyperbola_mounted" ] && umount "$_hyperbola_work" 2>/dev/null || true
		rm -rf "$_hyperbola_work"
		return 1
	fi

	if ! "$_hyperbola_7z" e -y -o"$_hyperbola_boot" "$_hyperbola_iso" "$HYPERBOLA_KERNEL_PATH" "$HYPERBOLA_INITRD_PATH" >/tmp/nb-hyperbola-7z.log 2>&1; then
		nb_error "Could not extract $HYPERBOLA_LABEL boot files from the ISO.\nSee /tmp/nb-hyperbola-7z.log for details."
		[ -n "$_hyperbola_mounted" ] && umount "$_hyperbola_work" 2>/dev/null || true
		rm -rf "$_hyperbola_work"
		return 1
	fi
	_hyperbola_kernel_file="${HYPERBOLA_KERNEL_PATH##*/}"
	_hyperbola_initrd_file="${HYPERBOLA_INITRD_PATH##*/}"
	if [ ! -s "$_hyperbola_boot/$_hyperbola_kernel_file" ] || [ ! -s "$_hyperbola_boot/$_hyperbola_initrd_file" ]; then
		nb_error "The $HYPERBOLA_LABEL ISO did not contain its expected kernel and initramfs."
		[ -n "$_hyperbola_mounted" ] && umount "$_hyperbola_work" 2>/dev/null || true
		rm -rf "$_hyperbola_work"
		return 1
	fi
	mv "$_hyperbola_boot/$_hyperbola_kernel_file" /tmp/nb-linux
	mv "$_hyperbola_boot/$_hyperbola_initrd_file" /tmp/nb-initrd
	rm -rf "$_hyperbola_boot"

	if ! "$_hyperbola_7z" e -y -o"$_hyperbola_work" "$_hyperbola_iso" "$HYPERBOLA_ROOTFS_PATH" "$HYPERBOLA_AITAB_PATH" >>/tmp/nb-hyperbola-7z.log 2>&1; then
		nb_error "Could not extract $HYPERBOLA_LABEL live filesystem from the ISO.\nSee /tmp/nb-hyperbola-7z.log for details."
		[ -n "$_hyperbola_mounted" ] && umount "$_hyperbola_work" 2>/dev/null || true
		rm -rf "$_hyperbola_work"
		rm -f /tmp/nb-linux /tmp/nb-initrd
		return 1
	fi
	_hyperbola_rootfs_file="${HYPERBOLA_ROOTFS_PATH##*/}"
	_hyperbola_aitab_file="${HYPERBOLA_AITAB_PATH##*/}"
	if [ ! -s "$_hyperbola_work/$_hyperbola_rootfs_file" ] || [ ! -s "$_hyperbola_work/$_hyperbola_aitab_file" ]; then
		nb_error "The $HYPERBOLA_LABEL ISO did not contain its expected live filesystem files."
		[ -n "$_hyperbola_mounted" ] && umount "$_hyperbola_work" 2>/dev/null || true
		rm -rf "$_hyperbola_work"
		rm -f /tmp/nb-linux /tmp/nb-initrd
		return 1
	fi
	mv "$_hyperbola_work/$_hyperbola_rootfs_file" "$_hyperbola_rootfs"
	mv "$_hyperbola_work/$_hyperbola_aitab_file" "$_hyperbola_aitab"
	rm -f "$_hyperbola_iso"

	dialog --backtitle "$TITLE" --infobox \
		"Embedding the $HYPERBOLA_LABEL root filesystem into the initrd.\n\nThis can take a while." 7 70 || true
	if ! hyperbola_repack_initrd_with_rootfs "$_hyperbola_rootfs" "$_hyperbola_aitab"; then
		[ -n "$_hyperbola_mounted" ] && umount "$_hyperbola_work" 2>/dev/null || true
		rm -rf "$_hyperbola_work"
		rm -f /tmp/nb-linux /tmp/nb-initrd /tmp/nb-initrd.new /tmp/nb-initrd.hyperbola
		return 1
	fi

	rm -f "$_hyperbola_iso" "$_hyperbola_rootfs" "$_hyperbola_aitab" /tmp/nb-hyperbola-7z.log /tmp/nb-hyperbola-mount.log
	[ -n "$_hyperbola_mounted" ] && umount "$_hyperbola_work" 2>/dev/null || true
	rm -rf "$_hyperbola_work"
	return 0
}

mocaccino_live_iso_setup ()
{
	MOCACCINO_LABEL="$1"
	MOCACCINO_ISO_URL="$2"
	MOCACCINO_KERNEL_PATH="$3"
	MOCACCINO_INITRD_PATH="$4"
	MOCACCINO_ROOTFS_PATH="$5"
	printf '%s' "netbootcd_mocaccino=1 rootdelay=7 " >>/tmp/nb-options
}

mocaccino_repack_initrd_with_rootfs ()
{
	_mocaccino_rootfs="$1"
	_mocaccino_work="/tmp/nb-mocaccino-initrd-work"
	_mocaccino_repacked="/tmp/nb-initrd.mocaccino"

	if ! _mocaccino_main_info=$(artix_find_main_initrd /tmp/nb-initrd); then
		nb_error "Could not determine the $MOCACCINO_LABEL initramfs compression format."
		return 1
	fi
	_mocaccino_format="${_mocaccino_main_info%% *}"
	_mocaccino_main_offset="${_mocaccino_main_info#* }"

	if ! nb_initrd_need_tool "$_mocaccino_format" "$MOCACCINO_LABEL"; then
		return 1
	fi

	rm -rf "$_mocaccino_work" "$_mocaccino_repacked" /tmp/nb-initrd.new
	mkdir -p "$_mocaccino_work"

	if ! nb_initrd_unpack /tmp/nb-initrd "$_mocaccino_work" "$_mocaccino_format" "$_mocaccino_main_offset" "-idmu" "/dev/null"; then
		nb_error "Could not unpack the $MOCACCINO_LABEL $_mocaccino_format initramfs."
		rm -rf "$_mocaccino_work"
		return 1
	fi

	if ! mv "$_mocaccino_rootfs" "$_mocaccino_work/rootfs.squashfs"; then
		nb_error "Could not embed the $MOCACCINO_LABEL root filesystem."
		rm -rf "$_mocaccino_work"
		return 1
	fi
	if [ -f "$_mocaccino_work/loader" ] && ! grep -q 'netbootcd_mocaccino_embedded_overlay' "$_mocaccino_work/loader"; then
		if ! sed '/^search_overlay() {/a\
  # netbootcd_mocaccino_embedded_overlay\
  if [ -f /rootfs.squashfs ] ; then\
    echo "Using embedded NetbootCD-Neo MocaccinoOS rootfs.squashfs."\
    mkdir -p /tmp/mnt/image\
    IMAGE_MNT=/tmp/mnt/image\
    LOOP_DEVICE=$(losetup -f)\
    losetup $LOOP_DEVICE /rootfs.squashfs\
    if mount $LOOP_DEVICE $IMAGE_MNT -t squashfs ; then\
      OVERLAY_DIR=$IMAGE_MNT\
      UPPER_DIR=$DEFAULT_UPPER_DIR\
      WORK_DIR=$DEFAULT_WORK_DIR\
      mkdir -p $UPPER_DIR $WORK_DIR\
      if mount -t overlay -o lowerdir=$OVERLAY_DIR:/mnt,upperdir=$UPPER_DIR,workdir=$WORK_DIR none /mnt ; then\
        echo "Embedded NetbootCD-Neo rootfs.squashfs has been merged."\
        return\
      fi\
      echo "Embedded NetbootCD-Neo overlay mount failed."\
      umount $IMAGE_MNT 2>/dev/null\
    else\
      echo "Embedded NetbootCD-Neo squashfs mount failed."\
    fi\
  fi\
' "$_mocaccino_work/loader" >"$_mocaccino_work/loader.new"; then
			nb_error "Could not patch the $MOCACCINO_LABEL live loader."
			rm -rf "$_mocaccino_work" "$_mocaccino_work/loader.new"
			return 1
		fi
		mv "$_mocaccino_work/loader.new" "$_mocaccino_work/loader"
		chmod 755 "$_mocaccino_work/loader"
	fi

	if ! nb_initrd_repack "$_mocaccino_work" "$_mocaccino_repacked" "$_mocaccino_format" "standard"; then
		nb_error "Could not repack the $MOCACCINO_LABEL $_mocaccino_format initramfs."
		rm -rf "$_mocaccino_work"
		return 1
	fi

	: >/tmp/nb-initrd.new
	if [ "$_mocaccino_main_offset" -gt 0 ]; then
		if ! head -c "$_mocaccino_main_offset" /tmp/nb-initrd >>/tmp/nb-initrd.new; then
			nb_error "Could not preserve the $MOCACCINO_LABEL early initramfs prefix."
			rm -rf "$_mocaccino_work" "$_mocaccino_repacked" /tmp/nb-initrd.new
			return 1
		fi
	fi
	if ! cat "$_mocaccino_repacked" >>/tmp/nb-initrd.new; then
		nb_error "Could not write the repacked $MOCACCINO_LABEL initramfs."
		rm -rf "$_mocaccino_work" "$_mocaccino_repacked" /tmp/nb-initrd.new
		return 1
	fi
	mv /tmp/nb-initrd.new /tmp/nb-initrd
	rm -rf "$_mocaccino_work" "$_mocaccino_repacked"
	return 0
}

mocaccino_prepare_from_iso ()
{
	_mocaccino_iso_url="$1"
	_mocaccino_work="/tmp/nb-mocaccino-work"
	_mocaccino_iso="$_mocaccino_work/nb-mocaccino.iso"
	_mocaccino_boot="$_mocaccino_work/boot"
	_mocaccino_rootfs="$_mocaccino_work/rootfs.squashfs"

	if ! _mocaccino_7z=$(artix_7z_cmd); then
		nb_error "7zip is required to extract $MOCACCINO_LABEL boot files. Rebuild NetbootCD-Neo with 7zip included."
		return 1
	fi

	if grep -q " $_mocaccino_work " /proc/mounts 2>/dev/null; then
		umount "$_mocaccino_work" 2>/dev/null || true
	fi
	rm -f /tmp/nb-linux /tmp/nb-initrd
	rm -rf "$_mocaccino_work" /tmp/nb-mocaccino-initrd-work /tmp/nb-initrd.mocaccino /tmp/nb-initrd.new
	mkdir -p "$_mocaccino_boot"
	_mocaccino_mounted=
	if mount -t tmpfs -o size=85%,mode=0755 tmpfs "$_mocaccino_work" 2>/tmp/nb-mocaccino-mount.log; then
		_mocaccino_mounted=1
		mkdir -p "$_mocaccino_boot"
	fi

	if ! wgetgauge "$_mocaccino_iso_url" "$_mocaccino_iso" "Downloading $MOCACCINO_LABEL ISO"; then
		nb_error "Could not download $MOCACCINO_LABEL ISO from:\n\n$_mocaccino_iso_url\n\nThis entry needs enough RAM to hold the ISO before kexec."
		[ -n "$_mocaccino_mounted" ] && umount "$_mocaccino_work" 2>/dev/null || true
		rm -rf "$_mocaccino_work"
		return 1
	fi

	if ! "$_mocaccino_7z" e -y -o"$_mocaccino_boot" "$_mocaccino_iso" "$MOCACCINO_KERNEL_PATH" "$MOCACCINO_INITRD_PATH" >/tmp/nb-mocaccino-7z.log 2>&1; then
		nb_error "Could not extract $MOCACCINO_LABEL boot files from the ISO.\nSee /tmp/nb-mocaccino-7z.log for details."
		[ -n "$_mocaccino_mounted" ] && umount "$_mocaccino_work" 2>/dev/null || true
		rm -rf "$_mocaccino_work"
		return 1
	fi
	_mocaccino_kernel_file="${MOCACCINO_KERNEL_PATH##*/}"
	_mocaccino_initrd_file="${MOCACCINO_INITRD_PATH##*/}"
	if [ ! -s "$_mocaccino_boot/$_mocaccino_kernel_file" ] || [ ! -s "$_mocaccino_boot/$_mocaccino_initrd_file" ]; then
		nb_error "The $MOCACCINO_LABEL ISO did not contain its expected kernel and initramfs."
		[ -n "$_mocaccino_mounted" ] && umount "$_mocaccino_work" 2>/dev/null || true
		rm -rf "$_mocaccino_work"
		return 1
	fi
	mv "$_mocaccino_boot/$_mocaccino_kernel_file" /tmp/nb-linux
	mv "$_mocaccino_boot/$_mocaccino_initrd_file" /tmp/nb-initrd
	rm -rf "$_mocaccino_boot"

	if ! "$_mocaccino_7z" e -y -o"$_mocaccino_work" "$_mocaccino_iso" "$MOCACCINO_ROOTFS_PATH" >>/tmp/nb-mocaccino-7z.log 2>&1; then
		nb_error "Could not extract $MOCACCINO_LABEL root filesystem from the ISO.\nSee /tmp/nb-mocaccino-7z.log for details."
		[ -n "$_mocaccino_mounted" ] && umount "$_mocaccino_work" 2>/dev/null || true
		rm -rf "$_mocaccino_work"
		rm -f /tmp/nb-linux /tmp/nb-initrd
		return 1
	fi
	_mocaccino_rootfs_file="${MOCACCINO_ROOTFS_PATH##*/}"
	if [ ! -s "$_mocaccino_work/$_mocaccino_rootfs_file" ]; then
		nb_error "The $MOCACCINO_LABEL ISO did not contain $MOCACCINO_ROOTFS_PATH."
		[ -n "$_mocaccino_mounted" ] && umount "$_mocaccino_work" 2>/dev/null || true
		rm -rf "$_mocaccino_work"
		rm -f /tmp/nb-linux /tmp/nb-initrd
		return 1
	fi
	mv "$_mocaccino_work/$_mocaccino_rootfs_file" "$_mocaccino_rootfs"
	rm -f "$_mocaccino_iso"

	dialog --backtitle "$TITLE" --infobox \
		"Embedding the $MOCACCINO_LABEL root filesystem into the initrd.\n\nThis can take a while for large ISOs." 7 70 || true
	if ! mocaccino_repack_initrd_with_rootfs "$_mocaccino_rootfs"; then
		[ -n "$_mocaccino_mounted" ] && umount "$_mocaccino_work" 2>/dev/null || true
		rm -rf "$_mocaccino_work"
		rm -f /tmp/nb-linux /tmp/nb-initrd /tmp/nb-initrd.new /tmp/nb-initrd.mocaccino
		return 1
	fi

	rm -f "$_mocaccino_iso" "$_mocaccino_rootfs" /tmp/nb-mocaccino-7z.log /tmp/nb-mocaccino-mount.log
	[ -n "$_mocaccino_mounted" ] && umount "$_mocaccino_work" 2>/dev/null || true
	rm -rf "$_mocaccino_work"
	return 0
}

puppy_iso_setup ()
{
	PUPPY_LABEL="$1"
	PUPPY_ISO_URL="$2"
	PUPPY_KERNEL_PATH="$3"
	PUPPY_INITRD_PATH="$4"
	shift 4
	PUPPY_SFS_PATHS="$*"
	printf '%s' "pfix=ram,fsck pmedia=cd net.ifnames=0 " >>/tmp/nb-options
}

puppy_repack_initrd_with_sfs ()
{
	_puppy_work="/tmp/nb-puppy-work/initrd-work"
	_puppy_repacked="/tmp/nb-puppy-work/nb-initrd.puppy"
	_puppy_new="/tmp/nb-puppy-work/nb-initrd.new"

	if ! _puppy_main_info=$(artix_find_main_initrd /tmp/nb-initrd); then
		nb_error "Could not determine the $PUPPY_LABEL initrd compression format."
		return 1
	fi
	_puppy_format="${_puppy_main_info%% *}"
	_puppy_main_offset="${_puppy_main_info#* }"

	if [ "$_puppy_format" = "zstd" ] && ! command -v zstd >/dev/null 2>&1; then
		nb_error "$PUPPY_LABEL initrd uses zstd compression, but zstd is not available."
		return 1
	fi
	if [ "$_puppy_format" = "xz" ] && ! command -v xz >/dev/null 2>&1; then
		nb_error "$PUPPY_LABEL initrd uses xz compression, but xz is not available."
		return 1
	fi

	rm -rf "$_puppy_work" "$_puppy_repacked" "$_puppy_new"
	mkdir -p "$_puppy_work"

	if ! nb_initrd_unpack /tmp/nb-initrd "$_puppy_work" "$_puppy_format" "$_puppy_main_offset" "-idmu" "/dev/null"; then
		nb_error "Could not unpack the $PUPPY_LABEL $_puppy_format initramfs."
		rm -rf "$_puppy_work"
		return 1
	fi

	for _puppy_sfs in "$@"; do
		if [ ! -s "$_puppy_sfs" ]; then
			nb_error "Could not find an extracted $PUPPY_LABEL SFS file: $_puppy_sfs"
			rm -rf "$_puppy_work"
			return 1
		fi
		_puppy_sfs_file="${_puppy_sfs##*/}"
		if ! mv "$_puppy_sfs" "$_puppy_work/$_puppy_sfs_file"; then
			nb_error "Could not embed $_puppy_sfs_file into the $PUPPY_LABEL initrd."
			rm -rf "$_puppy_work"
			return 1
		fi
	done

	if [ -f "$_puppy_work/init" ] && ! grep -q 'netbootcd_puppy_tmpfs_sfs' "$_puppy_work/init"; then
		if ! sed '/^stack_onepupdrv() {/,/^copy_onepupdrv() {/{
/^ ONE_BASENAME="$(basename $ONE_REL_FN)"$/a\
 # netbootcd_puppy_tmpfs_sfs\
 if [ ! -s "$ONE_FN" ] && [ -f "/mnt/tmpfs/$ONE_BASENAME" ]; then\
  ONE_FN="/mnt/tmpfs/$ONE_BASENAME"\
 fi
}' "$_puppy_work/init" >"$_puppy_work/init.new"; then
			nb_error "Could not patch the $PUPPY_LABEL humongous-initrd loader."
			rm -rf "$_puppy_work" "$_puppy_work/init.new"
			return 1
		fi
		mv "$_puppy_work/init.new" "$_puppy_work/init"
		chmod 755 "$_puppy_work/init"
	fi

	if ! nb_initrd_repack "$_puppy_work" "$_puppy_repacked" "$_puppy_format" "standard"; then
		nb_error "Could not repack the $PUPPY_LABEL $_puppy_format initramfs."
		rm -rf "$_puppy_work"
		return 1
	fi

	: >"$_puppy_new"
	if [ "$_puppy_main_offset" -gt 0 ]; then
		if ! head -c "$_puppy_main_offset" /tmp/nb-initrd >>"$_puppy_new"; then
			nb_error "Could not preserve the $PUPPY_LABEL early initrd prefix."
			rm -rf "$_puppy_work" "$_puppy_repacked" "$_puppy_new"
			return 1
		fi
	fi
	if ! cat "$_puppy_repacked" >>"$_puppy_new"; then
		nb_error "Could not write the repacked $PUPPY_LABEL initrd."
		rm -rf "$_puppy_work" "$_puppy_repacked" "$_puppy_new"
		return 1
	fi

	mv "$_puppy_new" /tmp/nb-initrd
	rm -rf "$_puppy_work" "$_puppy_repacked"
	return 0
}

puppy_prepare_from_iso ()
{
	_puppy_iso_url="$1"
	_puppy_work="/tmp/nb-puppy-work"
	_puppy_iso="$_puppy_work/nb-puppy.iso"
	_puppy_boot="$_puppy_work/boot"
	_puppy_sfs_dir="$_puppy_work/sfs"

	if ! _puppy_7z=$(artix_7z_cmd); then
		nb_error "7zip is required to extract $PUPPY_LABEL boot files. Rebuild NetbootCD-Neo with 7zip included."
		return 1
	fi

	if grep -q " $_puppy_work " /proc/mounts 2>/dev/null; then
		umount "$_puppy_work" 2>/dev/null || true
	fi
	rm -f /tmp/nb-linux /tmp/nb-initrd
	rm -rf "$_puppy_work" /tmp/nb-initrd.puppy /tmp/nb-initrd.new
	mkdir -p "$_puppy_boot" "$_puppy_sfs_dir"
	_puppy_mounted=
	if mount -t tmpfs -o size=85%,mode=0755 tmpfs "$_puppy_work" 2>/tmp/nb-puppy-mount.log; then
		_puppy_mounted=1
		mkdir -p "$_puppy_boot" "$_puppy_sfs_dir"
	fi

	if ! wgetgauge "$_puppy_iso_url" "$_puppy_iso" "Downloading $PUPPY_LABEL ISO"; then
		nb_error "Could not download $PUPPY_LABEL ISO from:\n\n$_puppy_iso_url\n\nThis entry needs enough RAM to hold the ISO and the repacked initrd."
		[ -n "$_puppy_mounted" ] && umount "$_puppy_work" 2>/dev/null || true
		rm -rf "$_puppy_work"
		return 1
	fi

	if ! "$_puppy_7z" e -y -o"$_puppy_boot" "$_puppy_iso" "$PUPPY_KERNEL_PATH" "$PUPPY_INITRD_PATH" >/tmp/nb-puppy-7z.log 2>&1; then
		nb_error "Could not extract $PUPPY_LABEL boot files from the ISO.\nSee /tmp/nb-puppy-7z.log for details."
		[ -n "$_puppy_mounted" ] && umount "$_puppy_work" 2>/dev/null || true
		rm -rf "$_puppy_work"
		return 1
	fi
	_puppy_kernel_file="${PUPPY_KERNEL_PATH##*/}"
	_puppy_initrd_file="${PUPPY_INITRD_PATH##*/}"
	if [ ! -s "$_puppy_boot/$_puppy_kernel_file" ] || [ ! -s "$_puppy_boot/$_puppy_initrd_file" ]; then
		nb_error "The $PUPPY_LABEL ISO did not contain its expected kernel and initrd."
		[ -n "$_puppy_mounted" ] && umount "$_puppy_work" 2>/dev/null || true
		rm -rf "$_puppy_work"
		return 1
	fi
	mv "$_puppy_boot/$_puppy_kernel_file" /tmp/nb-linux
	mv "$_puppy_boot/$_puppy_initrd_file" /tmp/nb-initrd
	rm -rf "$_puppy_boot"

	_puppy_sfs_files=
	for _puppy_sfs_path in $PUPPY_SFS_PATHS; do
		if ! "$_puppy_7z" e -y -o"$_puppy_sfs_dir" "$_puppy_iso" "$_puppy_sfs_path" >>/tmp/nb-puppy-7z.log 2>&1; then
			nb_error "Could not extract $_puppy_sfs_path from the $PUPPY_LABEL ISO.\nSee /tmp/nb-puppy-7z.log for details."
			[ -n "$_puppy_mounted" ] && umount "$_puppy_work" 2>/dev/null || true
			rm -rf "$_puppy_work"
			rm -f /tmp/nb-linux /tmp/nb-initrd
			return 1
		fi
		_puppy_sfs_file="${_puppy_sfs_path##*/}"
		if [ ! -s "$_puppy_sfs_dir/$_puppy_sfs_file" ]; then
			nb_error "The $PUPPY_LABEL ISO did not contain $_puppy_sfs_path."
			[ -n "$_puppy_mounted" ] && umount "$_puppy_work" 2>/dev/null || true
			rm -rf "$_puppy_work"
			rm -f /tmp/nb-linux /tmp/nb-initrd
			return 1
		fi
		_puppy_sfs_files="$_puppy_sfs_files $_puppy_sfs_dir/$_puppy_sfs_file"
	done

	if [ -z "$_puppy_sfs_files" ]; then
		nb_error "No $PUPPY_LABEL SFS files were selected for embedding."
		[ -n "$_puppy_mounted" ] && umount "$_puppy_work" 2>/dev/null || true
		rm -rf "$_puppy_work"
		rm -f /tmp/nb-linux /tmp/nb-initrd
		return 1
	fi
	rm -f "$_puppy_iso"

	dialog --backtitle "$TITLE" --infobox \
		"Embedding the $PUPPY_LABEL SFS files into the initrd.\n\nThis can take a while for large ISOs." 7 70 || true
	if ! puppy_repack_initrd_with_sfs $_puppy_sfs_files; then
		[ -n "$_puppy_mounted" ] && umount "$_puppy_work" 2>/dev/null || true
		rm -rf "$_puppy_work"
		rm -f /tmp/nb-linux /tmp/nb-initrd
		return 1
	fi

	rm -f "$_puppy_iso" /tmp/nb-puppy-7z.log /tmp/nb-puppy-mount.log
	[ -n "$_puppy_mounted" ] && umount "$_puppy_work" 2>/dev/null || true
	rm -rf "$_puppy_work"
	return 0
}

easyos_img_setup ()
{
	EASYOS_LABEL="$1"
	EASYOS_IMG_URL="$2"
	EASYOS_KERNEL_PATH="$3"
	EASYOS_INITRD_PATH="$4"
	EASYOS_WKG_IMAGE_PATH="$5"
	EASYOS_WKG_UUID="$6"
	EASYOS_WKG_DIR="$7"
	EASYOS_WKG_LABEL="$8"
	printf '%s' "rw intel_iommu=igfx_off wkg_uuid=$EASYOS_WKG_UUID " >>/tmp/nb-options
	[ -n "$EASYOS_WKG_LABEL" ] && printf '%s' "wkg_label=$EASYOS_WKG_LABEL " >>/tmp/nb-options
	printf '%s' "wkg_dir=$EASYOS_WKG_DIR " >>/tmp/nb-options
}

easyos_repack_initrd_with_wkg_image ()
{
	_easyos_wkg_image="$1"
	_easyos_work="/tmp/nb-easyos-work/initrd-work"
	_easyos_repacked="/tmp/nb-easyos-work/nb-initrd.easyos"
	_easyos_new="/tmp/nb-easyos-work/nb-initrd.new"

	if ! _easyos_main_info=$(artix_find_main_initrd /tmp/nb-initrd); then
		nb_error "Could not determine the $EASYOS_LABEL initrd compression format."
		return 1
	fi
	_easyos_format="${_easyos_main_info%% *}"
	_easyos_main_offset="${_easyos_main_info#* }"

	if [ "$_easyos_format" = "zstd" ] && ! command -v zstd >/dev/null 2>&1; then
		nb_error "$EASYOS_LABEL initrd uses zstd compression, but zstd is not available."
		return 1
	fi
	if [ "$_easyos_format" = "xz" ] && ! command -v xz >/dev/null 2>&1; then
		nb_error "$EASYOS_LABEL initrd uses xz compression, but xz is not available."
		return 1
	fi

	rm -rf "$_easyos_work" "$_easyos_repacked" "$_easyos_new"
	mkdir -p "$_easyos_work"

	if ! nb_initrd_unpack /tmp/nb-initrd "$_easyos_work" "$_easyos_format" "$_easyos_main_offset" "-idmu" "/dev/null"; then
		nb_error "Could not unpack the $EASYOS_LABEL $_easyos_format initramfs."
		rm -rf "$_easyos_work"
		return 1
	fi

	if ! mv "$_easyos_wkg_image" "$_easyos_work/netbootcd-easyos-wkg.img"; then
		nb_error "Could not embed the $EASYOS_LABEL working image."
		rm -rf "$_easyos_work"
		return 1
	fi

	mkdir -p "$_easyos_work/sbin"
	cat >"$_easyos_work/sbin/netbootcd_easyos_loop" <<'EOF'
#!/bin/sh
PATH=/bin:/sbin
export PATH

EASYOS_IMAGE=/netbootcd-easyos-wkg.img

netbootcd_easyos_log()
{
	echo "NetbootCD-Neo: $*" >/dev/console 2>/dev/null || true
}

netbootcd_easyos_grow_image()
{
	EASYOS_GROW_MB=2048
	if command -v truncate >/dev/null 2>&1 && command -v stat >/dev/null 2>&1; then
		EASYOS_SIZE="$(stat -c %s "$EASYOS_IMAGE" 2>/dev/null || echo 0)"
		case "$EASYOS_SIZE" in
			''|*[!0-9]*) EASYOS_SIZE=0 ;;
		esac
		if [ "$EASYOS_SIZE" -gt 0 ]; then
			EASYOS_NEW_SIZE=$(( EASYOS_SIZE + EASYOS_GROW_MB * 1024 * 1024 ))
			if truncate -s "$EASYOS_NEW_SIZE" "$EASYOS_IMAGE" 2>/dev/null; then
				netbootcd_easyos_log "expanded embedded EasyOS working image by ${EASYOS_GROW_MB}M"
				return 0
			fi
		fi
	fi
	netbootcd_easyos_log "could not expand embedded EasyOS working image"
	return 0
}

netbootcd_easyos_resize_loop()
{
	EASYOS_RESIZE_LOOP="$1"
	if command -v e2fsck >/dev/null 2>&1 && command -v resize2fs >/dev/null 2>&1; then
		e2fsck -fy "$EASYOS_RESIZE_LOOP" >/dev/console 2>&1 || true
		resize2fs "$EASYOS_RESIZE_LOOP" >/dev/console 2>&1 || true
	fi
}

[ -f "$EASYOS_IMAGE" ] || exit 0
netbootcd_easyos_grow_image
[ -e /dev/loop-control ] || mknod /dev/loop-control c 10 237 2>/dev/null || true
for EASYOS_LOOP_NR in 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
	[ -e "/dev/loop$EASYOS_LOOP_NR" ] || mknod "/dev/loop$EASYOS_LOOP_NR" b 7 "$EASYOS_LOOP_NR" 2>/dev/null || true
done

modprobe loop 2>/dev/null || true

EASYOS_LOOP_DEVICE="$(losetup -f 2>/dev/null || true)"
if [ -n "$EASYOS_LOOP_DEVICE" ] && losetup "$EASYOS_LOOP_DEVICE" "$EASYOS_IMAGE" 2>/dev/null; then
	netbootcd_easyos_log "attached embedded EasyOS working image to $EASYOS_LOOP_DEVICE"
	netbootcd_easyos_resize_loop "$EASYOS_LOOP_DEVICE"
	blkid "$EASYOS_LOOP_DEVICE" >/dev/console 2>/dev/null || true
	exit 0
fi

for EASYOS_LOOP_DEVICE in /dev/loop0 /dev/loop1 /dev/loop2 /dev/loop3 /dev/loop4 /dev/loop5 /dev/loop6 /dev/loop7 /dev/loop8 /dev/loop9 /dev/loop10 /dev/loop11 /dev/loop12 /dev/loop13 /dev/loop14 /dev/loop15; do
	if losetup "$EASYOS_LOOP_DEVICE" "$EASYOS_IMAGE" 2>/dev/null; then
		netbootcd_easyos_log "attached embedded EasyOS working image to $EASYOS_LOOP_DEVICE"
		netbootcd_easyos_resize_loop "$EASYOS_LOOP_DEVICE"
		blkid "$EASYOS_LOOP_DEVICE" >/dev/console 2>/dev/null || true
		exit 0
	fi
done

netbootcd_easyos_log "could not attach embedded EasyOS working image"
exit 0
EOF
	chmod 755 "$_easyos_work/sbin/netbootcd_easyos_loop"

	if [ -f "$_easyos_work/init" ] && ! grep -q 'netbootcd_easyos_loop' "$_easyos_work/init"; then
		if ! sed '/^mount -t devtmpfs devtmpfs \/dev$/a\
/sbin/netbootcd_easyos_loop || true
' "$_easyos_work/init" >"$_easyos_work/init.new"; then
			nb_error "Could not add the $EASYOS_LABEL loop hook to initrd init."
			rm -rf "$_easyos_work" "$_easyos_work/init.new"
			return 1
		fi
		mv "$_easyos_work/init.new" "$_easyos_work/init"

		if ! sed '/^\[ \$Pw -eq 1 \] && WKG_DRV=/a\
case "$WKG_DEV" in\
 loop*) WKG_DRV="$WKG_DEV" ;;\
esac
' "$_easyos_work/init" >"$_easyos_work/init.new"; then
			nb_error "Could not patch the $EASYOS_LABEL working-drive detection."
			rm -rf "$_easyos_work" "$_easyos_work/init.new"
			return 1
		fi
		mv "$_easyos_work/init.new" "$_easyos_work/init"
		chmod 755 "$_easyos_work/init"
	fi

	if [ -f "$_easyos_work/inc/01resize-wkg" ] && ! grep -q 'netbootcd_easyos_skip_loop_resize' "$_easyos_work/inc/01resize-wkg"; then
		if ! sed '1a\
# netbootcd_easyos_skip_loop_resize\
case "$WKG_DEV" in\
 loop*) return 0 ;;\
esac
' "$_easyos_work/inc/01resize-wkg" >"$_easyos_work/inc/01resize-wkg.new"; then
			nb_error "Could not patch the $EASYOS_LABEL resize helper."
			rm -rf "$_easyos_work" "$_easyos_work/inc/01resize-wkg.new"
			return 1
		fi
		mv "$_easyos_work/inc/01resize-wkg.new" "$_easyos_work/inc/01resize-wkg"
	fi

	if ! nb_initrd_repack "$_easyos_work" "$_easyos_repacked" "$_easyos_format" "standard"; then
		nb_error "Could not repack the $EASYOS_LABEL $_easyos_format initramfs."
		rm -rf "$_easyos_work"
		return 1
	fi

	: >"$_easyos_new"
	if [ "$_easyos_main_offset" -gt 0 ]; then
		if ! head -c "$_easyos_main_offset" /tmp/nb-initrd >>"$_easyos_new"; then
			nb_error "Could not preserve the $EASYOS_LABEL early initrd prefix."
			rm -rf "$_easyos_work" "$_easyos_repacked" "$_easyos_new"
			return 1
		fi
	fi
	if ! cat "$_easyos_repacked" >>"$_easyos_new"; then
		nb_error "Could not write the repacked $EASYOS_LABEL initrd."
		rm -rf "$_easyos_work" "$_easyos_repacked" "$_easyos_new"
		return 1
	fi

	mv "$_easyos_new" /tmp/nb-initrd
	rm -rf "$_easyos_work" "$_easyos_repacked"
	return 0
}

easyos_prepare_from_img ()
{
	_easyos_img_url="$1"
	_easyos_work="/tmp/nb-easyos-work"
	_easyos_img="$_easyos_work/nb-easyos.img"
	_easyos_boot="$_easyos_work/boot"
	_easyos_wkg_image="$_easyos_work/${EASYOS_WKG_IMAGE_PATH##*/}"

	if ! _easyos_7z=$(artix_7z_cmd); then
		nb_error "7zip is required to extract $EASYOS_LABEL boot files. Rebuild NetbootCD-Neo with 7zip included."
		return 1
	fi

	if grep -q " $_easyos_work " /proc/mounts 2>/dev/null; then
		umount "$_easyos_work" 2>/dev/null || true
	fi
	rm -f /tmp/nb-linux /tmp/nb-initrd
	rm -rf "$_easyos_work" /tmp/nb-initrd.easyos /tmp/nb-initrd.new
	mkdir -p "$_easyos_boot"
	_easyos_mounted=
	if mount -t tmpfs -o size=85%,mode=0755 tmpfs "$_easyos_work" 2>/tmp/nb-easyos-mount.log; then
		_easyos_mounted=1
		mkdir -p "$_easyos_boot"
	fi

	if ! wgetgauge "$_easyos_img_url" "$_easyos_img" "Downloading $EASYOS_LABEL disk image"; then
		nb_error "Could not download $EASYOS_LABEL disk image from:\n\n$_easyos_img_url\n\nThis entry needs enough RAM to hold and repack the working image."
		[ -n "$_easyos_mounted" ] && umount "$_easyos_work" 2>/dev/null || true
		rm -rf "$_easyos_work"
		return 1
	fi

	if ! "$_easyos_7z" e -y -o"$_easyos_work" "$_easyos_img" "$EASYOS_WKG_IMAGE_PATH" >/tmp/nb-easyos-7z.log 2>&1; then
		nb_error "Could not extract the $EASYOS_LABEL working image from the disk image.\nSee /tmp/nb-easyos-7z.log for details."
		[ -n "$_easyos_mounted" ] && umount "$_easyos_work" 2>/dev/null || true
		rm -rf "$_easyos_work"
		return 1
	fi
	if [ ! -s "$_easyos_wkg_image" ]; then
		nb_error "The $EASYOS_LABEL disk image did not contain $EASYOS_WKG_IMAGE_PATH."
		[ -n "$_easyos_mounted" ] && umount "$_easyos_work" 2>/dev/null || true
		rm -rf "$_easyos_work"
		return 1
	fi
	rm -f "$_easyos_img"

	if ! "$_easyos_7z" e -y -o"$_easyos_boot" "$_easyos_wkg_image" "$EASYOS_KERNEL_PATH" "$EASYOS_INITRD_PATH" >>/tmp/nb-easyos-7z.log 2>&1; then
		nb_error "Could not extract $EASYOS_LABEL boot files from the working image.\nSee /tmp/nb-easyos-7z.log for details."
		[ -n "$_easyos_mounted" ] && umount "$_easyos_work" 2>/dev/null || true
		rm -rf "$_easyos_work"
		return 1
	fi
	_easyos_kernel_file="${EASYOS_KERNEL_PATH##*/}"
	_easyos_initrd_file="${EASYOS_INITRD_PATH##*/}"
	if [ ! -s "$_easyos_boot/$_easyos_kernel_file" ] || [ ! -s "$_easyos_boot/$_easyos_initrd_file" ]; then
		nb_error "The $EASYOS_LABEL working image did not contain its expected kernel and initrd."
		[ -n "$_easyos_mounted" ] && umount "$_easyos_work" 2>/dev/null || true
		rm -rf "$_easyos_work"
		return 1
	fi
	mv "$_easyos_boot/$_easyos_kernel_file" /tmp/nb-linux
	mv "$_easyos_boot/$_easyos_initrd_file" /tmp/nb-initrd
	rm -rf "$_easyos_boot"

	dialog --backtitle "$TITLE" --infobox \
		"Embedding the $EASYOS_LABEL working image into the initrd.\n\nThis is a large payload and can take a while." 7 70 || true
	if ! easyos_repack_initrd_with_wkg_image "$_easyos_wkg_image"; then
		[ -n "$_easyos_mounted" ] && umount "$_easyos_work" 2>/dev/null || true
		rm -rf "$_easyos_work"
		rm -f /tmp/nb-linux /tmp/nb-initrd
		return 1
	fi

	rm -f "$_easyos_img" /tmp/nb-easyos-7z.log /tmp/nb-easyos-mount.log
	[ -n "$_easyos_mounted" ] && umount "$_easyos_work" 2>/dev/null || true
	rm -rf "$_easyos_work"
	return 0
}

libreelec_img_setup ()
{
	LIBREELEC_LABEL="$1"
	LIBREELEC_IMG_URL="$2"
	LIBREELEC_INIT_URL="$3"
	printf '%s' "boot=NETBOOTCD BOOT_IMAGE=KERNEL SYSTEM_IMAGE=SYSTEM installer nofsck quiet systemd.debug_shell vga=current " >>/tmp/nb-options
}

libreelec_prepare_from_img ()
{
	_libreelec_img_url="$1"
	_libreelec_work="/tmp/nb-libreelec-work"
	_libreelec_img_gz="$_libreelec_work/nb-libreelec.img.gz"
	_libreelec_fat="$_libreelec_work/system.fat"
	_libreelec_overlay="$_libreelec_work/initrd-overlay"
	_libreelec_flash="$_libreelec_overlay/.netbootcd/flash"

	if ! _libreelec_7z=$(artix_7z_cmd); then
		nb_error "7zip is required to extract $LIBREELEC_LABEL boot files. Rebuild NetbootCD-Neo with 7zip included."
		return 1
	fi
	if ! command -v zstd >/dev/null 2>&1; then
		nb_error "zstd is required to prepare the $LIBREELEC_LABEL ramdisk. Rebuild NetbootCD-Neo with zstd included."
		return 1
	fi

	if grep -q " $_libreelec_work " /proc/mounts 2>/dev/null; then
		umount "$_libreelec_work" 2>/dev/null || true
	fi
	rm -f /tmp/nb-linux /tmp/nb-initrd
	rm -rf "$_libreelec_work"
	mkdir -p "$_libreelec_flash"
	_libreelec_mounted=
	if mount -t tmpfs -o size=85%,mode=0755 tmpfs "$_libreelec_work" 2>/tmp/nb-libreelec-mount.log; then
		_libreelec_mounted=1
		mkdir -p "$_libreelec_flash"
	fi

	if ! wgetgauge "$_libreelec_img_url" "$_libreelec_img_gz" "Downloading $LIBREELEC_LABEL installer image"; then
		nb_error "Could not download $LIBREELEC_LABEL image from:\n\n$_libreelec_img_url\n\nThis entry needs enough RAM to unpack and embed the installer files."
		[ -n "$_libreelec_mounted" ] && umount "$_libreelec_work" 2>/dev/null || true
		rm -rf "$_libreelec_work"
		return 1
	fi

	# The 12.2.1 Generic image places its 1 GiB FAT installer partition at 4 MiB.
	# Pipe reads can be short, so use full blocks where BusyBox provides them.
	if dd if=/dev/zero of=/dev/null bs=1 count=0 iflag=fullblock 2>/dev/null; then
		gzip -cd "$_libreelec_img_gz" 2>/tmp/nb-libreelec-gzip.log |
			dd iflag=fullblock bs=1048576 skip=4 count=1024 of="$_libreelec_fat" 2>/tmp/nb-libreelec-dd.log || true
	else
		gzip -cd "$_libreelec_img_gz" 2>/tmp/nb-libreelec-gzip.log |
			dd bs=4096 skip=1024 count=262144 of="$_libreelec_fat" 2>/tmp/nb-libreelec-dd.log || true
	fi
	if [ "$(wc -c <"$_libreelec_fat" 2>/dev/null || echo 0)" -ne 1073741824 ]; then
		nb_error "Could not unpack the $LIBREELEC_LABEL installer partition.\nSee /tmp/nb-libreelec-dd.log for details."
		[ -n "$_libreelec_mounted" ] && umount "$_libreelec_work" 2>/dev/null || true
		rm -rf "$_libreelec_work"
		return 1
	fi
	rm -f "$_libreelec_img_gz"

	if ! "$_libreelec_7z" x -y -o"$_libreelec_flash" "$_libreelec_fat" >/tmp/nb-libreelec-7z.log 2>&1; then
		nb_error "Could not find $LIBREELEC_LABEL installer files in its system partition.\nSee /tmp/nb-libreelec-7z.log for details."
		[ -n "$_libreelec_mounted" ] && umount "$_libreelec_work" 2>/dev/null || true
		rm -rf "$_libreelec_work"
		return 1
	fi
	rm -f "$_libreelec_fat"
	if [ ! -s "$_libreelec_flash/KERNEL" ] || [ ! -s "$_libreelec_flash/SYSTEM" ]; then
		nb_error "The $LIBREELEC_LABEL image did not contain its expected KERNEL and SYSTEM files."
		[ -n "$_libreelec_mounted" ] && umount "$_libreelec_work" 2>/dev/null || true
		rm -rf "$_libreelec_work"
		return 1
	fi
	cp "$_libreelec_flash/KERNEL" /tmp/nb-linux

	if ! $WGET "$LIBREELEC_INIT_URL" -O "$_libreelec_overlay/init" >/tmp/nb-libreelec-init.log 2>&1; then
		nb_error "Could not download the $LIBREELEC_LABEL init overlay source.\nSee /tmp/nb-libreelec-init.log for details."
		[ -n "$_libreelec_mounted" ] && umount "$_libreelec_work" 2>/dev/null || true
		rm -rf "$_libreelec_work"
		rm -f /tmp/nb-linux
		return 1
	fi
	if ! awk '
		{
			gsub(/@KERNEL_NAME@/, "KERNEL")
			gsub(/@DISTRONAME@/, "LibreELEC")
			gsub(/@SYSTEM_SIZE@/, "1024")
			print
		}
		/^mount_flash\(\) \{/ && !inserted {
			print "  if [ \"$boot\" = \"NETBOOTCD\" ]; then"
			print "    progress \"Mounting embedded NetbootCD-Neo LibreELEC installer media\""
			print "    /usr/bin/busybox mount --bind /.netbootcd/flash /flash || error \"mount_flash\" \"Could not bind embedded installer media\""
			print "    return"
			print "  fi"
			inserted = 1
		}
		END {
			if (!inserted)
				exit 1
		}
	' "$_libreelec_overlay/init" >"$_libreelec_overlay/init.new"; then
		nb_error "Could not patch the $LIBREELEC_LABEL init overlay."
		[ -n "$_libreelec_mounted" ] && umount "$_libreelec_work" 2>/dev/null || true
		rm -rf "$_libreelec_work"
		rm -f /tmp/nb-linux
		return 1
	fi
	mv "$_libreelec_overlay/init.new" "$_libreelec_overlay/init"
	chmod 755 "$_libreelec_overlay/init"

	dialog --backtitle "$TITLE" --infobox \
		"Embedding the $LIBREELEC_LABEL installer files into the initrd.\n\nThis can take a while." 7 70 || true
	# LibreELEC Generic accepts zstd external initramfs archives; use one to
	# override init and bind its extracted installer files as /flash.
	if ! ( cd "$_libreelec_overlay" && find . | cpio -o -H newc | zstd -q -1 -c >/tmp/nb-initrd ); then
		nb_error "Could not create the $LIBREELEC_LABEL initrd overlay."
		[ -n "$_libreelec_mounted" ] && umount "$_libreelec_work" 2>/dev/null || true
		rm -rf "$_libreelec_work"
		rm -f /tmp/nb-linux /tmp/nb-initrd
		return 1
	fi

	rm -f /tmp/nb-libreelec-7z.log /tmp/nb-libreelec-dd.log /tmp/nb-libreelec-gzip.log /tmp/nb-libreelec-init.log /tmp/nb-libreelec-mount.log
	[ -n "$_libreelec_mounted" ] && umount "$_libreelec_work" 2>/dev/null || true
	rm -rf "$_libreelec_work"
	return 0
}

ARTIX_ISO_BASE="http://mirrors.ocf.berkeley.edu/artix-iso"
VOID_ISO_BASE="http://repo-fastly.voidlinux.org/live/current"
ALTLINUX_ISO_BASE="http://nightly.altlinux.org/sisyphus/current"
GUIX_ISO_BASE="https://ftp.gnu.org/gnu/guix"

pentesting_iso_setup ()
{
	case "$1" in
		fedora-security-44)
			dracut_live_iso_setup \
				"Fedora Security Lab 44" \
				"https://download.fedoraproject.org/pub/alt/releases/44/Labs/x86_64/iso/Fedora-Security-Live-44-1.7.x86_64.iso" \
				"quiet" || return
			;;
		*)
			nb_error "Unknown pentesting/security live ISO entry: $1"
			return 1
			;;
	esac
}

artix_iso_file ()
{
	case "$1" in
		base-dinit) printf '%s\n' 'artix-base-dinit-20250407-x86_64.iso' ;;
		base-openrc) printf '%s\n' 'artix-base-openrc-20250407-x86_64.iso' ;;
		base-runit) printf '%s\n' 'artix-base-runit-20250407-x86_64.iso' ;;
		base-s6) printf '%s\n' 'artix-base-s6-20250407-x86_64.iso' ;;
		*) return 1 ;;
	esac
}

artix_iso_url ()
{
	_artix_iso_file="$1"
	printf '%s/%s\n' "$ARTIX_ISO_BASE" "$_artix_iso_file"
}

artix_7z_cmd ()
{
	if command -v 7zz >/dev/null 2>&1; then
		printf '%s\n' 7zz
	elif command -v 7z >/dev/null 2>&1; then
		printf '%s\n' 7z
	else
		return 1
	fi
}

iso_prepare_boot_files ()
{
	_iso_url="$1"
	_iso_file="$2"
	_boot_dir="$3"
	_kernel_path="$4"
	_initrd_path="$5"
	_label="$6"

	if ! _iso_7z=$(artix_7z_cmd); then
		nb_error "7zip is required to extract $_label boot files. Rebuild NetbootCD-Neo with 7zip included."
		return 1
	fi

	rm -f /tmp/nb-linux /tmp/nb-initrd "$_iso_file"
	rm -rf "$_boot_dir"
	mkdir -p "$_boot_dir"

	if ! wgetgauge "$_iso_url" "$_iso_file" "Downloading $_label ISO"; then
		nb_error "Could not download $_label ISO from:\n\n$_iso_url"
		rm -f "$_iso_file"
		rm -rf "$_boot_dir"
		return 1
	fi

	if ! "$_iso_7z" e -y -o"$_boot_dir" "$_iso_file" "$_kernel_path" "$_initrd_path" >/tmp/nb-iso-7z.log 2>&1; then
		nb_error "Could not extract $_label boot files from the ISO.\nSee /tmp/nb-iso-7z.log for details."
		rm -f "$_iso_file"
		rm -rf "$_boot_dir"
		return 1
	fi

	_kernel_file="${_kernel_path##*/}"
	_initrd_file="${_initrd_path##*/}"

	if [ ! -s "$_boot_dir/$_kernel_file" ]; then
		nb_error "The $_label ISO did not contain $_kernel_path."
		rm -f "$_iso_file"
		rm -rf "$_boot_dir"
		return 1
	fi
	if [ ! -s "$_boot_dir/$_initrd_file" ]; then
		nb_error "The $_label ISO did not contain $_initrd_path."
		rm -f "$_iso_file"
		rm -rf "$_boot_dir"
		return 1
	fi

	mv "$_boot_dir/$_kernel_file" /tmp/nb-linux
	mv "$_boot_dir/$_initrd_file" /tmp/nb-initrd
	rm -f "$_iso_file" /tmp/nb-iso-7z.log
	rm -rf "$_boot_dir"
	return 0
}

iso_boot_setup ()
{
	ISO_BOOT_URL="$1"
	ISO_BOOT_LABEL="$2"
	ISO_BOOT_KERNEL_PATH="$3"
	ISO_BOOT_INITRD_PATH="$4"
}

iso_boot_prepare_from_iso ()
{
	iso_prepare_boot_files \
		"$ISO_BOOT_URL" \
		/tmp/nb-iso-boot.iso \
		/tmp/nb-iso-boot \
		"$ISO_BOOT_KERNEL_PATH" \
		"$ISO_BOOT_INITRD_PATH" \
		"$ISO_BOOT_LABEL"
}

antix_mx_iso_file ()
{
	case "$1" in
		antix-26-core) printf '%s\n' 'antix-linux/Final/antiX-26/antiX-26_x64-core.iso' ;;
		avlinux-mxe-251) printf '%s\n' 'https://downloads.bandshed.net/AVL_MXe_25/AVL_MXe-25.1_x64.iso' ;;
		mx-25.1-xfce) printf '%s\n' 'mx-linux/Final/Xfce/MX-25.1_Xfce_x64.iso' ;;
		mx-25.1-xfce-ahs) printf '%s\n' 'mx-linux/Final/Xfce/MX-25.1_Xfce_ahs_x64.iso' ;;
		*) return 1 ;;
	esac
}

antix_mx_iso_label ()
{
	case "$1" in
		antix-26-core) printf '%s\n' 'antiX 26 Core' ;;
		avlinux-mxe-251) printf '%s\n' 'AV Linux MXE 25.1' ;;
		mx-25.1-xfce) printf '%s\n' 'MX Linux 25.1 Xfce' ;;
		mx-25.1-xfce-ahs) printf '%s\n' 'MX Linux 25.1 Xfce AHS' ;;
		*) return 1 ;;
	esac
}

antix_mx_iso_url ()
{
	_antix_mx_iso_file="$1"
	case "$_antix_mx_iso_file" in
		http://*|https://*) printf '%s\n' "$_antix_mx_iso_file" ;;
		*) printf 'http://downloads.sourceforge.net/project/%s\n' "$_antix_mx_iso_file" ;;
	esac
}

antix_mx_iso_setup ()
{
	_antix_mx_iso_tag="$1"

	if ! _antix_mx_iso_file=$(antix_mx_iso_file "$_antix_mx_iso_tag"); then
		nb_error "Unknown antiX/MX Linux ISO entry: $_antix_mx_iso_tag"
		return 1
	fi
	if ! ANTIX_MX_LABEL=$(antix_mx_iso_label "$_antix_mx_iso_tag"); then
		nb_error "Unknown antiX/MX Linux ISO entry: $_antix_mx_iso_tag"
		return 1
	fi

	ANTIX_MX_ISO_URL=$(antix_mx_iso_url "$_antix_mx_iso_file")
	printf '%s' "from=all try=60 load=all sq=antiX/linuxfs quiet " >>/tmp/nb-options
}

antix_mx_add_embedded_linuxfs_hook ()
{
	_antix_mx_work="$1"
	_antix_mx_hook="$_antix_mx_work/live/custom/antiX/0.sh"

	mkdir -p "$_antix_mx_work/live/custom/antiX" \
		"$_antix_mx_work/live/custom/MX" \
		"$_antix_mx_work/live/custom/mx"
	cat >"$_antix_mx_hook" <<'EOFH'
find_linuxfs_file() {
    if [ -f /antiX/linuxfs ]; then
        heading "NetbootCD embedded linuxfs"
        mkdir -p "$BOOT_MP/antiX"
        if [ ! -f "$BOOT_MP/antiX/linuxfs" ]; then
            mv /antiX/linuxfs "$BOOT_MP/antiX/linuxfs" \
                || fatal "Could not move NetbootCD embedded linuxfs into place"
        fi
        SQFILE_FULL=$BOOT_MP/antiX/linuxfs
        SQFILE_MP=$BOOT_MP
        SQFILE_DEV=$BOOT_MP
        SQFILE_PATH=antiX
        DEFAULT_PERSIST_PATH=$SQFILE_PATH
        SQFILE_DIR=$BOOT_MP/antiX
        DEFAULT_DIR=$SQFILE_DIR
        return 0
    fi

    if [ -n "${ISO_FILE:-}" ] || [ -n "${FROM_ISO:-}" ]; then
        : ${ISO_FILE:=$DEFAULT_ISO_FILE}
        ISO_FILE=${ISO_FILE#/}

        heading "${cheat_co}fromiso"

        find_boot_file "$ISO_FILE" "$ISO_DEV_MP" "$BOOT_ID" "$BOOT_RETRY" \
            || fatal  "$_Could_not_find_X_file_Y_" iso "$(pqh $ISO_FILE)"

        _nb_antix_iso_full=$ISO_DEV_MP/$ISO_FILE
        DEFAULT_PERSIST_PATH=${ISO_FILE%/*}

        [ "$CHECK_MD5" ] && check_md5 "$_nb_antix_iso_full"

        mkdir -p $ISO_FILE_MP
        mount -t iso9660 -o loop,ro "$_nb_antix_iso_full" $ISO_FILE_MP \
            || mount -t udf -o loop,ro "$_nb_antix_iso_full" $ISO_FILE_MP \
            || fatal_dmesg  "$_Could_not_mount_X_as_a_Y_file_" "$(pqh $_nb_antix_iso_full)" 'iso'

        SQFILE_FULL="$ISO_FILE_MP/$SQFILE_FILE"
        [ -f "$SQFILE_FULL" ] \
            || linuxfs_error  "$_File_X_not_found_on_device_Y_" "$SQFILE_FULL" "$FOUND_DEV"

        SQFILE_MP=$ISO_FILE_MP
        BOOT_MP=$SQFILE_MP
        SQFILE_DEV=$FOUND_DEV
        SQFILE_PATH=${SQFILE_FILE%/*}

        DID_ISO=true
    else
        find_crypt_or_linuxfs
        tsplash_on

        SQFILE_MP=$BOOT_MP
        SQFILE_DEV=$FOUND_DEV

        SQFILE_FULL=$BOOT_MP/$SQFILE_FILE
        SQFILE_PATH=${SQFILE_FILE%/*}
        DEFAULT_PERSIST_PATH=$SQFILE_PATH
    fi

    SQFILE_DIR=$(dirname $SQFILE_FULL)
    DEFAULT_DIR=$SQFILE_DIR
}
EOFH
	chmod 0755 "$_antix_mx_hook"
	cp "$_antix_mx_hook" "$_antix_mx_work/live/custom/MX/0.sh"
	cp "$_antix_mx_hook" "$_antix_mx_work/live/custom/mx/0.sh"
}

antix_mx_repack_initrd_with_linuxfs ()
{
	_antix_mx_iso="$1"
	_antix_mx_work="/tmp/nb-antix-mx-initrd-work"
	_antix_mx_repacked="/tmp/nb-initrd.antix-mx"

	if ! _antix_mx_7z=$(artix_7z_cmd); then
		nb_error "7zip is required to extract $ANTIX_MX_LABEL live files."
		return 1
	fi
	if ! _antix_mx_main_info=$(artix_find_main_initrd /tmp/nb-initrd); then
		nb_error "Could not determine the $ANTIX_MX_LABEL initramfs compression format."
		return 1
	fi
	_antix_mx_format="${_antix_mx_main_info%% *}"
	_antix_mx_main_offset="${_antix_mx_main_info#* }"

	if ! nb_initrd_need_tool "$_antix_mx_format" "$ANTIX_MX_LABEL"; then
		return 1
	fi

	rm -rf "$_antix_mx_work" "$_antix_mx_repacked"
	mkdir -p "$_antix_mx_work"

	if ! nb_initrd_unpack /tmp/nb-initrd "$_antix_mx_work" "$_antix_mx_format" "$_antix_mx_main_offset" "-idm" "/dev/null"; then
		nb_error "Could not unpack the $ANTIX_MX_LABEL $_antix_mx_format initramfs."
		rm -rf "$_antix_mx_work"
		return 1
	fi

	mkdir -p "$_antix_mx_work/antiX"
	if ! "$_antix_mx_7z" e -y -o"$_antix_mx_work/antiX" "$_antix_mx_iso" antiX/linuxfs >/tmp/nb-antix-mx-7z.log 2>&1; then
		nb_error "Could not extract antiX/linuxfs from the $ANTIX_MX_LABEL ISO.\nSee /tmp/nb-antix-mx-7z.log for details."
		rm -rf "$_antix_mx_work"
		return 1
	fi
	if [ ! -s "$_antix_mx_work/antiX/linuxfs" ]; then
		nb_error "The $ANTIX_MX_LABEL ISO did not contain antiX/linuxfs."
		rm -rf "$_antix_mx_work"
		return 1
	fi
	rm -f "$_antix_mx_iso"

	antix_mx_add_embedded_linuxfs_hook "$_antix_mx_work"

	if ! nb_initrd_repack "$_antix_mx_work" "$_antix_mx_repacked" "$_antix_mx_format" "standard"; then
		nb_error "Could not repack the $ANTIX_MX_LABEL $_antix_mx_format initramfs."
		rm -rf "$_antix_mx_work"
		return 1
	fi

	: >/tmp/nb-initrd.new
	if [ "$_antix_mx_main_offset" -gt 0 ]; then
		if ! head -c "$_antix_mx_main_offset" /tmp/nb-initrd >>/tmp/nb-initrd.new; then
			nb_error "Could not preserve the $ANTIX_MX_LABEL early initramfs prefix."
			rm -rf "$_antix_mx_work" "$_antix_mx_repacked" /tmp/nb-initrd.new
			return 1
		fi
	fi
	if ! cat "$_antix_mx_repacked" >>/tmp/nb-initrd.new; then
		nb_error "Could not write the repacked $ANTIX_MX_LABEL initramfs."
		rm -rf "$_antix_mx_work" "$_antix_mx_repacked" /tmp/nb-initrd.new
		return 1
	fi
	mv /tmp/nb-initrd.new /tmp/nb-initrd
	rm -rf "$_antix_mx_work" "$_antix_mx_repacked" /tmp/nb-antix-mx-7z.log
	return 0
}

antix_mx_prepare_from_iso ()
{
	_antix_mx_iso_url="$1"
	_antix_mx_iso="/tmp/nb-antix-mx.iso"
	_antix_mx_boot="/tmp/nb-antix-mx-boot"

	if ! _antix_mx_7z=$(artix_7z_cmd); then
		nb_error "7zip is required to extract $ANTIX_MX_LABEL boot files. Rebuild NetbootCD-Neo with 7zip included."
		return 1
	fi

	rm -f /tmp/nb-linux /tmp/nb-initrd "$_antix_mx_iso"
	rm -rf "$_antix_mx_boot" /tmp/nb-antix-mx-initrd-work /tmp/nb-initrd.antix-mx /tmp/nb-initrd.new
	mkdir -p "$_antix_mx_boot"

	if ! wgetgauge "$_antix_mx_iso_url" "$_antix_mx_iso" "Downloading $ANTIX_MX_LABEL ISO"; then
		nb_error "Could not download $ANTIX_MX_LABEL ISO from:\n\n$_antix_mx_iso_url\n\nThis entry needs enough RAM to hold the ISO before kexec."
		rm -f "$_antix_mx_iso"
		rm -rf "$_antix_mx_boot"
		return 1
	fi

	if ! "$_antix_mx_7z" e -y -o"$_antix_mx_boot" "$_antix_mx_iso" antiX/vmlinuz antiX/initrd.gz >/tmp/nb-antix-mx-7z.log 2>&1; then
		nb_error "Could not extract $ANTIX_MX_LABEL boot files from the ISO.\nSee /tmp/nb-antix-mx-7z.log for details."
		rm -f "$_antix_mx_iso"
		rm -rf "$_antix_mx_boot"
		return 1
	fi
	if [ ! -s "$_antix_mx_boot/vmlinuz" ]; then
		nb_error "The $ANTIX_MX_LABEL ISO did not contain antiX/vmlinuz."
		rm -f "$_antix_mx_iso"
		rm -rf "$_antix_mx_boot"
		return 1
	fi
	if [ ! -s "$_antix_mx_boot/initrd.gz" ]; then
		nb_error "The $ANTIX_MX_LABEL ISO did not contain antiX/initrd.gz."
		rm -f "$_antix_mx_iso"
		rm -rf "$_antix_mx_boot"
		return 1
	fi

	mv "$_antix_mx_boot/vmlinuz" /tmp/nb-linux
	mv "$_antix_mx_boot/initrd.gz" /tmp/nb-initrd
	rm -rf "$_antix_mx_boot"

	dialog --backtitle "$TITLE" --infobox \
		"Embedding antiX/linuxfs from the $ANTIX_MX_LABEL ISO into the initrd.\n\nThis can take a while for large ISOs." 7 70 || true
	if ! antix_mx_repack_initrd_with_linuxfs "$_antix_mx_iso"; then
		rm -f "$_antix_mx_iso"
		rm -f /tmp/nb-linux /tmp/nb-initrd /tmp/nb-initrd.new /tmp/nb-initrd.antix-mx
		rm -rf /tmp/nb-antix-mx-initrd-work
		return 1
	fi

	rm -f "$_antix_mx_iso" /tmp/nb-antix-mx-7z.log
	return 0
}

daphile_patch_init ()
{
	_daphile_init="$1"
	_daphile_patched=0

	rm -f "$_daphile_init.new"
	while IFS= read -r _daphile_line || [ -n "$_daphile_line" ]; do
		printf '%s\n' "$_daphile_line"
		if [ "$_daphile_patched" -eq 0 ] && [ "$_daphile_line" = "mount_boot() {" ]; then
			printf '%s\n' '	if [[ -f "/boot/boot/${daphile}/rootfs" && -e "/boot/boot/live" ]]'
			printf '%s\n' '	then'
			printf '%s\n' '		return 0'
			printf '%s\n' '	fi'
			_daphile_patched=1
		fi
	done <"$_daphile_init" >"$_daphile_init.new"

	if [ "$_daphile_patched" -ne 1 ]; then
		rm -f "$_daphile_init.new"
		return 1
	fi
	mv "$_daphile_init.new" "$_daphile_init"
	chmod 0755 "$_daphile_init"
}

daphile_initrd_unpacked ()
{
	[ -f "$1/init" ] && [ -f "$1/bin/busybox" ]
}

daphile_repack_initrd_with_rootfs ()
{
	_daphile_rootfs="$1"
	_daphile_work="/tmp/nb-daphile-initrd-work"
	_daphile_repacked="/tmp/nb-initrd.daphile"

	if ! _daphile_main_info=$(artix_find_main_initrd /tmp/nb-initrd); then
		nb_error "Could not determine the $DAPHILE_LABEL initramfs compression format."
		return 1
	fi
	_daphile_format="${_daphile_main_info%% *}"
	_daphile_main_offset="${_daphile_main_info#* }"

	if ! nb_initrd_need_tool "$_daphile_format" "$DAPHILE_LABEL"; then
		return 1
	fi

	rm -rf "$_daphile_work" "$_daphile_repacked"
	mkdir -p "$_daphile_work"

	case "$_daphile_format" in
		gzip)
			if ! ( tail -c +"$(( _daphile_main_offset + 1 ))" /tmp/nb-initrd | gzip -cd | ( cd "$_daphile_work" && cpio -idm 2>/tmp/nb-daphile-cpio.log ) ); then
				if daphile_initrd_unpacked "$_daphile_work"; then
					:
				else
					nb_error "Could not unpack the $DAPHILE_LABEL gzip initramfs."
					rm -rf "$_daphile_work"
					return 1
				fi
			fi
			;;
		zstd)
			if ! ( tail -c +"$(( _daphile_main_offset + 1 ))" /tmp/nb-initrd | zstd -dc | ( cd "$_daphile_work" && cpio -idm 2>/tmp/nb-daphile-cpio.log ) ); then
				if daphile_initrd_unpacked "$_daphile_work"; then
					:
				else
					nb_error "Could not unpack the $DAPHILE_LABEL zstd initramfs."
					rm -rf "$_daphile_work"
					return 1
				fi
			fi
			;;
		xz)
			if ! ( tail -c +"$(( _daphile_main_offset + 1 ))" /tmp/nb-initrd | xz -dc | ( cd "$_daphile_work" && cpio -idm 2>/tmp/nb-daphile-cpio.log ) ); then
				if daphile_initrd_unpacked "$_daphile_work"; then
					:
				else
					nb_error "Could not unpack the $DAPHILE_LABEL xz initramfs."
					rm -rf "$_daphile_work"
					return 1
				fi
			fi
			;;
		cpio)
			if ! ( tail -c +"$(( _daphile_main_offset + 1 ))" /tmp/nb-initrd | ( cd "$_daphile_work" && cpio -idm 2>/tmp/nb-daphile-cpio.log ) ); then
				if daphile_initrd_unpacked "$_daphile_work"; then
					:
				else
					nb_error "Could not unpack the $DAPHILE_LABEL cpio initramfs."
					rm -rf "$_daphile_work"
					return 1
				fi
			fi
			;;
	esac

	if [ ! -f "$_daphile_work/init" ]; then
		nb_error "The $DAPHILE_LABEL initramfs did not contain /init."
		rm -rf "$_daphile_work"
		return 1
	fi
	if ! daphile_patch_init "$_daphile_work/init"; then
		nb_error "Could not patch the $DAPHILE_LABEL boot media check."
		rm -rf "$_daphile_work"
		return 1
	fi

	mkdir -p "$_daphile_work/boot/boot/$DAPHILE_VERSION_DIR"
	if ! cp "$_daphile_rootfs" "$_daphile_work/boot/boot/$DAPHILE_VERSION_DIR/rootfs"; then
		nb_error "Could not embed the $DAPHILE_LABEL rootfs into the initramfs."
		rm -rf "$_daphile_work"
		return 1
	fi
	: >"$_daphile_work/boot/boot/live"

	if ! nb_initrd_repack "$_daphile_work" "$_daphile_repacked" "$_daphile_format" "standard"; then
		nb_error "Could not repack the $DAPHILE_LABEL $_daphile_format initramfs."
		rm -rf "$_daphile_work"
		return 1
	fi

	: >/tmp/nb-initrd.new
	if [ "$_daphile_main_offset" -gt 0 ]; then
		if ! head -c "$_daphile_main_offset" /tmp/nb-initrd >>/tmp/nb-initrd.new; then
			nb_error "Could not preserve the $DAPHILE_LABEL early initramfs prefix."
			rm -rf "$_daphile_work" "$_daphile_repacked" /tmp/nb-initrd.new
			return 1
		fi
	fi
	if ! cat "$_daphile_repacked" >>/tmp/nb-initrd.new; then
		nb_error "Could not write the repacked $DAPHILE_LABEL initramfs."
		rm -rf "$_daphile_work" "$_daphile_repacked" /tmp/nb-initrd.new
		return 1
	fi
	mv /tmp/nb-initrd.new /tmp/nb-initrd
	rm -rf "$_daphile_work" "$_daphile_repacked" /tmp/nb-daphile-cpio.log
	return 0
}

daphile_prepare_from_iso ()
{
	_daphile_iso_url="$1"
	_daphile_iso="/tmp/nb-daphile.iso"
	_daphile_boot="/tmp/nb-daphile-boot"

	if ! _daphile_7z=$(artix_7z_cmd); then
		nb_error "7zip is required to extract $DAPHILE_LABEL boot files. Rebuild NetbootCD-Neo with 7zip included."
		return 1
	fi

	rm -f /tmp/nb-linux /tmp/nb-initrd "$_daphile_iso"
	rm -rf "$_daphile_boot" /tmp/nb-daphile-initrd-work /tmp/nb-initrd.daphile /tmp/nb-initrd.new
	mkdir -p "$_daphile_boot"

	if ! wgetgauge "$_daphile_iso_url" "$_daphile_iso" "Downloading $DAPHILE_LABEL ISO"; then
		nb_error "Could not download $DAPHILE_LABEL ISO from:\n\n$_daphile_iso_url"
		rm -f "$_daphile_iso"
		rm -rf "$_daphile_boot"
		return 1
	fi

	if ! "$_daphile_7z" e -y -o"$_daphile_boot" "$_daphile_iso" "$DAPHILE_KERNEL_PATH" "$DAPHILE_INITRD_PATH" "$DAPHILE_ROOTFS_PATH" >/tmp/nb-daphile-7z.log 2>&1; then
		nb_error "Could not extract $DAPHILE_LABEL boot files from the ISO.\nSee /tmp/nb-daphile-7z.log for details."
		rm -f "$_daphile_iso"
		rm -rf "$_daphile_boot"
		return 1
	fi

	_daphile_kernel_file="${DAPHILE_KERNEL_PATH##*/}"
	_daphile_initrd_file="${DAPHILE_INITRD_PATH##*/}"
	_daphile_rootfs_file="${DAPHILE_ROOTFS_PATH##*/}"

	if [ ! -s "$_daphile_boot/$_daphile_kernel_file" ]; then
		nb_error "The $DAPHILE_LABEL ISO did not contain $DAPHILE_KERNEL_PATH."
		rm -f "$_daphile_iso"
		rm -rf "$_daphile_boot"
		return 1
	fi
	if [ ! -s "$_daphile_boot/$_daphile_initrd_file" ]; then
		nb_error "The $DAPHILE_LABEL ISO did not contain $DAPHILE_INITRD_PATH."
		rm -f "$_daphile_iso"
		rm -rf "$_daphile_boot"
		return 1
	fi
	if [ ! -s "$_daphile_boot/$_daphile_rootfs_file" ]; then
		nb_error "The $DAPHILE_LABEL ISO did not contain $DAPHILE_ROOTFS_PATH."
		rm -f "$_daphile_iso"
		rm -rf "$_daphile_boot"
		return 1
	fi

	mv "$_daphile_boot/$_daphile_kernel_file" /tmp/nb-linux
	mv "$_daphile_boot/$_daphile_initrd_file" /tmp/nb-initrd
	rm -f "$_daphile_iso"

	dialog --backtitle "$TITLE" --infobox \
		"Embedding the $DAPHILE_LABEL rootfs into the initrd.\n\nThis can take a while." 7 70 || true
	if ! daphile_repack_initrd_with_rootfs "$_daphile_boot/$_daphile_rootfs_file"; then
		rm -f /tmp/nb-linux /tmp/nb-initrd /tmp/nb-initrd.new /tmp/nb-initrd.daphile
		rm -rf "$_daphile_boot" /tmp/nb-daphile-initrd-work
		return 1
	fi

	rm -f /tmp/nb-daphile-7z.log
	rm -rf "$_daphile_boot"
	return 0
}

void_iso_file ()
{
	case "$1" in
		glibc-base) printf '%s\n' 'void-live-x86_64-20250202-base.iso' ;;
		glibc-xfce) printf '%s\n' 'void-live-x86_64-20250202-xfce.iso' ;;
		musl-base) printf '%s\n' 'void-live-x86_64-musl-20250202-base.iso' ;;
		musl-xfce) printf '%s\n' 'void-live-x86_64-musl-20250202-xfce.iso' ;;
		*) return 1 ;;
	esac
}

void_iso_url ()
{
	_void_iso_file="$1"
	printf '%s/%s\n' "$VOID_ISO_BASE" "$_void_iso_file"
}

void_iso_setup ()
{
	_void_iso_tag="$1"

	if ! _void_iso_file=$(void_iso_file "$_void_iso_tag"); then
		nb_error "Unknown Void Linux ISO entry: $_void_iso_tag"
		return 1
	fi

	VOID_ISO_URL=$(void_iso_url "$_void_iso_file")
	printf '%s' "root=live:/LiveOS/squashfs.img init=/sbin/init ro rd.luks=0 rd.md=0 rd.dm=0 rd.live.overlay.overlayfs=1 loglevel=4 vconsole.unicode=1 locale.LANG=en_US.UTF-8 " >>/tmp/nb-options
}

void_repack_initrd_with_iso ()
{
	_void_iso="$1"
	_void_work="/tmp/nb-void-initrd-work"
	_void_repacked="/tmp/nb-initrd.void"

	if ! _void_7z=$(artix_7z_cmd); then
		nb_error "7zip is required to extract Void Linux live files."
		return 1
	fi
	if ! _void_main_info=$(artix_find_main_initrd /tmp/nb-initrd); then
		nb_error "Could not determine the Void Linux initramfs compression format."
		return 1
	fi
	_void_format="${_void_main_info%% *}"
	_void_main_offset="${_void_main_info#* }"

	if [ "$_void_format" = "zstd" ] && ! command -v zstd >/dev/null 2>&1; then
		nb_error "Void Linux initramfs uses zstd compression, but zstd is not available."
		return 1
	fi
	if [ "$_void_format" = "xz" ] && ! command -v xz >/dev/null 2>&1; then
		nb_error "Void Linux initramfs uses xz compression, but xz is not available."
		return 1
	fi

	rm -rf "$_void_work" "$_void_repacked"
	mkdir -p "$_void_work"

	if ! nb_initrd_unpack /tmp/nb-initrd "$_void_work" "$_void_format" "$_void_main_offset" "-idm" "/dev/null"; then
		nb_error "Could not unpack the $VOID_LABEL $_void_format initramfs."
		rm -rf "$_void_work"
		return 1
	fi

	if ! "$_void_7z" x -y -o"$_void_work" "$_void_iso" LiveOS/squashfs.img >/tmp/nb-void-7z.log 2>&1; then
		nb_error "Could not extract LiveOS/squashfs.img from the Void Linux ISO.\nSee /tmp/nb-void-7z.log for details."
		rm -rf "$_void_work"
		return 1
	fi
	if [ ! -s "$_void_work/LiveOS/squashfs.img" ]; then
		nb_error "The Void Linux ISO did not contain LiveOS/squashfs.img."
		rm -rf "$_void_work"
		return 1
	fi
	rm -f "$_void_iso"

	if ! nb_initrd_repack "$_void_work" "$_void_repacked" "$_void_format" "artix"; then
		nb_error "Could not repack the $VOID_LABEL $_void_format initramfs."
		rm -rf "$_void_work"
		return 1
	fi

	: >/tmp/nb-initrd.new
	if [ "$_void_main_offset" -gt 0 ]; then
		if ! head -c "$_void_main_offset" /tmp/nb-initrd >>/tmp/nb-initrd.new; then
			nb_error "Could not preserve the Void Linux early initramfs prefix."
			rm -rf "$_void_work" "$_void_repacked" /tmp/nb-initrd.new
			return 1
		fi
	fi
	if ! cat "$_void_repacked" >>/tmp/nb-initrd.new; then
		nb_error "Could not write the repacked Void Linux initramfs."
		rm -rf "$_void_work" "$_void_repacked" /tmp/nb-initrd.new
		return 1
	fi
	mv /tmp/nb-initrd.new /tmp/nb-initrd
	rm -rf "$_void_work" "$_void_repacked" /tmp/nb-void-7z.log
	return 0
}

void_prepare_from_iso ()
{
	_void_iso_url="$1"
	_void_iso="/tmp/nb-void.iso"
	_void_boot="/tmp/nb-void-boot"

	if ! _void_7z=$(artix_7z_cmd); then
		nb_error "7zip is required to extract Void Linux boot files. Rebuild NetbootCD-Neo with 7zip included."
		return 1
	fi

	rm -f /tmp/nb-linux /tmp/nb-initrd "$_void_iso"
	rm -rf "$_void_boot" /tmp/nb-void-initrd-work /tmp/nb-initrd.void /tmp/nb-initrd.new
	mkdir -p "$_void_boot"

	if ! wgetgauge "$_void_iso_url" "$_void_iso" "Downloading Void Linux ISO"; then
		nb_error "Could not download Void Linux ISO from:\n\n$_void_iso_url"
		rm -f "$_void_iso"
		rm -rf "$_void_boot"
		return 1
	fi

	if ! "$_void_7z" e -y -o"$_void_boot" "$_void_iso" boot/vmlinuz boot/initrd >/tmp/nb-void-7z.log 2>&1; then
		nb_error "Could not extract Void Linux boot files from the ISO.\nSee /tmp/nb-void-7z.log for details."
		rm -f "$_void_iso"
		rm -rf "$_void_boot"
		return 1
	fi
	if [ ! -s "$_void_boot/vmlinuz" ]; then
		nb_error "The Void Linux ISO did not contain boot/vmlinuz."
		rm -f "$_void_iso"
		rm -rf "$_void_boot"
		return 1
	fi
	if [ ! -s "$_void_boot/initrd" ]; then
		nb_error "The Void Linux ISO did not contain boot/initrd."
		rm -f "$_void_iso"
		rm -rf "$_void_boot"
		return 1
	fi

	mv "$_void_boot/vmlinuz" /tmp/nb-linux
	mv "$_void_boot/initrd" /tmp/nb-initrd
	rm -rf "$_void_boot"

	if ! void_repack_initrd_with_iso "$_void_iso"; then
		rm -f "$_void_iso"
		rm -f /tmp/nb-linux /tmp/nb-initrd /tmp/nb-initrd.new /tmp/nb-initrd.void
		rm -rf /tmp/nb-void-initrd-work
		return 1
	fi

	rm -f "$_void_iso" /tmp/nb-void-7z.log
	return 0
}

altlinux_iso_file ()
{
	case "$1" in
		regular-jeos-systemd) printf '%s\n' 'regular-net-install-latest-x86_64.iso' ;;
		*) return 1 ;;
	esac
}

altlinux_iso_url ()
{
	_altlinux_iso_file="$1"
	printf '%s/%s\n' "$ALTLINUX_ISO_BASE" "$_altlinux_iso_file"
}

altlinux_iso_setup ()
{
	_altlinux_iso_tag="$1"

	if ! _altlinux_iso_file=$(altlinux_iso_file "$_altlinux_iso_tag"); then
		nb_error "Unknown ALT Linux ISO entry: $_altlinux_iso_tag"
		return 1
	fi

	ALTLINUX_ISO_URL=$(altlinux_iso_url "$_altlinux_iso_file")
	case "$_altlinux_iso_tag" in
		regular-jeos-systemd)
			_altlinux_stage_iso_file="regular-jeos-systemd-latest-x86_64.iso"
			;;
	esac

	_altlinux_stage_iso_path="/sisyphus/current/$_altlinux_stage_iso_file"
	# With method:http,type:iso, ramdisk_size makes ALT fetch /live instead of the ISO.
	printf '%s' "fastboot live root=bootchain bootchain=fg,altboot ip=dhcp automatic=method:http,type:iso,server:nightly.altlinux.org,directory:$_altlinux_stage_iso_path stagename=live systemd.unit=install2.target lowmem lang=en_US " >>/tmp/nb-options
}

altlinux_prepare_from_iso ()
{
	_altlinux_iso_url="$1"

	iso_prepare_boot_files "$_altlinux_iso_url" /tmp/nb-altlinux.iso /tmp/nb-altlinux-boot boot/vmlinuz boot/initrd.img "ALT Linux"
}

guix_iso_setup ()
{
	_guix_version="$1"

	case "$_guix_version" in
		''|*[!A-Za-z0-9._-]*)
			nb_error "Invalid GNU Guix System version: $_guix_version"
			return 1
			;;
	esac

	GUIX_LABEL="GNU Guix System $_guix_version"
	GUIX_ISO_URL="$GUIX_ISO_BASE/guix-system-install-$_guix_version.x86_64-linux.iso"
}

guix_repack_initrd_with_iso_root ()
{
	_guix_iso="$1"
	_guix_work="/tmp/nb-guix-initrd-work"
	_guix_repacked="/tmp/nb-initrd.guix"

	if ! _guix_7z=$(artix_7z_cmd); then
		nb_error "7zip is required to extract $GUIX_LABEL module files."
		return 1
	fi
	if ! _guix_main_info=$(artix_find_main_initrd /tmp/nb-initrd); then
		nb_error "Could not determine the $GUIX_LABEL initramfs compression format."
		return 1
	fi
	_guix_format="${_guix_main_info%% *}"
	_guix_main_offset="${_guix_main_info#* }"

	if ! nb_initrd_need_tool "$_guix_format" "$GUIX_LABEL"; then
		return 1
	fi

	rm -rf "$_guix_work" "$_guix_repacked"
	mkdir -p "$_guix_work"

	if ! nb_initrd_unpack /tmp/nb-initrd "$_guix_work" "$_guix_format" "$_guix_main_offset" "-idmu" "/dev/null"; then
		nb_error "Could not unpack the $GUIX_LABEL $_guix_format initramfs."
		rm -rf "$_guix_work"
		return 1
	fi

	mkdir -p "$_guix_work/.netbootcd-modules"
	for _guix_module_path in \
		'gnu/store/*-linux-libre-*/lib/modules/*/kernel/fs/isofs/isofs.ko*' \
		'gnu/store/*-linux-libre-*/lib/modules/*/kernel/fs/udf/udf.ko*' \
		'gnu/store/*-linux-libre-*/lib/modules/*/kernel/fs/overlayfs/overlay.ko*' \
		'gnu/store/*-linux-libre-*/lib/modules/*/kernel/drivers/block/loop.ko*' \
		'gnu/store/*-linux-libre-*/lib/modules/*/kernel/block/loop.ko*'
	do
		"$_guix_7z" e -y -o"$_guix_work/.netbootcd-modules" "$_guix_iso" "$_guix_module_path" >>/tmp/nb-guix-7z.log 2>&1 || true
	done

	if ! mv "$_guix_iso" "$_guix_work/.netbootcd-guix.iso"; then
		nb_error "Could not embed the $GUIX_LABEL ISO into the initramfs."
		rm -rf "$_guix_work"
		return 1
	fi

	_guix_linux_boot_scm=$(find "$_guix_work/gnu/store" -path '*/gnu/store/*-module-import/gnu/build/linux-boot.scm' 2>/dev/null | head -1)
	if [ -z "$_guix_linux_boot_scm" ]; then
		_guix_linux_boot_scm=$(find "$_guix_work/gnu/store" -path '*/gnu/build/linux-boot.scm' 2>/dev/null | head -1)
	fi
	if [ -z "$_guix_linux_boot_scm" ] || [ ! -f "$_guix_linux_boot_scm" ]; then
		nb_error "Could not find Guix's linux-boot.scm in the embedded installer root."
		rm -rf "$_guix_work"
		return 1
	fi

	find "$_guix_work/gnu/store" -path '*/gnu/build/linux-boot.go' 2>/dev/null |
	while read -r _guix_linux_boot_go; do
		[ -n "$_guix_linux_boot_go" ] && rm -f "$_guix_linux_boot_go"
	done

	: >"$_guix_work/.netbootcd-guix-root"
	cat >>"$_guix_linux_boot_scm" <<'EOFG'

(use-modules (system foreign)
             (ice-9 binary-ports))

(define %netbootcd-guix-ioctl-int
  ((@@ (guix build syscalls) syscall->procedure)
   int "ioctl" (list int unsigned-long int)))
(define %netbootcd-loop-set-fd #x4c00)

(define %netbootcd-original-mount-root-file-system mount-root-file-system)
(define* (mount-root-file-system root type
                                 #:key volatile-root? (flags 0) options
                                 check? skip-check-if-clean? repair)
  (if (file-exists? "/.netbootcd-guix-root")
      (let ((root-device (netbootcd-guix-root-device)))
        (format #t "NetbootCD-Neo: mounting embedded Guix ISO from ~a.~%"
                root-device)
        (netbootcd-guix-load-module "/.netbootcd-modules/isofs.ko")
        (netbootcd-guix-load-module "/.netbootcd-modules/udf.ko")
        (netbootcd-guix-load-module "/.netbootcd-modules/overlay.ko")
        (mkdir-p "/real-root")
        (mkdir-p "/rw-root")
        (mkdir-p "/root")
        (catch 'system-error
          (lambda ()
            (mount root-device "/real-root" "iso9660" MS_RDONLY ""))
          (lambda args
            (format (current-error-port)
                    "NetbootCD-Neo: iso9660 mount failed, trying udf.~%")
            (mount root-device "/real-root" "udf" MS_RDONLY "")))
        (mount "none" "/rw-root" "tmpfs")
        (mkdir-p "/rw-root/upper")
        (mkdir-p "/rw-root/work")
        (mkdir-p "/rw-root/upper/dev")
        (false-if-exception
         (mount "none" "/rw-root/upper/dev" "devtmpfs"))
        (mount "none" "/root" "overlay" 0
               "lowerdir=/real-root,upperdir=/rw-root/upper,workdir=/rw-root/work"))
      (%netbootcd-original-mount-root-file-system
       root type
       #:volatile-root? volatile-root?
       #:flags flags
       #:options options
       #:check? check?
       #:skip-check-if-clean? skip-check-if-clean?
       #:repair repair)))

(define (netbootcd-guix-load-module module)
  (let loop ((candidates (list module
                               (string-append module ".zst")
                               (string-append module ".xz")
                               (string-append module ".gz"))))
    (match candidates
      (() #f)
      ((candidate rest ...)
       (if (file-exists? candidate)
           (false-if-exception
            (load-linux-module* candidate #:recursive? #f))
           (loop rest))))))

(define (netbootcd-guix-root-device)
  (or (netbootcd-guix-loop-device)
      (netbootcd-guix-ram-device)
      (error "could not attach embedded Guix ISO to a block device")))

(define (netbootcd-guix-loop-device)
  (netbootcd-guix-load-module "/.netbootcd-modules/loop.ko")
  (let ((iso-port (open-file "/.netbootcd-guix.iso" "rb")))
    (let loop ((number 0))
      (if (> number 15)
          (begin
            (close-port iso-port)
            #f)
          (let ((device (string-append "/dev/loop" (number->string number))))
            (unless (file-exists? device)
              (false-if-exception
               (mknod device 'block-special #o660 (device-number 7 number))))
            (if (netbootcd-guix-loop-set-fd device iso-port)
                (begin
                  (close-port iso-port)
                  device)
                (loop (+ number 1))))))))

(define (netbootcd-guix-loop-set-fd device iso-port)
  (catch 'system-error
    (lambda ()
      (let ((loop-port (open-file device "r0")))
        (let-values (((ret err)
                      (%netbootcd-guix-ioctl-int
                       (fileno loop-port)
                       %netbootcd-loop-set-fd
                       (fileno iso-port))))
          (close-port loop-port)
          (if (zero? ret)
              #t
              (begin
                (unless (= err EBUSY)
                  (format (current-error-port)
                          "NetbootCD-Neo: LOOP_SET_FD failed on ~a: ~a~%"
                          device (strerror err)))
                #f)))))
    (lambda args
      (let ((errno (system-error-errno args)))
        (format (current-error-port)
                "NetbootCD-Neo: could not open ~a: ~a~%"
                device (strerror errno)))
      #f)))

(define (netbootcd-guix-ram-device)
  (let ((device "/dev/ram0"))
    (unless (file-exists? device)
      (false-if-exception
       (mknod device 'block-special #o660 (device-number 1 0))))
    (catch 'system-error
      (lambda ()
        (format #t "NetbootCD-Neo: copying embedded Guix ISO to ~a.~%"
                device)
        (netbootcd-guix-copy-file "/.netbootcd-guix.iso" device)
        (false-if-exception
         (delete-file "/.netbootcd-guix.iso"))
        device)
      (lambda args
        (let ((errno (system-error-errno args)))
          (format (current-error-port)
                  "NetbootCD-Neo: could not use ~a: ~a~%"
                  device (strerror errno)))
        #f))))

(define (netbootcd-guix-copy-file source target)
  (let ((in (open-file source "rb"))
        (out (open-file target "r+b0")))
    (let loop ()
      (let ((bytes (get-bytevector-n in 1048576)))
        (if (eof-object? bytes)
            (begin
              (close-port in)
              (close-port out)
              #t)
            (begin
              (put-bytevector out bytes)
              (loop)))))))
EOFG

	if ! nb_initrd_repack "$_guix_work" "$_guix_repacked" "$_guix_format" "standard"; then
		nb_error "Could not repack the $GUIX_LABEL $_guix_format initramfs."
		rm -rf "$_guix_work"
		return 1
	fi

	: >/tmp/nb-initrd.new
	if [ "$_guix_main_offset" -gt 0 ]; then
		if ! head -c "$_guix_main_offset" /tmp/nb-initrd >>/tmp/nb-initrd.new; then
			nb_error "Could not preserve the $GUIX_LABEL early initramfs prefix."
			rm -rf "$_guix_work" "$_guix_repacked" /tmp/nb-initrd.new
			return 1
		fi
	fi
	if ! cat "$_guix_repacked" >>/tmp/nb-initrd.new; then
		nb_error "Could not write the repacked $GUIX_LABEL initramfs."
		rm -rf "$_guix_work" "$_guix_repacked" /tmp/nb-initrd.new
		return 1
	fi
	mv /tmp/nb-initrd.new /tmp/nb-initrd
	rm -rf "$_guix_work" "$_guix_repacked" /tmp/nb-guix-7z.log
	return 0
}

guix_prepare_from_iso ()
{
	_guix_iso_url="$1"
	_guix_iso="/tmp/nb-guix.iso"
	_guix_boot="/tmp/nb-guix-boot"
	_guix_grub_cfg="$_guix_boot/grub.cfg"

	if ! _guix_7z=$(artix_7z_cmd); then
		nb_error "7zip is required to extract $GUIX_LABEL boot files. Rebuild NetbootCD-Neo with 7zip included."
		return 1
	fi

	rm -f /tmp/nb-linux /tmp/nb-initrd "$_guix_iso"
	rm -rf "$_guix_boot" /tmp/nb-guix-initrd-work /tmp/nb-initrd.guix /tmp/nb-initrd.new
	mkdir -p "$_guix_boot"

	if ! wgetgauge "$_guix_iso_url" "$_guix_iso" "Downloading $GUIX_LABEL ISO"; then
		nb_error "Could not download $GUIX_LABEL ISO from:\n\n$_guix_iso_url\n\nThis entry needs enough RAM to hold and repack the installer ISO."
		rm -f "$_guix_iso"
		rm -rf "$_guix_boot"
		return 1
	fi

	if ! "$_guix_7z" e -y -o"$_guix_boot" "$_guix_iso" boot/grub/grub.cfg >/tmp/nb-guix-7z.log 2>&1; then
		nb_error "Could not extract the $GUIX_LABEL GRUB configuration from the ISO.\nSee /tmp/nb-guix-7z.log for details."
		rm -f "$_guix_iso"
		rm -rf "$_guix_boot"
		return 1
	fi
	if [ ! -s "$_guix_grub_cfg" ]; then
		nb_error "The $GUIX_LABEL ISO did not contain boot/grub/grub.cfg."
		rm -f "$_guix_iso"
		rm -rf "$_guix_boot"
		return 1
	fi

	_guix_linux_line=$(sed -n 's/^[	 ]*linux[	 ][	 ]*//p;s/^[	 ]*linuxefi[	 ][	 ]*//p' "$_guix_grub_cfg" | head -1)
	_guix_initrd_line=$(sed -n 's/^[	 ]*initrd[	 ][	 ]*//p;s/^[	 ]*initrdefi[	 ][	 ]*//p' "$_guix_grub_cfg" | head -1)
	if [ -z "$_guix_linux_line" ] || [ -z "$_guix_initrd_line" ]; then
		nb_error "Could not parse the $GUIX_LABEL kernel and initrd paths from GRUB."
		rm -f "$_guix_iso"
		rm -rf "$_guix_boot"
		return 1
	fi

	_guix_kernel_path=$(printf '%s\n' "$_guix_linux_line" | awk '{ print $1 }')
	_guix_kernel_path="${_guix_kernel_path#/}"
	_guix_cmdline=$(printf '%s\n' "$_guix_linux_line" | awk '
		{
			sep = ""
			for (i = 2; i <= NF; i++) {
				if ($i ~ /^(root|rootfstype|rootflags|fsck[.]mode)=/) {
					continue
				}
				printf "%s%s", sep, $i
				sep = " "
			}
		}
	')

	_guix_initrd_path=$(printf '%s\n' "$_guix_initrd_line" | awk '{ print $1 }')
	_guix_initrd_path="${_guix_initrd_path#/}"
	if [ -z "$_guix_kernel_path" ] || [ -z "$_guix_initrd_path" ]; then
		nb_error "Could not parse the $GUIX_LABEL kernel and initrd filenames from GRUB."
		rm -f "$_guix_iso"
		rm -rf "$_guix_boot"
		return 1
	fi

	if ! "$_guix_7z" e -y -o"$_guix_boot" "$_guix_iso" "$_guix_kernel_path" "$_guix_initrd_path" >/tmp/nb-guix-7z.log 2>&1; then
		nb_error "Could not extract $GUIX_LABEL boot files from the ISO.\nSee /tmp/nb-guix-7z.log for details."
		rm -f "$_guix_iso"
		rm -rf "$_guix_boot"
		return 1
	fi

	_guix_kernel_file="${_guix_kernel_path##*/}"
	_guix_initrd_file="${_guix_initrd_path##*/}"
	if [ ! -s "$_guix_boot/$_guix_kernel_file" ]; then
		nb_error "The $GUIX_LABEL ISO did not contain $_guix_kernel_path."
		rm -f "$_guix_iso"
		rm -rf "$_guix_boot"
		return 1
	fi
	if [ ! -s "$_guix_boot/$_guix_initrd_file" ]; then
		nb_error "The $GUIX_LABEL ISO did not contain $_guix_initrd_path."
		rm -f "$_guix_iso"
		rm -rf "$_guix_boot"
		return 1
	fi

	mv "$_guix_boot/$_guix_kernel_file" /tmp/nb-linux
	mv "$_guix_boot/$_guix_initrd_file" /tmp/nb-initrd
	rm -rf "$_guix_boot"
	_guix_iso_bytes=$(wc -c <"$_guix_iso" | tr -d '[:space:]')
	case "$_guix_iso_bytes" in
		''|*[!0-9]*)
			_guix_ramdisk_kb=1600000
			;;
		*)
			_guix_ramdisk_kb=$(( ( _guix_iso_bytes + 1048575 ) / 1024 + 131072 ))
			;;
	esac

	dialog --backtitle "$TITLE" --infobox \
		"Embedding the $GUIX_LABEL installer filesystem into the initrd.\n\nThis can take a while and needs plenty of RAM." 7 70 || true
	if ! guix_repack_initrd_with_iso_root "$_guix_iso"; then
		rm -f "$_guix_iso"
		rm -f /tmp/nb-linux /tmp/nb-initrd /tmp/nb-initrd.new /tmp/nb-initrd.guix
		rm -rf /tmp/nb-guix-initrd-work
		return 1
	fi

	printf '%s' "root=/dev/null rootfstype=tmpfs fsck.mode=skip ramdisk_size=$_guix_ramdisk_kb $_guix_cmdline netbootcd_guix=1 " >>/tmp/nb-options
	rm -f "$_guix_iso" /tmp/nb-guix-7z.log
	return 0
}

artix_dns_option ()
{
	_artix_dns_list=

	if [ -r /etc/resolv.conf ]; then
		while read -r _artix_resolv_key _artix_resolv_value _artix_resolv_rest; do
			[ "$_artix_resolv_key" = "nameserver" ] || continue
			[ -n "$_artix_resolv_value" ] || continue
			case "$_artix_resolv_value" in
				*,*|*[!A-Za-z0-9:.]*)
					continue
					;;
			esac
			case ",$_artix_dns_list," in
				*,"$_artix_resolv_value",*) ;;
				,,)
					_artix_dns_list="$_artix_resolv_value"
					;;
				*)
					_artix_dns_list="$_artix_dns_list,$_artix_resolv_value"
					;;
			esac
		done </etc/resolv.conf
	fi

	[ -n "$_artix_dns_list" ] && printf ' netbootcd_dns=%s' "$_artix_dns_list"
}

artix_iso_setup ()
{
	_artix_iso_tag="$1"

	if ! _artix_iso_file=$(artix_iso_file "$_artix_iso_tag"); then
		nb_error "Unknown Artix ISO entry: $_artix_iso_tag"
		return 1
	fi

	ARTIX_ISO_URL=$(artix_iso_url "$_artix_iso_file")
	printf '%s' "ip=dhcp artix_iso_url=$ARTIX_ISO_URL$(artix_dns_option) " >>/tmp/nb-options
}

artix_add_network_modules_overlay ()
{
	_artix_iso="$1"
	_overlay_dir="$2"
	_rootfs_dir="/tmp/nb-artix-rootfs-extract"
	_rootfs_img="$_rootfs_dir/rootfs.img"

	[ -f "$_artix_iso" ] || return 0
	if ! _artix_7z=$(artix_7z_cmd); then
		nb_error "7zip is required to extract Artix network modules."
		return 1
	fi

	rm -rf "$_rootfs_dir"
	mkdir -p "$_rootfs_dir"

	if ! "$_artix_7z" e -y -o"$_rootfs_dir" "$_artix_iso" LiveOS/rootfs.img >/tmp/nb-artix-network.log 2>&1; then
		nb_error "Could not extract LiveOS/rootfs.img for Artix network module support.\nSee /tmp/nb-artix-network.log for details."
		rm -rf "$_rootfs_dir"
		return 1
	fi

	if ! "$_artix_7z" x -y -o"$_overlay_dir" "$_rootfs_img" \
		'usr/lib/modules/*/modules.*' \
		'usr/lib/modules/*/kernel/drivers/net/virtio_net.ko.zst' \
		'usr/lib/modules/*/kernel/drivers/net/net_failover.ko.zst' \
		'usr/lib/modules/*/kernel/drivers/net/mii.ko.zst' \
		'usr/lib/modules/*/kernel/drivers/net/mdio.ko.zst' \
		'usr/lib/modules/*/kernel/drivers/net/phy/libphy.ko.zst' \
		'usr/lib/modules/*/kernel/drivers/net/phy/mdio_devres.ko.zst' \
		'usr/lib/modules/*/kernel/drivers/net/phy/phylink.ko.zst' \
		'usr/lib/modules/*/kernel/drivers/net/phy/realtek.ko.zst' \
		'usr/lib/modules/*/kernel/drivers/net/ethernet/amd/pcnet32.ko.zst' \
		'usr/lib/modules/*/kernel/drivers/net/ethernet/intel/e1000/e1000.ko.zst' \
		'usr/lib/modules/*/kernel/drivers/net/ethernet/intel/e1000e/e1000e.ko.zst' \
		'usr/lib/modules/*/kernel/drivers/net/ethernet/intel/igb/igb.ko.zst' \
		'usr/lib/modules/*/kernel/drivers/net/ethernet/intel/ixgbe/ixgbe.ko.zst' \
		'usr/lib/modules/*/kernel/drivers/net/ethernet/realtek/8139cp.ko.zst' \
		'usr/lib/modules/*/kernel/drivers/net/ethernet/realtek/8139too.ko.zst' \
		'usr/lib/modules/*/kernel/drivers/net/ethernet/realtek/r8169.ko.zst' \
		'usr/lib/modules/*/kernel/drivers/net/vmxnet3/vmxnet3.ko.zst' \
		'usr/lib/modules/*/kernel/drivers/virtio/*.ko.zst' >>/tmp/nb-artix-network.log 2>&1; then
		nb_error "Could not extract Artix network modules from rootfs.img.\nSee /tmp/nb-artix-network.log for details."
		rm -rf "$_rootfs_dir"
		return 1
	fi

	rm -rf "$_rootfs_dir"
}

make_artix_iso_overlay ()
{
	_artix_iso_url="$1"
	_artix_iso="$2"
	_overlay_dir="/tmp/nb-artix-overlay"

	if ! command -v cpio >/dev/null 2>&1; then
		nb_error "cpio is required to build the Artix ISO overlay."
		return 1
	fi

	rm -rf "$_overlay_dir" /tmp/nb-artix-overlay.cpio
	mkdir -p "$_overlay_dir/hooks"
	printf '%s\n' "$_artix_iso_url" >"$_overlay_dir/.nb-artix-iso-url"

cat >"$_overlay_dir/hooks/netbootcd_artix_iso" <<'EOFH'
run_hook() {
    msg ":: NetbootCD Artix ISO hook starting..."
    _nb_artix_iso_url="${artix_iso_url:-}"
    [ -r /.nb-artix-iso-url ] && _nb_artix_iso_url="$(cat /.nb-artix-iso-url)"
    [ -z "${root:-}" ] && root="LiveOS"

    if [ -n "${_nb_artix_iso_url:-}" ]; then
        msg ":: Setting up NetbootCD Artix ISO download"
        artix_iso_url="$_nb_artix_iso_url"
        [ -z "${artix_http_spc:-}" ] && artix_http_spc="85%"
        mount_handler="netbootcd_artix_iso_mount_handler"
    else
        msg ":: NetbootCD Artix ISO hook skipped: no ISO URL"
    fi
}

_nb_fetch_url() {
    _url="$1"
    _out="$2"

    mkdir -p "${_out%/*}"
    msg ":: Downloading '${_url}'"

    if _nb_try_fetch_url "$_url" "$_out"; then
        return
    fi

    msg ":: Download failed, retrying after network/DNS refresh"
    netbootcd_artix_iso_network
    if _nb_try_fetch_url "$_url" "$_out"; then
        return
    fi

    echo "ERROR: Downloading '${_url}'"
    echo "   Falling back to interactive prompt"
    launch_interactive_shell
}

_nb_try_fetch_url() {
    _url="$1"
    _out="$2"

    if command -v curl >/dev/null 2>&1; then
        curl -k -L -f -o "$_out" "$_url" && return
    fi
    if command -v wget >/dev/null 2>&1; then
        wget --no-check-certificate -O "$_out" "$_url" && return
    fi

    return 1
}

_nb_busybox() {
    if command -v busybox >/dev/null 2>&1; then
        busybox "$@"
        return $?
    fi
    if [ -x /usr/bin/busybox ]; then
        /usr/bin/busybox "$@"
        return $?
    fi
    if [ -x /bin/busybox ]; then
        /bin/busybox "$@"
        return $?
    fi
    return 127
}

_nb_ifconfig() {
    if command -v ifconfig >/dev/null 2>&1; then
        ifconfig "$@"
        return $?
    fi
    _nb_busybox ifconfig "$@"
}

_nb_route() {
    if command -v route >/dev/null 2>&1; then
        route "$@"
        return $?
    fi
    _nb_busybox route "$@"
}

netbootcd_artix_iso_udhcpc_script() {
    cat >/tmp/netbootcd-udhcpc.script <<'EOFS'
#!/bin/sh
case "$1" in
    bound|renew)
        if command -v ifconfig >/dev/null 2>&1; then
            ifconfig "$interface" "$ip" netmask "$subnet" ${broadcast:+broadcast "$broadcast"} up
        elif [ -x /usr/bin/busybox ]; then
            /usr/bin/busybox ifconfig "$interface" "$ip" netmask "$subnet" ${broadcast:+broadcast "$broadcast"} up
        elif [ -x /bin/busybox ]; then
            /bin/busybox ifconfig "$interface" "$ip" netmask "$subnet" ${broadcast:+broadcast "$broadcast"} up
        fi

        if command -v route >/dev/null 2>&1; then
            route del default 2>/dev/null || true
            for r in $router; do route add default gw "$r" dev "$interface" 2>/dev/null || true; break; done
        elif [ -x /usr/bin/busybox ]; then
            /usr/bin/busybox route del default 2>/dev/null || true
            for r in $router; do /usr/bin/busybox route add default gw "$r" dev "$interface" 2>/dev/null || true; break; done
        elif [ -x /bin/busybox ]; then
            /bin/busybox route del default 2>/dev/null || true
            for r in $router; do /bin/busybox route add default gw "$r" dev "$interface" 2>/dev/null || true; break; done
        fi

        : >/etc/resolv.conf
        set -- $dns
        [ -n "$1" ] && printf 'nameserver %s\n' "$1" >>/etc/resolv.conf
        [ -n "$2" ] && printf 'nameserver %s\n' "$2" >>/etc/resolv.conf
        [ -n "$domain" ] && printf 'search %s\n' "$domain" >>/etc/resolv.conf

        {
            printf 'DEVICE=%s\n' "$interface"
            printf 'IPV4ADDR=%s\n' "$ip"
            printf 'IPV4BROADCAST=%s\n' "$broadcast"
            printf 'IPV4NETMASK=%s\n' "$subnet"
            set -- $router
            printf 'IPV4GATEWAY=%s\n' "$1"
            set -- $dns
            printf 'IPV4DNS0=%s\n' "$1"
            printf 'IPV4DNS1=%s\n' "$2"
            printf 'DNSDOMAIN=%s\n' "$domain"
        } >"/tmp/net-${interface}.conf"
        ;;
esac
EOFS
    chmod 0755 /tmp/netbootcd-udhcpc.script
}

netbootcd_artix_iso_resolv_conf() {
    _nb_dns_written=0

    if [ -n "${netbootcd_dns:-}" ]; then
        : >/etc/resolv.conf
        _nb_dns_list="$netbootcd_dns"
        while [ -n "$_nb_dns_list" ]; do
            case "$_nb_dns_list" in
                *,*)
                    _nb_dns="${_nb_dns_list%%,*}"
                    _nb_dns_list="${_nb_dns_list#*,}"
                    ;;
                *)
                    _nb_dns="$_nb_dns_list"
                    _nb_dns_list=
                    ;;
            esac
            [ -n "$_nb_dns" ] || continue
            printf 'nameserver %s\n' "$_nb_dns" >>/etc/resolv.conf
            _nb_dns_written=1
        done
    fi

    if [ "$_nb_dns_written" -eq 0 ]; then
        for _nb_netconf in /tmp/net-*.conf; do
            [ -f "$_nb_netconf" ] || continue
            IPV4DNS0=
            IPV4DNS1=
            DNSDOMAIN=
            . "$_nb_netconf"
            : >/etc/resolv.conf
            if [ -n "${IPV4DNS0:-}" ] && [ "$IPV4DNS0" != "0.0.0.0" ]; then
                printf 'nameserver %s\n' "$IPV4DNS0" >>/etc/resolv.conf
                _nb_dns_written=1
            fi
            if [ -n "${IPV4DNS1:-}" ] && [ "$IPV4DNS1" != "0.0.0.0" ]; then
                printf 'nameserver %s\n' "$IPV4DNS1" >>/etc/resolv.conf
                _nb_dns_written=1
            fi
            if [ -n "${DNSDOMAIN:-}" ]; then
                printf 'search %s\n' "$DNSDOMAIN" >>/etc/resolv.conf
                printf 'domain %s\n' "$DNSDOMAIN" >>/etc/resolv.conf
            fi
            break
        done
    fi

    if ! grep -q '^nameserver ' /etc/resolv.conf 2>/dev/null; then
        {
            echo "# added by NetbootCD Artix hook"
            echo "nameserver 1.1.1.1"
            echo "nameserver 8.8.8.8"
        } >/etc/resolv.conf
    fi
}

netbootcd_artix_iso_load_net_modules() {
    for _nb_module in virtio_net e1000 e1000e pcnet32 vmxnet3 8139cp 8139too r8169 igb ixgbe; do
        modprobe "$_nb_module" 2>/dev/null || true
    done
    if command -v udevadm >/dev/null 2>&1; then
        udevadm trigger --subsystem-match=net --action=add 2>/dev/null || true
        udevadm settle --timeout=5 2>/dev/null || true
    fi
    sleep 2
}

netbootcd_artix_iso_dhcp() {
    [ -n "${ip:-}" ] || return 1

    netbootcd_artix_iso_load_net_modules

    rm -f /tmp/net-*.conf
    if command -v ipconfig >/dev/null 2>&1; then
        msg ":: Configuring network for Artix ISO download (${ip})"
        if ipconfig -t 30 "ip=${ip}"; then
            return 0
        fi
    fi

    netbootcd_artix_iso_udhcpc_script
    for _nb_iface_path in /sys/class/net/*; do
        [ -e "$_nb_iface_path" ] || continue
        _nb_iface="${_nb_iface_path##*/}"
        [ "$_nb_iface" = "lo" ] && continue
        msg ":: Trying DHCP on ${_nb_iface}"
        rm -f /tmp/net-*.conf
        if command -v ipconfig >/dev/null 2>&1; then
            if ipconfig -t 30 "ip=:::::${_nb_iface}:dhcp"; then
                return 0
            fi
        fi
        _nb_ifconfig "$_nb_iface" up 2>/dev/null || true
        if _nb_busybox udhcpc -i "$_nb_iface" -n -q -t 5 -T 5 -s /tmp/netbootcd-udhcpc.script; then
            return 0
        fi
    done

    return 1
}

netbootcd_artix_iso_network() {
    if ! netbootcd_artix_iso_dhcp; then
        msg ":: NetbootCD Artix hook could not configure DHCP automatically"
    fi
    netbootcd_artix_iso_resolv_conf
}

netbootcd_artix_iso_mount_handler () {
    newroot="$1"

    msg ":: Mounting ${live_root}/httpspace (tmpfs) filesystem, size='${artix_http_spc}'"
    mkdir -p "${live_root}/httpspace"
    mount -t tmpfs -o size="${artix_http_spc}",mode=0755 httpspace "${live_root}/httpspace"

    _nb_iso_path="${live_root}/httpspace/artix.iso"
    netbootcd_artix_iso_network
    _nb_fetch_url "$artix_iso_url" "$_nb_iso_path"

    modprobe loop 2>/dev/null || true
    modprobe isofs 2>/dev/null || true
    modprobe udf 2>/dev/null || true
    if _nb_iso_dev=$(losetup --find --show --read-only "$_nb_iso_path"); then
        artixdevice="$_nb_iso_dev"
    else
        echo "ERROR: Could not create a loop device for '${_nb_iso_path}'"
        echo "   Falling back to interactive prompt"
        launch_interactive_shell
    fi

    artix_mount_handler "$newroot"
}
EOFH
	chmod 0755 "$_overlay_dir/hooks/netbootcd_artix_iso"

	if ! artix_add_network_modules_overlay "$_artix_iso" "$_overlay_dir"; then
		rm -rf "$_overlay_dir" /tmp/nb-artix-overlay.cpio
		return 1
	fi

	if ! ( cd "$_overlay_dir" && find . | cpio -o -H newc >/tmp/nb-artix-overlay.cpio ); then
		nb_error "Could not build the Artix ISO overlay."
		rm -rf "$_overlay_dir" /tmp/nb-artix-overlay.cpio
		return 1
	fi

	rm -rf "$_overlay_dir"
}

artix_file_size ()
{
	wc -c <"$1" | tr -d '[:space:]'
}

artix_initrd_format_at ()
{
	_artix_initrd="$1"
	_artix_offset="${2:-0}"
	_artix_sig=$(dd if="$_artix_initrd" bs=1 skip="$_artix_offset" count=6 2>/dev/null | od -An -tx1 | sed 's/[[:space:]]//g')

	case "$_artix_sig" in
		1f8b*) printf '%s\n' gzip ;;
		28b52ffd*) printf '%s\n' zstd ;;
		fd377a585a00*) printf '%s\n' xz ;;
		303730373031*) printf '%s\n' cpio ;;
		*) return 1 ;;
	esac
}

artix_initrd_format ()
{
	artix_initrd_format_at "$1" 0
}

artix_cpio_blocks_offset ()
{
	_artix_initrd="$1"
	_artix_cpio_offset="${2:-0}"
	_artix_blocks_file="/tmp/nb-artix-cpio-blocks"

	rm -f "$_artix_blocks_file"
	if [ "$_artix_cpio_offset" -gt 0 ]; then
		if ! ( tail -c +"$(( _artix_cpio_offset + 1 ))" "$_artix_initrd" | cpio -t >/dev/null 2>"$_artix_blocks_file" ); then
			rm -f "$_artix_blocks_file"
			return 1
		fi
	elif ! ( cpio -t <"$_artix_initrd" >/dev/null 2>"$_artix_blocks_file" ); then
		rm -f "$_artix_blocks_file"
		return 1
	fi
	_artix_blocks=$(sed -n 's/^\([0-9][0-9]*\)[[:space:]]*blocks.*/\1/p' "$_artix_blocks_file" | tail -1)
	rm -f "$_artix_blocks_file"
	case "$_artix_blocks" in
		''|*[!0-9]*) return 1 ;;
	esac
	printf '%s\n' "$(( _artix_cpio_offset + _artix_blocks * 512 ))"
}

artix_find_main_initrd ()
{
	_artix_initrd="$1"

	if ! _artix_format=$(artix_initrd_format "$_artix_initrd"); then
		return 1
	fi
	if [ "$_artix_format" != "cpio" ]; then
		printf '%s %s\n' "$_artix_format" 0
		return 0
	fi

	_artix_size=$(artix_file_size "$_artix_initrd")
	_artix_cpio_offset=0

	while :; do
		if ! _artix_scan=$(artix_cpio_blocks_offset "$_artix_initrd" "$_artix_cpio_offset"); then
			printf '%s %s\n' cpio 0
			return 0
		fi
		_artix_limit=$(( _artix_scan + 1048576 ))
		[ "$_artix_limit" -gt "$_artix_size" ] && _artix_limit="$_artix_size"

		while [ "$_artix_scan" -lt "$_artix_limit" ]; do
			_artix_byte=$(dd if="$_artix_initrd" bs=1 skip="$_artix_scan" count=1 2>/dev/null | od -An -tx1 | sed 's/[[:space:]]//g')
			[ -z "$_artix_byte" ] && break
			if [ "$_artix_byte" = "00" ]; then
				_artix_scan=$(( _artix_scan + 1 ))
				continue
			fi
			if _artix_tail_format=$(artix_initrd_format_at "$_artix_initrd" "$_artix_scan"); then
				if [ "$_artix_tail_format" = "cpio" ]; then
					_artix_cpio_offset="$_artix_scan"
					break
				fi
				printf '%s %s\n' "$_artix_tail_format" "$_artix_scan"
				return 0
			fi
			printf '%s %s\n' cpio 0
			return 0
		done

		if [ "$_artix_cpio_offset" != "$_artix_scan" ]; then
			break
		fi
	done

	printf '%s %s\n' cpio 0
}

artix_repack_initrd_fragments ()
{
	_artix_count="$1"
	_artix_last="/tmp/nb-initrd.$_artix_count"
	_artix_work="/tmp/nb-artix-initrd-work"
	_artix_repacked="/tmp/nb-initrd.repacked"

	if ! _artix_main_info=$(artix_find_main_initrd "$_artix_last"); then
		nb_error "Could not determine the Artix initramfs compression format."
		return 1
	fi
	_artix_format="${_artix_main_info%% *}"
	_artix_main_offset="${_artix_main_info#* }"

	if [ "$_artix_format" = "zstd" ] && ! command -v zstd >/dev/null 2>&1; then
		nb_error "Artix initramfs uses zstd compression, but zstd is not available."
		return 1
	fi
	if [ "$_artix_format" = "xz" ] && ! command -v xz >/dev/null 2>&1; then
		nb_error "Artix initramfs uses xz compression, but xz is not available."
		return 1
	fi

	rm -rf "$_artix_work" "$_artix_repacked" /tmp/nb-initrd
	mkdir -p "$_artix_work"

	if ! nb_initrd_unpack "$_artix_last" "$_artix_work" "$_artix_format" "$_artix_main_offset" "-idm" "/dev/null"; then
		nb_error "Could not unpack the $ARTIX_LABEL $_artix_format initramfs."
		rm -rf "$_artix_work"
		return 1
	fi

	if ! ( cd "$_artix_work" && cpio -idmu </tmp/nb-artix-overlay.cpio ); then
		nb_error "Could not merge the Artix ISO overlay into the initramfs."
		rm -rf "$_artix_work"
		return 1
	fi
	if [ -f "$_artix_work/config" ] && ! grep -q 'netbootcd_artix_iso' "$_artix_work/config"; then
		if grep -q '^HOOKS="' "$_artix_work/config"; then
			if ! sed 's/^HOOKS="\([^"]*\)"/HOOKS="\1 netbootcd_artix_iso"/' "$_artix_work/config" >"$_artix_work/config.new"; then
				nb_error "Could not update the Artix initramfs hook list."
				rm -rf "$_artix_work" "$_artix_repacked" "$_artix_work/config.new"
				return 1
			fi
			mv "$_artix_work/config.new" "$_artix_work/config"
		else
			printf '\nHOOKS="${HOOKS} netbootcd_artix_iso"\n' >>"$_artix_work/config"
		fi
	fi

	if ! nb_initrd_repack "$_artix_work" "$_artix_repacked" "$_artix_format" "artix"; then
		nb_error "Could not repack the $ARTIX_LABEL $_artix_format initramfs."
		rm -rf "$_artix_work"
		return 1
	fi

	: >/tmp/nb-initrd
	_artix_i=1
	while [ "$_artix_i" -lt "$_artix_count" ]; do
		cat "/tmp/nb-initrd.$_artix_i" >>/tmp/nb-initrd
		_artix_i=$(( _artix_i + 1 ))
	done
	if [ "$_artix_main_offset" -gt 0 ]; then
		if ! head -c "$_artix_main_offset" "$_artix_last" >>/tmp/nb-initrd; then
			nb_error "Could not preserve the Artix early initramfs prefix."
			rm -rf "$_artix_work" "$_artix_repacked" /tmp/nb-artix-overlay.cpio /tmp/nb-initrd.*
			return 1
		fi
	fi
	if ! cat "$_artix_repacked" >>/tmp/nb-initrd; then
		nb_error "Could not append the repacked Artix initramfs."
		rm -rf "$_artix_work" "$_artix_repacked" /tmp/nb-artix-overlay.cpio /tmp/nb-initrd.*
		return 1
	fi
	rm -rf "$_artix_work" "$_artix_repacked" /tmp/nb-artix-overlay.cpio /tmp/nb-initrd.*
}

combine_initrd_fragments ()
{
	_initrd_count="$1"

	: >/tmp/nb-initrd
	_initrd_i=1
	while [ "$_initrd_i" -le "$_initrd_count" ]; do
		cat "/tmp/nb-initrd.$_initrd_i" >>/tmp/nb-initrd
		rm -f "/tmp/nb-initrd.$_initrd_i"
		_initrd_i=$(( _initrd_i + 1 ))
	done
}

artix_prepare_from_iso ()
{
	_artix_iso_url="$1"
	_artix_iso="/tmp/nb-artix.iso"
	_artix_boot="/tmp/nb-artix-boot"

	if ! _artix_7z=$(artix_7z_cmd); then
		nb_error "7zip is required to extract Artix ISO boot files. Rebuild NetbootCD-Neo with 7zip included."
		return 1
	fi

	rm -f /tmp/nb-linux /tmp/nb-initrd /tmp/nb-initrd.* "$_artix_iso" /tmp/nb-artix-overlay.cpio
	rm -rf "$_artix_boot"
	mkdir -p "$_artix_boot"

	if ! wgetgauge "$_artix_iso_url" "$_artix_iso" "Downloading Artix ISO"; then
		nb_error "Could not download Artix ISO from:\n\n$_artix_iso_url"
		rm -f "$_artix_iso"
		rm -rf "$_artix_boot"
		return 1
	fi

	if ! "$_artix_7z" e -y -o"$_artix_boot" "$_artix_iso" \
		boot/vmlinuz-x86_64 \
		boot/intel-ucode.img \
		boot/amd-ucode.img \
		boot/initramfs-x86_64.img >/tmp/nb-artix-7z.log 2>&1; then
		nb_error "Could not extract Artix boot files from the ISO.\nSee /tmp/nb-artix-7z.log for details."
		rm -f "$_artix_iso"
		rm -rf "$_artix_boot"
		return 1
	fi

	for _artix_file in vmlinuz-x86_64 intel-ucode.img amd-ucode.img initramfs-x86_64.img; do
		if [ ! -s "$_artix_boot/$_artix_file" ]; then
			nb_error "The Artix ISO did not contain boot/$_artix_file."
			rm -f "$_artix_iso"
			rm -rf "$_artix_boot"
			return 1
		fi
	done

	mv "$_artix_boot/vmlinuz-x86_64" /tmp/nb-linux
	mv "$_artix_boot/intel-ucode.img" /tmp/nb-initrd.1
	mv "$_artix_boot/amd-ucode.img" /tmp/nb-initrd.2
	mv "$_artix_boot/initramfs-x86_64.img" /tmp/nb-initrd.3
	rm -rf "$_artix_boot"

	if ! make_artix_iso_overlay "$_artix_iso_url" "$_artix_iso"; then
		rm -f "$_artix_iso"
		rm -f /tmp/nb-linux /tmp/nb-initrd /tmp/nb-initrd.* /tmp/nb-artix-overlay.cpio
		return 1
	fi
	rm -f "$_artix_iso"
	if ! artix_repack_initrd_fragments 3; then
		rm -f /tmp/nb-linux /tmp/nb-initrd /tmp/nb-initrd.* /tmp/nb-artix-overlay.cpio
		return 1
	fi

	rm -f /tmp/nb-artix-7z.log
	return 0
}


# Download URL ($1) to OUT ($2) with a dialog gauge when Content-Length exists.
wgetgauge ()
{
	_url="$1"
	_out="$2"
	_label="$3"

	_size=$($WGET --spider -S -T 10 "$_url" 2>&1 \
		| grep -i 'content-length:' | tail -1 | tr -d '\r' | awk '{print $2}')
	[ -z "$_size" ] && _size=0
	case "$_size" in *[!0-9]*) _size=0 ;; esac

	if [ "$_size" -le 0 ]; then
		$WGET "$_url" -O "$_out"
		return $?
	fi

	_out_dir="${_out%/*}"
	[ "$_out_dir" = "$_out" ] && _out_dir=.
	_avail_k=$(df -k "$_out_dir" 2>/dev/null | awk 'NR==2 {print $4}')
	case "$_avail_k" in ''|*[!0-9]*) _avail_k=0 ;; esac
	_need_k=$(( ( _size + 1023 ) / 1024 ))
	if [ "$_avail_k" -gt 0 ] && [ "$_need_k" -gt "$_avail_k" ]; then
		nb_error "Not enough temporary space to download:\n\n$_url\n\nRequired: ${_need_k} KB\nAvailable: ${_avail_k} KB\n\nTry again with more VM RAM, or choose a smaller ISO entry."
		return 1
	fi

	rm -f "$_out" /tmp/nb-wget-rc
	: > "$_out"
	(
		set +e
		_attempt=1
		_rc=1
		while [ "$_attempt" -le 3 ]; do
			if [ "$_attempt" -eq 1 ]; then
				$WGET -q "$_url" -O "$_out"
			else
				$WGET -q -c "$_url" -O "$_out"
			fi
			_rc=$?
			[ "$_rc" -eq 0 ] && break
			_attempt=$(( _attempt + 1 ))
			sleep 2
		done
		echo "$_rc" >/tmp/nb-wget-rc
	) &
	_wpid=$!

	(
		set +e
		while [ ! -f /tmp/nb-wget-rc ]; do
			_now=$(wc -c < "$_out" 2>/dev/null || echo 0)
			_pct=$(( _now * 100 / _size ))
			[ "$_pct" -gt 100 ] && _pct=100
			printf '%d\n' "$_pct"
			sleep 1
		done
		printf '100\n'
	) | dialog --backtitle "$TITLE" --gauge "$_label" 8 70 0

	wait "$_wpid" 2>/dev/null || true
	_rc=$(cat /tmp/nb-wget-rc 2>/dev/null || echo 1)
	rm -f /tmp/nb-wget-rc
	return "$_rc"
}


askforopts ()
{
	if dialog --backtitle "$TITLE" --defaultno --yesno "Would you like to pass extra kernel parameters to the new kernel?" 6 60; then
		printf 'Extra kernel parameters: '
		read -r NB_CUSTOM
		printf '%s' "$NB_CUSTOM" >/tmp/nb-custom
	fi
}


wifimenu ()
{
	if ! command -v wpa_supplicant >/dev/null 2>&1; then
		dialog --backtitle "$TITLE" --msgbox \
			"WiFi tools not found.\nPlease use the WiFi-enabled ISO (NetbootCD-Neo-*-wifi.iso)." 8 57 || true
		return
	fi

	WIFI_IFACE=""
	for _d in /sys/class/net/*/wireless; do
		[ -d "$_d" ] && WIFI_IFACE=$(basename "$(dirname "$_d")") && break
	done
	if [ -z "$WIFI_IFACE" ] && command -v iw >/dev/null 2>&1; then
		WIFI_IFACE=$(iw dev 2>/dev/null | awk '/Interface/{print $2}' | head -1)
	fi

	if [ -z "$WIFI_IFACE" ]; then
		dialog --backtitle "$TITLE" --msgbox \
			"No wireless interface found.\nCheck that your hardware is supported and firmware is loaded." 8 57 || true
		return
	fi

	ifconfig "$WIFI_IFACE" up 2>/dev/null || true

	SSID_COUNT=0
	if command -v iw >/dev/null 2>&1; then
		dialog --backtitle "$TITLE" --infobox \
			"Scanning for wireless networks on $WIFI_IFACE...\nThis may take a few seconds." 5 57 || true
		sleep 2
		iw dev "$WIFI_IFACE" scan 2>/dev/null > /tmp/nb-wifiscan || true
		if [ ! -s /tmp/nb-wifiscan ]; then
			sleep 3
			iw dev "$WIFI_IFACE" scan 2>/dev/null > /tmp/nb-wifiscan || true
		fi
		awk '/^\s+SSID:/{sub(/^\s+SSID: */,""); if(length > 0) print}' /tmp/nb-wifiscan \
			| sort -u > /tmp/nb-ssidlist 2>/dev/null || true
		if [ -s /tmp/nb-ssidlist ]; then
			SSID_COUNT=$(wc -l < /tmp/nb-ssidlist)
		fi
	else
		touch /tmp/nb-ssidlist
	fi

	if [ "$SSID_COUNT" -gt 0 ]; then
		set --
		i=1
		while IFS= read -r ssid; do
			set -- "$@" "$i" "$ssid"
			i=$((i+1))
		done < /tmp/nb-ssidlist
		set -- "$@" "manual" "Enter SSID manually"
		dialog --backtitle "$TITLE" --menu \
			"Select a wireless network:" 20 70 13 \
			"$@" 2>/tmp/nb-wifisel || { rm -f /tmp/nb-wifisel /tmp/nb-ssidlist /tmp/nb-wifiscan; return; }
		WIFI_SEL=$(cat /tmp/nb-wifisel)
		rm -f /tmp/nb-wifisel
		if [ "$WIFI_SEL" = "manual" ]; then
			printf 'SSID: '
			read -r _SSID
			if [ -z "$_SSID" ]; then rm -f /tmp/nb-wifissid /tmp/nb-ssidlist /tmp/nb-wifiscan; return; fi
			printf '%s' "$_SSID" >/tmp/nb-wifissid
		else
			sed -n "${WIFI_SEL}p" /tmp/nb-ssidlist > /tmp/nb-wifissid
		fi
	else
		printf 'No networks found. SSID: '
		read -r _SSID
		if [ -z "$_SSID" ]; then rm -f /tmp/nb-wifissid /tmp/nb-ssidlist /tmp/nb-wifiscan; return; fi
		printf '%s' "$_SSID" >/tmp/nb-wifissid
	fi

	SSID=$(cat /tmp/nb-wifissid)
	rm -f /tmp/nb-wifissid /tmp/nb-ssidlist /tmp/nb-wifiscan

	if [ -z "$SSID" ]; then return; fi

	dialog --backtitle "$TITLE" --inputbox "Password for \"$SSID\":\n(Leave blank for an open network)" 8 60 2>/tmp/nb-wifipass || { rm -f /tmp/nb-wifipass; return; }
	WIFI_PASS=$(cat /tmp/nb-wifipass)
	rm -f /tmp/nb-wifipass

	killall wpa_supplicant 2>/dev/null || true
	sleep 1

	if [ -n "$WIFI_PASS" ]; then
		wpa_passphrase "$SSID" "$WIFI_PASS" > /tmp/nb-wpa.conf 2>/dev/null || true
	else
		printf 'network={\n\tssid="%s"\n\tkey_mgmt=NONE\n}\n' "$SSID" > /tmp/nb-wpa.conf
	fi

	dialog --backtitle "$TITLE" --infobox "Connecting to \"$SSID\"..." 4 45 || true
	wpa_supplicant -B -i "$WIFI_IFACE" -c /tmp/nb-wpa.conf -D nl80211,wext \
		>/tmp/nb-wpa.log 2>&1 || true
	sleep 4

	CONNECTED=0
	if command -v iw >/dev/null 2>&1; then
		iw dev "$WIFI_IFACE" link 2>/dev/null | grep -q "SSID:" && CONNECTED=1 || true
	else
		pidof wpa_supplicant >/dev/null 2>&1 && CONNECTED=1 || true
	fi

	if [ "$CONNECTED" -eq 0 ]; then
		dialog --backtitle "$TITLE" --msgbox \
			"Could not associate with \"$SSID\".\nCheck the password and try again." 8 57 || true
		return
	fi

	dialog --backtitle "$TITLE" --infobox "Requesting IP address via DHCP..." 4 45 || true
	killall udhcpc 2>/dev/null || true
	udhcpc -i "$WIFI_IFACE" -q >/dev/null 2>&1 || true
	sleep 2

	if wget --no-check-certificate --tries=1 -T 10 --spider \
		http://www.example.com >/dev/null 2>&1; then
		echo > /tmp/internet-is-up
		WIFIINFO=$(ifconfig "$WIFI_IFACE" 2>/dev/null | head -4)
		dialog --backtitle "$TITLE" --msgbox \
			"Connected to \"$SSID\" with internet access!\n\n${WIFIINFO}\n\nYou can now install or boot a Linux system." \
			15 62 || true
	else
		dialog --backtitle "$TITLE" --msgbox \
			"Associated with \"$SSID\" but internet is not reachable.\nCheck network settings and try again." \
			9 57 || true
	fi
}



ipadrmenu ()
{
	IFACE_COUNT=0
	set --
	for _iface in /sys/class/net/*; do
		_name=$(basename "$_iface")
		[ "$_name" = "lo" ] && continue
		[ -f "$_iface/tun_flags" ] && continue
		_type=$(cat "$_iface/type" 2>/dev/null)
		[ "$_type" != "1" ] && continue
		case "$_name" in dummy*) continue;; esac
		_state=$(cat "$_iface/operstate" 2>/dev/null || echo "unknown")
		set -- "$@" "$_name" "[$_state]"
		IFACE_COUNT=$((IFACE_COUNT+1))
	done

	if [ "$IFACE_COUNT" -gt 0 ]; then
		set -- "$@" "manual" "Enter interface name manually"
		dialog --backtitle "$TITLE" --menu \
			"Select a network interface (use arrow keys):" 20 50 13 \
			"$@" 2>/tmp/nb-ifsel || { rm -f /tmp/nb-ifsel; return 0; }
		IFACE_SEL=$(cat /tmp/nb-ifsel)
		rm -f /tmp/nb-ifsel
		if [ "$IFACE_SEL" = "manual" ]; then
			printf 'Network interface: '
			read -r IFACE
			if [ -z "$IFACE" ]; then return 0; fi
		else
			IFACE="$IFACE_SEL"
		fi
	else
		printf 'Network interface [eth0]: '
		read -r IFACE
		IFACE="${IFACE:-eth0}"
	fi
	IFINFO=$(ifconfig "$IFACE" 2>&1) || true
	dialog --backtitle "$TITLE" --msgbox "$IFINFO" 15 70 || true
	dialog --backtitle "$TITLE" --yesno \
		"Release IP address on $IFACE?" 6 45 || return 0
	killall -SIGUSR2 udhcpc 2>/dev/null || true
	dialog --backtitle "$TITLE" --msgbox \
		"IP address on $IFACE released." 5 45 || true
	dialog --backtitle "$TITLE" --yesno \
		"Request a new IP address via DHCP?" 6 50 || return 0
	dialog --backtitle "$TITLE" --infobox \
		"Requesting IP address via DHCP on $IFACE..." 4 52 || true
	udhcpc -i "$IFACE" -q >/dev/null 2>&1 || true
	sleep 2
	IFINFO=$(ifconfig "$IFACE" 2>&1) || true
	dialog --backtitle "$TITLE" --msgbox \
		"Done.\n\n$IFINFO" 15 70 || true
	return 0
}


installmenu ()
{
KERNELURL=
INITRDURL=
ARTIX_ISO_URL=
VOID_ISO_URL=
ALTLINUX_ISO_URL=
GUIX_ISO_URL=
GUIX_LABEL=
PIKA_ISO_URL=
PIKA_LABEL=
PIKA_ISO_FILE=
PIKA_ISO_VOLUME=
PORTEUX_ISO_URL=
PORTEUX_LABEL=
PORTEUX_KERNEL_PATH=
PORTEUX_INITRD_PATH=
PORTEUS_ISO_URL=
PORTEUS_LABEL=
PORTEUS_KERNEL_PATH=
PORTEUS_INITRD_PATH=
NEMESIS_ISO_URL=
NEMESIS_LABEL=
NEMESIS_KERNEL_PATH=
NEMESIS_INITRD_PATH=
CHIMERA_ISO_URL=
CHIMERA_LABEL=
CHIMERA_KERNEL_PATH=
CHIMERA_INITRD_PATH=
COYOTE_ISO_URL=
COYOTE_LABEL=
COYOTE_KERNEL_PATH=
COYOTE_INITRD_PATH=
NUTYX_ISO_URL=
NUTYX_LABEL=
NUTYX_KERNEL_PATH=
NUTYX_INITRD_PATH=
NUTYX_ROOTFS_PATH=
SALIX_ISO_URL=
SALIX_LABEL=
SALIX_KERNEL_PATH=
SALIX_INITRD_PATH=
DAPHILE_ISO_URL=
DAPHILE_LABEL=
DAPHILE_KERNEL_PATH=
DAPHILE_INITRD_PATH=
DAPHILE_ROOTFS_PATH=
DAPHILE_VERSION_DIR=
BERRY_ISO_URL=
BERRY_LABEL=
BERRY_KERNEL_PATH=
BERRY_INITRD_PATH=
BERRY_ROOTFS_PATH=
VENOM_ISO_URL=
VENOM_LABEL=
VENOM_KERNEL_PATH=
VENOM_INITRD_PATH=
PUPPY_ISO_URL=
PUPPY_LABEL=
PUPPY_KERNEL_PATH=
PUPPY_INITRD_PATH=
PUPPY_SFS_PATHS=
EASYOS_IMG_URL=
EASYOS_LABEL=
EASYOS_KERNEL_PATH=
EASYOS_INITRD_PATH=
EASYOS_WKG_IMAGE_PATH=
EASYOS_WKG_UUID=
EASYOS_WKG_DIR=
EASYOS_WKG_LABEL=
LIBREELEC_IMG_URL=
LIBREELEC_LABEL=
LIBREELEC_INIT_URL=
ARCHISO_ISO_URL=
ARCHISO_LABEL=
	ARCHISO_KERNEL_PATH=
	ARCHISO_INITRD_PATH=
	ARCHISO_ROOTFS_PATH=
	ARCHISO_CHECKSUM_PATH=
	PARABOLA_ISO_URL=
	PARABOLA_LABEL=
	PARABOLA_KERNEL_PATH=
	PARABOLA_INITRD_PATH=
	PARABOLA_ROOTFS_PATH=
	PARABOLA_AITAB_PATH=
	HYPERBOLA_ISO_URL=
	HYPERBOLA_LABEL=
	HYPERBOLA_KERNEL_PATH=
	HYPERBOLA_INITRD_PATH=
	HYPERBOLA_ROOTFS_PATH=
	HYPERBOLA_AITAB_PATH=
	MOCACCINO_ISO_URL=
	MOCACCINO_LABEL=
MOCACCINO_KERNEL_PATH=
MOCACCINO_INITRD_PATH=
MOCACCINO_ROOTFS_PATH=
ISO_BOOT_URL=
ISO_BOOT_LABEL=
ISO_BOOT_KERNEL_PATH=
ISO_BOOT_INITRD_PATH=
ANTIX_MX_ISO_URL=
ANTIX_MX_LABEL=
DEBIAN_LIVE_ISO_URL=
DEBIAN_LIVE_BOOT_URL=
DEBIAN_LIVE_MODE=
dialog --backtitle "$TITLE" --menu "Choose a distribution:" 24 75 20 \
ubuntu "Ubuntu" \
ubuntuflavor "Ubuntu flavors and derivatives" \
debian "Debian GNU/Linux" \
devuan "Devuan GNU/Linux" \
debianlive "Debian-based live installers" \
antixmx "antiX / MX Linux live installers" \
communitylive "Community live installers" \
pentesting "Pentesting and security live systems" \
q4os "Q4OS Trinity 6.6" \
fedora "Fedora" \
opensuse "openSUSE" \
mageia "Mageia" \
rhel "RHEL-compatible installers" \
arch "Arch Linux" \
artix "Artix Linux" \
void "Void Linux" \
altlinux "ALT Linux" \
guix "GNU Guix System" \
slackware "Slackware" \
rescue "Rescue and utility tools" 2>/tmp/nb-distro || { rm -f /tmp/nb-distro; return; }
DISTRO=$(cat /tmp/nb-distro)
rm /tmp/nb-distro
if [ "$DISTRO" = "rhel" ];then
	dialog --backtitle "$TITLE" --menu "Choose a RHEL-compatible installer family:" 18 78 8 \
	rhel-type-10 "AlmaLinux 10 / CentOS 10-Stream / Rocky Linux 10" \
	rhel-type-9 "AlmaLinux 9 / CentOS 9-Stream / Rocky Linux 9" \
	rhel-type-8 "AlmaLinux 8 / Rocky Linux 8" \
	cloudlinux "CloudLinux 8 / CloudLinux 9" \
	openeuler "openEuler" \
	rhel-extra "Other RHEL-compatible installers" 2>/tmp/nb-version || { rm -f /tmp/nb-version; return; }
	DISTRO=$(cat /tmp/nb-version)
	rm /tmp/nb-version
fi
if [ "$DISTRO" = "ubuntu" ];then
	dialog --backtitle "$TITLE" --menu "Choose a system to install:" 20 70 13 \
	resolute "Ubuntu 26.04 LTS (Subiquity)" \
	questing "Ubuntu 25.10 (Subiquity)" \
	noble "Ubuntu 24.04 LTS (Subiquity)" \
	jammy "Ubuntu 22.04 LTS (Subiquity)" \
	focal "Ubuntu 20.04 LTS" \
	bionic "Ubuntu 18.04 LTS" \
	Manual "Manually enter a version to install" 2>/tmp/nb-version || { rm -f /tmp/nb-version; return; }
	getversion || return 0
	if [ "$VERSION" = "noble" ]; then
		ubuntu_live_server \
			"https://releases.ubuntu.com/noble/netboot/amd64/linux" \
			"https://releases.ubuntu.com/noble/netboot/amd64/initrd" \
			"https://releases.ubuntu.com/24.04.4/ubuntu-24.04.4-live-server-amd64.iso" || return
	elif [ "$VERSION" = "resolute" ]; then
		ubuntu_live_server \
			"https://releases.ubuntu.com/resolute/netboot/amd64/linux" \
			"https://releases.ubuntu.com/resolute/netboot/amd64/initrd" \
			"https://releases.ubuntu.com/resolute/ubuntu-26.04-live-server-amd64.iso" || return
	elif [ "$VERSION" = "questing" ]; then
		ubuntu_live_server \
			"https://releases.ubuntu.com/questing/netboot/amd64/linux" \
			"https://releases.ubuntu.com/questing/netboot/amd64/initrd" \
			"https://releases.ubuntu.com/questing/ubuntu-25.10-live-server-amd64.iso" || return
	elif [ "$VERSION" = "jammy" ]; then
		# Canonical no longer publishes the old jammy debian-installer
		# netboot images.  Use netboot.xyz's ISO-extracted live-server
		# kernel/initrd pair and let casper fetch the official ISO.
		ubuntu_live_server \
			"https://github.com/netbootxyz/ubuntu-squash/releases/download/22.04.5-be230164/vmlinuz" \
			"https://github.com/netbootxyz/ubuntu-squash/releases/download/22.04.5-be230164/initrd" \
			"https://releases.ubuntu.com/22.04/ubuntu-22.04.5-live-server-amd64.iso" || return
	else
		KERNELURL="http://archive.ubuntu.com/ubuntu/dists/$VERSION-updates/main/installer-amd64/current/images/netboot/ubuntu-installer/amd64/linux"
		INITRDURL="http://archive.ubuntu.com/ubuntu/dists/$VERSION-updates/main/installer-amd64/current/images/netboot/ubuntu-installer/amd64/initrd.gz"
		if ! $WGET --spider -q "$KERNELURL"; then
			KERNELURL="http://archive.ubuntu.com/ubuntu/dists/$VERSION/main/installer-amd64/current/images/netboot/ubuntu-installer/amd64/linux"
			INITRDURL="http://archive.ubuntu.com/ubuntu/dists/$VERSION/main/installer-amd64/current/images/netboot/ubuntu-installer/amd64/initrd.gz"
		fi
		if ! $WGET --spider -q "$KERNELURL"; then
			KERNELURL="http://archive.ubuntu.com/ubuntu/dists/$VERSION/main/installer-amd64/current/legacy-images/netboot/ubuntu-installer/amd64/linux"
			INITRDURL="http://archive.ubuntu.com/ubuntu/dists/$VERSION/main/installer-amd64/current/legacy-images/netboot/ubuntu-installer/amd64/initrd.gz"
		fi
		printf '%s' 'vga=normal quiet '>>/tmp/nb-options
		if dialog --yesno "Would you like to install language packs?\n(Choose no for a command-line system.)" 7 43;then
			printf '%s' 'tasks=standard pkgsel/language-pack-patterns= pkgsel/install-language-support=false'>>/tmp/nb-options
		fi
	fi
fi
if [ "$DISTRO" = "ubuntuflavor" ];then
	UBUNTU_LIVE_CUSTOM=
	dialog --backtitle "$TITLE" --menu "Choose an Ubuntu flavor or derivative to boot:" 24 78 19 \
	kubuntu-26.04 "Kubuntu 26.04 LTS" \
	xubuntu-26.04 "Xubuntu 26.04 LTS" \
	lubuntu-26.04 "Lubuntu 26.04 LTS" \
	budgie-26.04 "Ubuntu Budgie 26.04 LTS" \
	cinnamon-26.04 "Ubuntu Cinnamon 26.04 LTS" \
	studio-26.04 "Ubuntu Studio 26.04 LTS" \
	unity-26.04 "Ubuntu Unity 26.04 LTS" \
	edubuntu-26.04 "Edubuntu 26.04 LTS" \
		mate-24.04 "Ubuntu MATE 24.04.4 LTS" \
		bodhi-7.0 "Bodhi Linux 7.0.0" \
		funos-24.04 "FunOS 24.04.4 LTS Calamares" \
		kde-neon-user "KDE neon User Edition" \
		linuxlite-7.8 "Linux Lite 7.8" \
		mint-22.3-cinnamon "Linux Mint 22.3 Cinnamon" \
		mint-22.3-mate "Linux Mint 22.3 MATE" \
		mint-22.3-xfce "Linux Mint 22.3 Xfce" \
		rhino-2025.4 "Rhino Linux 2025.4" \
	trisquel-mini-12 "Trisquel Mini 12.0" \
	trisquel-netinst-12 "Trisquel 12.0 NetInstall" \
	voyager-26.04 "Voyager 26.04 LTS" \
	Manual "Manually enter an Ubuntu live ISO URL" 2>/tmp/nb-version || { rm -f /tmp/nb-version; return; }
	VERSION=$(cat /tmp/nb-version)
	rm /tmp/nb-version
	UBUNTU_KERNEL_SERIES="resolute"
	if [ "$VERSION" = "kubuntu-26.04" ]; then
		ISODEFAULT="https://cdimage.ubuntu.com/kubuntu/releases/26.04/release/kubuntu-26.04-desktop-amd64.iso"
	elif [ "$VERSION" = "xubuntu-26.04" ]; then
		ISODEFAULT="https://cdimage.ubuntu.com/xubuntu/releases/26.04/release/xubuntu-26.04-desktop-amd64.iso"
	elif [ "$VERSION" = "lubuntu-26.04" ]; then
		ISODEFAULT="https://cdimage.ubuntu.com/lubuntu/releases/26.04/release/lubuntu-26.04-desktop-amd64.iso"
	elif [ "$VERSION" = "budgie-26.04" ]; then
		ISODEFAULT="https://cdimage.ubuntu.com/ubuntu-budgie/releases/26.04/release/ubuntu-budgie-26.04-desktop-amd64.iso"
	elif [ "$VERSION" = "cinnamon-26.04" ]; then
		ISODEFAULT="https://cdimage.ubuntu.com/ubuntucinnamon/releases/26.04/release/ubuntucinnamon-26.04-desktop-amd64.iso"
	elif [ "$VERSION" = "studio-26.04" ]; then
		ISODEFAULT="https://cdimage.ubuntu.com/ubuntustudio/releases/26.04/release/ubuntustudio-26.04-desktop-amd64.iso"
	elif [ "$VERSION" = "unity-26.04" ]; then
		ISODEFAULT="https://cdimage.ubuntu.com/ubuntu-unity/releases/26.04/release/ubuntu-unity-26.04-desktop-amd64.iso"
	elif [ "$VERSION" = "edubuntu-26.04" ]; then
		ISODEFAULT="https://cdimage.ubuntu.com/edubuntu/releases/26.04/release/edubuntu-26.04-desktop-amd64.iso"
	elif [ "$VERSION" = "mate-24.04" ]; then
		UBUNTU_KERNEL_SERIES="noble"
		ISODEFAULT="https://cdimage.ubuntu.com/ubuntu-mate/releases/24.04/release/ubuntu-mate-24.04.4-desktop-amd64.iso"
	elif [ "$VERSION" = "bodhi-7.0" ]; then
		ubuntu_casper_iso_setup \
			"Bodhi Linux 7.0.0" \
			"http://downloads.sourceforge.net/project/bodhilinux/7.0.0/bodhi-7.0.0-64.iso" \
			"username=bodhi hostname=bodhi" || return
		UBUNTU_LIVE_CUSTOM=1
		ISODEFAULT=custom
	elif [ "$VERSION" = "funos-24.04" ]; then
		ubuntu_casper_iso_setup \
			"FunOS 24.04.4 LTS Calamares" \
			"http://downloads.sourceforge.net/project/funos/noble/final/24.04.4/funos-24.04.4-stable.20260407-calamares.iso" \
			"username=funos hostname=funos" || return
		UBUNTU_LIVE_CUSTOM=1
		ISODEFAULT=custom
	elif [ "$VERSION" = "kde-neon-user" ]; then
		ubuntu_casper_iso_setup \
			"KDE neon User Edition" \
			"https://files.kde.org/neon/images/user/current/neon-user-current.iso" \
			"username=neon hostname=neon" || return
		UBUNTU_LIVE_CUSTOM=1
		ISODEFAULT=custom
	elif [ "$VERSION" = "linuxlite-7.8" ]; then
		ubuntu_casper_iso_setup \
			"Linux Lite 7.8" \
			"http://master.dl.sourceforge.net/project/linux-lite/7.8/linux-lite-7.8-64bit.iso?viasf=1" \
			"username=linuxlite hostname=linuxlite" \
			"http://downloads.sourceforge.net/project/linux-lite/7.8/linux-lite-7.8-64bit.iso" || return
		UBUNTU_LIVE_CUSTOM=1
		ISODEFAULT=custom
	elif [ "$VERSION" = "mint-22.3-cinnamon" ]; then
		ubuntu_casper_iso_setup \
			"Linux Mint 22.3 Cinnamon" \
			"http://mirrors.edge.kernel.org/linuxmint/stable/22.3/linuxmint-22.3-cinnamon-64bit.iso" \
			"username=mint hostname=mint" || return
		UBUNTU_LIVE_CUSTOM=1
		ISODEFAULT=custom
	elif [ "$VERSION" = "mint-22.3-mate" ]; then
		ubuntu_casper_iso_setup \
			"Linux Mint 22.3 MATE" \
			"http://mirrors.edge.kernel.org/linuxmint/stable/22.3/linuxmint-22.3-mate-64bit.iso" \
			"username=mint hostname=mint" || return
		UBUNTU_LIVE_CUSTOM=1
		ISODEFAULT=custom
	elif [ "$VERSION" = "mint-22.3-xfce" ]; then
		ubuntu_casper_iso_setup \
			"Linux Mint 22.3 Xfce" \
			"http://mirrors.edge.kernel.org/linuxmint/stable/22.3/linuxmint-22.3-xfce-64bit.iso" \
			"username=mint hostname=mint" || return
		UBUNTU_LIVE_CUSTOM=1
		ISODEFAULT=custom
	elif [ "$VERSION" = "rhino-2025.4" ]; then
		ubuntu_casper_iso_setup \
			"Rhino Linux 2025.4" \
			"http://downloads.sourceforge.net/project/rhino-linux-builder/2025.4/Rhino-Linux-2025.4-amd64.iso?use_mirror=netactuate" \
			"username=rhino hostname=rhino" \
			"http://netactuate.dl.sourceforge.net/project/rhino-linux-builder/2025.4/Rhino-Linux-2025.4-amd64.iso" || return
		UBUNTU_LIVE_CUSTOM=1
		ISODEFAULT=custom
	elif [ "$VERSION" = "trisquel-mini-12" ]; then
		ubuntu_casper_iso_setup \
			"Trisquel Mini 12.0" \
			"http://cdimage.trisquel.info/trisquel-images/trisquel-mini_12.0_amd64.iso" \
			"username=trisquel hostname=trisquel" || return
		UBUNTU_LIVE_CUSTOM=1
		ISODEFAULT=custom
	elif [ "$VERSION" = "trisquel-netinst-12" ]; then
		iso_boot_setup \
			"http://cdimage.trisquel.info/trisquel-images/trisquel-netinst_12.0_amd64.iso" \
			"Trisquel 12.0 NetInstall" \
			"linux" \
			"initrd.gz"
		printf '%s' "vga=normal quiet " >>/tmp/nb-options
		UBUNTU_LIVE_CUSTOM=1
		ISODEFAULT=custom
	elif [ "$VERSION" = "voyager-26.04" ]; then
		ubuntu_casper_iso_setup \
			"Voyager 26.04 LTS" \
			"http://downloads.sourceforge.net/project/voyagerlive/Voyager-26.04-lts-amd64.iso" \
			"username=ubuntu hostname=voyager" || return
		UBUNTU_LIVE_CUSTOM=1
		ISODEFAULT=custom
	else
		ISODEFAULT=
	fi
	if [ "$VERSION" = "Manual" ]; then
		UBUNTU_KERNEL_SERIES="resolute"
		dialog --backtitle "$TITLE" --inputbox "URL for the Ubuntu flavor live ISO:" 8 70 "" 2>/tmp/nb-isourl || { rm -f /tmp/nb-isourl; return; }
		ISODEFAULT=$(cat /tmp/nb-isourl)
		rm /tmp/nb-isourl
	fi
	if [ -z "$ISODEFAULT" ]; then
		dialog --backtitle "$TITLE" --msgbox \
			"No Ubuntu flavor ISO URL was selected." 6 50 || true
		return 1
	fi
	if [ "$UBUNTU_LIVE_CUSTOM" != "1" ]; then
		ubuntu_live_iso \
			"https://releases.ubuntu.com/$UBUNTU_KERNEL_SERIES/netboot/amd64/linux" \
			"https://releases.ubuntu.com/$UBUNTU_KERNEL_SERIES/netboot/amd64/initrd" \
			"$ISODEFAULT" \
			"Ubuntu live ISO" || return
	fi
fi
if [ "$DISTRO" = "debian" ];then
	dialog --backtitle "$TITLE" --menu "Choose a system to install:" 20 70 13 \
	trixie "Debian 13" \
	bookworm "Debian 12" \
	bullseye "Debian 11" \
	stable "Debian stable" \
	testing "Debian testing" \
	Manual "Manually enter a version to install" 2>/tmp/nb-version || { rm -f /tmp/nb-version; return; }
	getversion || return 0
	KERNELURL="http://http.us.debian.org/debian/dists/$VERSION/main/installer-amd64/current/images/netboot/debian-installer/amd64/linux"
	INITRDURL="http://http.us.debian.org/debian/dists/$VERSION/main/installer-amd64/current/images/netboot/debian-installer/amd64/initrd.gz"
	printf '%s' 'vga=normal quiet '>>/tmp/nb-options
fi
if [ "$DISTRO" = "devuan" ];then
	dialog --backtitle "$TITLE" --menu "Choose a system to install:" 20 70 13 \
 	excalibur "Devuan excalibur" \
	daedalus "Devuan daedalus" \
	chimaera "Devuan chimaera" \
	ceres "Devuan ceres" \
	Manual "Manually enter a version to install" 2>/tmp/nb-version || { rm -f /tmp/nb-version; return; }
	getversion || return 0
	KERNELURL="http://deb.devuan.org/devuan/dists/$VERSION/main/installer-amd64/current/images/netboot/debian-installer/amd64/linux"
	INITRDURL="http://deb.devuan.org/devuan/dists/$VERSION/main/installer-amd64/current/images/netboot/debian-installer/amd64/initrd.gz"
	printf '%s' 'vga=normal quiet '>>/tmp/nb-options
fi

if [ "$DISTRO" = "debianlive" ];then
	dialog --backtitle "$TITLE" --menu "Choose a Debian-based live installer to boot:" 24 78 22 \
	besgnulinux-jwm "Besgnulinux JWM 3.3" \
	butterbian-xfce "Butterbian Xfce 0.2.1" \
	butterknife "Butterknife 0.1.11" \
	bunsenlabs-carbon "BunsenLabs Carbon 1" \
	crunchbangplusplus-120 "CrunchBang++ 12.0" \
	crowz-openbox "CROWZ 5.0.1 Openbox" \
	crowz-fluxbox "CROWZ 5.0.1 Fluxbox" \
	crowz-jwm "CROWZ 5.0.1 JWM" \
	emmabuntus-de6-core "Emmabuntus DE6 Core" \
	enux-533 "ENux 5.3.3 Xfce" \
	exegnu-daedalus "Exe GNU/Linux Daedalus Trinity" \
	kanotix-towelfire-lxde "KANOTIX Towelfire LXDE" \
	lmde-7-cinnamon "LMDE 7 Cinnamon" \
	locos-24 "Loc-OS 24" \
	mauna-christian "Mauna Linux 25.2 Christian Edition" \
	minios-standard "MiniOS 5.1.1 Standard" \
	nakedeb-16 "nakeDeb 1.6" \
	neptune-91 "Neptune 9.1" \
	peppermint-trixie "Peppermint OS Debian 64" \
	pureos-11-gnome "PureOS 11 GNOME" \
	refracta-xfce "Refracta 13.3 Xfce" \
	refracta-nox "Refracta 13.3 noX" \
	solydx-13 "SolydX 13" \
	sparky-lxqt-83 "SparkyLinux 8.3 LXQt" \
	sparky-xfce-831 "SparkyLinux 8.3.1 Xfce" \
	synex-icewm "Synex 13 IceWM" \
	synex-lxde "Synex 13 LXDE" \
	synex-xfce "Synex 13 Xfce" \
	voyager-debian-133 "Voyager 13.3 Debian" \
	wattos-r13 "wattOS R13" 2>/tmp/nb-version || { rm -f /tmp/nb-version; return; }
	VERSION=$(cat /tmp/nb-version)
	rm /tmp/nb-version
	debian_live_iso_setup "$VERSION" || return
fi

if [ "$DISTRO" = "antixmx" ];then
	dialog --backtitle "$TITLE" --menu "Choose an antiX/MX live installer to boot:" 18 75 8 \
	antix-26-core "antiX 26 Core" \
	avlinux-mxe-251 "AV Linux MXE 25.1" \
	mx-25.1-xfce "MX Linux 25.1 Xfce" \
	mx-25.1-xfce-ahs "MX Linux 25.1 Xfce AHS" 2>/tmp/nb-version || { rm -f /tmp/nb-version; return; }
	VERSION=$(cat /tmp/nb-version)
	rm /tmp/nb-version
	antix_mx_iso_setup "$VERSION" || return
fi

if [ "$DISTRO" = "communitylive" ];then
	dialog --backtitle "$TITLE" --menu "Choose a community live installer to boot:" 25 78 21 \
	acreetionos-cinnamon-10 "AcreetionOS 1.0 Cinnamon" \
	adelie-inst-beta6 "Adelie Linux 1.0-beta6 Installer" \
	bredos-20251027 "BredOS 2025.10.27" \
	berry-142 "Berry Linux 1.42" \
	cachyos-desktop-260426 "CachyOS Desktop 260426" \
	chimera-base "Chimera Linux Base 2025-12-20" \
	coyote-installer-40192 "Coyote Linux 4.0.192 Technology Preview (router)" \
	daphile-2505 "Daphile 25.05 x86_64 (music server)" \
	ditana-09-beta "Ditana GNU/Linux 0.9 Beta" \
	endeavouros-titan-neo-20260427 "EndeavourOS Titan Neo 2026.04.27" \
	easyos-excalibur "EasyOS Excalibur 7.3.8" \
	fatdog64-903 "Fatdog64 903" \
	garuda-kde-lite-latest "Garuda KDE Lite latest" \
	gobolinux-01701 "GoboLinux 017.01" \
	hyperbola-milky-way-044 "Hyperbola GNU/Linux-libre Milky Way 0.4.4" \
	keskos-layer-v3 "KeskOS Layer v3" \
	libreelec-generic "LibreELEC Generic x86_64 12.2.1" \
	mocaccino-kde-20260505 "MocaccinoOS KDE 0.20260505" \
	nemesis-lxde-2510 "Nemesis Linux 25.10 LXDE" \
	nutyx-xfce-260403 "NuTyX 26.04.3 Xfce" \
	obarun-minimal-20260430 "Obarun Minimal 2026.04.30" \
	parabola-cli-202204 "Parabola GNU/Linux-libre 2022.04 CLI netinstall" \
	pikaos-gnome "PikaOS 4.0 GNOME" \
	pikaos-kde "PikaOS 4.0 KDE" \
	pikaos-hyprland "PikaOS 4.0 Hyprland" \
	pikaos-niri "PikaOS 4.0 Niri" \
	pikaos-cosmic "PikaOS 4.0 COSMIC" \
	prismlinux-20260505 "PrismLinux 2026.05.05" \
	rebornos-20260122 "RebornOS 2026.01.22" \
	porteus-xfce-501 "Porteus 5.01 Xfce" \
	porteux-lxde "PorteuX 2.4 LXDE" \
	puppy-bookwormpup64 "BookwormPup64 10.0.12" \
	puppy-trixiepup64-legacy-114 "TrixiePup64 Legacy 11.4" \
	salixlive-xfce-150 "SalixLive64 Xfce 15.0" \
	slackel-openbox-80 "Slackel 8.0 Openbox" \
	sdesk-quartz-202510 "SDesk Quartz 2025.10" \
	solus-xfce "Solus Xfce 2026-04-18" \
	venom-base-sysv-20260320 "Venom Linux Base SysV 2026-03-20" 2>/tmp/nb-version || { rm -f /tmp/nb-version; return; }
	VERSION=$(cat /tmp/nb-version)
	rm /tmp/nb-version
	community_live_iso_setup "$VERSION" || return
fi

if [ "$DISTRO" = "pentesting" ];then
	dialog --backtitle "$TITLE" --menu "Choose a pentesting/security live system to boot:" 12 78 4 \
	fedora-security-44 "Fedora Security Lab 44" 2>/tmp/nb-version || { rm -f /tmp/nb-version; return; }
	VERSION=$(cat /tmp/nb-version)
	rm /tmp/nb-version
	pentesting_iso_setup "$VERSION" || return
fi

if [ "$DISTRO" = "q4os" ];then
	BASE="https://github.com/netbootxyz/debian-squash/releases/download/6.6-5d30850e"
	KERNELURL="$BASE/vmlinuz"
	INITRDURL="$BASE/initrd"
	printf '%s' "boot=live fetch=$BASE/filesystem.squashfs" >>/tmp/nb-options
fi
if [ "$DISTRO" = "fedora" ];then
	dialog --backtitle "$TITLE" --menu "Choose a system to install:" 20 70 13 \
	releases/44/Server "Fedora Server 44" \
	Manual "Manually enter a version to install" 2>/tmp/nb-version || { rm -f /tmp/nb-version; return; }
	getversion || return 0
	dialog --inputbox "Where do you want to install Fedora from?" 8 70 "http://mirrors.kernel.org/fedora/$VERSION/x86_64/os" 2>/tmp/nb-server || { rm -f /tmp/nb-server; return; }
	SERVER=$(cat /tmp/nb-server)
	KERNELURL="$SERVER/images/pxeboot/vmlinuz"
	INITRDURL="$SERVER/images/pxeboot/initrd.img"
	printf '%s' "inst.stage2=$SERVER" >>/tmp/nb-options
	rm /tmp/nb-server
fi
if [ "$DISTRO" = "opensuse" ];then
	dialog --backtitle "$TITLE" --menu "Choose a system to install:" 20 70 13 \
	tumbleweed "openSUSE Tumbleweed" \
	slowroll "openSUSE Slowroll" \
	leap/16.0 "openSUSE Leap 16.0" \
	Manual "Manually enter a version to install" 2>/tmp/nb-version || { rm -f /tmp/nb-version; return; }
	getversion || return 0
	if [ "$VERSION" != "tumbleweed" ] && [ "$VERSION" != "slowroll" ];then
		VERSION=distribution/$VERSION
	fi
	KERNELURL="http://download.opensuse.org/$VERSION/repo/oss/boot/x86_64/loader/linux"
	INITRDURL="http://download.opensuse.org/$VERSION/repo/oss/boot/x86_64/loader/initrd"
	printf '%s' 'splash=silent showopts '>>/tmp/nb-options
	dialog --inputbox "Where do you want to install openSUSE from?" 8 70 "http://download.opensuse.org/$VERSION/repo/oss" 2>/tmp/nb-server || { rm -f /tmp/nb-server; return; }
	printf '%s' "install=$(cat /tmp/nb-server)" >>/tmp/nb-options
	rm /tmp/nb-server
fi
if [ "$DISTRO" = "mageia" ];then
	dialog --backtitle "$TITLE" --menu "Choose a system to install:" 20 70 13 \
	10 "Mageia 10 pre-release" \
	9 "Mageia 9" \
	cauldron "Mageia cauldron" \
	Manual "Manually enter a version to install" 2>/tmp/nb-version || { rm -f /tmp/nb-version; return; }
	getversion || return 0
	KERNELURL="http://mirrors.kernel.org/mageia/distrib/$VERSION/x86_64/isolinux/x86_64/vmlinuz"
	INITRDURL="http://mirrors.kernel.org/mageia/distrib/$VERSION/x86_64/isolinux/x86_64/all.rdz"
	printf '%s' 'automatic=method:http' >>/tmp/nb-options
fi
if [ "$DISTRO" = "rhel-type-10" ];then
	dialog --backtitle "$TITLE" --menu "Choose a system to install:" 20 70 13 \
	a_10 "Latest version of AlmaLinux 10" \
	c_10-stream "Latest version of CentOS Stream 10" \
	r_10 "Latest version of Rocky Linux 10" \
	Manual "Manually enter a version to install (prefix with a_, c_, or r_)" 2>/tmp/nb-version || { rm -f /tmp/nb-version; return; }
	getversion || return 0
	TYPE=$(echo $VERSION|head -c 1)
	VERSION=$(echo $VERSION|tail -c +3)
	if [ "$TYPE" = a ];then
		dialog --inputbox "Where do you want to install AlmaLinux OS from?" 8 70 "http://repo.almalinux.org/almalinux/$VERSION/BaseOS/x86_64/os" 2>/tmp/nb-server || { rm -f /tmp/nb-server; return; }
	elif [ "$TYPE" = c ];then
		dialog --inputbox "Where do you want to install CentOS Stream from?" 8 70 "https://ftp-chi.osuosl.org/pub/centos-stream/$VERSION/BaseOS/x86_64/os" 2>/tmp/nb-server || { rm -f /tmp/nb-server; return; }
	elif [ "$TYPE" = r ];then
		dialog --inputbox "Where do you want to install Rocky Linux from?" 8 70 "http://download.rockylinux.org/pub/rocky/$VERSION/BaseOS/x86_64/os" 2>/tmp/nb-server || { rm -f /tmp/nb-server; return; }
	else
		dialog --inputbox "Where do you want to install this distribution from?" 8 70 "" 2>/tmp/nb-server || { rm -f /tmp/nb-server; return; }
	fi
	SERVER=$(cat /tmp/nb-server)
	KERNELURL="$SERVER/images/pxeboot/vmlinuz"
	INITRDURL="$SERVER/images/pxeboot/initrd.img"
	printf '%s' "nomodeset inst.repo=$SERVER" >>/tmp/nb-options
	rm /tmp/nb-server
fi
if [ "$DISTRO" = "rhel-type-9" ];then
	dialog --backtitle "$TITLE" --menu "Choose a system to install:" 20 70 13 \
	a_9 "Latest version of AlmaLinux 9" \
	c_9-stream "Latest version of CentOS Stream 9" \
	r_9 "Latest version of Rocky Linux 9" \
	Manual "Manually enter a version to install (prefix with a_, c_, or r_)" 2>/tmp/nb-version || { rm -f /tmp/nb-version; return; }
	getversion || return 0
	TYPE=$(echo $VERSION|head -c 1)
	VERSION=$(echo $VERSION|tail -c +3)
	if [ "$TYPE" = a ];then
		dialog --inputbox "Where do you want to install AlmaLinux OS from?" 8 70 "http://repo.almalinux.org/almalinux/$VERSION/BaseOS/x86_64/os" 2>/tmp/nb-server || { rm -f /tmp/nb-server; return; }
	elif [ "$TYPE" = c ];then
		dialog --inputbox "Where do you want to install CentOS Stream from?" 8 70 "https://ftp-chi.osuosl.org/pub/centos-stream/$VERSION/BaseOS/x86_64/os" 2>/tmp/nb-server || { rm -f /tmp/nb-server; return; }
	elif [ "$TYPE" = r ];then
		dialog --inputbox "Where do you want to install Rocky Linux from?" 8 70 "http://download.rockylinux.org/pub/rocky/$VERSION/BaseOS/x86_64/os" 2>/tmp/nb-server || { rm -f /tmp/nb-server; return; }
	else
		dialog --inputbox "Where do you want to install this distribution from?" 8 70 "" 2>/tmp/nb-server || { rm -f /tmp/nb-server; return; }
	fi
	SERVER=$(cat /tmp/nb-server)
	KERNELURL="$SERVER/isolinux/vmlinuz"
	INITRDURL="$SERVER/isolinux/initrd.img"
	printf '%s' "nomodeset inst.repo=$SERVER" >>/tmp/nb-options
	rm /tmp/nb-server
fi
if [ "$DISTRO" = "rhel-type-8" ];then
	dialog --backtitle "$TITLE" --menu "Choose a system to install:" 20 70 13 \
	a_8 "Latest version of AlmaLinux 8" \
	r_8 "Latest version of Rocky Linux 8" \
	Manual "Manually enter a version to install (prefix with a_ or r_)" 2>/tmp/nb-version || { rm -f /tmp/nb-version; return; }
	getversion || return 0
	TYPE=$(echo $VERSION|head -c 1)
	VERSION=$(echo $VERSION|tail -c +3)
	if [ "$TYPE" = a ];then
		dialog --inputbox "Where do you want to install AlmaLinux OS from?" 8 70 "http://repo.almalinux.org/almalinux/$VERSION/BaseOS/x86_64/os" 2>/tmp/nb-server || { rm -f /tmp/nb-server; return; }
	elif [ "$TYPE" = r ];then
		dialog --inputbox "Where do you want to install Rocky Linux from?" 8 70 "http://download.rockylinux.org/pub/rocky/$VERSION/BaseOS/x86_64/os" 2>/tmp/nb-server || { rm -f /tmp/nb-server; return; }
	else
		dialog --inputbox "Where do you want to install this distribution from?" 8 70 "" 2>/tmp/nb-server || { rm -f /tmp/nb-server; return; }
	fi
	SERVER=$(cat /tmp/nb-server)
	KERNELURL="$SERVER/isolinux/vmlinuz"
	INITRDURL="$SERVER/isolinux/initrd.img"
	printf '%s' "nomodeset inst.repo=$SERVER" >>/tmp/nb-options
	rm /tmp/nb-server
fi
if [ "$DISTRO" = "cloudlinux" ];then
	dialog --backtitle "$TITLE" --menu "Choose a system to install:" 20 70 13 \
	9 "CloudLinux 9" \
	8 "CloudLinux 8" 2>/tmp/nb-version || { rm -f /tmp/nb-version; return; }
	getversion || return 0
	dialog --backtitle "$TITLE" --inputbox "Where do you want to install CloudLinux from?" 8 70 "https://download.cloudlinux.com/cloudlinux/$VERSION/BaseOS/x86_64/os" 2>/tmp/nb-server || { rm -f /tmp/nb-server; return; }
	SERVER=$(cat /tmp/nb-server)
	KERNELURL="$SERVER/images/pxeboot/vmlinuz"
	INITRDURL="$SERVER/images/pxeboot/initrd.img"
	printf '%s' "nomodeset inst.repo=$SERVER" >>/tmp/nb-options
	rm /tmp/nb-server
fi
if [ "$DISTRO" = "rhel-extra" ];then
	dialog --backtitle "$TITLE" --menu "Choose a system to install:" 20 70 13 \
	opencloudos-9 "OpenCloudOS 9 latest" \
	opencloudos-9.4 "OpenCloudOS 9.4" \
	opencloudos-9.2 "OpenCloudOS 9.2" \
	opencloudos-8.10 "OpenCloudOS 8.10" \
	eurolinux-9.4 "EuroLinux 9.4" \
	eurolinux-8.10 "EuroLinux 8.10" \
	springdale-9.2 "Springdale Linux 9.2" \
	springdale-8.8 "Springdale Linux 8.8" \
	smeserver-11.0-beta1 "Koozali SME Server 11.0 Beta 1" \
	tencentos-4 "TencentOS Server 4 latest" \
	tencentos-3.3 "TencentOS Server 3.3" \
	custom "Custom RHEL-compatible installer tree" 2>/tmp/nb-version || { rm -f /tmp/nb-version; return; }
	VERSION=$(cat /tmp/nb-version)
	rm /tmp/nb-version
	if [ "$VERSION" = "opencloudos-9" ];then
		DISTNAME="OpenCloudOS"
		SERVERDEFAULT="https://mirrors.opencloudos.org/opencloudos/9/BaseOS/x86_64/os"
	elif [ "$VERSION" = "opencloudos-9.4" ];then
		DISTNAME="OpenCloudOS"
		SERVERDEFAULT="https://mirrors.opencloudos.org/opencloudos/9.4/BaseOS/x86_64/os"
	elif [ "$VERSION" = "opencloudos-9.2" ];then
		DISTNAME="OpenCloudOS"
		SERVERDEFAULT="https://mirrors.opencloudos.org/opencloudos/9.2/BaseOS/x86_64/os"
	elif [ "$VERSION" = "opencloudos-8.10" ];then
		DISTNAME="OpenCloudOS"
		SERVERDEFAULT="https://mirrors.opencloudos.org/opencloudos/8.10/BaseOS/x86_64/os"
	elif [ "$VERSION" = "eurolinux-9.4" ];then
		DISTNAME="EuroLinux"
		SERVERDEFAULT="https://vault.cdn.euro-linux.com/legacy/eurolinux/9/9.4/BaseOS/x86_64/os"
	elif [ "$VERSION" = "eurolinux-8.10" ];then
		DISTNAME="EuroLinux"
		SERVERDEFAULT="https://vault.cdn.euro-linux.com/legacy/eurolinux/8/8.10/BaseOS/x86_64/os"
	elif [ "$VERSION" = "springdale-9.2" ];then
		DISTNAME="Springdale Linux"
		SERVERDEFAULT="http://springdale.princeton.edu/data/puias/9.2/x86_64/os"
	elif [ "$VERSION" = "springdale-8.8" ];then
		DISTNAME="Springdale Linux"
		SERVERDEFAULT="http://springdale.princeton.edu/data/puias/8.8/x86_64/os"
	elif [ "$VERSION" = "smeserver-11.0-beta1" ];then
		DISTNAME="Koozali SME Server"
		SERVERDEFAULT="https://distro.ibiblio.org/smeserver/releases/testing/11/smeos/x86_64"
	elif [ "$VERSION" = "tencentos-4" ];then
		DISTNAME="TencentOS Server"
		SERVERDEFAULT="https://mirrors.tencent.com/tlinux/4/BaseOS/x86_64/os"
	elif [ "$VERSION" = "tencentos-3.3" ];then
		DISTNAME="TencentOS Server"
		SERVERDEFAULT="https://mirrors.tencent.com/tlinux/3.3/BaseOS/x86_64/os"
	else
		DISTNAME="this RHEL-compatible distribution"
		SERVERDEFAULT=
	fi
	dialog --backtitle "$TITLE" --inputbox "Where do you want to install $DISTNAME from?" 8 70 "$SERVERDEFAULT" 2>/tmp/nb-server || { rm -f /tmp/nb-server; return; }
	SERVER=$(cat /tmp/nb-server)
	if [ -z "$SERVER" ];then
		dialog --backtitle "$TITLE" --msgbox \
			"No installer repository URL was entered." 6 50 || true
		rm -f /tmp/nb-server
		return 1
	fi
	KERNELURL="$SERVER/images/pxeboot/vmlinuz"
	INITRDURL="$SERVER/images/pxeboot/initrd.img"
	if [ "$VERSION" = "smeserver-11.0-beta1" ];then
		printf '%s' "ip=dhcp initcall_blacklist=clocksource_done_booting inst.stage2=$SERVER inst.repo=$SERVER quiet" >>/tmp/nb-options
	elif [ "$VERSION" = "tencentos-4" ] || [ "$VERSION" = "tencentos-3.3" ];then
		printf '%s' "ip=dhcp nomodeset inst.stage2=$SERVER inst.repo=$SERVER inst.noverifyssl" >>/tmp/nb-options
	else
		printf '%s' "nomodeset inst.repo=$SERVER" >>/tmp/nb-options
	fi
	rm /tmp/nb-server
fi
if [ "$DISTRO" = "openeuler" ];then
	dialog --backtitle "$TITLE" --menu "Choose a system to install:" 20 70 13 \
	24.03-LTS-SP3 "openEuler 24.03 LTS SP3" \
	24.03-LTS-SP1 "openEuler 24.03 LTS SP1" \
	24.03-LTS "openEuler 24.03 LTS" \
	22.03-LTS-SP4 "openEuler 22.03 LTS SP4" \
	Manual "Manually enter a version to install (e.g. 24.03-LTS)" 2>/tmp/nb-version || { rm -f /tmp/nb-version; return; }
	getversion || return 0
	dialog --inputbox "Where do you want to install openEuler from?" 8 70 "https://repo.openeuler.org/openEuler-$VERSION/everything/x86_64" 2>/tmp/nb-server || { rm -f /tmp/nb-server; return; }
	SERVER=$(cat /tmp/nb-server)
	KERNELURL="$SERVER/images/pxeboot/vmlinuz"
	INITRDURL="$SERVER/images/pxeboot/initrd.img"
	printf '%s' "inst.repo=$SERVER" >>/tmp/nb-options
	rm /tmp/nb-server
fi
if [ "$DISTRO" = "arch" ];then
	dialog --backtitle "$TITLE" --menu "Choose a system to install:" 20 70 13 \
	latest "Arch x86_64" \
	archboot-latest "Archboot latest installer" 2>/tmp/nb-version || { rm -f /tmp/nb-version; return; }
	getversion || return 0
	if [ "$VERSION" = "archboot-latest" ];then
		BASE="https://release.archboot.com/x86_64/latest/ipxe"
		KERNELURL="$BASE/vmlinuz"
		INITRDURL="$BASE/amd-ucode.img $BASE/intel-ucode.img $BASE/initrd-latest-x86_64.img"
		printf '%s' 'vga=normal quiet ip=dhcp net.ifnames=0 '>>/tmp/nb-options
	else
		KERNELURL="http://mirror.rackspace.com/archlinux/iso/$VERSION/arch/boot/x86_64/vmlinuz-linux"
		INITRDURL="http://mirror.rackspace.com/archlinux/iso/$VERSION/arch/boot/x86_64/initramfs-linux.img"
		printf '%s' 'vga=normal quiet archiso_http_srv=http://mirror.rackspace.com/archlinux/iso/latest/ archisobasedir=arch verify=n ip=dhcp net.ifnames=0 BOOTIF=01-${netX/mac} boot '>>/tmp/nb-options
	fi
fi
if [ "$DISTRO" = "artix" ];then
	dialog --backtitle "$TITLE" --menu "Choose an Artix system to boot:" 12 70 4 \
	base-dinit "Base dinit" \
	base-openrc "Base OpenRC" \
	base-runit "Base runit" \
	base-s6 "Base s6" 2>/tmp/nb-version || { rm -f /tmp/nb-version; return; }
	VERSION=$(cat /tmp/nb-version)
	rm /tmp/nb-version
	artix_iso_setup "$VERSION" || return
fi
if [ "$DISTRO" = "void" ];then
	dialog --backtitle "$TITLE" --menu "Choose a Void Linux live system to boot:" 14 76 6 \
	glibc-base "Base (glibc)" \
	glibc-xfce "Xfce (glibc)" \
	musl-base "Base (musl)" \
	musl-xfce "Xfce (musl)" 2>/tmp/nb-version || { rm -f /tmp/nb-version; return; }
	VERSION=$(cat /tmp/nb-version)
	rm /tmp/nb-version
	void_iso_setup "$VERSION" || return
fi
if [ "$DISTRO" = "altlinux" ];then
	dialog --backtitle "$TITLE" --menu "Choose an ALT Linux system to boot:" 10 76 2 \
	regular-jeos-systemd "Sisyphus regular JeOS systemd installer (latest)" 2>/tmp/nb-version || { rm -f /tmp/nb-version; return; }
	VERSION=$(cat /tmp/nb-version)
	rm /tmp/nb-version
	altlinux_iso_setup "$VERSION" || return
fi
if [ "$DISTRO" = "guix" ];then
	dialog --backtitle "$TITLE" --menu "Choose a GNU Guix System version to install:" 12 70 4 \
	1.5.0 "GNU Guix System 1.5.0 (latest)" \
	1.4.0 "GNU Guix System 1.4.0" \
	1.3.0 "GNU Guix System 1.3.0" \
	Manual "Manually enter a version to install" 2>/tmp/nb-version || { rm -f /tmp/nb-version; return; }
	VERSION=$(cat /tmp/nb-version)
	rm /tmp/nb-version

	if [ "$VERSION" = "Manual" ]; then
		printf 'Version (e.g., 1.5.0): '
		read -r VERSION
		if [ -z "$VERSION" ]; then rm -f /tmp/nb-version; return 1; fi
	fi

	guix_iso_setup "$VERSION" || return
fi
if [ "$DISTRO" = "slackware" ];then
	dialog --backtitle "$TITLE" --menu "Choose a system to install:" 20 70 13 \
	slackware64-current "Slackware64-current" \
	slackware64-15.0 "Slackware 15.0" \
	slackware64-14.2 "Slackware 14.2" \
	Manual "Manually enter a version to install" 2>/tmp/nb-version || { rm -f /tmp/nb-version; return; }
	getversion || return 0
	if [ "$VERSION" = "slackware64-current" ];then
		KERNELURL="https://slackware.cs.utah.edu/pub/slackware/$VERSION/kernels/generic.s/bzImage"
		INITRDURL="https://slackware.cs.utah.edu/pub/slackware/$VERSION/isolinux/initrd.img"
		printf '%s' "rw printk.time=0 nomodeset SLACK_KERNEL=generic.s" >>/tmp/nb-options
	else
		KERNELURL="http://slackware.cs.utah.edu/pub/slackware/$VERSION/kernels/huge.s/bzImage"
		INITRDURL="http://slackware.cs.utah.edu/pub/slackware/$VERSION/isolinux/initrd.img"
		printf '%s' "load_ramdisk=1 prompt_ramdisk=0 rw" >>/tmp/nb-options
	fi
fi
if [ "$DISTRO" = "rescue" ];then
	dialog --backtitle "$TITLE" --menu "Choose a rescue tool:" 20 75 13 \
	gparted           "GParted Live 1.8.1-3" \
	clonezilla-deb    "Clonezilla Live 3.3.1 (Debian-based)" \
	rescuezilla       "Rescuezilla 2.6.1" \
	4mlinux           "4MLinux 51.0" \
	grml-full         "Grml Full 2026.04" \
	grml-small        "Grml Small 2026.04" 2>/tmp/nb-rescue || { rm -f /tmp/nb-rescue; return; }
	DISTRO=$(cat /tmp/nb-rescue)
	rm /tmp/nb-rescue
	if [ "$DISTRO" = "gparted" ];then
		BASE="https://github.com/netbootxyz/debian-squash/releases/download/1.8.1-3-5616e296"
		KERNELURL="$BASE/vmlinuz"
		INITRDURL="$BASE/initrd"
		SQUASH="$BASE/filesystem.squashfs"
		printf '%s' "boot=live fetch=$SQUASH union=overlay username=user vga=788" >>/tmp/nb-options
	fi
	if [ "$DISTRO" = "clonezilla-deb" ];then
		BASE="https://github.com/netbootxyz/debian-squash/releases/download/3.3.1-35-1a41a72c"
		KERNELURL="$BASE/vmlinuz"
		INITRDURL="$BASE/initrd"
		SQUASH="$BASE/filesystem.squashfs"
		printf '%s' "boot=live username=user union=overlay config components noswap edd=on nomodeset ocs_live_run=ocs-live-general ocs_live_batch=no net.ifnames=0 nosplash noprompt fetch=$SQUASH" >>/tmp/nb-options
	fi
	if [ "$DISTRO" = "rescuezilla" ];then
		BASE="https://github.com/netbootxyz/asset-mirror/releases/download/2.6.1-123ed276"
		KERNELURL="$BASE/vmlinuz"
		INITRDURL="$BASE/initrd"
		SQUASH="$BASE/filesystem.squashfs"
		printf '%s' "ip=dhcp boot=casper netboot=url url=$SQUASH" >>/tmp/nb-options
	fi
	if [ "$DISTRO" = "4mlinux" ];then
		BASE="https://github.com/netbootxyz/asset-mirror/releases/download/51.0-fcaac630"
		KERNELURL="$BASE/vmlinuz"
		INITRDURL="$BASE/initrd"
	fi
	if [ "$DISTRO" = "grml-full" ];then
		BASE="https://github.com/netbootxyz/debian-squash/releases/download/2026.04-23b18cd7"
		KERNELURL="$BASE/vmlinuz"
		INITRDURL="$BASE/initrd"
		SQUASH="$BASE/filesystem.squashfs"
		printf '%s' "boot=live fetch=$SQUASH" >>/tmp/nb-options
	fi
	if [ "$DISTRO" = "grml-small" ];then
		BASE="https://github.com/netbootxyz/debian-squash/releases/download/2026.04-410a8803"
		KERNELURL="$BASE/vmlinuz"
		INITRDURL="$BASE/initrd"
		SQUASH="$BASE/filesystem.squashfs"
		printf '%s' "boot=live fetch=$SQUASH" >>/tmp/nb-options
	fi
fi
askforopts
if [ -n "${ARTIX_ISO_URL:-}" ]; then
	if ! artix_prepare_from_iso "$ARTIX_ISO_URL"; then
		rm -f /tmp/nb-linux /tmp/nb-initrd /tmp/nb-initrd.* /tmp/nb-artix-overlay.cpio
		return 1
	fi
elif [ -n "${VOID_ISO_URL:-}" ]; then
	if ! void_prepare_from_iso "$VOID_ISO_URL"; then
		rm -f /tmp/nb-linux /tmp/nb-initrd /tmp/nb-void.iso
		return 1
	fi
elif [ -n "${ALTLINUX_ISO_URL:-}" ]; then
	if ! altlinux_prepare_from_iso "$ALTLINUX_ISO_URL"; then
		rm -f /tmp/nb-linux /tmp/nb-initrd /tmp/nb-altlinux.iso
		return 1
	fi
elif [ -n "${GUIX_ISO_URL:-}" ]; then
	if ! guix_prepare_from_iso "$GUIX_ISO_URL"; then
		rm -f /tmp/nb-linux /tmp/nb-initrd /tmp/nb-guix.iso
		return 1
	fi
elif [ -n "${ARCHISO_ISO_URL:-}" ]; then
	if ! archiso_prepare_from_iso "$ARCHISO_ISO_URL"; then
		rm -f /tmp/nb-linux /tmp/nb-initrd /tmp/nb-archiso.iso
		return 1
	fi
elif [ -n "${GARUDA_ISO_URL:-}" ]; then
	if ! garuda_prepare_from_iso "$GARUDA_ISO_URL"; then
		rm -f /tmp/nb-linux /tmp/nb-initrd /tmp/nb-garuda.iso
		return 1
	fi
elif [ -n "${PARABOLA_ISO_URL:-}" ]; then
	if ! parabola_prepare_from_iso "$PARABOLA_ISO_URL"; then
		rm -f /tmp/nb-linux /tmp/nb-initrd /tmp/nb-parabola.iso
		return 1
	fi
elif [ -n "${HYPERBOLA_ISO_URL:-}" ]; then
	if ! hyperbola_prepare_from_iso "$HYPERBOLA_ISO_URL"; then
		rm -f /tmp/nb-linux /tmp/nb-initrd /tmp/nb-hyperbola.iso
		return 1
	fi
elif [ -n "${MOCACCINO_ISO_URL:-}" ]; then
	if ! mocaccino_prepare_from_iso "$MOCACCINO_ISO_URL"; then
		rm -f /tmp/nb-linux /tmp/nb-initrd /tmp/nb-mocaccino.iso
		return 1
	fi
elif [ -n "${PIKA_ISO_URL:-}" ]; then
	if ! pika_prepare_from_iso "$PIKA_ISO_URL"; then
		rm -f /tmp/nb-linux /tmp/nb-initrd /tmp/nb-pika.iso
		return 1
	fi
elif [ -n "${PORTEUX_ISO_URL:-}" ]; then
	if ! porteux_prepare_from_iso "$PORTEUX_ISO_URL"; then
		rm -f /tmp/nb-linux /tmp/nb-initrd /tmp/nb-porteux.iso
		return 1
	fi
elif [ -n "${PORTEUS_ISO_URL:-}" ]; then
	if ! porteus_prepare_from_iso "$PORTEUS_ISO_URL"; then
		rm -f /tmp/nb-linux /tmp/nb-initrd /tmp/nb-porteus.iso
		return 1
	fi
elif [ -n "${NEMESIS_ISO_URL:-}" ]; then
	if ! nemesis_prepare_from_iso "$NEMESIS_ISO_URL"; then
		rm -f /tmp/nb-linux /tmp/nb-initrd /tmp/nb-nemesis.iso
		return 1
	fi
elif [ -n "${CHIMERA_ISO_URL:-}" ]; then
	if ! chimera_prepare_from_iso "$CHIMERA_ISO_URL"; then
		rm -f /tmp/nb-linux /tmp/nb-initrd /tmp/nb-chimera.iso
		return 1
	fi
elif [ -n "${COYOTE_ISO_URL:-}" ]; then
	if ! coyote_prepare_from_iso "$COYOTE_ISO_URL"; then
		rm -f /tmp/nb-linux /tmp/nb-initrd /tmp/nb-coyote.iso
		return 1
	fi
elif [ -n "${NUTYX_ISO_URL:-}" ]; then
	if ! nutyx_prepare_from_iso "$NUTYX_ISO_URL"; then
		rm -f /tmp/nb-linux /tmp/nb-initrd /tmp/nb-nutyx.iso
		return 1
	fi
elif [ -n "${SALIX_ISO_URL:-}" ]; then
	if ! salix_prepare_from_iso "$SALIX_ISO_URL"; then
		rm -f /tmp/nb-linux /tmp/nb-initrd /tmp/nb-salix.iso
		return 1
	fi
elif [ -n "${DAPHILE_ISO_URL:-}" ]; then
	if ! daphile_prepare_from_iso "$DAPHILE_ISO_URL"; then
		rm -f /tmp/nb-linux /tmp/nb-initrd /tmp/nb-daphile.iso
		return 1
	fi
elif [ -n "${BERRY_ISO_URL:-}" ]; then
	if ! berry_prepare_from_iso; then
		rm -f /tmp/nb-linux /tmp/nb-initrd /tmp/nb-berry.iso
		return 1
	fi
elif [ -n "${VENOM_ISO_URL:-}" ]; then
	if ! venom_prepare_from_iso "$VENOM_ISO_URL"; then
		rm -f /tmp/nb-linux /tmp/nb-initrd /tmp/nb-venom.iso
		return 1
	fi
elif [ -n "${PUPPY_ISO_URL:-}" ]; then
	if ! puppy_prepare_from_iso "$PUPPY_ISO_URL"; then
		rm -f /tmp/nb-linux /tmp/nb-initrd /tmp/nb-puppy.iso
		return 1
	fi
elif [ -n "${EASYOS_IMG_URL:-}" ]; then
	if ! easyos_prepare_from_img "$EASYOS_IMG_URL"; then
		rm -f /tmp/nb-linux /tmp/nb-initrd /tmp/nb-easyos.img
		return 1
	fi
elif [ -n "${LIBREELEC_IMG_URL:-}" ]; then
	if ! libreelec_prepare_from_img "$LIBREELEC_IMG_URL"; then
		rm -f /tmp/nb-linux /tmp/nb-initrd
		return 1
	fi
elif [ -n "${ISO_BOOT_URL:-}" ]; then
	if ! iso_boot_prepare_from_iso; then
		rm -f /tmp/nb-linux /tmp/nb-initrd /tmp/nb-iso-boot.iso
		return 1
	fi
elif [ -n "${ANTIX_MX_ISO_URL:-}" ]; then
	if ! antix_mx_prepare_from_iso "$ANTIX_MX_ISO_URL"; then
		rm -f /tmp/nb-linux /tmp/nb-initrd /tmp/nb-antix-mx.iso
		return 1
	fi
elif [ -n "${DEBIAN_LIVE_ISO_URL:-}" ]; then
	if ! debian_live_prepare_from_iso "$DEBIAN_LIVE_ISO_URL"; then
		rm -f /tmp/nb-linux /tmp/nb-initrd /tmp/nb-debian-live.iso
		return 1
	fi
else
	if [ -z "${KERNELURL:-}" ]; then
		dialog --backtitle "$TITLE" --msgbox \
			"No kernel URL was selected for this entry." 6 50 || true
		rm -f /tmp/nb-linux /tmp/nb-initrd
		return 1
	fi
	if ! wgetgauge "$KERNELURL" /tmp/nb-linux "Downloading kernel"; then
		dialog --backtitle "$TITLE" --msgbox \
			"Could not download kernel from:\n\n$KERNELURL" 9 70 || true
		rm -f /tmp/nb-linux /tmp/nb-initrd
		return 1
	fi
	if [ -n "${INITRDURL:-}" ]; then
		rm -f /tmp/nb-initrd /tmp/nb-initrd.*
		_INITRD_COUNT=0
		# INITRDURL may contain multiple space-separated initrd fragments.
		# BusyBox ash has no arrays, so split intentionally on spaces here.
		for _INITRD_URL in $INITRDURL; do
			_INITRD_COUNT=$(( _INITRD_COUNT + 1 ))
			_INITRD_OUT="/tmp/nb-initrd.$_INITRD_COUNT"
			if ! wgetgauge "$_INITRD_URL" "$_INITRD_OUT" "Downloading initrd"; then
				dialog --backtitle "$TITLE" --msgbox \
					"Could not download initrd from:\n\n$_INITRD_URL" 9 70 || true
				rm -f /tmp/nb-linux /tmp/nb-initrd /tmp/nb-initrd.*
				return 1
			fi
		done
		combine_initrd_fragments "$_INITRD_COUNT"
	fi
fi
}


while true; do
	dialog --backtitle "$TITLE" --menu "What would you like to do?" 16 70 9 \
	install "Install or boot a Linux system" \
	update  "Download and run newest nbscript.sh" \
	wifi    "Configure wireless network" \
	ipaddr  "View/release IP address" \
	quit    "Quit to prompt (do not reboot)" 2>/tmp/nb-mainmenu || { rm -f /tmp/nb-mainmenu; continue; }
	MAINMENU=$(cat /tmp/nb-mainmenu)
	rm /tmp/nb-mainmenu
	if [ "$MAINMENU" = quit ]; then
		exit 1
	fi
	if [ "$MAINMENU" = "install" ]; then
		true>/tmp/nb-options
		true>/tmp/nb-custom
		rm -f /tmp/nb-linux /tmp/nb-initrd
		installmenu || true
		if [ -f /tmp/nb-linux ]; then break; fi
		continue
	fi
	if [ "$MAINMENU" = "update" ]; then
		downloadandrun "$NBSCRIPT_UPDATE_URL" || true
		continue
	fi
	if [ "$MAINMENU" = "wifi" ]; then
		wifimenu || true
		exec "$0" "$@"
	fi
	if [ "$MAINMENU" = "ipaddr" ]; then
		ipadrmenu || true
		continue
	fi
done
if [ -f /tmp/nb-initrd ]; then
	ARGS="-l /tmp/nb-linux --initrd=/tmp/nb-initrd $OPTIONS $CUSTOM"
else
	ARGS="-l /tmp/nb-linux $OPTIONS $CUSTOM"
fi

if [ "$DISTRO" = "rhel-type-5" ];then
	ARGS=$ARGS" --args-linux"
fi
if [ "$EFIMODE" = 1 ]; then
	case "$DISTRO" in
		fedora64|rhel-type-*-64)
			printf '%s' ' inst.efi' >>/tmp/nb-options
			;;
	esac
fi
if [ -d /home/tc ];then
	CMDLINE="$(cat /tmp/nb-options) $(cat /tmp/nb-custom)"

	dialog --backtitle "$TITLE" --title " Executing " --infobox \
"kexec $ARGS --command-line=\"$CMDLINE\"

Loading kernel and booting new system..." 15 80 || true

	# On UEFI systems, prefer kexec_file_load (-s) which preserves the EFI
	# memory map and system table for the incoming kernel.  Fall back to the
	# classic kexec_load syscall if -s is not compiled in (e.g. 32-bit kernel).
	rm -f /tmp/nb-kexec.log
	_krc=0
	if [ "$EFIMODE" = 1 ] && kexec --help 2>&1 | grep -q -- '-s'; then
		kexec -s $ARGS --command-line="$CMDLINE" >>/tmp/nb-kexec.log 2>&1 || \
			kexec $ARGS --command-line="$CMDLINE" >>/tmp/nb-kexec.log 2>&1 || \
			_krc=$?
	else
		kexec $ARGS --command-line="$CMDLINE" >>/tmp/nb-kexec.log 2>&1 || _krc=$?
	fi

	if [ "$_krc" -ne 0 ]; then
		dialog --backtitle "$TITLE" --title " kexec load failed " \
			--textbox /tmp/nb-kexec.log 20 80 || true
		rm -f /tmp/nb-kexec.log
		exit "$_krc"
	fi
	rm -f /tmp/nb-kexec.log

	sleep 5
	sync
	clear
	kexec -e
fi
