FROM debian:10.9-slim AS base

ENV MOSQUITTO_VERSION=2.0.10 \
    MOSQUITTO_GO_AUTH_VERSION=1.5.0 \
    CJSON_VERSION=1.7.14 \
    LWS_VERSION=4.1.6 \
    GOLANG_VERSION=1.15.6

RUN set -x && \
# Install build dependencies
    apt-get update && \
    apt-get install -y --no-install-recommends \
        wget \
        libssl-dev \
        cmake \
        ca-certificates \
        build-essential && \
# Download libwebsockets source code and build
    wget \
        -nv \
        -O /tmp/lws.tar.gz \
        https://github.com/warmcat/libwebsockets/archive/refs/tags/v${LWS_VERSION}.tar.gz && \
    mkdir -p /build/lws/build && \
    tar --strip-components=1 -zxf /tmp/lws.tar.gz -C /build/lws && \
    rm /tmp/lws.tar.gz && \
    cd /build/lws/build && \
    cmake .. \
        -DCMAKE_BUILD_TYPE=MinSizeRel \
        -DBUILD_TESTING:BOOL=OFF \
        -DLWS_WITH_SHARED:BOOL=OFF \
        -DLWS_WITH_EXTERNAL_POLL:BOOL=ON \
        -DLWS_WITHOUT_CLIENT:BOOL=ON \
        -DLWS_WITHOUT_EXTENSIONS:BOOL=ON \
        -DLWS_WITHOUT_TESTAPPS:BOOL=ON \
        -DLWS_WITHOUT_TEST_CLIENT:BOOL=ON \
        -DLWS_WITHOUT_TEST_PING:BOOL=ON \
        -DLWS_WITHOUT_TEST_SERVER:BOOL=ON \
        -DLWS_WITHOUT_TEST_SERVER_EXTPOLL=ON && \
    make -j "$(nproc)" && \
    rm -rf ~/.cmake && \
# Download cJSON source code and build
    wget \
        -nv \
        -O /tmp/cjson.tar.gz \
        https://github.com/DaveGamble/cJSON/archive/refs/tags/v${CJSON_VERSION}.tar.gz && \
    mkdir -p /build/cjson/build && \
    tar --strip-components=1 -zxf /tmp/cjson.tar.gz -C /build/cjson && \
    rm /tmp/cjson.tar.gz && \
    cd /build/cjson/build && \
    cmake .. \
        -DCMAKE_BUILD_TYPE=MinSizeRel \
        -DENABLE_CJSON_TEST=Off \
        -DENABLE_CJSON_UTILS=Off \
        -DBUILD_SHARED_LIBS=Off \
        -DBUILD_SHARED_AND_STATIC_LIBS=Off && \
    make -j "$(nproc)" && \
    rm -rf ~/.cmake && \
    wget \
        -nv \
        -O /tmp/mosquitto.tar.gz \
        https://mosquitto.org/files/source/mosquitto-${MOSQUITTO_VERSION}.tar.gz && \
    mkdir -p /build/mosquitto && \
    tar --strip-components=1 -zxf /tmp/mosquitto.tar.gz -C /build/mosquitto && \
    rm /tmp/mosquitto.tar.gz && \
    cd /build/mosquitto && \
    make \
        CFLAGS="-I/build/lws/build/include -I/build" \
        LDFLAGS="-L/build/lws/build/lib -L/build/cjson/build" \
        -j "$(nproc)" \
        WITH_WEBSOCKETS=yes \
        WITH_STRIP=yes \
        WITH_SRV=no \
        WITH_DOCS=no && \
# Install the header files since the mosquitto-go-auth needs it
    install -d /usr/local/include && \
    install -m544 -t /usr/local/include include/* && \
# Download golang binary files
    wget \
        -nv \
        -O /tmp/go.tar.gz \
        https://dl.google.com/go/go${GOLANG_VERSION}.linux-amd64.tar.gz && \
    mkdir -p /build/golang && \
    tar --strip-components=1 -zxf /tmp/go.tar.gz -C /build/golang && \
    rm /tmp/go.tar.gz && \
    export PATH=$PATH:/build/golang/bin && \
# Download mosquitto-go-auth source code and build
    wget \
        -nv \
        -O /tmp/mosquitto-go-auth.tar.gz \
        https://github.com/iegomez/mosquitto-go-auth/archive/${MOSQUITTO_GO_AUTH_VERSION}.tar.gz && \
    mkdir -p /build/mosquitto-go-auth && \
    tar \
        --strip-components=1 \
        -zxf /tmp/mosquitto-go-auth.tar.gz \
        -C /build/mosquitto-go-auth && \
    rm /tmp/mosquitto-go-auth.tar.gz && \
    cd /build/mosquitto-go-auth && \
    make -j "$(nproc)" && \
# Install the eclipse mosquitto executable file, client executable files
# and shared libraries.
    install -d /usr/local/lib /usr/local/bin && \
    install -s -m755 /build/mosquitto/src/mosquitto /usr/local/bin/mosquitto && \
    install -s -m755 /build/mosquitto/client/mosquitto_pub /usr/local/bin/mosquitto_pub && \
    install -s -m755 /build/mosquitto/client/mosquitto_rr /usr/local/bin/mosquitto_rr && \
    install -s -m755 /build/mosquitto/client/mosquitto_sub /usr/local/bin/mosquitto_sub && \
    install -s -m755 /build/mosquitto/lib/libmosquitto.so.1 /usr/local/lib/libmosquitto.so.1 && \
    install \
        -s \
        -m755 \
        /build/mosquitto/apps/mosquitto_ctrl/mosquitto_ctrl \
        /usr/local/bin/mosquitto_ctrl && \
    install \
        -s \
        -m755 \
        /build/mosquitto/apps/mosquitto_passwd/mosquitto_passwd \
        /usr/local/bin/mosquitto_passwd && \
    install \
        -s \
        -m755 \
        /build/mosquitto/plugins/dynamic-security/mosquitto_dynamic_security.so \
        /usr/local/lib/mosquitto_dynamic_security.so && \
# Install other required shared libraries
    cp -a \
        /build/mosquitto-go-auth/go-auth.so \
        /usr/local/lib && \
    chmod a-x /usr/local/lib/*.so* && \
# Strip the symbol tables from those shared object files to reduce their size
    strip /usr/local/lib/*.so*

FROM debian:10.9-slim

WORKDIR /mosquitto

# Copy the required shared libraries from the base image
COPY --from=base /usr/local/lib/ /usr/local/lib/

# Copy the eclipse mosquitto and client executable file from the base image
COPY --from=base /usr/local/bin/ /usr/local/bin/

# Copy the default eclipse mosquitto configuration file from the base image
COPY --from=base /build/mosquitto/mosquitto.conf /mosquitto/config/

COPY entrypoint.sh /

RUN set -x && \
# Install run-time dependencies
    apt-get update && \
    apt-get install -y libssl-dev && \
    mkdir -p /mosquitto/config /mosquitto/data /mosquitto/log && \
# Add a group and an user named mosquitto
    groupadd -g 1883 -r mosquitto 2>/dev/null && \
    useradd -g mosquitto -u 1883 -M -r -s /usr/sbin/nologin mosquitto 2>/dev/null && \
    chown -R mosquitto:mosquitto /mosquitto && \
# Rebuild ld cache
    rm /etc/ld.so.cache && \
    ldconfig >/dev/null 2>&1 && \
# Remove packages index
    rm -rf /var/lib/apt/lists/*

VOLUME ["/mosquitto/data", "/mosquitto/log"]

EXPOSE 1883/tcp

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/usr/local/bin/mosquitto", "-c", "/mosquitto/config/mosquitto.conf"]
