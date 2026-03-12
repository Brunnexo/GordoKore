#!/usr/bin/env bash

set -e

source /etc/os-release

echo "Detected distribution: $NAME"

install_arch() {

echo "Using pacman..."

packages=(
base-devel
ncurses
readline
perl
git
glibc
linux-headers
linux-api-headers
libxcrypt-compat
libxcrypt
curl
scons
pahole
perl-cpanel-json-xs
)

# SteamOS-exclusive packages
if [[ "$ID" == "steamos" ]]; then
packages+=(
linux-neptune-611
linux-neptune-611-headers
steamos-customizations-jupiter
inputplumber
)
fi

sudo pacman -Syu --noconfirm
sudo pacman -S --needed --noconfirm "${packages[@]}"
}

install_debian() {

echo "Using apt..."

sudo apt update

packages=(
build-essential
libncurses-dev
libreadline-dev
perl
git
libc6
linux-headers-generic
curl
scons
pahole
)

sudo apt install -y "${packages[@]}"
}

install_fedora() {

echo "Using dnf..."

packages=(
gcc
gcc-c++
make
ncurses-devel
readline-devel
perl
git
glibc
kernel-headers
curl
scons
pahole
)

sudo dnf install -y "${packages[@]}"
}

case "$ID" in
arch|steamos|manjaro)
install_arch
;;

ubuntu|debian|linuxmint|pop)
install_debian
;;

fedora)
install_fedora
;;

*)
echo "Unsupported distribution: $ID"
echo "Please install the required packages manually."
exit 1
;;
esac

echo "Installation completed."