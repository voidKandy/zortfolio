FROM debian:12

# Install dependencies
RUN apt-get update && apt-get install -y curl xz-utils libc6-dev tar && \
    rm -rf /var/lib/apt/lists/*

# Set up Zig
ARG ZIGVER=0.15.1
WORKDIR /deps
RUN curl -L https://ziglang.org/download/$ZIGVER/zig-x86_64-linux-$ZIGVER.tar.xz -o zig.tar.xz && \
    tar xf zig.tar.xz && \
    mv zig-x86_64-linux-$ZIGVER /usr/local/zig

ENV PATH="/usr/local/zig:${PATH}"

# Set up project directory and pull latest release tarball
WORKDIR /zortfolio
RUN curl -L https://github.com/voidKandy/zortfolio/releases/latest/download/zortfolio-latest.tar \
    -o zortfolio.tar && \
    tar xf zortfolio.tar && \
    rm zortfolio.tar

# Build the project
RUN zig build

# Default command
CMD ["./zig-out/bin/zortfolio"]
