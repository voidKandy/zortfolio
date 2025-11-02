FROM alpine:3.13 as builder

# Set the Zig version explicitly
ARG ZIGVER=0.15.0

# Install curl and xz for downloading and extracting Zig
RUN apk update && \
    apk add \
        curl \
        xz

# Download and extract the Zig compiler
RUN mkdir -p /deps
WORKDIR /deps

# Download the Zig binary for the given version
RUN curl -L https://ziglang.org/download/$ZIGVER/zig-linux-x86_64-$ZIGVER.tar.xz -o zig.tar.xz && \
    tar xf zig.tar.xz && \
    mv zig-linux-x86_64-$ZIGVER /zig

FROM alpine:3.13

RUN apk --no-cache add \
      libc-dev \
      curl

COPY --from=builder /zig/ /usr/local/zig/

ENV PATH="/usr/local/zig:${PATH}"

WORKDIR ./zortfolio
ARG SPOTIFY_CLIENT_ID
ARG SPOTIFY_CLIENT_SECRET
ARG PORT

ADD . ./

RUN ls serve
# So sourcing .env doesnt lead to failure
RUN touch .env 

RUN zig build

CMD ["./zig-out/bin/zortfolio"]
