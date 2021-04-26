#!/usr/bin/env sh

# openSUSE build script for onivim2
# this script is licensed under the GNU Affero GPL
# see http://www.gnu.org/licenses for complete terms

function main {

	# echo commands and stop the build on error
	set -xe

	# control flow across sudo/chroot calls
	if [ -z "$STEP" ]; then
		begin
	else
		$STEP
	fi
}

function begin {

	# sanity check inputs
	[ $USER != root ] || exit 1
	set -- $(realpath _build)
	[ $# -eq 1 ] || exit 1
	set -- $(realpath $0)
	[ $# -eq 1 ] || exit 1
	set --

	# setup build directory
	DIR=$(realpath _build)
	mkdir -p $DIR/$HOME
	mkdir -p $DIR/etc
	cp /etc/resolv.conf $DIR/etc/
	cp $0 $DIR/${0##*/}
	
	# continue as root
	sudo STEP=prep OWNER=$USER DIR=$DIR $0
	
	# get the final build artifact
	cp $DIR/$HOME/oni2/_release/*.AppImage ./
}

function prep {

	# configuration
	LIBS="
		$(: libraries )
		fontconfig ncurses Mesa-libGL glu harfbuzz libSDL2 gtk3 libacl libICE libSM

		$(: X extensions )
		libXext libXrandr libXi libXcursor libXinerama libXxf86vm libxkbfile libXt
	"
	TOOLS="
		$(: languages )
		gcc-c++ clang nasm npm-default python

		$(: utilities )
		git make sed curl tar gzip bzip2 grep wget AppStream fuse

		$(: miscellaneous )
		glibc-locale libfuse2
	"
	DEPS="$TOOLS $(printf '%s-devel ' $LIBS)"
	
	# temporarily enable manual error handling to ensure unmount on error
	set +e	

	# setup chroot
	MOUNTS="proc dev run"
	for MNT in $MOUNTS; do
		mkdir -p $DIR/$MNT
		mount -o bind /$MNT $DIR/$MNT
	done

	# install dependencies
	zypper \
		--non-interactive \
		--gpg-auto-import-keys \
		--installroot $DIR \
		install $DEPS &&
	chroot $DIR update-ca-certificates &&
	
	# start build
	STEP=build chroot $DIR su -l -w STEP -c /${0##*/} $OWNER
	RET=$?

	# teardown chroot
	for MNT in $MOUNTS; do
		umount $DIR/$MNT
	done
	set -e
	return $RET
}

function build {

	# setup dependencies
	mkdir -p npm 
	export NPM_CONFIG_PREFIX=~/npm
	export PATH=~/npm/bin:$PATH
	npm install -g esy
	if [ -d oni2 ]; then
		cd oni2
		git pull
	else
		git clone https://github.com/onivim/oni2
		cd oni2
	fi
	npm install -g node-gyp
	node install-node-deps.js

	# build project
	esy install
	esy bootstrap
	esy build

	# create release package
	esy '@release' install
	esy '@release' run -f --checkhealth
	esy '@release' create
}

main
