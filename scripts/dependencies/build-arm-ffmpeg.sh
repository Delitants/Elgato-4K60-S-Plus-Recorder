#!/bin/bash
set -euo pipefail
ROOT="$(pwd)/work/implementation/arm"
PREFIX="$ROOT/prefix"
cd "$ROOT/ffmpeg-8.1.2"
PKG_CONFIG_LIBDIR="/opt/homebrew/lib/pkgconfig" ./configure --prefix="$PREFIX" --arch=arm64 --target-os=darwin --enable-cross-compile --cc=clang --cxx=clang++ --extra-cflags="-arch arm64 -mmacosx-version-min=26.0 -I/opt/homebrew/include" --extra-ldflags="-arch arm64 -L/opt/homebrew/lib" --disable-x86asm --enable-shared --disable-static --disable-programs --disable-doc --disable-autodetect --disable-everything --enable-gpl --enable-version3 --enable-libx264 --enable-libx265 --enable-libsvtav1 --enable-libopus --enable-videotoolbox --enable-audiotoolbox --enable-avcodec --enable-avformat --enable-swscale --enable-swresample --enable-protocol=file,pipe --enable-decoder=h264,hevc --enable-parser=h264,hevc --enable-encoder=libx264,libx265,libsvtav1,libopus,aac,alac,flac,pcm_s16le,h264_videotoolbox,hevc_videotoolbox,prores_videotoolbox --enable-muxer=mov,mp4,matroska,mpegts --enable-bsf=hevc_mp4toannexb,h264_mp4toannexb,extract_extradata --enable-hwaccel=h264_videotoolbox,hevc_videotoolbox
make -j 2
make install
