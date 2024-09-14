
# syntax=docker/dockerfile:1

FROM rust:1.81-slim-bookworm AS plato-builder-base

ARG PLATO_CURRENT_VERSION=0.9.43

# install dependencies
ARG DEBIAN_FRONTEND=noninteractive
RUN dpkg --add-architecture armhf \
    && apt-get update \
    && apt-get install --no-install-recommends --yes \
    jq \
    patchelf \
    pkg-config \
    unzip \
    wget \
    #  add armhf as target to rust
    && rustup target add arm-unknown-linux-gnueabihf \
    #  clean up stuff
    && rm --recursive --force \
    /var/lib/apt/lists/* \
    /usr/share/doc/ \
    /usr/share/man/ \
    /tmp/* \
    /var/tmp/* \
    && apt-get clean
RUN apt-get update && apt-get install -y \
    autoconf \
    automake \
    libtool \
    libevdev-dev \
    python3.11 \
    pkg-config \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

ENV PATH=/gcc-linaro/bin:$PATH
ENV CC=arm-linux-gnueabihf-gcc
ENV CXX=arm-linux-gnueabihf-g++

FROM plato-builder-base AS plato-builder-libs

RUN apt-get update \
    && apt-get install --no-install-recommends --yes \
    cmake \
    git \
    make \
    xz-utils \
    #  clean up
    && apt-get clean \
    && rm --recursive --force /var/lib/apt/lists/*

# download and extract gcc linaro to $PATH
# checksum is same with the Kobo Reader's toolchain Git LFS file reference:
# https://github.com/kobolabs/Kobo-Reader/blob/master/toolchain/gcc-linaro-4.9.4-2017.01-x86_64_arm-linux-gnueabihf.tar.xz
ADD --checksum=sha256:22914118fd963f953824b58107015c6953b5bbdccbdcf25ad9fd9a2f9f11ac07 \
    https://releases.linaro.org/components/toolchain/binaries/4.9-2017.01/arm-linux-gnueabihf/gcc-linaro-4.9.4-2017.01-x86_64_arm-linux-gnueabihf.tar.xz /
RUN tar --extract --xz --verbose \
    --file gcc-linaro-4.9.4-2017.01-x86_64_arm-linux-gnueabihf.tar.xz \
    && mv --verbose /gcc-linaro-4.9.4-2017.01-x86_64_arm-linux-gnueabihf/ /gcc-linaro/ \
    && rm --verbose /gcc-linaro-4.9.4-2017.01-x86_64_arm-linux-gnueabihf.tar.xz

RUN cd /usr/src/ \
    && git clone --depth 1 --recurse-submodules https://github.com/arjpar/aristotle.git \
    && git config --global --add safe.directory /usr/src/aristotle \
    && cd /usr/src/aristotle/ \
    && ./build.sh

FROM plato-builder-base AS plato-builder

COPY --from=plato-builder-libs /gcc-linaro/ /gcc-linaro/

# Rust crate caching:
# https://doc.rust-lang.org/cargo/guide/cargo-home.html#caching-the-cargo-home-in-ci
COPY --from=plato-builder-libs $CARGO_HOME/registry/index/ $CARGO_HOME/registry/index/
COPY --from=plato-builder-libs $CARGO_HOME/registry/cache/ $CARGO_HOME/registry/cache/

COPY --from=plato-builder-libs /usr/src/aristotle/libs/ /usr/src/aristotle/libs/
COPY --from=plato-builder-libs /usr/src/aristotle/target/ /usr/src/aristotle/target/
COPY --from=plato-builder-libs /usr/src/aristotle/thirdparty/mupdf/ /usr/src/aristotle/thirdparty/mupdf/
COPY --from=plato-builder-libs /usr/src/aristotle/aristotle-${PLATO_CURRENT_VERSION}.zip /usr/src/aristotle/

WORKDIR /usr/src/aristotle

COPY . .

#RUN cargo install cross
#RUN cross build --target=arm-unknown-linux-gnueabihf --release

CMD [ "./build.sh" ]
