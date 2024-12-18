#!/bin/bash

# Enable immediate exit on error and trace execution
set -e
trap 'echo "Error occurred on line $LINENO"; exit 1' ERR

# Function to check command execution status
check_status() {
    if [ $? -ne 0 ]; then
        echo "Error occurred in the previous command. Exiting..."
        exit 1
    fi
}

# Install k3s and start the service
install_k3s() {
    echo "Installing k3s..."
    curl -sfL https://get.k3s.io | sh -
    check_status
    sudo systemctl enable k3s
    check_status
    sudo systemctl start k3s
    check_status
    sudo kubectl get nodes
    check_status
}

# Install Tor
install_tor() {
    echo "Installing Tor..."
    sudo apt update
    check_status
    sudo apt install -y tor
    check_status
}

# Test Tor connection
test_tor_connection() {
    echo "Testing Tor connection..."
    curl --socks5 127.0.0.1:9050 https://check.torproject.org/
    check_status
}

# Install InspireIRCd
install_inspireircd() {
    echo "Installing InspireIRCd..."
    sudo apt update
    check_status
    sudo apt install -y inspireircd
    check_status
}

# Configure InspireIRCd
configure_inspireircd() {
    echo "Generating inspireircd.conf for InspireIRCd..."

    # Generate a default inspirercd.conf file for the IRC server with Tor hidden service
    cat <<EOF > inspirercd.conf
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
    check_status

    echo "inspirercd.conf has been generated successfully."
}

# Add Tor hidden service configuration
configure_tor_hidden_service() {
    echo "Configuring Tor hidden service..."
    sudo bash -c 'echo "HiddenServiceDir /var/lib/tor/hidden_service/" >> /etc/tor/torrc'
    check_status
    sudo bash -c 'echo "HiddenServicePort 6667 127.0.0.1:6667" >> /etc/tor/torrc'
    check_status
    sudo systemctl restart tor
    check_status
    echo "Tor hidden service hostname: $(cat /var/lib/tor/hidden_service/hostname)"
}

# Create Dockerfile for InspireIRCd and Tor
create_dockerfile() {
    echo "Creating Dockerfile for InspireIRCd and Tor..."
    cat <<EOF > Dockerfile
FROM debian:bullseye-slim

# Install necessary packages
RUN apt update && \
    apt install -y inspireircd tor && \
    rm -rf /var/lib/apt/lists/*

# Copy the generated IRC server configuration file
COPY inspirercd.conf /etc/inspireircd/

# Expose the IRC port
EXPOSE 6667

# Start both Tor and the IRC server
CMD tor & inspireircd
EOF
    check_status
}

# Build Docker image
build_docker_image() {
    echo "Building Docker image..."
    docker build -t inspireircd-tor .
    check_status
}

# Create Kubernetes deployment YAML
create_deployment_yaml() {
    echo "Creating Kubernetes deployment YAML..."
    cat <<EOF > deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ircd-tor
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ircd-tor
  template:
    metadata:
      labels:
        app: ircd-tor
    spec:
      containers:
        - name: ircd-tor
          image: inspireircd-tor:latest
          ports:
            - containerPort: 6667
          securityContext:
            capabilities:
              add:
                - NET_ADMIN  # Allow Tor to create the hidden service
EOF
    check_status
}

# Apply Kubernetes deployment
apply_kubernetes_deployment() {
    echo "Applying Kubernetes deployment..."
    kubectl apply -f deployment.yaml
    check_status
}

# Get Kubernetes pod status
get_kubernetes_pods() {
    echo "Checking Kubernetes pods..."
    kubectl get pods
    check_status
}

# Create Kubernetes service YAML
create_service_yaml() {
    echo "Creating Kubernetes service YAML..."
    cat <<EOF > service.yaml
apiVersion: v1
kind: Service
metadata:
  name: ircd-tor-service
spec:
  selector:
    app: ircd-tor
  ports:
    - protocol: TCP
      port: 6667
      targetPort: 6667
  type: ClusterIP
EOF
    check_status
}

# Apply Kubernetes service
apply_kubernetes_service() {
    echo "Applying Kubernetes service..."
    kubectl apply -f service.yaml
    check_status
}

# Fetch pod logs dynamically
get_pod_logs() {
    log_info "Fetching pod logs..."

    # Define the label selector (or pod name pattern) to find the correct pod
    POD_NAME=$(kubectl get pods --selector=app=ircd-tor -o jsonpath='{.items[0].metadata.name}')

    if [ -z "$POD_NAME" ]; then
        log_error "No pod found matching the selector. Exiting..."
        exit 1
    fi

    # Fetch logs from the identified pod
    kubectl logs "$POD_NAME"
    check_status
}

# Tail Tor logs
tail_tor_logs() {
    echo "Tailing Tor logs..."
    sudo tail -f /var/log/tor/log
    check_status
}

# Main function to call all necessary setup steps
main() {
    install_k3s
    install_tor
    test_tor_connection
    install_inspireircd
    configure_inspireircd
    configure_tor_hidden_service
    create_dockerfile
    build_docker_image
    create_deployment_yaml
    apply_kubernetes_deployment
    get_kubernetes_pods
    create_service_yaml
    apply_kubernetes_service
    get_pod_logs
    tail_tor_logs
}

# Run the main function
main
