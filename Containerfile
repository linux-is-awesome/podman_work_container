FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    ffmpeg \
    gettext-base \
    git \
    gnupg \
    iproute2 \
    iptables \
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
    mesa-va-drivers \
    mesa-vulkan-drivers \
    libcharon-extra-plugins \
    libcharon-extauth-plugins \
    libstrongswan-extra-plugins \
    libstrongswan-standard-plugins \
    procps \
    strongswan \
    strongswan-swanctl \
    xauth \
    vainfo \
    xz-utils \
    xdg-utils \
    firefox-esr \
    && rm -rf /var/lib/apt/lists/*

# Install Google Chrome from official repo.
RUN mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor -o /etc/apt/keyrings/google-chrome.gpg \
    && echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/google-chrome.gpg] http://dl.google.com/linux/chrome/deb/ stable main" > /etc/apt/sources.list.d/google-chrome.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends google-chrome-stable \
    && rm -rf /var/lib/apt/lists/*

# Install Salesforce CLI.
RUN curl -fsSL https://developer.salesforce.com/media/salesforce-cli/sf/channels/stable/sf-linux-x64.tar.xz -o /tmp/sf.tar.xz \
    && mkdir -p /opt/sf \
    && tar -xJf /tmp/sf.tar.xz -C /opt/sf --strip-components=1 \
    && ln -s /opt/sf/bin/sf /usr/local/bin/sf \
    && rm -f /tmp/sf.tar.xz

COPY scripts/entrypoint /usr/local/bin/work_container-entrypoint
RUN chmod +x /usr/local/bin/work_container-entrypoint

ENTRYPOINT ["/usr/local/bin/work_container-entrypoint"]
CMD ["bash"]
