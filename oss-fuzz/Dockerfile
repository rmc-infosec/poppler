FROM gcr.io/oss-fuzz-base/base-builder

# Install build tools
RUN apt-get update && apt-get install -y \
    wget \
    autoconf \
    automake \
    libtool \
    pkg-config \
    gperf \
    python3-pip \
    python3-setuptools \
    python3-wheel \
    ninja-build

# Install python build system deps
RUN pip3 install meson gyp-next packaging

# --- Clone Dependencies ---

# zlib
RUN git clone --depth 1 https://github.com/madler/zlib.git

# FreeType
RUN git clone --depth 1 https://gitlab.freedesktop.org/freetype/freetype.git

# Little-CMS
RUN git clone --depth 1 https://github.com/mm2/Little-CMS.git

# OpenJPEG
RUN git clone --depth 1 https://github.com/uclouvain/openjpeg

# libpng (Pinned version to avoid build issues)
RUN git clone https://github.com/glennrp/libpng.git && \
    cd libpng && \
    git checkout b4800bae3379f1abf82359703c28e727b5df4135

# Fontconfig
RUN git clone --depth 1 https://gitlab.freedesktop.org/fontconfig/fontconfig.git

# Cairo
RUN git clone --depth 1 https://gitlab.freedesktop.org/cairo/cairo.git

# Qt5 (Branch 5.15)
RUN git clone --depth 1 --branch=5.15 git://code.qt.io/qt/qtbase.git

# Pango (Pinned version)
RUN git clone https://gitlab.gnome.org/GNOME/pango.git && \
    cd pango && \
    git checkout d0cd499e17cdcfdc3f7a93d0d28a3df3c5f9b10e

# GLib (Release 2.80.0)
RUN wget https://download.gnome.org/sources/glib/2.80/glib-2.80.0.tar.xz && \
    tar xvJf glib-2.80.0.tar.xz && \
    rm glib-2.80.0.tar.xz

# Boost (1.87.0)
RUN wget https://archives.boost.io/release/1.87.0/source/boost_1_87_0.tar.bz2

# NSS (3.99)
RUN wget https://ftp.mozilla.org/pub/security/nss/releases/NSS_3_99_RTM/src/nss-3.99-with-nspr-4.35.tar.gz

# --- Target Project ---
RUN git clone --depth 1 https://gitlab.freedesktop.org/poppler/poppler.git

WORKDIR poppler
COPY build.sh $SRC/