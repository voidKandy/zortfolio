FROM debian:12 as builder

# Set the Zig version explicitly
ARG ZIGVER=0.15.1

# Install curl and xz for downloading and extracting Zig
RUN apt-get update && \
apt-get install -y curl xz-utils && \
rm -rf /var/lib/apt/lists/*

# Download and extract the Zig compiler
RUN mkdir -p /deps
WORKDIR /deps

# Download the Zig binary for the given version
RUN curl -L https://ziglang.org/download/$ZIGVER/zig-x86_64-linux-$ZIGVER.tar.xz -o zig.tar.xz && \
    tar xf zig.tar.xz && \
    mv zig-x86_64-linux-$ZIGVER /zig

FROM debian:12

RUN apt-get update && \
    apt-get install -y libc6-dev curl && \
    rm -rf /var/lib/apt/lists/*

COPY --from=builder /zig/ /usr/local/zig/

ENV PATH="/usr/local/zig:${PATH}"

WORKDIR ./zortfolio
ADD . ./
RUN touch .env 

RUN zig build

CMD ["./zig-out/bin/zortfolio"]
