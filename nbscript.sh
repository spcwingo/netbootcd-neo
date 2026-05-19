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

TITLE="NetbootCD-Neo Script 17.1 - May 11, 2026"

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
	echo -n "root=/dev/ram0 ramdisk_size=3500000 ip=dhcp url=$ISOURL cloud-config-url=/dev/null ---" >>/tmp/nb-options
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
	DEBIAN_LIVE_INITRD_PATHS="casper/initrd casper/initrd.lz casper/initrd.img casper/initrd.gz casper/initrd.zst live/initrd live/initrd.lz live/initrd.img live/initrd.gz live/initrd.zst boot/initrd boot/initrd.lz boot/initrd.img boot/initrd.gz boot/initrd.zst"
	echo -n "ip=dhcp boot=casper netboot=url url=$DEBIAN_LIVE_BOOT_URL iso-url=$DEBIAN_LIVE_BOOT_URL noprompt noeject $3 " >>/tmp/nb-options
}

dracut_live_iso_setup ()
{
	DEBIAN_LIVE_LABEL="$1"
	DEBIAN_LIVE_ISO_URL="$2"
	DEBIAN_LIVE_BOOT_URL="$2"
	DEBIAN_LIVE_MODE=embed
	DEBIAN_LIVE_KERNEL_PATHS="images/pxeboot/vmlinuz isolinux/vmlinuz boot/kernel boot/vmlinuz boot/vmlinuz-*"
	DEBIAN_LIVE_INITRD_PATHS="images/pxeboot/initrd.img isolinux/initrd.img boot/initramfs.img boot/initrd.img boot/initrd boot/initrd-*"
	DEBIAN_LIVE_ROOTFS_PATHS="LiveOS/squashfs.img"
	DEBIAN_LIVE_EMBED_ROOTFS_PATH="LiveOS/squashfs.img"
	echo -n "root=live:/LiveOS/squashfs.img ro rd.live.image rd.live.overlay.overlayfs=1 rd.luks=0 rd.md=0 rd.dm=0 $3 " >>/tmp/nb-options
}

pika_iso_setup ()
{
	PIKA_LABEL="$1"
	PIKA_ISO_URL="$2"
	PIKA_ISO_FILE="$3"
	PIKA_ISO_VOLUME="$4"
	echo -n "VTOY_ISO_NAME=$PIKA_ISO_FILE ISO_LABEL_NAME=\"$PIKA_ISO_VOLUME\" boot=live booster.loadcdrom booster.skiproot " >>/tmp/nb-options
}

community_live_iso_setup ()
{
	_community_live_tag="$1"

	case "$_community_live_tag" in
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
		solus-xfce)
			dracut_live_iso_setup \
				"Solus Xfce 2026-04-18" \
				"https://downloads.getsol.us/isos/2026-04-18/Solus-Xfce-Release-2026-04-18.iso" \
				"quiet splash" || return
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

DEBIAN_LIVE_KERNEL_PATHS="live/vmlinuz live/vmlinuz-* boot/vmlinuz boot/vmlinuz-*"
DEBIAN_LIVE_INITRD_PATHS="live/initrd.img live/initrd live/initrd.gz live/initrd.lz live/initrd.xz live/initrd.zst live/initrd.img-* live/initrd-* boot/initrd.img boot/initrd boot/initrd.gz boot/initrd.lz boot/initrd.xz boot/initrd.zst boot/initrd.img-* boot/initrd-*"
DEBIAN_LIVE_ROOTFS_PATHS="live/filesystem.squashfs live/filesystem.squashfs-* live/*.squashfs"
DEBIAN_LIVE_EMBED_ROOTFS_PATH="live/filesystem.squashfs"

debian_live_iso_setup ()
{
	_debian_live_tag="$1"
	DEBIAN_LIVE_ISO_URL=
	DEBIAN_LIVE_BOOT_URL=
	DEBIAN_LIVE_LABEL=
	DEBIAN_LIVE_MODE=fetch
	DEBIAN_LIVE_OPTIONS=
	DEBIAN_LIVE_KERNEL_PATHS="live/vmlinuz live/vmlinuz-* boot/vmlinuz boot/vmlinuz-*"
	DEBIAN_LIVE_INITRD_PATHS="live/initrd.img live/initrd live/initrd.gz live/initrd.lz live/initrd.xz live/initrd.zst live/initrd.img-* live/initrd-* boot/initrd.img boot/initrd boot/initrd.gz boot/initrd.lz boot/initrd.xz boot/initrd.zst boot/initrd.img-* boot/initrd-*"
	DEBIAN_LIVE_ROOTFS_PATHS="live/filesystem.squashfs live/filesystem.squashfs-* live/*.squashfs"
	DEBIAN_LIVE_EMBED_ROOTFS_PATH="live/filesystem.squashfs"

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
		emmabuntus-de6-core)
			DEBIAN_LIVE_LABEL="Emmabuntus DE6 Core"
			DEBIAN_LIVE_ISO_URL="http://cfhcable.dl.sourceforge.net/project/emmabuntus/Emmabuntus_DE6/Images/1.01/emmabuntus-de6-core-amd64-13.4-1.01.iso?viasf=1&fid=d15787c9fd137e59"
			DEBIAN_LIVE_BOOT_URL="http://downloads.sourceforge.net/project/emmabuntus/Emmabuntus_DE6/Images/1.01/emmabuntus-de6-core-amd64-13.4-1.01.iso"
			DEBIAN_LIVE_OPTIONS="username=user hostname=emmabuntus"
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
		refracta-*)
			DEBIAN_LIVE_MODE=embed
			;;
	esac

	if [ "$DEBIAN_LIVE_MODE" = "embed" ]; then
		echo -n "boot=live config components live-media=/ noeject noprompt $DEBIAN_LIVE_OPTIONS " >>/tmp/nb-options
	elif [ "$DEBIAN_LIVE_MODE" = "minios-embed" ]; then
		echo -n "boot=live $DEBIAN_LIVE_OPTIONS " >>/tmp/nb-options
	else
		echo -n "ip=dhcp boot=live config components fetch=$DEBIAN_LIVE_BOOT_URL ramdisk-size=85% noeject noprompt $DEBIAN_LIVE_OPTIONS " >>/tmp/nb-options
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

	if [ "$_debian_live_format" = "zstd" ] && ! command -v zstd >/dev/null 2>&1; then
		nb_error "$DEBIAN_LIVE_LABEL initramfs uses zstd compression, but zstd is not available."
		return 1
	fi
	if [ "$_debian_live_format" = "xz" ] && ! command -v xz >/dev/null 2>&1; then
		nb_error "$DEBIAN_LIVE_LABEL initramfs uses xz compression, but xz is not available."
		return 1
	fi

	rm -rf "$_debian_live_work" "$_debian_live_repacked" "$_debian_live_new" "$_debian_live_final"
	mkdir -p "$_debian_live_work"

	case "$_debian_live_format" in
		gzip)
			if ! ( tail -c +"$(( _debian_live_main_offset + 1 ))" /tmp/nb-initrd | gzip -cd | ( cd "$_debian_live_work" && cpio -idm ) ); then
				nb_error "Could not unpack the $DEBIAN_LIVE_LABEL gzip initramfs."
				rm -rf "$_debian_live_work"
				return 1
			fi
			;;
		zstd)
			if ! ( tail -c +"$(( _debian_live_main_offset + 1 ))" /tmp/nb-initrd | zstd -dc | ( cd "$_debian_live_work" && cpio -idm ) ); then
				nb_error "Could not unpack the $DEBIAN_LIVE_LABEL zstd initramfs."
				rm -rf "$_debian_live_work"
				return 1
			fi
			;;
		xz)
			if ! ( tail -c +"$(( _debian_live_main_offset + 1 ))" /tmp/nb-initrd | xz -dc | ( cd "$_debian_live_work" && cpio -idm ) ); then
				nb_error "Could not unpack the $DEBIAN_LIVE_LABEL xz initramfs."
				rm -rf "$_debian_live_work"
				return 1
			fi
			;;
		cpio)
			if ! ( tail -c +"$(( _debian_live_main_offset + 1 ))" /tmp/nb-initrd | ( cd "$_debian_live_work" && cpio -idm ) ); then
				nb_error "Could not unpack the $DEBIAN_LIVE_LABEL cpio initramfs."
				rm -rf "$_debian_live_work"
				return 1
			fi
		;;
	esac

	_debian_live_embed_rootfs="$_debian_live_work/$DEBIAN_LIVE_EMBED_ROOTFS_PATH"
	_debian_live_embed_rootfs_dir="${_debian_live_embed_rootfs%/*}"
	mkdir -p "$_debian_live_embed_rootfs_dir"
	if ! mv "$_debian_live_rootfs" "$_debian_live_embed_rootfs"; then
		nb_error "Could not add the $DEBIAN_LIVE_LABEL live filesystem to the initramfs."
		rm -rf "$_debian_live_work"
		return 1
	fi

	case "$_debian_live_format" in
		gzip)
			if ! ( cd "$_debian_live_work" && find . | cpio -o -H newc | gzip -1 -c >"$_debian_live_repacked" ); then
				nb_error "Could not repack the $DEBIAN_LIVE_LABEL gzip initramfs."
				rm -rf "$_debian_live_work"
				return 1
			fi
			;;
		zstd)
			if ! ( cd "$_debian_live_work" && find . | cpio -o -H newc | zstd -q -c >"$_debian_live_repacked" ); then
				nb_error "Could not repack the $DEBIAN_LIVE_LABEL zstd initramfs."
				rm -rf "$_debian_live_work"
				return 1
			fi
			;;
		xz)
			if ! ( cd "$_debian_live_work" && find . | cpio -o -H newc | xz --check=crc32 --lzma2=dict=1MiB -c >"$_debian_live_repacked" ); then
				nb_error "Could not repack the $DEBIAN_LIVE_LABEL xz initramfs."
				rm -rf "$_debian_live_work"
				return 1
			fi
			;;
		cpio)
			if ! ( cd "$_debian_live_work" && find . | cpio -o -H newc >"$_debian_live_repacked" ); then
				nb_error "Could not repack the $DEBIAN_LIVE_LABEL cpio initramfs."
				rm -rf "$_debian_live_work"
				return 1
			fi
			;;
	esac

	rm -rf "$_debian_live_work"

	: >"$_debian_live_new"
	if [ "$_debian_live_main_offset" -gt 0 ]; then
		if ! head -c "$_debian_live_main_offset" /tmp/nb-initrd >>"$_debian_live_new"; then
			nb_error "Could not preserve the $DEBIAN_LIVE_LABEL early initramfs prefix."
			rm -rf "$_debian_live_work" "$_debian_live_repacked" "$_debian_live_new"
			return 1
		fi
	fi
	if ! cat "$_debian_live_repacked" >>"$_debian_live_new"; then
		nb_error "Could not write the repacked $DEBIAN_LIVE_LABEL initramfs."
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

	if [ "$_debian_live_format" = "zstd" ] && ! command -v zstd >/dev/null 2>&1; then
		nb_error "$DEBIAN_LIVE_LABEL initramfs uses zstd compression, but zstd is not available."
		return 1
	fi
	if [ "$_debian_live_format" = "xz" ] && ! command -v xz >/dev/null 2>&1; then
		nb_error "$DEBIAN_LIVE_LABEL initramfs uses xz compression, but xz is not available."
		return 1
	fi

	rm -rf "$_debian_live_work" "$_debian_live_repacked" "$_debian_live_new" "$_debian_live_final"
	mkdir -p "$_debian_live_work"

	case "$_debian_live_format" in
		gzip)
			if ! ( tail -c +"$(( _debian_live_main_offset + 1 ))" /tmp/nb-initrd | gzip -cd | ( cd "$_debian_live_work" && cpio -idm ) ); then
				nb_error "Could not unpack the $DEBIAN_LIVE_LABEL gzip initramfs."
				rm -rf "$_debian_live_work"
				return 1
			fi
			;;
		zstd)
			if ! ( tail -c +"$(( _debian_live_main_offset + 1 ))" /tmp/nb-initrd | zstd -dc | ( cd "$_debian_live_work" && cpio -idm ) ); then
				nb_error "Could not unpack the $DEBIAN_LIVE_LABEL zstd initramfs."
				rm -rf "$_debian_live_work"
				return 1
			fi
			;;
		xz)
			if ! ( tail -c +"$(( _debian_live_main_offset + 1 ))" /tmp/nb-initrd | xz -dc | ( cd "$_debian_live_work" && cpio -idm ) ); then
				nb_error "Could not unpack the $DEBIAN_LIVE_LABEL xz initramfs."
				rm -rf "$_debian_live_work"
				return 1
			fi
			;;
		cpio)
			if ! ( tail -c +"$(( _debian_live_main_offset + 1 ))" /tmp/nb-initrd | ( cd "$_debian_live_work" && cpio -idm ) ); then
				nb_error "Could not unpack the $DEBIAN_LIVE_LABEL cpio initramfs."
				rm -rf "$_debian_live_work"
				return 1
			fi
			;;
	esac

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

	case "$_debian_live_format" in
		gzip)
			if ! ( cd "$_debian_live_work" && find . | cpio -o -H newc | gzip -1 -c >"$_debian_live_repacked" ); then
				nb_error "Could not repack the $DEBIAN_LIVE_LABEL gzip initramfs."
				rm -rf "$_debian_live_work"
				return 1
			fi
			;;
		zstd)
			if ! ( cd "$_debian_live_work" && find . | cpio -o -H newc | zstd -q -c >"$_debian_live_repacked" ); then
				nb_error "Could not repack the $DEBIAN_LIVE_LABEL zstd initramfs."
				rm -rf "$_debian_live_work"
				return 1
			fi
			;;
		xz)
			if ! ( cd "$_debian_live_work" && find . | cpio -o -H newc | xz --check=crc32 --lzma2=dict=1MiB -c >"$_debian_live_repacked" ); then
				nb_error "Could not repack the $DEBIAN_LIVE_LABEL xz initramfs."
				rm -rf "$_debian_live_work"
				return 1
			fi
			;;
		cpio)
			if ! ( cd "$_debian_live_work" && find . | cpio -o -H newc >"$_debian_live_repacked" ); then
				nb_error "Could not repack the $DEBIAN_LIVE_LABEL cpio initramfs."
				rm -rf "$_debian_live_work"
				return 1
			fi
			;;
	esac

	: >"$_debian_live_new"
	if [ "$_debian_live_main_offset" -gt 0 ]; then
		if ! head -c "$_debian_live_main_offset" /tmp/nb-initrd >>"$_debian_live_new"; then
			nb_error "Could not preserve the $DEBIAN_LIVE_LABEL early initramfs prefix."
			rm -rf "$_debian_live_work" "$_debian_live_repacked" "$_debian_live_new"
			return 1
		fi
	fi
	if ! cat "$_debian_live_repacked" >>"$_debian_live_new"; then
		nb_error "Could not write the repacked $DEBIAN_LIVE_LABEL initramfs."
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
		embed) ;;
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

	if [ "$_pika_format" = "zstd" ] && ! command -v zstd >/dev/null 2>&1; then
		nb_error "$PIKA_LABEL initramfs uses zstd compression, but zstd is not available."
		return 1
	fi
	if [ "$_pika_format" = "xz" ] && ! command -v xz >/dev/null 2>&1; then
		nb_error "$PIKA_LABEL initramfs uses xz compression, but xz is not available."
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

	case "$_pika_format" in
		gzip)
			if ! ( cd "$_pika_work" && find . | cpio -o -H newc | gzip -1 -c >"$_pika_repacked" ); then
				nb_error "Could not repack the $PIKA_LABEL gzip initramfs."
				rm -rf "$_pika_work"
				return 1
			fi
			;;
		zstd)
			if ! ( cd "$_pika_work" && find . | cpio -o -H newc | zstd -q -c >"$_pika_repacked" ); then
				nb_error "Could not repack the $PIKA_LABEL zstd initramfs."
				rm -rf "$_pika_work"
				return 1
			fi
			;;
		xz)
			if ! ( cd "$_pika_work" && find . | cpio -o -H newc | xz --check=crc32 --lzma2=dict=1MiB -c >"$_pika_repacked" ); then
				nb_error "Could not repack the $PIKA_LABEL xz initramfs."
				rm -rf "$_pika_work"
				return 1
			fi
			;;
		cpio)
			if ! ( cd "$_pika_work" && find . | cpio -o -H newc >"$_pika_repacked" ); then
				nb_error "Could not repack the $PIKA_LABEL cpio initramfs."
				rm -rf "$_pika_work"
				return 1
			fi
			;;
	esac

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

ARTIX_ISO_BASE="http://mirrors.ocf.berkeley.edu/artix-iso"
VOID_ISO_BASE="http://repo-fastly.voidlinux.org/live/current"
ALTLINUX_ISO_BASE="http://nightly.altlinux.org/sisyphus/current"
GUIX_ISO_BASE="https://ftp.gnu.org/gnu/guix"

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
		mx-25.1-xfce) printf '%s\n' 'mx-linux/Final/Xfce/MX-25.1_Xfce_x64.iso' ;;
		mx-25.1-xfce-ahs) printf '%s\n' 'mx-linux/Final/Xfce/MX-25.1_Xfce_ahs_x64.iso' ;;
		*) return 1 ;;
	esac
}

antix_mx_iso_label ()
{
	case "$1" in
		antix-26-core) printf '%s\n' 'antiX 26 Core' ;;
		mx-25.1-xfce) printf '%s\n' 'MX Linux 25.1 Xfce' ;;
		mx-25.1-xfce-ahs) printf '%s\n' 'MX Linux 25.1 Xfce AHS' ;;
		*) return 1 ;;
	esac
}

antix_mx_iso_url ()
{
	_antix_mx_iso_file="$1"
	printf 'http://downloads.sourceforge.net/project/%s\n' "$_antix_mx_iso_file"
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
	echo -n "from=all try=60 load=all sq=antiX/linuxfs quiet " >>/tmp/nb-options
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

	if [ "$_antix_mx_format" = "zstd" ] && ! command -v zstd >/dev/null 2>&1; then
		nb_error "$ANTIX_MX_LABEL initramfs uses zstd compression, but zstd is not available."
		return 1
	fi
	if [ "$_antix_mx_format" = "xz" ] && ! command -v xz >/dev/null 2>&1; then
		nb_error "$ANTIX_MX_LABEL initramfs uses xz compression, but xz is not available."
		return 1
	fi

	rm -rf "$_antix_mx_work" "$_antix_mx_repacked"
	mkdir -p "$_antix_mx_work"

	case "$_antix_mx_format" in
		gzip)
			if ! ( tail -c +"$(( _antix_mx_main_offset + 1 ))" /tmp/nb-initrd | gzip -cd | ( cd "$_antix_mx_work" && cpio -idm ) ); then
				nb_error "Could not unpack the $ANTIX_MX_LABEL gzip initramfs."
				rm -rf "$_antix_mx_work"
				return 1
			fi
			;;
		zstd)
			if ! ( tail -c +"$(( _antix_mx_main_offset + 1 ))" /tmp/nb-initrd | zstd -dc | ( cd "$_antix_mx_work" && cpio -idm ) ); then
				nb_error "Could not unpack the $ANTIX_MX_LABEL zstd initramfs."
				rm -rf "$_antix_mx_work"
				return 1
			fi
			;;
		xz)
			if ! ( tail -c +"$(( _antix_mx_main_offset + 1 ))" /tmp/nb-initrd | xz -dc | ( cd "$_antix_mx_work" && cpio -idm ) ); then
				nb_error "Could not unpack the $ANTIX_MX_LABEL xz initramfs."
				rm -rf "$_antix_mx_work"
				return 1
			fi
			;;
		cpio)
			if ! ( tail -c +"$(( _antix_mx_main_offset + 1 ))" /tmp/nb-initrd | ( cd "$_antix_mx_work" && cpio -idm ) ); then
				nb_error "Could not unpack the $ANTIX_MX_LABEL cpio initramfs."
				rm -rf "$_antix_mx_work"
				return 1
			fi
			;;
	esac

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

	case "$_antix_mx_format" in
		gzip)
			if ! ( cd "$_antix_mx_work" && find . | cpio -o -H newc | gzip -1 -c >"$_antix_mx_repacked" ); then
				nb_error "Could not repack the $ANTIX_MX_LABEL gzip initramfs."
				rm -rf "$_antix_mx_work"
				return 1
			fi
			;;
		zstd)
			if ! ( cd "$_antix_mx_work" && find . | cpio -o -H newc | zstd -q -c >"$_antix_mx_repacked" ); then
				nb_error "Could not repack the $ANTIX_MX_LABEL zstd initramfs."
				rm -rf "$_antix_mx_work"
				return 1
			fi
			;;
		xz)
			if ! ( cd "$_antix_mx_work" && find . | cpio -o -H newc | xz --check=crc32 --lzma2=dict=1MiB -c >"$_antix_mx_repacked" ); then
				nb_error "Could not repack the $ANTIX_MX_LABEL xz initramfs."
				rm -rf "$_antix_mx_work"
				return 1
			fi
			;;
		cpio)
			if ! ( cd "$_antix_mx_work" && find . | cpio -o -H newc >"$_antix_mx_repacked" ); then
				nb_error "Could not repack the $ANTIX_MX_LABEL cpio initramfs."
				rm -rf "$_antix_mx_work"
				return 1
			fi
			;;
	esac

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
	echo -n "root=live:/LiveOS/squashfs.img init=/sbin/init ro rd.luks=0 rd.md=0 rd.dm=0 rd.live.overlay.overlayfs=1 loglevel=4 vconsole.unicode=1 locale.LANG=en_US.UTF-8 " >>/tmp/nb-options
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

	case "$_void_format" in
		gzip)
			if ! ( tail -c +"$(( _void_main_offset + 1 ))" /tmp/nb-initrd | gzip -cd | ( cd "$_void_work" && cpio -idm ) ); then
				nb_error "Could not unpack the Void Linux gzip initramfs."
				rm -rf "$_void_work"
				return 1
			fi
			;;
		zstd)
			if ! ( tail -c +"$(( _void_main_offset + 1 ))" /tmp/nb-initrd | zstd -dc | ( cd "$_void_work" && cpio -idm ) ); then
				nb_error "Could not unpack the Void Linux zstd initramfs."
				rm -rf "$_void_work"
				return 1
			fi
			;;
		xz)
			if ! ( tail -c +"$(( _void_main_offset + 1 ))" /tmp/nb-initrd | xz -dc | ( cd "$_void_work" && cpio -idm ) ); then
				nb_error "Could not unpack the Void Linux xz initramfs."
				rm -rf "$_void_work"
				return 1
			fi
			;;
		cpio)
			if ! ( tail -c +"$(( _void_main_offset + 1 ))" /tmp/nb-initrd | ( cd "$_void_work" && cpio -idm ) ); then
				nb_error "Could not unpack the Void Linux cpio initramfs."
				rm -rf "$_void_work"
				return 1
			fi
			;;
	esac

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

	case "$_void_format" in
		gzip)
			if ! ( cd "$_void_work" && find . | cpio -o -H newc | gzip -c >"$_void_repacked" ); then
				nb_error "Could not repack the Void Linux gzip initramfs."
				rm -rf "$_void_work"
				return 1
			fi
			;;
		zstd)
			if ! ( cd "$_void_work" && find . | cpio -o -H newc | zstd -q -c >"$_void_repacked" ); then
				nb_error "Could not repack the Void Linux zstd initramfs."
				rm -rf "$_void_work"
				return 1
			fi
			;;
		xz)
			if ! ( cd "$_void_work" && find . | cpio -o -H newc | xz --check=crc32 --lzma2=dict=1MiB -c >"$_void_repacked" ); then
				nb_error "Could not repack the Void Linux xz initramfs."
				rm -rf "$_void_work"
				return 1
			fi
			;;
		cpio)
			if ! ( cd "$_void_work" && find . | cpio -o -H newc >"$_void_repacked" ); then
				nb_error "Could not repack the Void Linux cpio initramfs."
				rm -rf "$_void_work"
				return 1
			fi
			;;
	esac

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
	echo -n "fastboot live root=bootchain bootchain=fg,altboot ip=dhcp automatic=method:http,type:iso,server:nightly.altlinux.org,directory:$_altlinux_stage_iso_path stagename=live systemd.unit=install2.target lowmem lang=en_US " >>/tmp/nb-options
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

	if [ "$_guix_format" = "zstd" ] && ! command -v zstd >/dev/null 2>&1; then
		nb_error "$GUIX_LABEL initramfs uses zstd compression, but zstd is not available."
		return 1
	fi
	if [ "$_guix_format" = "xz" ] && ! command -v xz >/dev/null 2>&1; then
		nb_error "$GUIX_LABEL initramfs uses xz compression, but xz is not available."
		return 1
	fi

	rm -rf "$_guix_work" "$_guix_repacked"
	mkdir -p "$_guix_work"

	case "$_guix_format" in
		gzip)
			if ! ( tail -c +"$(( _guix_main_offset + 1 ))" /tmp/nb-initrd | gzip -cd | ( cd "$_guix_work" && cpio -idmu ) ); then
				nb_error "Could not unpack the $GUIX_LABEL gzip initramfs."
				rm -rf "$_guix_work"
				return 1
			fi
			;;
		zstd)
			if ! ( tail -c +"$(( _guix_main_offset + 1 ))" /tmp/nb-initrd | zstd -dc | ( cd "$_guix_work" && cpio -idmu ) ); then
				nb_error "Could not unpack the $GUIX_LABEL zstd initramfs."
				rm -rf "$_guix_work"
				return 1
			fi
			;;
		xz)
			if ! ( tail -c +"$(( _guix_main_offset + 1 ))" /tmp/nb-initrd | xz -dc | ( cd "$_guix_work" && cpio -idmu ) ); then
				nb_error "Could not unpack the $GUIX_LABEL xz initramfs."
				rm -rf "$_guix_work"
				return 1
			fi
			;;
		cpio)
			if ! ( tail -c +"$(( _guix_main_offset + 1 ))" /tmp/nb-initrd | ( cd "$_guix_work" && cpio -idmu ) ); then
				nb_error "Could not unpack the $GUIX_LABEL cpio initramfs."
				rm -rf "$_guix_work"
				return 1
			fi
			;;
	esac

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

	case "$_guix_format" in
		gzip)
			if ! ( cd "$_guix_work" && find . | cpio -o -H newc | gzip -1 -c >"$_guix_repacked" ); then
				nb_error "Could not repack the $GUIX_LABEL gzip initramfs."
				rm -rf "$_guix_work"
				return 1
			fi
			;;
		zstd)
			if ! ( cd "$_guix_work" && find . | cpio -o -H newc | zstd -q -c >"$_guix_repacked" ); then
				nb_error "Could not repack the $GUIX_LABEL zstd initramfs."
				rm -rf "$_guix_work"
				return 1
			fi
			;;
		xz)
			if ! ( cd "$_guix_work" && find . | cpio -o -H newc | xz --check=crc32 --lzma2=dict=1MiB -c >"$_guix_repacked" ); then
				nb_error "Could not repack the $GUIX_LABEL xz initramfs."
				rm -rf "$_guix_work"
				return 1
			fi
			;;
		cpio)
			if ! ( cd "$_guix_work" && find . | cpio -o -H newc >"$_guix_repacked" ); then
				nb_error "Could not repack the $GUIX_LABEL cpio initramfs."
				rm -rf "$_guix_work"
				return 1
			fi
			;;
	esac

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
	echo -n "ip=dhcp artix_iso_url=$ARTIX_ISO_URL$(artix_dns_option) " >>/tmp/nb-options
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
	_artix_blocks_file="/tmp/nb-artix-cpio-blocks"

	rm -f "$_artix_blocks_file"
	if ! ( cpio -t <"$_artix_initrd" >/dev/null 2>"$_artix_blocks_file" ); then
		rm -f "$_artix_blocks_file"
		return 1
	fi
	_artix_blocks=$(sed -n 's/^\([0-9][0-9]*\)[[:space:]]*blocks.*/\1/p' "$_artix_blocks_file" | tail -1)
	rm -f "$_artix_blocks_file"
	case "$_artix_blocks" in
		''|*[!0-9]*) return 1 ;;
	esac
	printf '%s\n' "$(( _artix_blocks * 512 ))"
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

	if ! _artix_scan=$(artix_cpio_blocks_offset "$_artix_initrd"); then
		printf '%s %s\n' cpio 0
		return 0
	fi
	_artix_size=$(artix_file_size "$_artix_initrd")
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
			printf '%s %s\n' "$_artix_tail_format" "$_artix_scan"
			return 0
		fi
		break
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

	case "$_artix_format" in
		gzip)
			if ! ( tail -c +"$(( _artix_main_offset + 1 ))" "$_artix_last" | gzip -cd | ( cd "$_artix_work" && cpio -idm ) ); then
				nb_error "Could not unpack the Artix gzip initramfs."
				rm -rf "$_artix_work"
				return 1
			fi
			;;
		zstd)
			if ! ( tail -c +"$(( _artix_main_offset + 1 ))" "$_artix_last" | zstd -dc | ( cd "$_artix_work" && cpio -idm ) ); then
				nb_error "Could not unpack the Artix zstd initramfs."
				rm -rf "$_artix_work"
				return 1
			fi
			;;
		xz)
			if ! ( tail -c +"$(( _artix_main_offset + 1 ))" "$_artix_last" | xz -dc | ( cd "$_artix_work" && cpio -idm ) ); then
				nb_error "Could not unpack the Artix xz initramfs."
				rm -rf "$_artix_work"
				return 1
			fi
			;;
		cpio)
			if ! ( tail -c +"$(( _artix_main_offset + 1 ))" "$_artix_last" | ( cd "$_artix_work" && cpio -idm ) ); then
				nb_error "Could not unpack the Artix cpio initramfs."
				rm -rf "$_artix_work"
				return 1
			fi
			;;
	esac

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

	case "$_artix_format" in
		gzip)
			if ! ( cd "$_artix_work" && find . | cpio -o -H newc | gzip -c >"$_artix_repacked" ); then
				nb_error "Could not repack the Artix gzip initramfs."
				rm -rf "$_artix_work"
				return 1
			fi
			;;
		zstd)
			if ! ( cd "$_artix_work" && find . | cpio -o -H newc | zstd -q -c >"$_artix_repacked" ); then
				nb_error "Could not repack the Artix zstd initramfs."
				rm -rf "$_artix_work"
				return 1
			fi
			;;
		xz)
			if ! ( cd "$_artix_work" && find . | cpio -o -H newc | xz --check=crc32 --lzma2=dict=1MiB -c >"$_artix_repacked" ); then
				nb_error "Could not repack the Artix xz initramfs."
				rm -rf "$_artix_work"
				return 1
			fi
			;;
		cpio)
			if ! ( cd "$_artix_work" && find . | cpio -o -H newc >"$_artix_repacked" ); then
				nb_error "Could not repack the Artix cpio initramfs."
				rm -rf "$_artix_work"
				return 1
			fi
			;;
	esac

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
debiandaily "Debian GNU/Linux - daily installers" \
devuan "Devuan GNU/Linux" \
debianlive "Debian-based live installers" \
antixmx "antiX / MX Linux live installers" \
communitylive "Community live installers" \
q4os "Q4OS Trinity 6.6" \
fedora "Fedora" \
opensuse "openSUSE" \
mageia "Mageia" \
rhel-type-10 "AlmaLinux 10 / CentOS 10-Stream / Rocky Linux 10" \
rhel-type-9 "AlmaLinux 9 / CentOS 9-Stream / Rocky Linux 9" \
rhel-type-8 "AlmaLinux 8 / Rocky Linux 8" \
cloudlinux "CloudLinux 8 / CloudLinux 9" \
rhel-extra "RHEL-compatible extras" \
openeuler "openEuler" \
arch "Arch Linux" \
artix "Artix Linux" \
void "Void Linux" \
altlinux "ALT Linux" \
guix "GNU Guix System" \
slackware "Slackware" \
rescue "Rescue and utility tools" 2>/tmp/nb-distro || { rm -f /tmp/nb-distro; return; }
DISTRO=$(cat /tmp/nb-distro)
rm /tmp/nb-distro
if [ $DISTRO = "ubuntu" ];then
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
		echo -n 'vga=normal quiet '>>/tmp/nb-options
		if dialog --yesno "Would you like to install language packs?\n(Choose no for a command-line system.)" 7 43;then
			echo -n 'tasks=standard pkgsel/language-pack-patterns= pkgsel/install-language-support=false'>>/tmp/nb-options
		fi
	fi
fi
if [ $DISTRO = "ubuntuflavor" ];then
	UBUNTU_LIVE_CUSTOM=
	dialog --backtitle "$TITLE" --menu "Choose an Ubuntu flavor or derivative to boot:" 24 78 17 \
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
		linuxlite-7.8 "Linux Lite 7.8" \
		rhino-2025.4 "Rhino Linux 2025.4" \
	trisquel-mini-12 "Trisquel Mini 12.0" \
	trisquel-netinst-12 "Trisquel 12.0 NetInstall" \
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
	elif [ "$VERSION" = "linuxlite-7.8" ]; then
		ubuntu_casper_iso_setup \
			"Linux Lite 7.8" \
			"http://master.dl.sourceforge.net/project/linux-lite/7.8/linux-lite-7.8-64bit.iso?viasf=1" \
			"username=linuxlite hostname=linuxlite" \
			"http://downloads.sourceforge.net/project/linux-lite/7.8/linux-lite-7.8-64bit.iso" || return
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
		echo -n "vga=normal quiet " >>/tmp/nb-options
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
if [ $DISTRO = "debian" ];then
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
	echo -n 'vga=normal quiet '>>/tmp/nb-options
fi
if [ $DISTRO = "debiandaily" ];then
	dialog --backtitle "$TITLE" --menu "Choose a system to install:" 20 70 13 \
	high "Default" \
	medium "Show installation menu" \
	low "Expert mode" 2>/tmp/nb-version || { rm -f /tmp/nb-version; return; }
	getversion || return 0
	KERNELURL="http://d-i.debian.org/daily-images/amd64/daily/netboot/debian-installer/amd64/linux"
	INITRDURL="http://d-i.debian.org/daily-images/amd64/daily/netboot/debian-installer/amd64/initrd.gz"
	echo -n 'vga=normal quiet '>>/tmp/nb-options
	echo -n "priority=$VERSION ">>/tmp/nb-options
fi
if [ $DISTRO = "devuan" ];then
	dialog --backtitle "$TITLE" --menu "Choose a system to install:" 20 70 13 \
 	excalibur "Devuan excalibur" \
	daedalus "Devuan daedalus" \
	chimaera "Devuan chimaera" \
	ceres "Devuan ceres" \
	Manual "Manually enter a version to install" 2>/tmp/nb-version || { rm -f /tmp/nb-version; return; }
	getversion || return 0
	KERNELURL="http://deb.devuan.org/devuan/dists/$VERSION/main/installer-amd64/current/images/netboot/debian-installer/amd64/linux"
	INITRDURL="http://deb.devuan.org/devuan/dists/$VERSION/main/installer-amd64/current/images/netboot/debian-installer/amd64/initrd.gz"
	echo -n 'vga=normal quiet '>>/tmp/nb-options
fi

if [ $DISTRO = "debianlive" ];then
	dialog --backtitle "$TITLE" --menu "Choose a Debian-based live installer to boot:" 24 78 18 \
	butterbian-xfce "Butterbian Xfce 0.2.1" \
	butterknife "Butterknife 0.1.11" \
	bunsenlabs-carbon "BunsenLabs Carbon 1" \
	emmabuntus-de6-core "Emmabuntus DE6 Core" \
	locos-24 "Loc-OS 24" \
	mauna-christian "Mauna Linux 25.2 Christian Edition" \
	minios-standard "MiniOS 5.1.1 Standard" \
	nakedeb-16 "nakeDeb 1.6" \
	neptune-91 "Neptune 9.1" \
	peppermint-trixie "Peppermint OS Debian 64" \
	refracta-xfce "Refracta 13.3 Xfce" \
	refracta-nox "Refracta 13.3 noX" \
	solydx-13 "SolydX 13" \
	synex-icewm "Synex 13 IceWM" \
	synex-lxde "Synex 13 LXDE" \
	synex-xfce "Synex 13 Xfce" \
	wattos-r13 "wattOS R13" 2>/tmp/nb-version || { rm -f /tmp/nb-version; return; }
	VERSION=$(cat /tmp/nb-version)
	rm /tmp/nb-version
	debian_live_iso_setup "$VERSION" || return
fi

if [ $DISTRO = "antixmx" ];then
	dialog --backtitle "$TITLE" --menu "Choose an antiX/MX live installer to boot:" 18 75 8 \
	antix-26-core "antiX 26 Core" \
	mx-25.1-xfce "MX Linux 25.1 Xfce" \
	mx-25.1-xfce-ahs "MX Linux 25.1 Xfce AHS" 2>/tmp/nb-version || { rm -f /tmp/nb-version; return; }
	VERSION=$(cat /tmp/nb-version)
	rm /tmp/nb-version
	antix_mx_iso_setup "$VERSION" || return
fi

if [ "$DISTRO" = "communitylive" ];then
	dialog --backtitle "$TITLE" --menu "Choose a community live installer to boot:" 22 78 12 \
	pikaos-gnome "PikaOS 4.0 GNOME" \
	pikaos-kde "PikaOS 4.0 KDE" \
	pikaos-hyprland "PikaOS 4.0 Hyprland" \
	pikaos-niri "PikaOS 4.0 Niri" \
	pikaos-cosmic "PikaOS 4.0 COSMIC" \
	solus-xfce "Solus Xfce 2026-04-18" 2>/tmp/nb-version || { rm -f /tmp/nb-version; return; }
	VERSION=$(cat /tmp/nb-version)
	rm /tmp/nb-version
	community_live_iso_setup "$VERSION" || return
fi

if [ $DISTRO = "q4os" ];then
	BASE="https://github.com/netbootxyz/debian-squash/releases/download/6.6-5d30850e"
	KERNELURL="$BASE/vmlinuz"
	INITRDURL="$BASE/initrd"
	echo -n "boot=live fetch=$BASE/filesystem.squashfs" >>/tmp/nb-options
fi
if [ $DISTRO = "fedora" ];then
	dialog --backtitle "$TITLE" --menu "Choose a system to install:" 20 70 13 \
	releases/44/Server "Fedora Server 44" \
	Manual "Manually enter a version to install" 2>/tmp/nb-version || { rm -f /tmp/nb-version; return; }
	getversion || return 0
	dialog --inputbox "Where do you want to install Fedora from?" 8 70 "http://mirrors.kernel.org/fedora/$VERSION/x86_64/os" 2>/tmp/nb-server || { rm -f /tmp/nb-server; return; }
	SERVER=$(cat /tmp/nb-server)
	KERNELURL="$SERVER/images/pxeboot/vmlinuz"
	INITRDURL="$SERVER/images/pxeboot/initrd.img"
	echo -n "inst.stage2=$SERVER" >>/tmp/nb-options
	rm /tmp/nb-server
fi
if [ $DISTRO = "opensuse" ];then
	dialog --backtitle "$TITLE" --menu "Choose a system to install:" 20 70 13 \
	tumbleweed "openSUSE Tumbleweed" \
	slowroll "openSUSE Slowroll" \
	leap/16.0 "openSUSE Leap 16.0" \
	Manual "Manually enter a version to install" 2>/tmp/nb-version || { rm -f /tmp/nb-version; return; }
	getversion || return 0
	if [ $VERSION != "tumbleweed" ] && [ $VERSION != "slowroll" ];then
		VERSION=distribution/$VERSION
	fi
	KERNELURL="http://download.opensuse.org/$VERSION/repo/oss/boot/x86_64/loader/linux"
	INITRDURL="http://download.opensuse.org/$VERSION/repo/oss/boot/x86_64/loader/initrd"
	echo -n 'splash=silent showopts '>>/tmp/nb-options
	dialog --inputbox "Where do you want to install openSUSE from?" 8 70 "http://download.opensuse.org/$VERSION/repo/oss" 2>/tmp/nb-server || { rm -f /tmp/nb-server; return; }
	echo -n "install=$(cat /tmp/nb-server)" >>/tmp/nb-options
	rm /tmp/nb-server
fi
if [ $DISTRO = "mageia" ];then
	dialog --backtitle "$TITLE" --menu "Choose a system to install:" 20 70 13 \
	10 "Mageia 10 pre-release" \
	9 "Mageia 9" \
	cauldron "Mageia cauldron" \
	Manual "Manually enter a version to install" 2>/tmp/nb-version || { rm -f /tmp/nb-version; return; }
	getversion || return 0
	KERNELURL="http://mirrors.kernel.org/mageia/distrib/$VERSION/x86_64/isolinux/x86_64/vmlinuz"
	INITRDURL="http://mirrors.kernel.org/mageia/distrib/$VERSION/x86_64/isolinux/x86_64/all.rdz"
	echo -n 'automatic=method:http' >>/tmp/nb-options
fi
if [ $DISTRO = "rhel-type-10" ];then
	dialog --backtitle "$TITLE" --menu "Choose a system to install:" 20 70 13 \
	a_10 "Latest version of AlmaLinux 10" \
	c_10-stream "Latest version of CentOS Stream 10" \
	r_10 "Latest version of Rocky Linux 10" \
	Manual "Manually enter a version to install (prefix with a_, c_, or r_)" 2>/tmp/nb-version || { rm -f /tmp/nb-version; return; }
	getversion || return 0
	TYPE=$(echo $VERSION|head -c 1)
	VERSION=$(echo $VERSION|tail -c +3)
	if [ $TYPE = a ];then
		dialog --inputbox "Where do you want to install AlmaLinux OS from?" 8 70 "http://repo.almalinux.org/almalinux/$VERSION/BaseOS/x86_64/os" 2>/tmp/nb-server || { rm -f /tmp/nb-server; return; }
	elif [ $TYPE = c ];then
		dialog --inputbox "Where do you want to install CentOS Stream from?" 8 70 "https://ftp-chi.osuosl.org/pub/centos-stream/$VERSION/BaseOS/x86_64/os" 2>/tmp/nb-server || { rm -f /tmp/nb-server; return; }
	elif [ $TYPE = r ];then
		dialog --inputbox "Where do you want to install Rocky Linux from?" 8 70 "http://download.rockylinux.org/pub/rocky/$VERSION/BaseOS/x86_64/os" 2>/tmp/nb-server || { rm -f /tmp/nb-server; return; }
	else
		dialog --inputbox "Where do you want to install this distribution from?" 8 70 "" 2>/tmp/nb-server || { rm -f /tmp/nb-server; return; }
	fi
	SERVER=$(cat /tmp/nb-server)
	KERNELURL="$SERVER/images/pxeboot/vmlinuz"
	INITRDURL="$SERVER/images/pxeboot/initrd.img"
	echo -n "nomodeset inst.repo=$SERVER" >>/tmp/nb-options
	rm /tmp/nb-server
fi
if [ $DISTRO = "rhel-type-9" ];then
	dialog --backtitle "$TITLE" --menu "Choose a system to install:" 20 70 13 \
	a_9 "Latest version of AlmaLinux 9" \
	c_9-stream "Latest version of CentOS Stream 9" \
	r_9 "Latest version of Rocky Linux 9" \
	Manual "Manually enter a version to install (prefix with a_, c_, or r_)" 2>/tmp/nb-version || { rm -f /tmp/nb-version; return; }
	getversion || return 0
	TYPE=$(echo $VERSION|head -c 1)
	VERSION=$(echo $VERSION|tail -c +3)
	if [ $TYPE = a ];then
		dialog --inputbox "Where do you want to install AlmaLinux OS from?" 8 70 "http://repo.almalinux.org/almalinux/$VERSION/BaseOS/x86_64/os" 2>/tmp/nb-server || { rm -f /tmp/nb-server; return; }
	elif [ $TYPE = c ];then
		dialog --inputbox "Where do you want to install CentOS Stream from?" 8 70 "https://ftp-chi.osuosl.org/pub/centos-stream/$VERSION/BaseOS/x86_64/os" 2>/tmp/nb-server || { rm -f /tmp/nb-server; return; }
	elif [ $TYPE = r ];then
		dialog --inputbox "Where do you want to install Rocky Linux from?" 8 70 "http://download.rockylinux.org/pub/rocky/$VERSION/BaseOS/x86_64/os" 2>/tmp/nb-server || { rm -f /tmp/nb-server; return; }
	else
		dialog --inputbox "Where do you want to install this distribution from?" 8 70 "" 2>/tmp/nb-server || { rm -f /tmp/nb-server; return; }
	fi
	SERVER=$(cat /tmp/nb-server)
	KERNELURL="$SERVER/isolinux/vmlinuz"
	INITRDURL="$SERVER/isolinux/initrd.img"
	echo -n "nomodeset inst.repo=$SERVER" >>/tmp/nb-options
	rm /tmp/nb-server
fi
if [ $DISTRO = "rhel-type-8" ];then
	dialog --backtitle "$TITLE" --menu "Choose a system to install:" 20 70 13 \
	a_8 "Latest version of AlmaLinux 8" \
	r_8 "Latest version of Rocky Linux 8" \
	Manual "Manually enter a version to install (prefix with a_ or r_)" 2>/tmp/nb-version || { rm -f /tmp/nb-version; return; }
	getversion || return 0
	TYPE=$(echo $VERSION|head -c 1)
	VERSION=$(echo $VERSION|tail -c +3)
	if [ $TYPE = a ];then
		dialog --inputbox "Where do you want to install AlmaLinux OS from?" 8 70 "http://repo.almalinux.org/almalinux/$VERSION/BaseOS/x86_64/os" 2>/tmp/nb-server || { rm -f /tmp/nb-server; return; }
	elif [ $TYPE = r ];then
		dialog --inputbox "Where do you want to install Rocky Linux from?" 8 70 "http://download.rockylinux.org/pub/rocky/$VERSION/BaseOS/x86_64/os" 2>/tmp/nb-server || { rm -f /tmp/nb-server; return; }
	else
		dialog --inputbox "Where do you want to install this distribution from?" 8 70 "" 2>/tmp/nb-server || { rm -f /tmp/nb-server; return; }
	fi
	SERVER=$(cat /tmp/nb-server)
	KERNELURL="$SERVER/isolinux/vmlinuz"
	INITRDURL="$SERVER/isolinux/initrd.img"
	echo -n "nomodeset inst.repo=$SERVER" >>/tmp/nb-options
	rm /tmp/nb-server
fi
if [ $DISTRO = "cloudlinux" ];then
	dialog --backtitle "$TITLE" --menu "Choose a system to install:" 20 70 13 \
	9 "CloudLinux 9" \
	8 "CloudLinux 8" 2>/tmp/nb-version || { rm -f /tmp/nb-version; return; }
	getversion || return 0
	dialog --backtitle "$TITLE" --inputbox "Where do you want to install CloudLinux from?" 8 70 "https://download.cloudlinux.com/cloudlinux/$VERSION/BaseOS/x86_64/os" 2>/tmp/nb-server || { rm -f /tmp/nb-server; return; }
	SERVER=$(cat /tmp/nb-server)
	KERNELURL="$SERVER/images/pxeboot/vmlinuz"
	INITRDURL="$SERVER/images/pxeboot/initrd.img"
	echo -n "nomodeset inst.repo=$SERVER" >>/tmp/nb-options
	rm /tmp/nb-server
fi
if [ $DISTRO = "rhel-extra" ];then
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
		echo -n "ip=dhcp initcall_blacklist=clocksource_done_booting inst.stage2=$SERVER inst.repo=$SERVER quiet" >>/tmp/nb-options
	elif [ "$VERSION" = "tencentos-4" ] || [ "$VERSION" = "tencentos-3.3" ];then
		echo -n "ip=dhcp nomodeset inst.stage2=$SERVER inst.repo=$SERVER inst.noverifyssl" >>/tmp/nb-options
	else
		echo -n "nomodeset inst.repo=$SERVER" >>/tmp/nb-options
	fi
	rm /tmp/nb-server
fi
if [ $DISTRO = "openeuler" ];then
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
	echo -n "inst.repo=$SERVER" >>/tmp/nb-options
	rm /tmp/nb-server
fi
if [ $DISTRO = "arch" ];then
	dialog --backtitle "$TITLE" --menu "Choose a system to install:" 20 70 13 \
	latest "Arch x86_64" \
	archboot-latest "Archboot latest installer" 2>/tmp/nb-version || { rm -f /tmp/nb-version; return; }
	getversion || return 0
	if [ "$VERSION" = "archboot-latest" ];then
		BASE="https://release.archboot.com/x86_64/latest/ipxe"
		KERNELURL="$BASE/vmlinuz"
		INITRDURL="$BASE/amd-ucode.img $BASE/intel-ucode.img $BASE/initrd-latest-x86_64.img"
		echo -n 'vga=normal quiet ip=dhcp net.ifnames=0 '>>/tmp/nb-options
	else
		KERNELURL="http://mirror.rackspace.com/archlinux/iso/$VERSION/arch/boot/x86_64/vmlinuz-linux"
		INITRDURL="http://mirror.rackspace.com/archlinux/iso/$VERSION/arch/boot/x86_64/initramfs-linux.img"
		echo -n 'vga=normal quiet archiso_http_srv=http://mirror.rackspace.com/archlinux/iso/latest/ archisobasedir=arch verify=n ip=dhcp net.ifnames=0 BOOTIF=01-${netX/mac} boot '>>/tmp/nb-options
	fi
fi
if [ $DISTRO = "artix" ];then
	dialog --backtitle "$TITLE" --menu "Choose an Artix system to boot:" 12 70 4 \
	base-dinit "Base dinit" \
	base-openrc "Base OpenRC" \
	base-runit "Base runit" \
	base-s6 "Base s6" 2>/tmp/nb-version || { rm -f /tmp/nb-version; return; }
	VERSION=$(cat /tmp/nb-version)
	rm /tmp/nb-version
	artix_iso_setup "$VERSION" || return
fi
if [ $DISTRO = "void" ];then
	dialog --backtitle "$TITLE" --menu "Choose a Void Linux live system to boot:" 14 76 6 \
	glibc-base "Base (glibc)" \
	glibc-xfce "Xfce (glibc)" \
	musl-base "Base (musl)" \
	musl-xfce "Xfce (musl)" 2>/tmp/nb-version || { rm -f /tmp/nb-version; return; }
	VERSION=$(cat /tmp/nb-version)
	rm /tmp/nb-version
	void_iso_setup "$VERSION" || return
fi
if [ $DISTRO = "altlinux" ];then
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
if [ $DISTRO = "slackware" ];then
	dialog --backtitle "$TITLE" --menu "Choose a system to install:" 20 70 13 \
	slackware64-current "Slackware64-current" \
	slackware64-15.0 "Slackware 15.0" \
	slackware64-14.2 "Slackware 14.2" \
	Manual "Manually enter a version to install" 2>/tmp/nb-version || { rm -f /tmp/nb-version; return; }
	getversion || return 0
	if [ "$VERSION" = "slackware64-current" ];then
		KERNELURL="https://slackware.cs.utah.edu/pub/slackware/$VERSION/kernels/generic.s/bzImage"
		INITRDURL="https://slackware.cs.utah.edu/pub/slackware/$VERSION/isolinux/initrd.img"
		echo -n "rw printk.time=0 nomodeset SLACK_KERNEL=generic.s" >>/tmp/nb-options
	else
		KERNELURL="http://slackware.cs.utah.edu/pub/slackware/$VERSION/kernels/huge.s/bzImage"
		INITRDURL="http://slackware.cs.utah.edu/pub/slackware/$VERSION/isolinux/initrd.img"
		echo -n "load_ramdisk=1 prompt_ramdisk=0 rw" >>/tmp/nb-options
	fi
fi
if [ $DISTRO = "rescue" ];then
	dialog --backtitle "$TITLE" --menu "Choose a rescue tool:" 20 75 13 \
	gparted           "GParted Live 1.8.1-3" \
	clonezilla-deb    "Clonezilla Live 3.3.1 (Debian-based)" \
	rescuezilla       "Rescuezilla 2.6.1" \
	4mlinux           "4MLinux 51.0" \
	grml-full         "Grml Full 2026.04" \
	grml-small        "Grml Small 2026.04" 2>/tmp/nb-rescue || { rm -f /tmp/nb-rescue; return; }
	DISTRO=$(cat /tmp/nb-rescue)
	rm /tmp/nb-rescue
	if [ $DISTRO = "gparted" ];then
		BASE="https://github.com/netbootxyz/debian-squash/releases/download/1.8.1-3-5616e296"
		KERNELURL="$BASE/vmlinuz"
		INITRDURL="$BASE/initrd"
		SQUASH="$BASE/filesystem.squashfs"
		echo -n "boot=live fetch=$SQUASH union=overlay username=user vga=788" >>/tmp/nb-options
	fi
	if [ $DISTRO = "clonezilla-deb" ];then
		BASE="https://github.com/netbootxyz/debian-squash/releases/download/3.3.1-35-1a41a72c"
		KERNELURL="$BASE/vmlinuz"
		INITRDURL="$BASE/initrd"
		SQUASH="$BASE/filesystem.squashfs"
		echo -n "boot=live username=user union=overlay config components noswap edd=on nomodeset ocs_live_run=ocs-live-general ocs_live_batch=no net.ifnames=0 nosplash noprompt fetch=$SQUASH" >>/tmp/nb-options
	fi
	if [ $DISTRO = "rescuezilla" ];then
		BASE="https://github.com/netbootxyz/asset-mirror/releases/download/2.6.1-123ed276"
		KERNELURL="$BASE/vmlinuz"
		INITRDURL="$BASE/initrd"
		SQUASH="$BASE/filesystem.squashfs"
		echo -n "ip=dhcp boot=casper netboot=url url=$SQUASH" >>/tmp/nb-options
	fi
	if [ $DISTRO = "4mlinux" ];then
		BASE="https://github.com/netbootxyz/asset-mirror/releases/download/51.0-fcaac630"
		KERNELURL="$BASE/vmlinuz"
		INITRDURL="$BASE/initrd"
	fi
	if [ $DISTRO = "grml-full" ];then
		BASE="https://github.com/netbootxyz/debian-squash/releases/download/2026.04-23b18cd7"
		KERNELURL="$BASE/vmlinuz"
		INITRDURL="$BASE/initrd"
		SQUASH="$BASE/filesystem.squashfs"
		echo -n "boot=live fetch=$SQUASH" >>/tmp/nb-options
	fi
	if [ $DISTRO = "grml-small" ];then
		BASE="https://github.com/netbootxyz/debian-squash/releases/download/2026.04-410a8803"
		KERNELURL="$BASE/vmlinuz"
		INITRDURL="$BASE/initrd"
		SQUASH="$BASE/filesystem.squashfs"
		echo -n "boot=live fetch=$SQUASH" >>/tmp/nb-options
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
elif [ -n "${PIKA_ISO_URL:-}" ]; then
	if ! pika_prepare_from_iso "$PIKA_ISO_URL"; then
		rm -f /tmp/nb-linux /tmp/nb-initrd /tmp/nb-pika.iso
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

if [ $DISTRO = "rhel-type-5" ];then
	ARGS=$ARGS" --args-linux"
fi
if [ $EFIMODE = 1 ]; then
	case "$DISTRO" in
		fedora64|rhel-type-*-64)
			echo -n ' inst.efi' >>/tmp/nb-options
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
	if [ $EFIMODE = 1 ] && kexec --help 2>&1 | grep -q -- '-s'; then
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
