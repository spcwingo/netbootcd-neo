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

TITLE="NetbootCD-Neo Script 17.0 - April 17, 2026"

# Detect UEFI mode once at startup; used throughout the script.
EFIMODE=0
[ -d /sys/firmware/efi ] && EFIMODE=1

# TinyCore has no CA certificate store, so HTTPS connections fail at the
# TLS handshake unless we skip verification.  --tries=3 retries transient
# connection resets automatically.
WGET="wget --no-check-certificate --tries=3"

getversion ()
{
	VERSION=$(cat /tmp/nb-version)
	if [ "$VERSION" = "Manual" ]; then
		printf 'Version (codename for Debian/Ubuntu, number for others): '
		read VERSION
		if [ -z "$VERSION" ]; then rm -f /tmp/nb-version; return 1; fi
	fi
	rm /tmp/nb-version
}


askforopts ()
{
#Extra kernel options can be useful in some cases; i.e. hardware problems, Debian preseeding, or maybe you just want to utilise your whole 1280x1024 monitor (use: vga=794).
# dialog --inputbox is unreliable on BusyBox-based systems (TinyCore); use --yesno + read instead.
if dialog --backtitle "$TITLE" --defaultno --yesno "Would you like to pass extra kernel parameters to the new kernel?" 6 60; then
	printf 'Extra kernel parameters: '
	read NB_CUSTOM
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

	# Detect wireless interface - check sys/class/net first (works for DOWN interfaces too)
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

	# Scan for networks
	SSID_COUNT=0
	if command -v iw >/dev/null 2>&1; then
		dialog --backtitle "$TITLE" --infobox \
			"Scanning for wireless networks on $WIFI_IFACE...\nThis may take a few seconds." 5 57 || true
		sleep 2
		iw dev "$WIFI_IFACE" scan 2>/dev/null > /tmp/nb-wifiscan || true
		# Retry once if the first scan returned nothing (card may still be initializing)
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

	# Show networks and get SSID from user
	if [ "$SSID_COUNT" -gt 0 ]; then
		set --
		i=1
		while IFS= read -r ssid; do
			set -- "$@" "$i" "$ssid"
			i=$((i+1))
		done < /tmp/nb-ssidlist
		set -- "$@" "manual" "Enter SSID manually"
		dialog --backtitle "$TITLE" --menu \
			"Select a wireless network (use arrow keys):" 20 70 13 \
			"$@" 2>/tmp/nb-wifisel || { rm -f /tmp/nb-wifisel /tmp/nb-ssidlist /tmp/nb-wifiscan; return; }
		WIFI_SEL=$(cat /tmp/nb-wifisel)
		rm -f /tmp/nb-wifisel
		if [ "$WIFI_SEL" = "manual" ]; then
			printf 'SSID: '
			read _SSID
			if [ -z "$_SSID" ]; then rm -f /tmp/nb-wifissid /tmp/nb-ssidlist /tmp/nb-wifiscan; return; fi
			printf '%s' "$_SSID" >/tmp/nb-wifissid
		else
			sed -n "${WIFI_SEL}p" /tmp/nb-ssidlist > /tmp/nb-wifissid
		fi
	else
		printf 'No networks found. SSID: '
		read _SSID
		if [ -z "$_SSID" ]; then rm -f /tmp/nb-wifissid /tmp/nb-ssidlist /tmp/nb-wifiscan; return; fi
		printf '%s' "$_SSID" >/tmp/nb-wifissid
	fi

	SSID=$(cat /tmp/nb-wifissid)
	rm -f /tmp/nb-wifissid /tmp/nb-ssidlist /tmp/nb-wifiscan

	if [ -z "$SSID" ]; then return; fi

	# Get password (blank = open network)
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

	# Check association
	CONNECTED=0
	if command -v iw >/dev/null 2>&1; then
		iw dev "$WIFI_IFACE" link 2>/dev/null | grep -q "SSID:" && CONNECTED=1 || true
	else
		# Fallback: if wpa_supplicant is still running, assume association succeeded
		pidof wpa_supplicant >/dev/null 2>&1 && CONNECTED=1 || true
	fi

	if [ "$CONNECTED" -eq 0 ]; then
		dialog --backtitle "$TITLE" --msgbox \
			"Could not associate with \"$SSID\".\nCheck the password and try again." 8 57 || true
		return
	fi

	# Request IP via DHCP
	dialog --backtitle "$TITLE" --infobox "Requesting IP address via DHCP..." 4 45 || true
	killall udhcpc 2>/dev/null || true
	udhcpc -i "$WIFI_IFACE" -q >/dev/null 2>&1 || true
	sleep 2

	# Verify internet connectivity
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
	# Enumerate network interfaces from /sys/class/net (skip loopback and tunnels)
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
			read IFACE
			if [ -z "$IFACE" ]; then return 0; fi
		else
			IFACE="$IFACE_SEL"
		fi
	else
		printf 'Network interface [eth0]: '
		read IFACE
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
dialog --backtitle "$TITLE" --menu "Choose a distribution:" 24 75 17 \
ubuntu "Ubuntu" \
debian "Debian GNU/Linux" \
debiandaily "Debian GNU/Linux - daily installers" \
devuan "Devuan GNU/Linux" \
kali "Kali Linux" \
lmde "Linux Mint Debian Edition" \
pardus "Pardus" \
sparky "Sparky Linux" \
q4os "Q4OS Trinity 6.6" \
fedora "Fedora" \
opensuse "openSUSE" \
mageia "Mageia" \
rhel-type-10 "AlmaLinux 10 / CentOS 10-Stream / Rocky Linux 10" \
rhel-type-9 "AlmaLinux 9 / CentOS 9-Stream / Rocky Linux 9" \
rhel-type-8 "AlmaLinux 8 / CentOS 8 / Rocky Linux 8" \
rhel-type-7 "CentOS 7 and Scientific Linux 7" \
rhel-type-6 "CentOS 6 and Scientific Linux 6" \
cloudlinux "CloudLinux 8 / CloudLinux 9" \
openeuler "openEuler" \
arch "Arch Linux" \
alpine "Alpine Linux" \
nixos "NixOS" \
slackware "Slackware" \
bodhi "Bodhi Linux 7.0.0" \
flatcar "Flatcar Container Linux" \
rescue "Rescue and utility tools" 2>/tmp/nb-distro || { rm -f /tmp/nb-distro; return; }
DISTRO=$(cat /tmp/nb-distro)
rm /tmp/nb-distro
if [ $DISTRO = "ubuntu" ];then
	dialog --backtitle "$TITLE" --menu "Choose a system to install:" 20 70 13 \
	noble "Ubuntu 24.04 LTS (Subiquity)" \
	jammy "Ubuntu 22.04 LTS" \
	focal "Ubuntu 20.04 LTS" \
	bionic "Ubuntu 18.04 LTS" \
	xenial "Ubuntu 16.04 LTS" \
	Manual "Manually enter a version to install" 2>/tmp/nb-version || { rm -f /tmp/nb-version; return; }
	getversion || return 0
	if [ "$VERSION" = "noble" ]; then
		KERNELURL="https://releases.ubuntu.com/noble/netboot/amd64/linux"
		INITRDURL="https://releases.ubuntu.com/noble/netboot/amd64/initrd"
		ISODEFAULT="https://releases.ubuntu.com/24.04.4/ubuntu-24.04.4-live-server-amd64.iso"
		dialog --backtitle "$TITLE" --inputbox "URL for the Ubuntu live-server ISO:" 8 70 "$ISODEFAULT" 2>/tmp/nb-isourl || { rm -f /tmp/nb-isourl; return; }
		echo -n "ip=dhcp iso-url=$(cat /tmp/nb-isourl)" >>/tmp/nb-options
		rm /tmp/nb-isourl
	else
		#Set the URL to download the kernel and initrd from. The server used here is archive.ubuntu.com.
		KERNELURL="http://archive.ubuntu.com/ubuntu/dists/$VERSION-updates/main/installer-amd64/current/images/netboot/ubuntu-installer/amd64/linux"
		INITRDURL="http://archive.ubuntu.com/ubuntu/dists/$VERSION-updates/main/installer-amd64/current/images/netboot/ubuntu-installer/amd64/initrd.gz"
		# Test if distro-updates exists
		if ! $WGET --spider -q $KERNELURL; then # fallback to known distro
			KERNELURL="http://archive.ubuntu.com/ubuntu/dists/$VERSION/main/installer-amd64/current/images/netboot/ubuntu-installer/amd64/linux"
			INITRDURL="http://archive.ubuntu.com/ubuntu/dists/$VERSION/main/installer-amd64/current/images/netboot/ubuntu-installer/amd64/initrd.gz"
		fi
		if ! $WGET --spider -q $KERNELURL; then # try new path
			KERNELURL="http://archive.ubuntu.com/ubuntu/dists/$VERSION/main/installer-amd64/current/legacy-images/netboot/ubuntu-installer/amd64/linux"
			INITRDURL="http://archive.ubuntu.com/ubuntu/dists/$VERSION/main/installer-amd64/current/legacy-images/netboot/ubuntu-installer/amd64/initrd.gz"
		fi
		#These options are good for all Ubuntu installers.
		echo -n 'vga=normal quiet '>>/tmp/nb-options
		#If the user wants a command-line install, then add some more kernel arguments. The CLI install is akin to "standard system" in Debian.
		if dialog --yesno "Would you like to install language packs?\n(Choose no for a command-line system.)" 7 43;then
			echo -n 'tasks=standard pkgsel/language-pack-patterns= pkgsel/install-language-support=false'>>/tmp/nb-options
		fi
	fi
fi
if [ $DISTRO = "debian" ];then
	dialog --backtitle "$TITLE" --menu "Choose a system to install:" 20 70 13 \
	trixie "Debian 13" \
	bookworm "Debian 12" \
	bullseye "Debian 11" \
	buster "Debian 10" \
	stretch "Debian 9" \
	jessie "Debian 8" \
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
if [ $DISTRO = "kali" ];then
	dialog --backtitle "$TITLE" --menu "Choose a system to install:" 20 70 13 \
	kali-rolling "Kali Linux Rolling" 2>/tmp/nb-version || { rm -f /tmp/nb-version; return; }
	getversion || return 0
	KERNELURL="https://http.kali.org/kali/dists/$VERSION/main/installer-amd64/current/images/netboot/debian-installer/amd64/linux"
	INITRDURL="https://http.kali.org/kali/dists/$VERSION/main/installer-amd64/current/images/netboot/debian-installer/amd64/initrd.gz"
	echo -n 'vga=normal quiet '>>/tmp/nb-options
fi
if [ $DISTRO = "lmde" ];then
	dialog --backtitle "$TITLE" --menu "Choose a system to boot:" 20 70 13 \
	6 "LMDE 6 Cinnamon" 2>/tmp/nb-version || { rm -f /tmp/nb-version; return; }
	getversion || return 0
	BASE="https://github.com/netbootxyz/debian-squash/releases/download/6-dc29210f"
	KERNELURL="$BASE/vmlinuz"
	INITRDURL="$BASE/initrd"
	echo -n "boot=live fetch=$BASE/filesystem.squashfs" >>/tmp/nb-options
fi
if [ $DISTRO = "pardus" ];then
	dialog --backtitle "$TITLE" --menu "Choose a system to install:" 20 70 13 \
	yirmibes "Pardus 25" \
	yirmiuc  "Pardus 23" 2>/tmp/nb-version || { rm -f /tmp/nb-version; return; }
	getversion || return 0
	BASE="https://depo.pardus.org.tr/pardus/dists/$VERSION/main/installer-amd64/current/images/netboot/debian-installer/amd64"
	KERNELURL="$BASE/linux"
	INITRDURL="$BASE/initrd.gz"
	echo -n 'vga=normal quiet '>>/tmp/nb-options
fi
if [ $DISTRO = "sparky" ];then
	dialog --backtitle "$TITLE" --menu "Choose a system to boot:" 20 70 13 \
	rolling-xfce "Sparky Rolling XFCE (Mar 2026)" \
	rolling-lxqt "Sparky Rolling LXQt (Mar 2026)" \
	stable "Sparky Stable 8.2 XFCE" 2>/tmp/nb-version || { rm -f /tmp/nb-version; return; }
	getversion || return 0
	case "$VERSION" in
		rolling-xfce) BASE="https://github.com/netbootxyz/debian-squash/releases/download/2026.03-314f0a50" ;;
		rolling-lxqt) BASE="https://github.com/netbootxyz/debian-squash/releases/download/2026.03-1a7f6c6a" ;;
		stable)       BASE="https://github.com/netbootxyz/debian-squash/releases/download/8.2-28fbf253" ;;
	esac
	KERNELURL="$BASE/vmlinuz"
	INITRDURL="$BASE/initrd"
	echo -n "boot=live fetch=$BASE/filesystem.squashfs" >>/tmp/nb-options
fi
if [ $DISTRO = "q4os" ];then
	BASE="https://github.com/netbootxyz/debian-squash/releases/download/6.6-5d30850e"
	KERNELURL="$BASE/vmlinuz"
	INITRDURL="$BASE/initrd"
	echo -n "boot=live fetch=$BASE/filesystem.squashfs" >>/tmp/nb-options
fi
if [ $DISTRO = "fedora" ];then
	dialog --backtitle "$TITLE" --menu "Choose a system to install:" 20 70 13 \
 	releases/43 "Fedora 43" \
	releases/42 "Fedora 42" \
	releases/41 "Fedora 41" \
	development/rawhide "Rawhide" \
	Manual "Manually enter a version to install" 2>/tmp/nb-version || { rm -f /tmp/nb-version; return; }
	getversion || return 0
	dialog --inputbox "Where do you want to install Fedora from?" 8 70 "http://mirrors.kernel.org/fedora/$VERSION/Server/x86_64/os/" 2>/tmp/nb-server || { rm -f /tmp/nb-server; return; }
	KERNELURL="$(cat /tmp/nb-server)/images/pxeboot/vmlinuz"
	INITRDURL="$(cat /tmp/nb-server)/images/pxeboot/initrd.img"
	echo -n "inst.stage2=$(cat /tmp/nb-server)" >>/tmp/nb-options
	rm /tmp/nb-server
fi
if [ $DISTRO = "opensuse" ];then
	dialog --backtitle "$TITLE" --menu "Choose a system to install:" 20 70 13 \
	tumbleweed "openSUSE Tumbleweed" \
	slowroll "openSUSE Slowroll" \
	leap/16.0 "openSUSE Leap 16.0" \
	leap/15.6 "openSUSE Leap 15.6" \
	leap/15.5 "openSUSE Leap 15.5" \
	leap/15.4 "openSUSE Leap 15.4" \
	leap/15.3 "openSUSE Leap 15.3" \
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
	9 "Mageia 9" \
	8 "Mageia 8" \
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
	c_8 "Latest version of CentOS 8" \
	r_8 "Latest version of Rocky Linux 8" \
	Manual "Manually enter a version to install (prefix with a_, c_, or r_)" 2>/tmp/nb-version || { rm -f /tmp/nb-version; return; }
	getversion || return 0
	TYPE=$(echo $VERSION|head -c 1)
	VERSION=$(echo $VERSION|tail -c +3)
	if [ $TYPE = a ];then
		dialog --inputbox "Where do you want to install AlmaLinux OS from?" 8 70 "http://repo.almalinux.org/almalinux/$VERSION/BaseOS/x86_64/os" 2>/tmp/nb-server || { rm -f /tmp/nb-server; return; }
	elif [ $TYPE = c ];then
		dialog --inputbox "Where do you want to install CentOS from?" 8 70 "http://mirrors.kernel.org/centos/$VERSION/BaseOS/x86_64/os" 2>/tmp/nb-server || { rm -f /tmp/nb-server; return; }
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
if [ $DISTRO = "rhel-type-7" ];then
	dialog --backtitle "$TITLE" --menu "Choose a system to install:" 20 70 13 \
	c_7 "Latest version of CentOS 7" \
	s_7x "Latest version of Scientific Linux 7" \
	Manual "Manually enter a version to install (prefix with s_ or c_)" 2>/tmp/nb-version || { rm -f /tmp/nb-version; return; }
	getversion || return 0
	TYPE=$(echo $VERSION|head -c 1)
	VERSION=$(echo $VERSION|tail -c +3)
	if [ $TYPE = s ];then
		dialog --inputbox "Where do you want to install Scientific Linux from?" 8 70 "ftp://linux1.fnal.gov/linux/scientific/$VERSION/x86_64/os" 2>/tmp/nb-server || { rm -f /tmp/nb-server; return; }
	else
		dialog --inputbox "Where do you want to install CentOS from?" 8 70 "http://mirrors.kernel.org/centos/$VERSION/os/x86_64" 2>/tmp/nb-server || { rm -f /tmp/nb-server; return; }
	fi
	SERVER=$(cat /tmp/nb-server)
	KERNELURL="$SERVER/isolinux/vmlinuz"
	INITRDURL="$SERVER/isolinux/initrd.img"
	echo -n "xdriver=vesa nomodeset repo=$SERVER" >>/tmp/nb-options
	rm /tmp/nb-server
fi
if [ $DISTRO = "rhel-type-6" ];then
	dialog --backtitle "$TITLE" --menu "Choose a system to install:" 20 70 13 \
	c_6 "Latest version of CentOS 6" \
	s_6x "Latest version of Scientific Linux 6" \
	Manual "Manually enter a version to install (prefix with s_ or c_)" 2>/tmp/nb-version || { rm -f /tmp/nb-version; return; }
	getversion || return 0
	TYPE=$(echo $VERSION|head -c 1)
	VERSION=$(echo $VERSION|tail -c +3)
	if [ $TYPE = s ];then
		dialog --inputbox "Where do you want to install Scientific Linux from?" 8 70 "ftp://linux1.fnal.gov/linux/scientific/$VERSION/x86_64/os" 2>/tmp/nb-server || { rm -f /tmp/nb-server; return; }
	else
		dialog --inputbox "Where do you want to install CentOS from?" 8 70 "http://mirrors.kernel.org/centos/$VERSION/os/x86_64" 2>/tmp/nb-server || { rm -f /tmp/nb-server; return; }
	fi
	SERVER=$(cat /tmp/nb-server)
	KERNELURL="$SERVER/isolinux/vmlinuz"
	INITRDURL="$SERVER/isolinux/initrd.img"
	echo -n "ide=nodma method=$SERVER" >>/tmp/nb-options
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
if [ $DISTRO = "openeuler" ];then
	dialog --backtitle "$TITLE" --menu "Choose a system to install:" 20 70 13 \
	24.03-LTS-SP1 "openEuler 24.03 LTS SP1" \
	24.03-LTS "openEuler 24.03 LTS" \
	22.03-LTS-SP4 "openEuler 22.03 LTS SP4" \
	25.03 "openEuler 25.03" \
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
	latest "Arch x86_64" 2>/tmp/nb-version || { rm -f /tmp/nb-version; return; }
	getversion || return 0
	KERNELURL="http://mirror.rackspace.com/archlinux/iso/$VERSION/arch/boot/x86_64/vmlinuz-linux"
	INITRDURL="http://mirror.rackspace.com/archlinux/iso/$VERSION/arch/boot/x86_64/initramfs-linux.img"
	echo -n 'vga=normal quiet archiso_http_srv=http://mirror.rackspace.com/archlinux/iso/latest/ archisobasedir=arch verify=n ip=dhcp net.ifnames=0 BOOTIF=01-${netX/mac} boot '>>/tmp/nb-options
fi
if [ $DISTRO = "slackware" ];then
	dialog --backtitle "$TITLE" --menu "Choose a system to install:" 20 70 13 \
	slackware64-15.0 "Slackware 15.0" \
	slackware64-14.2 "Slackware 14.2" \
	Manual "Manually enter a version to install" 2>/tmp/nb-version || { rm -f /tmp/nb-version; return; }
	getversion || return 0
	dialog --backtitle "$TITLE" --menu "Choose a kernel type:" 20 70 13 \
	huge.s "" \
	hugesmp.s "" 2>/tmp/nb-kerntype || { rm -f /tmp/nb-kerntype; return; }
	KERNTYPE=$(cat /tmp/nb-kerntype)
	rm /tmp/nb-kerntype
	KERNELURL="http://slackware.cs.utah.edu/pub/slackware/$VERSION/kernels/$KERNTYPE/bzImage"
	INITRDURL="http://slackware.cs.utah.edu/pub/slackware/$VERSION/isolinux/initrd.img"
	echo -n "load_ramdisk=1 prompt_ramdisk=0 rw SLACK_KERNEL=$KERNTYPE" >>/tmp/nb-options
fi
if [ $DISTRO = "alpine" ];then
	dialog --backtitle "$TITLE" --menu "Choose a system to install:" 20 70 13 \
	latest-stable "Alpine Linux (latest stable)" \
	v3.21 "Alpine Linux 3.21" \
	v3.20 "Alpine Linux 3.20" \
	Manual "Manually enter a version to install (e.g. v3.21)" 2>/tmp/nb-version || { rm -f /tmp/nb-version; return; }
	getversion || return 0
	BASE="https://dl-cdn.alpinelinux.org/alpine/$VERSION/releases/x86_64/netboot"
	KERNELURL="$BASE/vmlinuz-lts"
	INITRDURL="$BASE/initramfs-lts"
	echo -n "modloop=$BASE/modloop-lts alpine_repo=https://dl-cdn.alpinelinux.org/alpine/$VERSION/main" >>/tmp/nb-options
fi
if [ $DISTRO = "nixos" ];then
	dialog --backtitle "$TITLE" --menu "Choose a system to install:" 20 70 13 \
	nixos-unstable "NixOS Unstable" \
	nixos-25.11 "NixOS 25.11" \
	nixos-25.05 "NixOS 25.05" \
	Manual "Manually enter a version to install (e.g. nixos-25.11)" 2>/tmp/nb-version || { rm -f /tmp/nb-version; return; }
	getversion || return 0
	KERNELURL="https://github.com/nix-community/nixos-images/releases/download/$VERSION/bzImage-x86_64-linux"
	INITRDURL="https://github.com/nix-community/nixos-images/releases/download/$VERSION/initrd-x86_64-linux"
	# The init= path is a Nix store hash that changes every build; parse it from the official iPXE script.
	$WGET "https://github.com/nix-community/nixos-images/releases/download/$VERSION/netboot-x86_64-linux.ipxe" -O /tmp/nb-nixos.ipxe
	NIXOS_PARAMS=$(grep '^kernel ' /tmp/nb-nixos.ipxe | tr -d '\r' | sed 's|^kernel [^ ]* ||' | sed 's|initrd=[^ ]*||g' | tr -s ' ')
	rm -f /tmp/nb-nixos.ipxe
	echo -n "$NIXOS_PARAMS" >>/tmp/nb-options
fi
if [ $DISTRO = "bodhi" ];then
	BASE="https://github.com/netbootxyz/ubuntu-squash/releases/download/7.0.0-f22738f2"
	KERNELURL="$BASE/vmlinuz"
	INITRDURL="$BASE/initrd"
	SQUASH="$BASE/filesystem.squashfs"
	echo -n "ip=dhcp boot=casper netboot=url url=$SQUASH" >>/tmp/nb-options
fi
if [ $DISTRO = "flatcar" ];then
	dialog --backtitle "$TITLE" --menu "Choose a release channel:" 20 70 13 \
	stable "Flatcar Stable (recommended)" \
	beta   "Flatcar Beta" \
	alpha  "Flatcar Alpha" 2>/tmp/nb-version || { rm -f /tmp/nb-version; return; }
	getversion || return 0
	BASE="https://$VERSION.release.flatcar-linux.net/amd64-usr/current"
	KERNELURL="$BASE/flatcar_production_pxe.vmlinuz"
	INITRDURL="$BASE/flatcar_production_pxe_image.cpio.gz"
	dialog --backtitle "$TITLE" --msgbox "Note: Flatcar downloads a complete OS image as its initrd.\nRequires at least 3 GB RAM to boot." 7 60 || true
	echo -n "flatcar.first_boot=1 flatcar.autologin=tty1" >>/tmp/nb-options
fi

if [ $DISTRO = "rescue" ];then
	dialog --backtitle "$TITLE" --menu "Choose a rescue tool:" 20 75 13 \
	gparted           "GParted Live 1.8.1-3" \
	clonezilla-deb    "Clonezilla Live 3.3.1 (Debian-based)" \
	rescuezilla       "Rescuezilla 2.6.1" \
	4mlinux           "4MLinux 51.0" \
	grml-full         "Grml Full 2025.12" \
	grml-small        "Grml Small 2025.12" 2>/tmp/nb-rescue || { rm -f /tmp/nb-rescue; return; }
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
		BASE="https://github.com/netbootxyz/debian-squash/releases/download/2025.12-ee78df85"
		KERNELURL="$BASE/vmlinuz"
		INITRDURL="$BASE/initrd"
		SQUASH="$BASE/filesystem.squashfs"
		echo -n "boot=live fetch=$SQUASH" >>/tmp/nb-options
	fi
	if [ $DISTRO = "grml-small" ];then
		BASE="https://github.com/netbootxyz/debian-squash/releases/download/2025.12-ca5dc013"
		KERNELURL="$BASE/vmlinuz"
		INITRDURL="$BASE/initrd"
		SQUASH="$BASE/filesystem.squashfs"
		echo -n "boot=live fetch=$SQUASH" >>/tmp/nb-options
	fi
fi
askforopts
#Now download the kernel and initrd.
$WGET $KERNELURL -O /tmp/nb-linux
if [ -n "${INITRDURL:-}" ]; then
	$WGET $INITRDURL -O /tmp/nb-initrd
fi
}


# Proceed with interactive menu
while true; do
	dialog --backtitle "$TITLE" --menu "What would you like to do?" 16 70 9 \
	install "Install or boot a Linux system" \
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
	if [ "$MAINMENU" = "wifi" ]; then
		wifimenu || true
		exec "$0" "$@"
	fi
	if [ "$MAINMENU" = "ipaddr" ]; then
		ipadrmenu || true
		continue
	fi
done
#This is what we will tell kexec.
if [ -f /tmp/nb-initrd ]; then
	ARGS="-l /tmp/nb-linux --initrd=/tmp/nb-initrd $OPTIONS $CUSTOM"
else
	ARGS="-l /tmp/nb-linux $OPTIONS $CUSTOM"
fi

if [ $DISTRO = "rhel-type-5" ];then
	ARGS=$ARGS" --args-linux"
fi
# Tell Anaconda to set up an EFI System Partition when in UEFI mode.
if [ $EFIMODE = 1 ]; then
	case "$DISTRO" in
		fedora64|rhel-type-*-64)
			echo -n ' inst.efi' >>/tmp/nb-options
			;;
	esac
fi
#This checks to make sure you are indeed on a TCB system.
if [ -d /home/tc ];then
	CMDLINE="$(cat /tmp/nb-options) $(cat /tmp/nb-custom)"
	echo kexec $ARGS --command-line="$CMDLINE"
	# On UEFI systems, prefer kexec_file_load (-s) which preserves the EFI
	# memory map and system table for the incoming kernel.  Fall back to the
	# classic kexec_load syscall if -s is not compiled in (e.g. 32-bit kernel).
	if [ $EFIMODE = 1 ] && kexec --help 2>&1 | grep -q -- '-s'; then
		kexec -s $ARGS --command-line="$CMDLINE" 2>/dev/null || \
		kexec $ARGS --command-line="$CMDLINE"
	else
		kexec $ARGS --command-line="$CMDLINE"
	fi
	sleep 5
	sync
	kexec -e
fi
