FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    fd-find \
    ffmpeg \
    file \
    gettext-base \
    git \
    gnupg \
    iproute2 \
    inotify-tools \
    iptables \
    jq \
    libcanberra-gtk3-module \
    libasound2 \
    libva2 \
    libva-drm2 \
    libva-wayland2 \
    libegl1 \
    libgbm1 \
    libgl1 \
    libgl1-mesa-dri \
    libavcodec-extra \
    libgtk-3-0 \
    libnss3 \
    libpci3 \
    libvulkan1 \
    libx11-6 \
    lsof \
    mesa-va-drivers \
    mesa-vulkan-drivers \
    libcharon-extra-plugins \
    libcharon-extauth-plugins \
    libstrongswan-extra-plugins \
    libstrongswan-standard-plugins \
    procps \
    psmisc \
    openssh-client \
    python3 \
    python3-pip \
    python3-venv \
    pipx \
    ripgrep \
    rsync \
    sqlite3 \
    strongswan \
    strongswan-swanctl \
    tinyproxy \
    tree \
    unzip \
    xauth \
    xxd \
    vainfo \
    xz-utils \
    xdg-utils \
    yq \
    zip \
    firefox-esr \
    && ln -sf /usr/bin/fdfind /usr/local/bin/fd \
    && rm -rf /var/lib/apt/lists/*

# Install Google Chrome from official repo.
RUN mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor -o /etc/apt/keyrings/google-chrome.gpg \
    && echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/google-chrome.gpg] http://dl.google.com/linux/chrome/deb/ stable main" > /etc/apt/sources.list.d/google-chrome.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends google-chrome-stable \
    && rm -rf /var/lib/apt/lists/*

# Install Visual Studio Code from Microsoft repo.
RUN curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /etc/apt/keyrings/packages.microsoft.gpg \
    && echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends code \
    && rm -rf /var/lib/apt/lists/*

# Install Cursor from official Anysphere repo.
RUN curl -fsSL https://downloads.cursor.com/keys/anysphere.asc | gpg --dearmor -o /usr/share/keyrings/anysphere.gpg \
    && echo "deb [arch=amd64,arm64 signed-by=/usr/share/keyrings/anysphere.gpg] https://downloads.cursor.com/aptrepo stable main" > /etc/apt/sources.list.d/cursor.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends cursor \
    && rm -rf /var/lib/apt/lists/*

# Install Salesforce CLI.
RUN curl -fsSL https://developer.salesforce.com/media/salesforce-cli/sf/channels/stable/sf-linux-x64.tar.xz -o /tmp/sf.tar.xz \
    && mkdir -p /opt/sf \
    && tar -xJf /tmp/sf.tar.xz -C /opt/sf --strip-components=1 \
    && ln -s /opt/sf/bin/sf /usr/local/bin/sf \
    && rm -f /tmp/sf.tar.xz

# Install ngrok CLI.
RUN arch="$(dpkg --print-architecture)" \
    && case "${arch}" in \
      amd64) ngrok_pkg="ngrok-v3-stable-linux-amd64.tgz" ;; \
      arm64) ngrok_pkg="ngrok-v3-stable-linux-arm64.tgz" ;; \
      *) echo "Unsupported architecture for ngrok: ${arch}" >&2; exit 1 ;; \
    esac \
    && curl -fsSL "https://bin.equinox.io/c/bNyj1mQVY4c/${ngrok_pkg}" -o /tmp/ngrok.tgz \
    && tar -xzf /tmp/ngrok.tgz -C /usr/local/bin ngrok \
    && chmod 755 /usr/local/bin/ngrok \
    && rm -f /tmp/ngrok.tgz

# Install mise (runtime version manager; tool installs live in container APP_HOME).
ENV MISE_INSTALL_PATH=/usr/local/bin/mise
RUN curl -fsSL https://mise.run | sh

COPY scripts/container/entrypoint /usr/local/bin/work_container-entrypoint
COPY scripts/container/vpn-updown /usr/local/bin/work-container-vpn-updown
COPY scripts/container/sfdx-auth-watch /usr/local/bin/work-container-sfdx-auth-watch
COPY config/vpn/charon-updown-dns.conf /etc/strongswan.d/charon/zz-updown-dns.conf
COPY config/vpn/charon-kernel-netlink-mss.conf /etc/strongswan.d/charon/zz-kernel-netlink-mss.conf
COPY config/vpn/charon-tunnel.conf /etc/strongswan.d/charon/zz-tunnel.conf
COPY config/vpn/gai.conf /etc/gai.conf
RUN chmod +x /usr/local/bin/work_container-entrypoint /usr/local/bin/work-container-vpn-updown /usr/local/bin/work-container-sfdx-auth-watch

ENTRYPOINT ["/usr/local/bin/work_container-entrypoint"]
CMD ["bash"]
