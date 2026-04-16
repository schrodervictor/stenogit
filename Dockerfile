FROM debian:stable-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        bash \
        bats \
        ca-certificates \
        git \
        inotify-tools \
        make \
        shellcheck \
        systemd \
    && rm -rf /var/lib/apt/lists/*


WORKDIR /src

CMD ["bats", "tests/"]
