FROM debian:stable-slim AS base

ENV MOSQUITTO_VERSION=2.0.10 \
    MOSQUITTO_GO_AUTH_VERSION=1.5.0 \
    CJSON_VERSION=1.7.14 \
    C_ARES_VERSION=1.17.1 \
    LWS_VERSION=4.1.6 \
    GOLANG_VERSION=1.15.6
WORKDIR /

RUN set -x && \
    apt-get update && \
    apt-get install -y wget libssl-dev libwrap0-dev gcc g++ make cmake && \
    wget -nv https://github.com/warmcat/libwebsockets/archive/refs/tags/v${LWS_VERSION}.tar.gz -O /tmp/lws.tar.gz && \
    mkdir -p /build/lws && \
    tar --strip-components=1 -zxf /tmp/lws.tar.gz -C /build/lws && \
    rm /tmp/lws.tar.gz && \
    cd /build/lws && \
    cmake . \
      -DLWS_WITH_SHARED:BOOL=OFF \
      -DLWS_WITHOUT_CLIENT:BOOL=ON \
      -DLWS_WITHOUT_EXTENSIONS:BOOL=ON \
      -DLWS_WITHOUT_TESTAPPS:BOOL=ON \
      -DLWS_WITHOUT_TEST_SERVER:BOOL=ON \
      -DLWS_WITHOUT_TEST_SERVER_EXTPOLL=ON && \
    make -j "$(nproc)" && \
    rm -rf ~/.cmake && \
    wget -nv https://github.com/DaveGamble/cJSON/archive/refs/tags/v${CJSON_VERSION}.tar.gz -O /tmp/cjson.tar.gz && \
    mkdir -p /build/cjson && \
    tar --strip-components=1 -zxf /tmp/cjson.tar.gz -C /build/cjson && \
    rm /tmp/cjson.tar.gz && \
    cd /build/cjson && \
    cmake . \
      -DENABLE_CJSON_TEST=Off \
      -DENABLE_CJSON_UTILS=Off \
      -DBUILD_SHARED_LIBS=Off \
      -DBUILD_SHARED_AND_STATIC_LIBS=Off && \
    make -j "$(nproc)" && \
    rm -rf ~/.cmake && \
    wget -nv https://c-ares.haxx.se/download/c-ares-${C_ARES_VERSION}.tar.gz -O /tmp/c-ares.tar.gz && \
    mkdir -p /build/c-ares && \
    tar --strip-components=1 -zxf /tmp/c-ares.tar.gz -C /build/c-ares && \
    rm /tmp/c-ares.tar.gz && \
    cd /build/c-ares && \
    cmake . \
      -DCARES_STATIC:BOOL=ON \
      -DCARES_SHARED:BOOL=OFF && \
    make -j "$(nproc)" && \
    rm -rf ~/.cmake && \
    wget -nv https://mosquitto.org/files/source/mosquitto-${MOSQUITTO_VERSION}.tar.gz -O /tmp/mosquitto.tar.gz && \
    mkdir -p /build/mosquitto && \
    tar --strip-components=1 -zxf /tmp/mosquitto.tar.gz -C /build/mosquitto && \
    rm /tmp/mosquitto.tar.gz && \
    cd /build/mosquitto && \
    make \
      CFLAGS="-I/build/lws/include -I/build/c-ares/include -I/build" \
      LDFLAGS="-L/build/lws/lib -L/build/c-ares/lib -L/build/cjson" \
      -j "$(nproc)" \
      WITH_WRAP=yes \
      WITH_SRV=yes \
      WITH_WEBSOCKETS=yes \
      WITH_DOCS=no && \
    make install && \
    wget -nv https://dl.google.com/go/go${GOLANG_VERSION}.linux-amd64.tar.gz -O /tmp/go.tar.gz && \
    mkdir -p /go && \
    tar --strip-components=1 -zxf /tmp/go.tar.gz -C /go && \
    rm /tmp/go.tar.gz && \
    export PATH=$PATH:/go/bin && \
    wget \
      -nv \
      https://github.com/iegomez/mosquitto-go-auth/archive/${MOSQUITTO_GO_AUTH_VERSION}.tar.gz \
      -O /tmp/mosquitto-go-auth.tar.gz && \
    mkdir -p /build/mosquitto-go-auth && \
    tar --strip-components=1 -zxf /tmp/mosquitto-go-auth.tar.gz -C /build/mosquitto-go-auth && \
    rm /tmp/mosquitto-go-auth.tar.gz && \
    cd /build/mosquitto-go-auth && \
    make

FROM debian:stable-slim

WORKDIR /mosquitto

RUN apt-get update && \
    apt-get install -y libssl-dev libwrap0-dev && \
    mkdir -p /mosquitto/config /mosquitto/data /mosquitto/log && \
    groupadd -g 1883 -r mosquitto 2>/dev/null && \
    useradd -g mosquitto -u 1883 -M -r -s /usr/sbin/nologin mosquitto 2>/dev/null && \
    chown -R mosquitto:mosquitto /mosquitto

COPY --from=base /usr/local/sbin/mosquitto /usr/local/bin/
COPY --from=base /build/mosquitto/mosquitto.conf /mosquitto/config/
COPY --from=base /build/mosquitto-go-auth/go-auth.so /usr/local/lib/
COPY entrypoint.sh /

VOLUME ["/mosquitto/data", "/mosquitto/log"]

EXPOSE 1883/tcp

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/usr/local/bin/mosquitto", "-c", "/mosquitto/config/mosquitto.conf"]
