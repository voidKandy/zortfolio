FROM alpine:3.13 as builder

# Set the Zig version explicitly

# Install curl and xz for downloading and extracting Zig
RUN apk update && \
    apk add \
        curl \
        xz

# Download and extract the Zig compiler
RUN mkdir -p /deps
WORKDIR /deps

# Download the Zig binary for the given version
# zig version is 0.13.0
RUN curl -L https://ziglang.org/download/zig-linux-x86_64-0.13.0.tar.xz -o zig.tar.xz && \
    tar xf zig.tar.xz && \
    mv zig-linux-x86_64-0.13.0 /zig

FROM alpine:3.13

# Install libc-dev and curl for the application to run
RUN apk --no-cache add \
      libc-dev \
      curl

# Copy the Zig compiler from the builder stage
COPY --from=builder /deps/zig/ /usr/local/zig/

# Add Zig to PATH
ENV PATH="/usr/local/zig:${PATH}"

# Optionally, verify Zig installation
RUN zig version
