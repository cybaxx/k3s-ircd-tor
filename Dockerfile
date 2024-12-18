# Use Ubuntu as the base image
FROM ubuntu:20.04

# Set environment variables to avoid interactive prompts during installation
ENV DEBIAN_FRONTEND=noninteractive

# Install necessary dependencies (Tor, build tools, etc.)
RUN apt update && \
    apt install -y \
    build-essential \
    cmake \
    libssl-dev \
    libcurl4-openssl-dev \
    zlib1g-dev \
    tor \
    curl \
    bash \
    nano \
    git \
    && rm -rf /var/lib/apt/lists/* || { echo 'Error during package installation'; exit 1; }

# Create the directory for InspireIRCd configuration if it doesn't exist
RUN mkdir -p /etc/inspireircd || { echo 'Failed to create /etc/inspireircd directory'; exit 1; }

# Clone the InspireIRCd repository and build it
RUN cd /tmp && \
    git clone https://github.com/inspircd/inspircd.git && \
    cd inspircd && \
    ./make.sh || { echo 'Error during InspireIRCd compilation'; exit 1; }

# Run the configuration script to set up InspireIRCd
RUN cd /tmp/inspircd && \
    ./inspircd configure || { echo 'Error configuring InspireIRCd'; exit 1; }

# Install InspireIRCd
RUN cd /tmp/inspircd && \
    sudo make install || { echo 'Error installing InspireIRCd'; exit 1; }

# Generate inspireircd.conf for InspireIRCd (with Tor hidden service support)
RUN echo "Generating inspireircd.conf for InspireIRCd..." && \
    cat <<EOF > /etc/inspireircd/inspirercd.conf || { echo 'Error creating /etc/inspireircd/inspirercd.conf'; exit 1; }
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
    echo "HiddenServicePort 6667 127.0.0.1:6667" >> /etc/tor/torrc || { echo 'Error configuring Tor hidden service'; exit 1; }

# Expose the IRC port
EXPOSE 6667

# Start Tor and InspireIRCd when the container starts
CMD tor & inspircd || { echo 'Error starting Tor and InspireIRCd'; exit 1; }
