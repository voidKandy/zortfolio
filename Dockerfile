FROM alpine:3.13 as builder

# Set the Zig version explicitly
ARG ZIGVER=0.13.0

# Install curl and xz for downloading and extracting Zig
RUN apk update && \
    apk add \
        curl \
        xz

# Download and extract the Zig compiler
RUN mkdir -p /deps
WORKDIR /deps

# Download the Zig binary for the given version
# https://ziglang.org/download/0.13.0/zig-linux-x86_64-0.13.0.tar.xz
RUN curl -L https://ziglang.org/download/$ZIGVER/zig-linux-x86_64-$ZIGVER.tar.xz -o zig.tar.xz && \
    tar xf zig.tar.xz && \
    mv zig-linux-x86_64-$ZIGVER /zig

FROM alpine:3.13

RUN apk --no-cache add \
      libc-dev \
      curl

COPY --from=builder /zig/ /usr/local/zig/

ENV PATH="/usr/local/zig:${PATH}"


RUN zig build run
