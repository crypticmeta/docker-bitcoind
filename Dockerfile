# Use the official latest Ubuntu as a base image
FROM ubuntu:latest AS builder
ARG TARGETARCH

FROM builder AS builder_amd64
ENV ARCH=x86_64
FROM builder AS builder_arm64
ENV ARCH=aarch64
FROM builder AS builder_riscv64
ENV ARCH=riscv64

FROM builder_${TARGETARCH} AS build

# Update the system and install necessary dependencies
RUN apt-get update && apt-get install -y \
    git \
    curl \
    build-essential \
    gnupg \
    libatomic1 \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Install Rust
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"

# Clone the repository
RUN git clone https://github.com/crypticmeta/ord.git /app

# Set the working directory
WORKDIR /app

# Checkout the ordapi branch
RUN git checkout ordapi

# Build the application
RUN cargo build --release

ARG VERSION=25.0
ARG BITCOIN_CORE_SIGNATURE=71A3B16735405025D447E8F274810B012346C9A6

RUN cd /tmp \
    && gpg --keyserver hkp://keyserver.ubuntu.com --recv-keys ${BITCOIN_CORE_SIGNATURE} \
    && wget https://bitcoincore.org/bin/bitcoin-core-${VERSION}/SHA256SUMS.asc \
    https://bitcoincore.org/bin/bitcoin-core-${VERSION}/SHA256SUMS \
    https://bitcoincore.org/bin/bitcoin-core-${VERSION}/bitcoin-${VERSION}-${ARCH}-linux-gnu.tar.gz \
    && gpg --verify --status-fd 1 --verify SHA256SUMS.asc SHA256SUMS 2>/dev/null | grep "^\[GNUPG:\] VALIDSIG.*${BITCOIN_CORE_SIGNATURE}\$" \
    && sha256sum --ignore-missing --check SHA256SUMS \
    && tar -xzvf bitcoin-${VERSION}-${ARCH}-linux-gnu.tar.gz -C /opt \
    && ln -sv bitcoin-${VERSION} /opt/bitcoin \
    && /opt/bitcoin/bin/test_bitcoin --show_progress \
    && rm -v /opt/bitcoin/bin/test_bitcoin /opt/bitcoin/bin/bitcoin-qt

FROM ubuntu:latest
LABEL maintainer="Crypticmeta <crypticmetadev@gmail.com>"

ENTRYPOINT ["docker-entrypoint.sh"]
ENV HOME /app
EXPOSE 8332 8333
VOLUME ["/app"]
WORKDIR /app

ARG GROUP_ID=1000
ARG USER_ID=1000
RUN groupadd -g ${GROUP_ID} bitcoin \
    && useradd -u ${USER_ID} -g bitcoin -d /app bitcoin

COPY --from=build /opt/ /opt/
COPY --from=build /app/target/release /app/target/release

RUN apt update \
    && apt install -y --no-install-recommends gosu libatomic1 \
    && apt clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
    && ln -sv /opt/bitcoin/bin/* /usr/local/bin

COPY ./bin ./docker-entrypoint.sh /usr/local/bin/
COPY bitcoin.conf $HOME/.bitcoin/bitcoin.conf  
# Add this line to copy the bitcoin.conf file

RUN chown -R bitcoin:bitcoin $HOME/.bitcoin  
# Set ownership for the bitcoin.conf file
RUN chmod 600 $HOME/.bitcoin/bitcoin.conf  
# Set permissions for the bitcoin.conf file

CMD ["bitcoind"]
