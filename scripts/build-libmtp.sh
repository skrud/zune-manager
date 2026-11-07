#!/usr/bin/env bash
# Builds the owner's libmtp fork (with MTPZ) and installs it where the app links it.
set -euo pipefail

FORK=${LIBMTP_FORK:-$HOME/workspace/libmtp}
PREFIX=${LIBMTP_PREFIX:-$HOME/.local/opt/libmtp-zune}

die() { echo "build-libmtp: $*" >&2; exit 1; }

[ -d "$FORK/src" ] || die "libmtp fork not found at $FORK (set LIBMTP_FORK)"
grep -A1 '"Zune", 0x0710' "$FORK/src/music-players.h" | grep -q DEVICE_FLAG_BROKEN_MTPGETOBJPROPLIST_ALL \
  || die "the fork's Zune entry lacks DEVICE_FLAG_BROKEN_MTPGETOBJPROPLIST_ALL (see third_party/libmtp-zune.patch)"
grep -q LIBMTP_Object_Exists_On_Device "$FORK/src/libmtp.h.in" \
  || die "the fork lacks LIBMTP_Object_Exists_On_Device (see third_party/libmtp-zune.patch)"

for dep in libgcrypt libusb libtool gettext; do
  brew --prefix "$dep" >/dev/null 2>&1 \
    || die "missing Homebrew packages; run: brew install libgcrypt libusb autoconf automake libtool gettext pkg-config"
done

export MACOSX_DEPLOYMENT_TARGET=14.0  # match the app's minimum macOS
export PATH="$(brew --prefix libtool)/libexec/gnubin:$(brew --prefix gettext)/bin:$PATH"
HB=$(brew --prefix)

cd "$FORK"
[ -x configure ] || ./autogen.sh
make clean >/dev/null 2>&1 || true
./configure --prefix="$PREFIX" CPPFLAGS="-I$HB/include" LDFLAGS="-L$HB/lib" >/dev/null
make -j8 >/dev/null
make install >/dev/null

grep -q 'define USE_MTPZ' config.h || die "MTPZ support was not enabled (is libgcrypt installed?)"
otool -L "$PREFIX/lib/libmtp.dylib" | grep -q gcrypt || die "installed libmtp is not linked against libgcrypt"
nm -gU "$PREFIX/lib/libmtp.dylib" | grep -q _LIBMTP_Object_Exists_On_Device \
  || die "installed libmtp does not export LIBMTP_Object_Exists_On_Device"

echo "libmtp-zune installed at $PREFIX"
