FROM debian:stable-slim AS base

ENV MOSQUITTO_VERSION=1.6.9 MOSQUITTO_GO_AUTH_VERSION=0.6.3 GOLANG_VERSION=1.14.2
WORKDIR /

RUN set -x && \
    apt-get update && \
    apt-get install -y wget libwebsockets-dev libssl-dev gcc make g++ && \
    wget -nv https://mosquitto.org/files/source/mosquitto-${MOSQUITTO_VERSION}.tar.gz \
             https://dl.google.com/go/go${GOLANG_VERSION}.linux-amd64.tar.gz \
             https://github.com/iegomez/mosquitto-go-auth/archive/${MOSQUITTO_GO_AUTH_VERSION}.tar.gz && \
    mkdir -p mosquitto mosquitto-go-auth go && \
    tar -C mosquitto --strip-components=1 -zxf mosquitto-${MOSQUITTO_VERSION}.tar.gz && \
    tar -C go --strip-components=1 -zxf go${GOLANG_VERSION}.linux-amd64.tar.gz && \
    tar -C mosquitto-go-auth --strip-components=1 -zxf ${MOSQUITTO_GO_AUTH_VERSION}.tar.gz && \
    export CGO_CFLAGS="-I/usr/local/include" CGO_LDFLAGS="-shared" PATH=$PATH:/go/bin && \
    make -C mosquitto WITH_WEBSOCKETS=yes WITH_DOCS=no && \
    make -C mosquitto install && \
    make -C mosquitto-go-auth

FROM debian:stable-slim

WORKDIR /mosquitto

RUN apt-get update && \
    apt-get install -y libwebsockets8 libssl1.1 && \
    mkdir -p /mosquitto/config /mosquitto/data /mosquitto/log && \
    groupadd -r mosquitto 2>/dev/null && \
    useradd -g mosquitto -M -r -s /usr/sbin/nologin mosquitto 2>/dev/null && \
    chown -R mosquitto:mosquitto /mosquitto

COPY --from=base /usr/local/sbin/mosquitto /usr/local/bin/
COPY --from=base /mosquitto/mosquitto.conf /mosquitto/config/
COPY --from=base /mosquitto-go-auth/go-auth.so /usr/local/lib/
COPY entrypoint.sh /

VOLUME ["/mosquitto/data", "/mosquitto/log"]

EXPOSE 1883/tcp

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/usr/local/bin/mosquitto", "-c", "/mosquitto/config/mosquitto.conf"]
