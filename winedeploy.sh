#!/bin/bash

# sudo add-apt-repository "deb http://archive.ubuntu.com/ubuntu $(lsb_release -sc) universe"
sudo dpkg --add-architecture i386
sudo apt-get update
sudo apt install p7zip-full icoutils # For Notepad++

# Get Wine
wget -c https://www.playonlinux.com/wine/binaries/phoenicis/upstream-linux-amd64/PlayOnLinux-wine-4.4-upstream-linux-amd64.tar.gz

# Get old Wine (for icons and such)
# apt download libc6:i386
# ./W	dpkg -x wine*.deb .

# Download ALL the i386 dependencies of Wine down to glibc/libc6, but not Wine itself
# (we have a newer one)
URLS=$(apt-get --allow-unauthenticated -o Apt::Get::AllowUnauthenticated=true \
-o Debug::NoLocking=1 -o APT::Cache-Limit=125829120 -o Dir::Etc::sourceparts=- \
-o APT::Get::List-Cleanup=0 -o APT::Get::AllowUnauthenticated=1 \
-o Debug::pkgProblemResolver=true -o Debug::pkgDepCache::AutoInstall=true \
-o APT::Install-Recommends=0 -o APT::Install-Suggests=0 -y \
install --print-uris wine:i386 | grep "_i386" | grep -v "wine" | cut -d "'" -f 2 )

wget -c $URLS

# Get unionfs-fuse to make shared read-only wineprefix usable for every user
apt download fuse unionfs-fuse libfuse2 # 32-bit versions seemingly do not work properly on 64-bit machines

# Get suitable old ld-linux.so and the stuff that comes with it
# apt download libc6:i386 # It is already included above

mkdir -p ./Wine.AppDir
tar xfv PlayOnLinux-wine-* -C ./Wine.AppDir 
cd Wine.AppDir/

# Extract debs
find ../.. -name '*.deb' -exec dpkg -x {} . \;

# Make absolutely sure it will not load stuff from /lib or /usr
sed -i -e 's|/usr|/xxx|g' lib/ld-linux.so.2
sed -i -e 's|/usr/lib|/ooo/ooo|g' lib/ld-linux.so.2

# Remove duplicate (why is it there?)
rm -f lib/i386-linux-gnu/ld-*.so

# Workaround for:
# p11-kit: couldn't load module
rm usr/lib/i386-linux-gnu/libp11-* || true
find . -path '*libp11*' -delete || true

# Only use Windows fonts. Do not attempt to use fonts from the host
# This should greatly speed up first-time launch times
# and get rid of fontconfig messages
sed -i -e 's|fontconfig|xxxxconfig|g'  lib/wine/gdi32.dll.so
find . -path '*fontconfig*' -delete

# Get libhookexecv.so
cp ../libhookexecv.so lib/libhookexecv.so

# Get wine-preloader_hook
cp ../wine-preloader_hook bin/
chmod +x bin/wine-preloader_hook

# Write custom AppRun
cat > AppRun <<\EOF 
#!/bin/bash
HERE="$(dirname "$(readlink -f "${0}")")"

export LD_LIBRARY_PATH="$HERE/usr/lib":$LD_LIBRARY_PATH
export LD_LIBRARY_PATH="$HERE/usr/lib/i386-linux-gnu":$LD_LIBRARY_PATH
export LD_LIBRARY_PATH="$HERE/lib":$LD_LIBRARY_PATH
export LD_LIBRARY_PATH="$HERE/lib/i386-linux-gnu":$LD_LIBRARY_PATH

#Sound Library
export LD_LIBRARY_PATH="$HERE/usr/lib/i386-linux-gnu/pulseaudio":$LD_LIBRARY_PATH
export LD_LIBRARY_PATH="$HERE/usr/lib/i386-linux-gnu/alsa-lib":$LD_LIBRARY_PATH

#LD
export WINELDLIBRARY="$HERE/lib/ld-linux.so.2"

# Do not ask to install Mono or Gecko
export WINEDLLOVERRIDES="mscoree,mshtml=" 

while getopts "a:c:" arg
do
        case $arg in
             a)
                Args="$OPTARG"
                ;;

             c)
                Command="$OPTARG"
                echo "Run Command: $Command"
                ;;
             ?)
                echo "Unknown argument"
        exit 1
        ;;
        esac
done
s
if [ -n "$Command" ] ; then
    if [ -n "$Args" ] ; then
        LD_PRELOAD="$HERE/bin/libhookexecv.so" "$WINELDLIBRARY" "$HERE/bin/$Command" "$Args" | cat
    else
        LD_PRELOAD="$HERE/bin/libhookexecv.so" "$WINELDLIBRARY" "$HERE/bin/$Command" | cat
    fi
else
    LD_PRELOAD="$HERE/bin/libhookexecv.so" "$WINELDLIBRARY" "$HERE/bin/wine" "$@" | cat
fi
EOF

chmod +x AppRun

# Why is this needed? Probably because our Wine was compiled on a different distribution
( cd ./lib/i386-linux-gnu/ ; ln -s libudev.so.1 libudev.so.0 )
( cd ./usr/lib/i386-linux-gnu/ ; rm -f libpng12.so.0 ; ln -s ../../../lib/libpng12.so.0 . )
rm -rf lib64/

# Cannot move around share since Wine has the relative path to it; hence symlinking
# so that the desktop file etc. are in the correct place for desktop integration
cp -r usr/share share/ && rm -rf usr/share
( cd usr/ ; ln -s ../share . )

cat > wine.desktop <<\EOF
[Desktop Entry]
Name=Wine
Exec=AppRun
Icon=wine
Type=Application
Categories=Network;
Name[en_US]=Wine
EOF

touch wine.svg # FIXME

export VERSION=$(strings ./lib/libwine.so.1 | grep wine-[\.0-9] | cut -d "-" -f 2)

cd ..

wget -c "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage"
chmod +x ./appimagetool-x86_64.AppImage
ARCH=x86_64 ./appimagetool-x86_64.AppImage -g ./Wine.AppDir

( cd ./Wine.AppDir )
