FROM alpine:3.13 as builder

RUN apk update && \
    apk add \
        curl \
        xz

ARG ZIGVER
RUN mkdir -p /deps
WORKDIR /deps
RUN curl https://ziglang.org/deps/zig+llvm+lld+clang-$(uname -m)-linux-musl-$ZIGVER.tar.xz  -O && \
    tar xf zig+llvm+lld+clang-$(uname -m)-linux-musl-$ZIGVER.tar.xz && \
    mv zig+llvm+lld+clang-$(uname -m)-linux-musl-$ZIGVER/ local/
    

COPY --from=builder /deps/local/ /deps/local/

RUN zig build run
