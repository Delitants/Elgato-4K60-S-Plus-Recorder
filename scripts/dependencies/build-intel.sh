#!/bin/bash
set -euo pipefail
ROOT="$(pwd)/work/implementation/intel"
PREFIX="$ROOT/prefix"
mkdir -p "$PREFIX/lib/pkgconfig" "$PREFIX/include"
cmake -S "$ROOT/svt-av1/SVT-AV1-v4.2.0" -B "$ROOT/svt-build" -G Ninja -DCMAKE_OSX_ARCHITECTURES=x86_64 -DCMAKE_OSX_DEPLOYMENT_TARGET=26.0 -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PREFIX" -DBUILD_APPS=OFF -DBUILD_TESTING=OFF -DCOMPILE_C_ONLY=ON -DBUILD_SHARED_LIBS=ON
cmake --build "$ROOT/svt-build" -j 6
cmake --install "$ROOT/svt-build"
cmake -S "$ROOT/opus/opus-1.6.1" -B "$ROOT/opus-build" -G Ninja -DCMAKE_OSX_ARCHITECTURES=x86_64 -DCMAKE_OSX_DEPLOYMENT_TARGET=26.0 -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PREFIX" -DBUILD_SHARED_LIBS=ON -DOPUS_BUILD_TESTING=OFF
cmake --build "$ROOT/opus-build" -j 6
cmake --install "$ROOT/opus-build"
mkdir -p "$ROOT/x265-build"
bash "$(pwd)/scripts/dependencies/build-intel-main10.sh"
SDK="$(pwd)/work/implementation/obsdeps"
lipo "$SDK/lib/libx264.dylib" -thin x86_64 -output "$PREFIX/lib/libx264.dylib"
cp "$SDK/include/x264.h" "$SDK/include/x264_config.h" "$PREFIX/include/"
cat > "$PREFIX/lib/pkgconfig/x264.pc" <<EOF
prefix=$PREFIX
libdir=\${prefix}/lib
includedir=\${prefix}/include
Name: x264
Description: H.264 encoder
Version: 0.164.3106
Libs: -L\${libdir} -lx264
Cflags: -I\${includedir}
EOF
cd "$ROOT/libusb/libusb-1.0.30"
ac_cv_func_pipe2=no CFLAGS='-arch x86_64 -mmacosx-version-min=26.0' LDFLAGS='-arch x86_64' ./configure --host=x86_64-apple-darwin --prefix="$PREFIX" --disable-static
make -j 6
make install
cd "$ROOT/ffmpeg-8.1.2"
PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig" ./configure --prefix="$PREFIX" --arch=x86_64 --target-os=darwin --enable-cross-compile --cc=clang --cxx=clang++ --extra-cflags="-arch x86_64 -mmacosx-version-min=26.0 -I$PREFIX/include" --extra-ldflags="-arch x86_64 -L$PREFIX/lib" --disable-x86asm --enable-shared --disable-static --disable-programs --disable-doc --disable-autodetect --disable-everything --enable-gpl --enable-version3 --enable-libx264 --enable-libx265 --enable-libsvtav1 --enable-libopus --enable-videotoolbox --enable-audiotoolbox --enable-avcodec --enable-avformat --enable-swscale --enable-swresample --enable-protocol=file,pipe --enable-decoder=h264,hevc --enable-parser=h264,hevc --enable-encoder=libx264,libx265,libsvtav1,libopus,aac,alac,flac,pcm_s16le,h264_videotoolbox,hevc_videotoolbox,prores_videotoolbox --enable-muxer=mov,mp4,matroska,mpegts --enable-bsf=hevc_mp4toannexb,h264_mp4toannexb,extract_extradata --enable-hwaccel=h264_videotoolbox,hevc_videotoolbox
make -j 6
make install
