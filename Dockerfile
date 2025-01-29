FROM alpine:3.13 as builder
RUN apk update && \
    apk add \
        curl \
        xz

ARG ZIGVER=0.13.0

RUN mkdir -p /deps
WORKDIR /deps
RUN curl -L https://ziglang.org/download/$ZIGVER/zig-linux-$(uname -m)-$ZIGVER.tar.xz -O && \
    tar xf zig-linux-$(uname -m)-$ZIGVER.tar.xz && \
    mv zig-linux-$(uname -m)-$ZIGVER/ local/

FROM alpine:3.13
COPY --from=builder /deps/local/ /deps/local/
RUN zig build run
