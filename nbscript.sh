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
	#This function reads the version the user selected from /tmp/nb-version and stores it in the VERSION variable, then deletes /tmp/nb-version.
	VERSION=$(cat /tmp/nb-version)
	if [ $VERSION = "Manual" ];then
		dialog --backtitle "$TITLE" --inputbox "Specify your preferred version here.\nFor Ubuntu and Debian, use the codename. For other distributions, use the version number." 11 54 2>/tmp/nb-version
		VERSION=$(cat /tmp/nb-version)
	fi
	rm /tmp/nb-version
}


askforopts ()
{
#Extra kernel options can be useful in some cases; i.e. hardware problems, Debian preseeding, or maybe you just want to utilise your whole 1280x1024 monitor (use: vga=794).
dialog --backtitle "$TITLE" --inputbox "Would you like to pass any extra kernel options?\n(Note: it is OK to leave this field blank)" 9 64 2>/tmp/nb-custom
}


wifimenu ()
{
	if ! command -v wpa_supplicant >/dev/null 2>&1; then
		dialog --backtitle "$TITLE" --msgbox \
			"WiFi tools not found.\nPlease use the WiFi-enabled ISO (NetbootCD-*-wifi.iso)." 8 57
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
			"No wireless interface found.\nCheck that your hardware is supported and firmware is loaded." 8 57
		return
	fi

	ifconfig "$WIFI_IFACE" up 2>/dev/null || true

	# Scan for networks
	SSID_COUNT=0
	if command -v iw >/dev/null 2>&1; then
		dialog --backtitle "$TITLE" --infobox \
			"Scanning for wireless networks on $WIFI_IFACE...\nThis may take a few seconds." 5 57
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
		{
			printf 'Wireless networks found:\n\n'
			awk '{print NR". "$0}' /tmp/nb-ssidlist
			printf '\nOn the next screen, enter the NUMBER of the network to connect to.\n'
		} > /tmp/nb-ssid-info
		dialog --backtitle "$TITLE" --textbox /tmp/nb-ssid-info 20 60
		rm -f /tmp/nb-ssid-info
		if ! dialog --backtitle "$TITLE" --inputbox \
			"Enter the number of the network to connect to (1-$SSID_COUNT):" 8 57 \
			"1" 2>/tmp/nb-wifinum; then
			rm -f /tmp/nb-wifinum /tmp/nb-ssidlist /tmp/nb-wifiscan
			return
		fi
		WIFI_NUM=$(cat /tmp/nb-wifinum)
		rm -f /tmp/nb-wifinum
		case "$WIFI_NUM" in
			''|*[!0-9]*)
				dialog --backtitle "$TITLE" --msgbox \
					"\"$WIFI_NUM\" is not a valid number." 6 45
				rm -f /tmp/nb-ssidlist /tmp/nb-wifiscan
				return ;;
		esac
		if [ "$WIFI_NUM" -lt 1 ] || [ "$WIFI_NUM" -gt "$SSID_COUNT" ]; then
			dialog --backtitle "$TITLE" --msgbox \
				"Please enter a number between 1 and $SSID_COUNT." 6 50
			rm -f /tmp/nb-ssidlist /tmp/nb-wifiscan
			return
		fi
		sed -n "${WIFI_NUM}p" /tmp/nb-ssidlist > /tmp/nb-wifissid
	else
		if ! dialog --backtitle "$TITLE" --inputbox \
			"No networks found. Enter SSID to connect to:" 8 57 "" \
			2>/tmp/nb-wifissid; then
			rm -f /tmp/nb-wifissid /tmp/nb-ssidlist /tmp/nb-wifiscan
			return
		fi
	fi

	SSID=$(cat /tmp/nb-wifissid)
	rm -f /tmp/nb-wifissid /tmp/nb-ssidlist /tmp/nb-wifiscan

	if [ -z "$SSID" ]; then return; fi

	# Get password (blank = open network)
	if ! dialog --backtitle "$TITLE" --inputbox \
		"Password for \"$SSID\" (leave blank for open network):" 8 57 \
		2>/tmp/nb-wifipass; then
		rm -f /tmp/nb-wifipass
		return
	fi
	WIFI_PASS=$(cat /tmp/nb-wifipass)
	rm -f /tmp/nb-wifipass

	killall wpa_supplicant 2>/dev/null || true
	sleep 1

	if [ -n "$WIFI_PASS" ]; then
		wpa_passphrase "$SSID" "$WIFI_PASS" > /tmp/nb-wpa.conf 2>/dev/null || true
	else
		printf 'network={\n\tssid="%s"\n\tkey_mgmt=NONE\n}\n' "$SSID" > /tmp/nb-wpa.conf
	fi

	dialog --backtitle "$TITLE" --infobox "Connecting to \"$SSID\"..." 4 45
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
			"Could not associate with \"$SSID\".\nCheck the password and try again." 8 57
		return
	fi

	# Request IP via DHCP
	dialog --backtitle "$TITLE" --infobox "Requesting IP address via DHCP..." 4 45
	killall udhcpc 2>/dev/null || true
	udhcpc -i "$WIFI_IFACE" -q >/dev/null 2>&1 || true
	sleep 2

	# Verify internet connectivity
	if wget --no-check-certificate --tries=1 -T 10 --spider \
		http://www.example.com >/dev/null 2>&1; then
		echo > /tmp/internet-is-up
		WIFIINFO=$(ifconfig "$WIFI_IFACE" 2>/dev/null | head -4)
		dialog --backtitle "$TITLE" --msgbox \
			"Connected to \"$SSID\" with internet access!\n\n${WIFIINFO}\n\nYou can now install a Linux system." \
			15 62
	else
		dialog --backtitle "$TITLE" --msgbox \
			"Associated with \"$SSID\" but internet is not reachable.\nCheck network settings and try again." \
			9 57
	fi
}


installmenu ()
{
#Ask the user to choose a distro, save the choice to /tmp/nb-distro
dialog --backtitle "$TITLE" --menu "Choose a distribution:" 20 70 13 \
ubuntu "Ubuntu [d-i]" \
debian "Debian GNU/Linux" \
debiandaily "Debian GNU/Linux - daily installers" \
devuan "Devuan GNU/Linux" \
fedora "Fedora" \
opensuse "openSUSE" \
mageia "Mageia" \
rhel-type-10 "AlmaLinux 10 / CentOS 10-Stream / Rocky Linux 10" \
rhel-type-9 "AlmaLinux 9 / CentOS 9-Stream / Rocky Linux 9" \
rhel-type-8 "AlmaLinux 8 / CentOS 8 / Rocky Linux 8" \
rhel-type-7 "CentOS 7 and Scientific Linux 7" \
rhel-type-6 "CentOS 6 and Scientific Linux 6" \
arch "Arch Linux" \
slackware "Slackware" 2>/tmp/nb-distro
#Read their choice, save it, and delete the old file
DISTRO=$(cat /tmp/nb-distro)
rm /tmp/nb-distro
#Now to check which distro the user picked.
if [ $DISTRO = "ubuntu" ];then
	#Ask about version
	dialog --menu "Choose a system to install:" 20 70 13 \
	focal "Ubuntu 20.04 LTS" \
	bionic "Ubuntu 18.04 LTS" \
	xenial "Ubuntu 16.04 LTS" \
	Manual "Manually enter a version to install" 2>/tmp/nb-version
	#Run the getversion() function above
	getversion

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
	Manual "Manually enter a version to install" 2>/tmp/nb-version
	getversion
	KERNELURL="http://http.us.debian.org/debian/dists/$VERSION/main/installer-amd64/current/images/netboot/debian-installer/amd64/linux"
	INITRDURL="http://http.us.debian.org/debian/dists/$VERSION/main/installer-amd64/current/images/netboot/debian-installer/amd64/initrd.gz"
	echo -n 'vga=normal quiet '>>/tmp/nb-options
fi
if [ $DISTRO = "debiandaily" ];then
	dialog --backtitle "$TITLE" --menu "Choose a system to install:" 20 70 13 \
	high "Default" \
	medium "Show installation menu" \
	low "Expert mode" 2>/tmp/nb-version
	getversion
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
	Manual "Manually enter a version to install" 2>/tmp/nb-version
	getversion
	KERNELURL="http://deb.devuan.org/devuan/dists/$VERSION/main/installer-amd64/current/images/netboot/debian-installer/amd64/linux"
	INITRDURL="http://deb.devuan.org/devuan/dists/$VERSION/main/installer-amd64/current/images/netboot/debian-installer/amd64/initrd.gz"
	echo -n 'vga=normal quiet '>>/tmp/nb-options
fi
if [ $DISTRO = "fedora" ];then
	dialog --backtitle "$TITLE" --menu "Choose a system to install:" 20 70 13 \
 releases/43/Server "Fedora 43" \
	releases/42/Server "Fedora 42" \
	releases/41/Server "Fedora 41" \
	development/rawhide "Rawhide" \
	Manual "Manually enter a version to install" 2>/tmp/nb-version
	getversion
	#Ask the user which server to use (the installer doesn't have a built-in list like Ubuntu and Debian do.)
	dialog --inputbox "Where do you want to install Fedora from?" 8 70 "http://mirrors.kernel.org/fedora/$VERSION/x86_64/os/" 2>/tmp/nb-server
	KERNELURL="$(cat /tmp/nb-server)/images/pxeboot/vmlinuz"
	INITRDURL="$(cat /tmp/nb-server)/images/pxeboot/initrd.img"
	echo -n "inst.stage2=$(cat /tmp/nb-server)" >>/tmp/nb-options
	rm /tmp/nb-server
fi
if [ $DISTRO = "opensuse" ];then
	dialog --backtitle "$TITLE" --menu "Choose a system to install:" 20 70 13 \
	tumbleweed "openSUSE Tumbleweed" \
	leap/16.0 "openSUSE Leap 16.0" \
	leap/15.6 "openSUSE Leap 15.6" \
	leap/15.5 "openSUSE Leap 15.5" \
	leap/15.4 "openSUSE Leap 15.4" \
	leap/15.3 "openSUSE Leap 15.3" \
	Manual "Manually enter a version to install" 2>/tmp/nb-version
	getversion
	#All versions of openSUSE are in the "distribution" folder, except for factory/tumbleweed.
	if [ $VERSION != "tumbleweed" ];then
		VERSION=distribution/$VERSION
	fi
	KERNELURL="http://download.opensuse.org/$VERSION/repo/oss/boot/x86_64/loader/linux"
	INITRDURL="http://download.opensuse.org/$VERSION/repo/oss/boot/x86_64/loader/initrd"
	#These options are common to openSUSE.
	echo -n 'splash=silent showopts '>>/tmp/nb-options
	#Ask the user which server to use (the installer doesn't have a built-in list like Ubuntu and Debian do.)
	dialog --inputbox "Where do you want to install openSUSE from?" 8 70 http://download.opensuse.org/$VERSION/repo/oss 2>/tmp/nb-server
	echo -n "install=$(cat /tmp/nb-server)" >>/tmp/nb-options
	rm /tmp/nb-server
fi
if [ $DISTRO = "mageia" ];then
	dialog --backtitle "$TITLE" --menu "Choose a system to install:" 20 70 13 \
	9 "Mageia 9" \
	8 "Mageia 8" \
	cauldron "Mageia cauldron" \
	Manual "Manually enter a version to install" 2>/tmp/nb-version
	getversion
	KERNELURL="http://mirrors.kernel.org/mageia/distrib/$VERSION/x86_64/isolinux/x86_64/vmlinuz"
	INITRDURL="http://mirrors.kernel.org/mageia/distrib/$VERSION/x86_64/isolinux/x86_64/all.rdz"
	echo -n 'automatic=method:http' >>/tmp/nb-options
fi
if [ $DISTRO = "rhel-type-10" ];then
	dialog --backtitle "$TITLE" --menu "Choose a system to install:" 20 70 13 \
	a_10 "Latest version of AlmaLinux 10" \
	c_10-stream "Latest version of CentOS Stream 10" \
	r_10 "Latest version of Rocky Linux 10" \
	Manual "Manually enter a version to install (prefix with a_, c_, or r_)" 2>/tmp/nb-version
	getversion
	TYPE=$(echo $VERSION|head -c 1)
	VERSION=$(echo $VERSION|tail -c +3)
	#Ask the user which server to use (the installer doesn't have a built-in list like Ubuntu and Debian do.)
	if [ $TYPE = a ];then
		dialog --inputbox "Where do you want to install AlmaLinux OS from?" 8 70 "http://repo.almalinux.org/almalinux/$VERSION/BaseOS/x86_64/os" 2>/tmp/nb-server
	elif [ $TYPE = c ];then
		dialog --inputbox "Where do you want to install CentOS Stream from?" 8 70 "https://ftp-chi.osuosl.org/pub/centos-stream/$VERSION/BaseOS/x86_64/os" 2>/tmp/nb-server
	elif [ $TYPE = r ];then
		dialog --inputbox "Where do you want to install Rocky Linux from?" 8 70 "http://download.rockylinux.org/pub/rocky/$VERSION/BaseOS/x86_64/os" 2>/tmp/nb-server
	else
		dialog --inputbox "Where do you want to install this distribution from?" 8 70 "" 2>/tmp/nb-server
	fi
	SERVER=$(cat /tmp/nb-server)
	KERNELURL="$SERVER/images/pxeboot/vmlinuz"
	INITRDURL="$SERVER/images/pxeboot/initrd.img"
	echo -n "nomodeset inst.repo=$(cat /tmp/nb-server)" >>/tmp/nb-options
	rm /tmp/nb-server
	askforopts
fi
if [ $DISTRO = "rhel-type-9" ];then
	dialog --backtitle "$TITLE" --menu "Choose a system to install:" 20 70 13 \
	a_9 "Latest version of AlmaLinux 9" \
	c_9-stream "Latest version of CentOS Stream 9" \
	r_9 "Latest version of Rocky Linux 9" \
	Manual "Manually enter a version to install (prefix with a_, c_, or r_)" 2>/tmp/nb-version
	getversion
	TYPE=$(echo $VERSION|head -c 1)
	VERSION=$(echo $VERSION|tail -c +3)
	#Ask the user which server to use (the installer doesn't have a built-in list like Ubuntu and Debian do.)
	if [ $TYPE = a ];then
		dialog --inputbox "Where do you want to install AlmaLinux OS from?" 8 70 "http://repo.almalinux.org/almalinux/$VERSION/BaseOS/x86_64/os" 2>/tmp/nb-server
	elif [ $TYPE = c ];then
		dialog --inputbox "Where do you want to install CentOS Stream from?" 8 70 "https://ftp-chi.osuosl.org/pub/centos-stream/$VERSION/BaseOS/x86_64/os" 2>/tmp/nb-server
	elif [ $TYPE = r ];then
		dialog --inputbox "Where do you want to install Rocky Linux from?" 8 70 "http://download.rockylinux.org/pub/rocky/$VERSION/BaseOS/x86_64/os" 2>/tmp/nb-server
	else
		dialog --inputbox "Where do you want to install this distribution from?" 8 70 "" 2>/tmp/nb-server
	fi
	SERVER=$(cat /tmp/nb-server)
	KERNELURL="$SERVER/isolinux/vmlinuz"
	INITRDURL="$SERVER/isolinux/initrd.img"
	echo -n "nomodeset inst.repo=$(cat /tmp/nb-server)" >>/tmp/nb-options
	rm /tmp/nb-server
	askforopts
fi
if [ $DISTRO = "rhel-type-8" ];then
	dialog --backtitle "$TITLE" --menu "Choose a system to install:" 20 70 13 \
	a_8 "Latest version of AlmaLinux 8" \
	c_8 "Latest version of CentOS 8" \
	r_8 "Latest version of Rocky Linux 8" \
	Manual "Manually enter a version to install (prefix with a_, c_, or r_)" 2>/tmp/nb-version
	getversion
	TYPE=$(echo $VERSION|head -c 1)
	VERSION=$(echo $VERSION|tail -c +3)
	#Ask the user which server to use (the installer doesn't have a built-in list like Ubuntu and Debian do.)
	if [ $TYPE = a ];then
		dialog --inputbox "Where do you want to install AlmaLinux OS from?" 8 70 "http://repo.almalinux.org/almalinux/$VERSION/BaseOS/x86_64/os" 2>/tmp/nb-server
	elif [ $TYPE = c ];then
		dialog --inputbox "Where do you want to install CentOS from?" 8 70 "http://mirrors.kernel.org/centos/$VERSION/BaseOS/x86_64/os" 2>/tmp/nb-server
	elif [ $TYPE = r ];then
		dialog --inputbox "Where do you want to install Rocky Linux from?" 8 70 "http://download.rockylinux.org/pub/rocky/$VERSION/BaseOS/x86_64/os" 2>/tmp/nb-server
	else
		dialog --inputbox "Where do you want to install this distribution from?" 8 70 "" 2>/tmp/nb-server
	fi
	SERVER=$(cat /tmp/nb-server)
	KERNELURL="$SERVER/isolinux/vmlinuz"
	INITRDURL="$SERVER/isolinux/initrd.img"
	echo -n "nomodeset inst.repo=$(cat /tmp/nb-server)" >>/tmp/nb-options
	rm /tmp/nb-server
	askforopts
fi
if [ $DISTRO = "rhel-type-7" ];then
	dialog --backtitle "$TITLE" --menu "Choose a system to install:" 20 70 13 \
	c_7 "Latest version of CentOS 7" \
	s_7x "Latest version of Scientific Linux 7" \
	Manual "Manually enter a version to install (prefix with s_ or c_)" 2>/tmp/nb-version
	getversion
	TYPE=$(echo $VERSION|head -c 1)
	VERSION=$(echo $VERSION|tail -c +3)
	#Ask the user which server to use (the installer doesn't have a built-in list like Ubuntu and Debian do.)
	if [ $TYPE = s ];then
		dialog --inputbox "Where do you want to install Scientific Linux from?" 8 70 "ftp://linux1.fnal.gov/linux/scientific/$VERSION/x86_64/os" 2>/tmp/nb-server
	else
		dialog --inputbox "Where do you want to install CentOS from?" 8 70 "http://mirrors.kernel.org/centos/$VERSION/os/x86_64" 2>/tmp/nb-server
	fi
	SERVER=$(cat /tmp/nb-server)
	KERNELURL="$SERVER/isolinux/vmlinuz"
	INITRDURL="$SERVER/isolinux/initrd.img"
	echo -n "xdriver=vesa nomodeset repo=$(cat /tmp/nb-server)" >>/tmp/nb-options
	rm /tmp/nb-server
	askforopts
fi
if [ $DISTRO = "rhel-type-6" ];then
	dialog --backtitle "$TITLE" --menu "Choose a system to install:" 20 70 13 \
	c_6 "Latest version of CentOS 6" \
	s_6x "Latest version of Scientific Linux 6" \
	Manual "Manually enter a version to install (prefix with s_ or c_)" 2>/tmp/nb-version
	getversion
	TYPE=$(echo $VERSION|head -c 1)
	VERSION=$(echo $VERSION|tail -c +3)
	#Ask the user which server to use (the installer doesn't have a built-in list like Ubuntu and Debian do.)
	if [ $TYPE = s ];then
		dialog --inputbox "Where do you want to install Scientific Linux from?" 8 70 "ftp://linux1.fnal.gov/linux/scientific/$VERSION/x86_64/os" 2>/tmp/nb-server
	else
		dialog --inputbox "Where do you want to install CentOS from?" 8 70 "http://mirrors.kernel.org/centos/$VERSION/os/x86_64" 2>/tmp/nb-server
	fi
	SERVER=$(cat /tmp/nb-server)
	KERNELURL="$SERVER/isolinux/vmlinuz"
	INITRDURL="$SERVER/isolinux/initrd.img"
	echo -n "ide=nodma method=$(cat /tmp/nb-server)" >>/tmp/nb-options
	rm /tmp/nb-server
	askforopts
fi
if [ $DISTRO = "arch" ];then
	dialog --backtitle "$TITLE" --menu "Choose a system to install:" 20 70 13 \
	latest "Arch x86_64" 2>/tmp/nb-version
	getversion
	KERNELURL="http://mirror.rackspace.com/archlinux/iso/$VERSION/arch/boot/x86_64/vmlinuz-linux"
	INITRDURL="http://mirror.rackspace.com/archlinux/iso/$VERSION/arch/boot/x86_64/initramfs-linux.img"
	echo -n 'vga=normal quiet archiso_http_srv=http://mirror.rackspace.com/archlinux/iso/latest/ archisobasedir=arch verify=n ip=dhcp net.ifnames=0 BOOTIF=01-${netX/mac} boot '>>/tmp/nb-options
fi
if [ $DISTRO = "slackware" ];then
	dialog --backtitle "$TITLE" --menu "Choose a system to install:" 20 70 13 \
	slackware64-15.0 "Slackware 15.0" \
	slackware64-14.2 "Slackware 14.2" \
	Manual "Manually enter a version to install" 2>/tmp/nb-version
	getversion
	dialog --backtitle "$TITLE" --menu "Choose a kernel type:" 20 70 13 \
	huge.s "" \
	hugesmp.s "" 2>/tmp/nb-kerntype
	KERNTYPE=$(cat /tmp/nb-kerntype)
	rm /tmp/nb-kerntype
	KERNELURL="http://slackware.cs.utah.edu/pub/slackware/$VERSION/kernels/$KERNTYPE/bzImage"
	INITRDURL="http://slackware.cs.utah.edu/pub/slackware/$VERSION/isolinux/initrd.img"
	echo -n "load_ramdisk=1 prompt_ramdisk=0 rw SLACK_KERNEL=$KERNTYPE" >>/tmp/nb-options
fi
#Now download the kernel and initrd.
$WGET $KERNELURL -O /tmp/nb-linux
$WGET $INITRDURL -O /tmp/nb-initrd
}


# Proceed with interactive menu
dialog --backtitle "$TITLE" --menu "What would you like to do?" 16 70 9 \
install "Install a Linux system" \
wifi    "Configure wireless network" \
ipaddr  "View/release IP address" \
quit    "Quit to prompt (do not reboot)" 2>/tmp/nb-mainmenu

MAINMENU=$(cat /tmp/nb-mainmenu)
rm /tmp/nb-mainmenu
if [ $MAINMENU = quit ];then
	exit 1
fi
#We are going to need /tmp/nb-options empty later.
true>/tmp/nb-options
true>/tmp/nb-custom
if [ $MAINMENU = "install" ];then
	installmenu
fi
if [ $MAINMENU = "wifi" ];then
	wifimenu
	exec "$0" "$@"
fi
if [ $MAINMENU = "ipaddr" ];then
  dialog --inputbox "Network interface:" 8 30 "eth0" 2>/tmp/nb-interface
  ifconfig $(cat /tmp/nb-interface)
  answer="invalid"
  while [ $? == 0 ];do
    read -p "Release IP address with \"killall -SIGUSR2 udhcpc\"? (Y/n) " answer
    if [ "$answer" == y ] || [ "$answer" == "" ];then
      killall -SIGUSR2 udhcpc
      echo "Released IP address."
      break
    elif [ "$answer" == n ];then
      break
    fi
  done
  exit
fi
#This is what we will tell kexec.
if [ $DISTRO != "grub4dos" ];then
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
