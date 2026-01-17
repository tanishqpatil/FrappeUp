# Use the official Frappe Bench image as the base
FROM frappe/bench:latest

# Metadata
LABEL maintainer="SwayAlgo"

# Switch to root to install dependencies
USER root

# Install gosu for easy privilege-dropping
# See https://github.com/tianon/gosu/blob/master/INSTALL.md
ENV GOSU_VERSION 1.17
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates wget gnupg; \
    dpkgArch="$(dpkg --print-architecture | awk -F- '{ print $NF }')"; \
    wget -O /usr/local/bin/gosu "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$dpkgArch"; \
    wget -O /usr/local/bin/gosu.asc "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$dpkgArch.asc"; \
    export GNUPGHOME="$(mktemp -d)"; \
    gpg --batch --keyserver keyserver.ubuntu.com --recv-keys B42F6819007F00F88E364FD4036A9C25BF357DD4; \
    gpg --batch --verify /usr/local/bin/gosu.asc /usr/local/bin/gosu; \
    command -v gpgconf && gpgconf --kill all || true; \
    rm -rf "$GNUPGHOME" /usr/local/bin/gosu.asc; \
    # We keep ca-certificates as it's needed by git and other tools for SSL verification
    apt-get purge -y --auto-remove wget gnupg; \
    rm -rf /var/lib/apt/lists/*; \
    chmod +x /usr/local/bin/gosu; \
    # Explicitly configure git to use the system's CA bundle to prevent SSL verification errors
    git config --global http.sslCAInfo /etc/ssl/certs/ca-certificates.crt; \
    gosu --version

# Install bench globally
RUN pip install frappe-bench

# Set up PATH to include global Python packages
ENV PATH="/usr/local/bin:${PATH}"

# Create a symlink from the virtual environment bench to global bench
RUN ln -sf /home/frappe/frappe-bench/env/bin/bench /usr/local/bin/bench