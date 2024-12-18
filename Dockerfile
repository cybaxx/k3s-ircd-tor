# Use a minimal Debian-based image
FROM debian:bullseye-slim

# Set environment variables to avoid interactive prompts during installation
ENV DEBIAN_FRONTEND=noninteractive

# Install necessary dependencies (Tor and InspireIRCd)
RUN apt update && \
    apt install -y \
    tor \
    inspireircd \
    curl \
    nano \
    && rm -rf /var/lib/apt/lists/*

# Configure InspireIRCd (generate inspirercd.conf dynamically)
RUN echo "Generating inspireircd.conf for InspireIRCd..." && \
    cat <<EOF > /etc/inspireircd/inspirercd.conf
# InspireIRCd Configuration File
serverinfo {
    name = "MyIRCServer";
    listen {
        address = "127.0.0.1";
        port = 6667;
    };
};

# Set up the IRC server to bind to the local loopback address (127.0.0.1)
listen {
    address = "127.0.0.1";
    port = 6667;
    ipv6 = false;
};

# Enable SSL and other security settings (optional, adjust to your needs)
# ssl {
#    enable = true;
#    certfile = "/path/to/cert.pem";
#    keyfile = "/path/to/key.pem";
#    port = 6697;
# };

# Tor hidden service configuration (will forward traffic on 6667 through Tor)
bind {
    address = "127.0.0.1";
    port = 6667;
    protocol = "IRC";
};

# Accept connections on the hidden Tor service
hidden_service {
    port = 6667;
    target = "127.0.0.1:6667";
};

# Additional configurations
user {
    username = "ircuser";
    password = "securepassword";
};
EOF

# Add the Tor hidden service configuration
RUN echo "Configuring Tor hidden service..." && \
    echo "HiddenServiceDir /var/lib/tor/hidden_service/" >> /etc/tor/torrc && \
    echo "HiddenServicePort 6667 127.0.0.1:6667" >> /etc/tor/torrc

# Expose the IRC port
EXPOSE 6667

# Start Tor and InspireIRCd in the container
CMD tor & inspireircd
