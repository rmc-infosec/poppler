#!/bin/bash -eu

# Setup install prefix
PREFIX=$WORK/prefix
mkdir -p $PREFIX
export PKG_CONFIG="pkg-config --static"
export PKG_CONFIG_PATH=$PREFIX/lib/pkgconfig
export PATH=$PREFIX/bin:$PATH

BUILD=$WORK/build
mkdir -p $BUILD

# Fix for FreeType/Harfbuzz cyclic dependency on some systems
export CFLAGS="$CFLAGS -D_GNU_SOURCE"

# --- Build Dependencies ---

echo "Building Boost..."
cd $SRC/
tar jxf boost_1_87_0.tar.bz2
cd boost_1_87_0/
CFLAGS="" CXXFLAGS="" ./bootstrap.sh
CFLAGS="" CXXFLAGS="" ./b2 headers
./b2 --with-math install

echo "Building zlib..."
cd $SRC/zlib
mkdir -p build && cd build
CFLAGS="-fPIC $CFLAGS" ../configure --static --prefix=$PREFIX
make install -j$(nproc)

echo "Building NSS..."
cd $SRC
tar zxf nss-3.99-with-nspr-4.35.tar.gz
cd nss-3.99
nss_flag=""
if [ "$SANITIZER" = "memory" ]; then
    nss_flag="--msan"
elif [ "$SANITIZER" = "address" ]; then
    nss_flag="--asan"
elif [ "$SANITIZER" = "undefined" ]; then
    nss_flag="--ubsan"
fi
# Disable tests, build static, point to our zlib
./nss/build.sh $nss_flag --disable-tests --static -v -Dmozilla_client=1 -Dzlib_libs=$PREFIX/lib/libz.a -Dsign_libs=0

# Install NSS pc files manually (NSS build doesn't do this well)
mkdir -p $PREFIX/lib/pkgconfig
cp nss/pkg/pkg-config/nss.pc.in $PREFIX/lib/pkgconfig/nss.pc
sed -i "s#
#${SRC}/nss-3.99/dist/public/nss#g" $PREFIX/lib/pkgconfig/nss.pc
sed -i "s#%NSS_VERSION%#3.99#g" $PREFIX/lib/pkgconfig/nss.pc
cp dist/Debug/lib/pkgconfig/nspr.pc $PREFIX/lib/pkgconfig/

echo "Building FreeType..."
cd $SRC/freetype
./autogen.sh
./configure --prefix="$PREFIX" --disable-shared PKG_CONFIG_PATH="$PKG_CONFIG_PATH"
make -j$(nproc)
make install

echo "Building Little-CMS..."
cd $SRC/Little-CMS
./autogen.sh --prefix="$PREFIX" --disable-shared PKG_CONFIG_PATH="$PKG_CONFIG_PATH"
make -j$(nproc)
make install

echo "Building OpenJPEG..."
mkdir -p $SRC/openjpeg/build
cd $SRC/openjpeg/build
# Fix linking against custom LCMS
sed -i "s#
#$PREFIX/lib 
#g" ../src/bin/jp2/CMakeLists.txt
cmake .. -DBUILD_SHARED_LIBS=OFF -DCMAKE_INSTALL_PREFIX=$PREFIX
make -j$(nproc) install

# Build others only if NOT MSan (MSan usually skips heavy GUI libs if possible, or build them carefully)
# For Poppler, we need Fontconfig/GLib for full feature coverage usually.
# The official script builds them ONLY if NOT memory sanitizer to avoid false positives in complex uninstrumented parts
# or simply because getting them MSan-clean is hard. We will follow that logic.
if [ "$SANITIZER" != "memory" ]; then
    echo "Building Fontconfig..."
    cd $SRC/fontconfig
    meson setup --prefix=$PREFIX --libdir=lib --default-library=static _builddir
    ninja -C _builddir install

    echo "Building GLib..."
    cd $SRC/glib-2.80.0
    meson setup --prefix=$PREFIX --libdir=lib --default-library=static -Db_lundef=false -Doss_fuzz=enabled -Dlibmount=disabled _builddir
    ninja -C _builddir install

    echo "Building libpng..."
    cd $SRC/libpng
    autoreconf -fi
    CPPFLAGS="-I$PREFIX/include" LDFLAGS="-L$PREFIX/lib" ./configure --prefix="$PREFIX" --disable-shared --disable-dependency-tracking
    make -j$(nproc)
    make install

    echo "Building Cairo..."
    cd $SRC/cairo
    meson setup --prefix=$PREFIX --libdir=lib --default-library=static _builddir
    ninja -C _builddir install

    echo "Building Pango..."
    cd $SRC/pango
    CFLAGS="$CFLAGS -fno-sanitize=vptr" CXXFLAGS="$CXXFLAGS -fno-sanitize=vptr" meson setup -Ddefault_library=static --prefix=$PREFIX --libdir=lib _builddir
    # Fix some build issues
    sed -i -e 's/ -Werror=implicit-fallthrough//g' _builddir/build.ninja
    ninja -C _builddir install
fi

# Qt5 Build (Skip for simplicity in this artifact, or keep if critical. Official script builds it. I'll include it.)
echo "Building Qt5..."
cd $SRC/qtbase
# Patch qmake configs to inject flags
sed -i -e "s~QMAKE_CXXFLAGS    += -stdlib=libc++~QMAKE_CXXFLAGS    += -stdlib=libc++  $CXXFLAGS\nQMAKE_CFLAGS += $CFLAGS~g" mkspecs/linux-clang-libc++/qmake.conf
sed -i -e "s~QMAKE_LFLAGS      += -stdlib=libc++~QMAKE_LFLAGS      += -stdlib=libc++ -lpthread $CXXFLAGS~g" mkspecs/linux-clang-libc++/qmake.conf
sed -i -e "s~QMAKE_CXX               = 
clang++~QMAKE_CXX = $CXX~g" mkspecs/common/clang.conf
sed -i -e "s~QMAKE_CC                = 
clang~QMAKE_CC = $CC~g" mkspecs/common/clang.conf
./configure --zlib=system --glib=no --libpng=qt -opensource -confirm-license -static -no-opengl -no-icu -platform linux-clang-libc++ -v -nomake tests -nomake examples -prefix $PREFIX -D QT_NO_DEPRECATED_WARNINGS -I $PREFIX/include/ -L $PREFIX/lib/
make -j$(nproc)
make install


# --- Build Poppler ---

# Reset PKG_CONFIG for Poppler
export PKG_CONFIG="pkg-config"

if [ "$SANITIZER" != "memory" ]; then
    POPPLER_ENABLE_GLIB=ON
    POPPLER_FONT_CONFIGURATION=fontconfig
else
    POPPLER_ENABLE_GLIB=OFF
    POPPLER_FONT_CONFIGURATION=generic
fi

mkdir -p $SRC/poppler/build
cd $SRC/poppler/build

cmake .. \
  -DCMAKE_BUILD_TYPE=Debug \
  -DBUILD_SHARED_LIBS=OFF \
  -DENABLE_FUZZER=OFF \
  -DFONT_CONFIGURATION=$POPPLER_FONT_CONFIGURATION \
  -DENABLE_DCTDECODER=none \
  -DENABLE_GOBJECT_INTROSPECTION=OFF \
  -DENABLE_LIBPNG=OFF \
  -DENABLE_ZLIB=OFF \
  -DENABLE_LIBTIFF=OFF \
  -DENABLE_LIBJPEG=OFF \
  -DENABLE_GLIB=$POPPLER_ENABLE_GLIB \
  -DENABLE_LIBCURL=OFF \
  -DENABLE_GPGME=OFF \
  -DENABLE_QT6=OFF \
  -DENABLE_QT5=ON \
  -DENABLE_UTILS=OFF \
  -DWITH_Cairo=$POPPLER_ENABLE_GLIB \
  -DCMAKE_INSTALL_PREFIX=$PREFIX

export PKG_CONFIG="pkg-config --static"
make -j$(nproc) poppler poppler-cpp poppler-qt5
if [ "$SANITIZER" != "memory" ]; then
    make -j$(nproc) poppler-glib
fi

# --- Compile Fuzzers ---

# Flags construction
PREDEPS_LDFLAGS="-Wl,-Bdynamic -ldl -lm -lc -lz -pthread -lrt -lpthread"
DEPS="freetype2 lcms2 libopenjp2"
if [ "$SANITIZER" != "memory" ]; then
    DEPS="$DEPS fontconfig libpng"
fi
# Get flags using our custom prefix pkg-config
BUILD_CFLAGS="$CFLAGS $(pkg-config --static --cflags $DEPS)"
BUILD_LDFLAGS="-Wl,-static $(pkg-config --static --libs $DEPS)"

# NSS Static Libs
NSS_STATIC_LIBS=$(ls $SRC/nss-3.99/dist/Debug/lib/lib*.a)
# Repeat libs to handle circular deps in static linking
NSS_STATIC_LIBS="$NSS_STATIC_LIBS $NSS_STATIC_LIBS $NSS_STATIC_LIBS"
BUILD_LDFLAGS="$BUILD_LDFLAGS $NSS_STATIC_LIBS"

LIB_FUZZING_ENGINE="${LIB_FUZZING_ENGINE:--fsanitize=fuzzer}"

# 1. CPP Fuzzers
echo "Compiling CPP Fuzzers..."
FUZZERS=$(find $SRC/poppler/cpp/tests/fuzzing/ -name "*_fuzzer.cc")
for f in $FUZZERS; do
    fuzzer_name=$(basename $f .cc)
    
    $CXX $CXXFLAGS -std=c++17 \
        -I$SRC/poppler/cpp -I$SRC/poppler/build/cpp \
        -I$SRC/poppler/cpp/tests/fuzzing \
        -I$SRC/poppler/poppler -I$SRC/poppler/fofi -I$SRC/poppler/goo -I$SRC/poppler \
        -I$SRC/poppler/build/poppler \
        $BUILD_CFLAGS \
        $f -o $OUT/$fuzzer_name \
        $PREDEPS_LDFLAGS \
        $SRC/poppler/build/cpp/libpoppler-cpp.a \
        $SRC/poppler/build/libpoppler.a \
        $BUILD_LDFLAGS \
        $LIB_FUZZING_ENGINE \
        -Wl,-Bdynamic
    
    # Resources
    cp $SRC/poppler/oss-fuzz/poppler_seed_corpus.zip $OUT/${fuzzer_name}_seed_corpus.zip
    cp $SRC/poppler/oss-fuzz/poppler.dict $OUT/${fuzzer_name}.dict
    cp $SRC/poppler/oss-fuzz/fuzzer.options $OUT/${fuzzer_name}.options
done

# 2. GLIB Fuzzers (Skip if MSan)
if [ "$SANITIZER" != "memory" ]; then
    echo "Compiling GLIB Fuzzers..."
    DEPS_GLIB="gmodule-2.0 glib-2.0 gio-2.0 gobject-2.0 freetype2 lcms2 libopenjp2 cairo cairo-gobject pango fontconfig libpng"
    BUILD_CFLAGS_GLIB="$CFLAGS $(pkg-config --static --cflags $DEPS_GLIB)"
    BUILD_LDFLAGS_GLIB="-Wl,-static $(pkg-config --static --libs $DEPS_GLIB) $NSS_STATIC_LIBS"

    FUZZERS=$(find $SRC/poppler/glib/tests/fuzzing/ -name "*_fuzzer.cc")
    for f in $FUZZERS; do
        fuzzer_name=$(basename $f .cc)
        
        $CXX $CXXFLAGS -std=c++17 \
            -I$SRC/poppler/glib -I$SRC/poppler/build/glib \
            $BUILD_CFLAGS_GLIB \
            $f -o $OUT/$fuzzer_name \
            $PREDEPS_LDFLAGS \
            $SRC/poppler/build/glib/libpoppler-glib.a \
            $SRC/poppler/build/cpp/libpoppler-cpp.a \
            $SRC/poppler/build/libpoppler.a \
            $BUILD_LDFLAGS_GLIB \
            $LIB_FUZZING_ENGINE \
            -Wl,-Bdynamic
        
        # Resources
        cp $SRC/poppler/oss-fuzz/poppler_seed_corpus.zip $OUT/${fuzzer_name}_seed_corpus.zip
        cp $SRC/poppler/oss-fuzz/poppler.dict $OUT/${fuzzer_name}.dict
        cp $SRC/poppler/oss-fuzz/fuzzer.options $OUT/${fuzzer_name}.options
    done
fi

# 3. Qt5 Fuzzers
echo "Compiling Qt5 Fuzzers..."
DEPS_QT="freetype2 lcms2 libopenjp2 Qt5Core Qt5Gui Qt5Xml"
if [ "$SANITIZER" != "memory" ]; then
    DEPS_QT="$DEPS_QT fontconfig libpng"
fi
BUILD_CFLAGS_QT="$CFLAGS $(pkg-config --static --cflags $DEPS_QT)"
BUILD_LDFLAGS_QT="-Wl,-static $(pkg-config --static --libs $DEPS_QT) $NSS_STATIC_LIBS"

FUZZERS=$(find $SRC/poppler/qt5/tests/fuzzing/ -name "*_fuzzer.cc")
for f in $FUZZERS; do
    fuzzer_name=$(basename $f .cc)
    
    $CXX $CXXFLAGS -std=c++17 -fPIC \
        -I$SRC/poppler/qt5/src -I$SRC/poppler/build/qt5/src \
        $BUILD_CFLAGS_QT \
        $f -o $OUT/$fuzzer_name \
        $PREDEPS_LDFLAGS \
        $SRC/poppler/build/qt5/src/libpoppler-qt5.a \
        $SRC/poppler/build/cpp/libpoppler-cpp.a \
        $SRC/poppler/build/libpoppler.a \
        $BUILD_LDFLAGS_QT \
        $LIB_FUZZING_ENGINE \
        -Wl,-Bdynamic

    # Resources
    cp $SRC/poppler/oss-fuzz/poppler_seed_corpus.zip $OUT/${fuzzer_name}_seed_corpus.zip
    cp $SRC/poppler/oss-fuzz/poppler.dict $OUT/${fuzzer_name}.dict
    cp $SRC/poppler/oss-fuzz/fuzzer.options $OUT/${fuzzer_name}.options
done

echo "Done."
