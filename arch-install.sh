#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

list_drives_with_model() {
	local count=0
	local model="MODEL"
	lsblk --filter 'TYPE == "disk"' --nodeps | while read line; do
		if [ ${count} -ne 0 ]; then
			name="$(echo "${line}" | awk '{print $1}')"
			model="$(cat /sys/block/${name}/device/model)"
		fi
		printf "%-32.32s %s\n" "${model}" "${line}"
		(( ++count ))
	done
}

format_drive() {
	{ [ $# -eq 0 ] || [ -z "${1}" ]; } && { printf "no drive selected. exiting.\n"; exit 0; }
	[ -v "2" ] && [ "${2}" == "mount-only" ]
	local mount_only=$?
	local drive="${1}"
	if [ "${mount_only}" == "0" ]; then
		printf "mounting existing installation from drive ${drive}\n"
	else
		printf "installing arch on drive ${drive}\n"
	fi
	if [[ "${drive}" =~ "nvme" ]]; then
		local bootpartition="${drive}p1"
		rootpartition="${drive}p2"
	else
		local bootpartition="${drive}1"
		rootpartition="${drive}2"
	fi
	local cryptrootuuid="$(lsblk --nodeps --noheadings --output UUID "/dev/${rootpartition}")"
	decryptedroot="luks2-${cryptrootuuid%%-*}"
	local volgroup="vg${cryptrootuuid%%-*}"
	lvroot="${volgroup}-root"
	if [ "${mount_only}" != "0" ]; then
		printf "/boot will be installed on ${bootpartition}\n/ will be installed on ${rootpartition}\n"
		printf "hostname:\n"
		read hostname
		[ -z "${hostname}" ] && { printf "empty hostname. exiting\n"; exit 1; }
		printf "username:\n"
		read username
		[ -z "${username}" ] && { printf "empty username. exiting\n"; exit 1; }
		printf "git username (optional):\n"
		read gitusername
		printf "git email (optional):\n"
		read gituseremail
		printf "password:\n"
		read -s password
		[ -z "${password}" ] && { printf "empty password. exiting\n"; exit 1; }
		sfdisk "/dev/${drive}" << EOF
label: gpt

size=     1024000, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B
type=0FC63DAF-8483-4772-8E79-3D69D8477DE4
EOF
		printf "${password}" | cryptsetup luksFormat --type luks2 "/dev/${rootpartition}" --key-file -
	fi

	cryptsetup open --type luks2 "/dev/${rootpartition}" "${decryptedroot}"
	
	if [ "${mount_only}" != "0" ]; then
		vgcreate "${volgroup}" "/dev/mapper/${decryptedroot}"
		lvcreate --size 32G "${volgroup}" --name root
		lvcreate --extents 100%FREE "${volgroup}" --name home
		
		mkfs.fat -F 32 "/dev/${bootpartition}"
		mkfs.ext4 "/dev/${volgroup}/root"
		mkfs.ext4 "/dev/${volgroup}/home"
	else
		sleep 1
	fi

	mount "/dev/${volgroup}/root" "/mnt"
	mount --mkdir "/dev/${volgroup}/home" "/mnt/home"
	mount --mkdir "/dev/${bootpartition}" "/mnt/boot"
}

eject_drive() {
	[ -d /mnt/home/ ] || { printf "directory /mnt/home does not exist\n"; exit 1; }
	local home=$( df /mnt/home/ | awk 'NR>1 {print $1}' )
	local root=$( df /mnt/ | awk 'NR>1 {print $1}' )
	local volgroup="${home%-home}"
	local luks2partition="/dev/mapper/luks2-${volgroup#/dev/mapper/vg}"

	umount --recursive /mnt/
	vgchange --activate n "${volgroup}"
	cryptsetup close "${luks2partition}"
}

chroot_install() {
	ln --symbolic --force /usr/share/zoneinfo/Europe/Berlin /etc/localtime
	hwclock --systohc
	cat >> /etc/skel/.bash_profile << EOF

if [ -z "\${DISPLAY}" ] && [ "\${XDG_VTNR}" -le 2 ]; then
	exec startx > /dev/null 2>&1
fi
EOF
	cat >> /etc/skel/.bashrc << EOF
export DOCKER_HOST="unix://\${XDG_RUNTIME_DIR}/docker.sock"
EOF
	systemctl enable NetworkManager
	systemctl enable systemd-timesyncd
	local lang="en_US.UTF-8"
	sed --in-place "/${lang}/s/^#//g" /etc/locale.gen
	locale-gen
	printf "LANG=${lang}\n" > /etc/locale.conf
	local jobs=$(nproc)
	sed --in-place "s/#MAKEFLAGS=.*/MAKEFLAGS=\"--jobs ${jobs}\"/g" /etc/makepkg.conf
	sed --in-place '/^OPTIONS=/s/ debug/ !debug/g' /etc/makepkg.conf
	(
		cd /tmp
		sudo --user nobody git clone https://aur.archlinux.org/docker-rootless-extras
		cd docker-rootless-extras
		. PKGBUILD
		pacman --sync --noconfirm --needed --asdeps "${depends[@]}"
		sudo --user nobody makepkg
		pacman --upgrade --noconfirm *.pkg.tar.zst
	)
	(
		cd /usr/bin
		ln --symbolic --force clang cc
		ln --symbolic --force clang++ c++
	)
	(
		cd /usr/local/src
		git clone https://git.suckless.org/dwm
		git clone https://git.suckless.org/dmenu
		git clone https://git.suckless.org/slstatus
	)
	(
		cd /mnt
		local readonly systemd_path="systemd/user/sockets.target.wants"
		local readonly docker_path="${systemd_path}/docker.socket"
		local readonly mpd_path="${systemd_path}/mpd.socket"
		mkdir --parents "/etc/skel/.config/${systemd_path}"
		ln --symbolic "/usr/lib/${docker_path}" "/etc/skel/.config/${docker_path}"
		ln --symbolic "/usr/lib/${mpd_path}" "/etc/skel/.config/${mpd_path}"
		mkdir /etc/skel/.config/alacritty
		mkdir /etc/skel/.config/dunst
		mkdir /etc/skel/.config/mpd
		mkdir /etc/skel/.config/ncmpcpp
		cp alacritty/alacritty.toml /etc/skel/.config/alacritty/
		cp alacritty/terafox.toml /etc/skel/.config/alacritty/
		cp bin/monbrightness /usr/local/bin/
		cp dmenu/config.h /usr/local/src/dmenu/
		cp dunst/dunst.toml /etc/skel/.config/dunst/
		cp dwm/config.h /usr/local/src/dwm/
		cp fonts/local.conf /etc/fonts/
		cp mpd/mpd.conf /etc/skel/.config/mpd/
		cp ncmpcpp/bindings /etc/skel/.config/ncmpcpp/
		cp rules.d/99-battery.rules /etc/udev/rules.d/
		cp rules.d/99-monitor-backlight.rules /etc/udev/rules.d/
		cp slstatus/battery.patch /usr/local/src/slstatus/
		cp slstatus/config.h /usr/local/src/slstatus/
		cp slstatus/realtime.patch /usr/local/src/slstatus/
		cp xinit/xinitrc /etc/X11/xinit/
		cp xorg.conf.d/20-amdgpu.conf /etc/X11/xorg.conf.d/
		cp xorg.conf.d/30-touchpad.conf /etc/X11/xorg.conf.d/
		cp xorg.conf.d/40-libinput.conf /etc/X11/xorg.conf.d/
	)
	(
		cd /usr/local/src/slstatus
		git apply realtime.patch
		git apply battery.patch
		if [ -n "${battery}" ]; then
			sed --in-place "/<battery>/s/\/\///" config.h
			sed --in-place "s/<battery>/${battery##*/}/" config.h
		fi
	)
	(
		cd /usr/local/src
		make --directory=dwm --jobs "${jobs}" install
		make --directory=dmenu --jobs "${jobs}" install
		make --directory=slstatus --jobs "${jobs}" install
	)
	useradd --create-home "${username}"
	usermod --append --groups wheel "${username}"
	sed --in-place '/%wheel ALL=(ALL:ALL) ALL/s/^# //g' /etc/sudoers
	printf "${password}" | passwd --stdin "${username}"
	printf "${password}" | passwd --stdin root
	mkdir --parent /etc/systemd/system/getty@tty1.service.d
	cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf << EOF
[Service]
Type=simple
ExecStart=
ExecStart=-/sbin/agetty --login-options '-p -f -- \\u' --noclear --autologin ${username} %I \$TERM
EOF
		cat > "/home/${username}/.gitconfig" << EOF
[core]
editor = vim
[init]
defaultBranch = main
EOF
	if [ -n "${gitusername}" ] || [ -n "${gituseremail}" ]; then
		printf "[user]\n" >> "/home/${username}/.gitconfig"
		[ -n "${gitusername}" ] && printf "name = ${gitusername}\n" >> "/home/${username}/.gitconfig"
		[ -n "${gituseremail}" ] && printf "email = ${gituseremail}\n" >> "/home/${username}/.gitconfig"
	fi
	chown "${username}:${username}" "/home/${username}/.gitconfig"
	(
		. /etc/mkinitcpio.conf
		declare -a hooks=()
		for hook in "${HOOKS[@]}"; do
			hooks+=( "${hook}" )
			[ "${hook}" == "block" ] && hooks+=( "encrypt" "lvm2" )
		done
		printf "HOOKS=(${hooks[*]})\n"
		sed --in-place "s/^HOOKS=.*/HOOKS=(${hooks[*]})/" /etc/mkinitcpio.conf
	)
	mkinitcpio --preset linux
	declare -a grubflags=( "--target=x86_64-efi" "--efi-directory=/boot" "--bootloader-id=GRUB ${hostname}" )
	local hotplug=$(lsblk --noheadings --nodeps --output HOTPLUG "/dev/${drive}")
	[ "${hotplug}" == '1' ] && grubflags+=( "--removable" )
	(
		IFS=""
		printf "grub-install ${grubflags[*]}\n"
		grub-install ${grubflags[*]}
	)
	grub-mkconfig --output /boot/grub/grub.cfg
}

main_install() {
	pacstrap -K /mnt - < "$(dirname "${0}")/pkglist.txt"
	
	genfstab -U /mnt >> /mnt/etc/fstab
	
	printf "${hostname}\n" > /mnt/etc/hostname
	cat >> /mnt/etc/hosts << EOF
127.0.0.1 localhost
127.0.1.1 ${hostname}
::1       localhost ip6-localhost ip6-loopback
ff02::1   ip6-allnodes
ff02::2   ip6-allrouters	
EOF
	(
		. /mnt/etc/default/grub
		local cryptrootuuid="$(lsblk --nodeps --noheadings --output UUID "/dev/${rootpartition}")"
		local rootuuid="$(lsblk --nodeps --noheadings --output UUID "/dev/mapper/${lvroot}")"
		GRUB_TIMEOUT=5
		GRUB_CMDLINE_LINUX_DEFAULT="${GRUB_CMDLINE_LINUX_DEFAULT}\
			cryptdevice=UUID=${cryptrootuuid}:${decryptedroot}\
		 	root=UUID=${rootuuid}\
		 	module_blacklist=pcspk,snd_pcsp\
		 	usbcore.autosuspend=-1"
		
		sed --in-place "s/GRUB_TIMEOUT=.*/GRUB_TIMEOUT=${GRUB_TIMEOUT}/" /mnt/etc/default/grub
		sed --in-place "s/GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT=\\\"${GRUB_CMDLINE_LINUX_DEFAULT}\\\"/" /mnt/etc/default/grub
	)
}

if [ $# -ne 0 ]; then
	case "$1" in

		"-h" | "--help")
			cat << EOF
usage: ${0} [OPTION]
options:
 -h, --help     Show this message
 -e, --eject    Unmount drive that was mounted with this script
 -c, --chroot   Used internally for chroot environment
EOF
			exit 0
			;;
		"-e" | "--eject")
			eject_drive
			exit 0
			;;
		"-c" | "--chroot")
			chroot_install
			exit 0
			;;
		*)
			printf "$1: unkown flag. use --help to see available flags.\n"
			;;
	esac
fi

ping -c 1 archlinux.org > /dev/null

batteries="$(find /sys/class/power_supply/ -maxdepth 1 -name 'BAT*')"
if [ "$(echo "${batteries}" | wc --lines)" -gt 1 ]; then
	print "please select a battery for slstatus:\n"
	battery="$(echo "${batteries}" | dmenu-cli)"
else
	battery="${batteries}"
fi
list_drives_with_model
printf "please select a hard drive:\n" # TODO support multiple
drive=$(lsblk --filter 'TYPE == "disk"' --nodeps --noheadings --output NAME | dmenu-cli)
format_drive "${drive}" # mount-only
main_install
export drive
export hostname
export username
export password
export gitusername
export gituseremail
export battery
mount --bind "$(dirname "${0}")"  /mnt/mnt/
arch-chroot /mnt/ bash /mnt/arch-install.sh --chroot 2>&1 | sed 's/^/>>> /'
umount /mnt/mnt
