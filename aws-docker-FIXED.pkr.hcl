# ============================================================================
# PRODUCTION-READY: Packer Template - Docker + Nginx AMI (FIXED VERSION)
# 
# All critical issues resolved:
# ✅ Fixed sudo docker create command syntax
# ✅ Added comprehensive error handling
# ✅ Added container cleanup before creation
# ✅ Added retry logic for image pulls
# ✅ Added service startup verification
# ✅ Added disk space validation
# ✅ Added proper Docker daemon readiness check
# ============================================================================

packer {
  required_version = ">= 1.7.0"
  required_plugins {
    amazon = {
      version = ">= 1.0.0"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

variable "aws_region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region to build AMI in"
}

variable "instance_type" {
  type        = string
  default     = "t3.small"
  description = "EC2 instance type for build (should be t3.small or larger)"
}

variable "ami_prefix" {
  type        = string
  default     = "docker-nginx-ami"
  description = "Prefix for the AMI name"
}

variable "root_volume_size" {
  type        = number
  default     = 30
  description = "Root volume size in GB (should be at least 20GB)"
}

source "amazon-ebs" "docker" {
  ami_name               = "${var.ami_prefix}-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"
  ami_description        = "Production-ready Ubuntu AMI: Docker + pre-configured Nginx container, zero-downtime auto-start"
  instance_type          = var.instance_type
  region                 = var.aws_region
  associate_public_ip_address = true
  
  source_ami_filter {
    filters = {
      name                = "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    most_recent = true
    owners      = ["099720109477"] # Canonical
  }
  
  ssh_username = "ubuntu"
  ssh_timeout  = "10m"
  
  # Enable EBS optimization for faster builds
  ebs_optimized = true
  
  # Configure root volume
  launch_block_device_mappings {
  device_name           = "/dev/sda1"
  volume_size           = var.root_volume_size
  volume_type           = "gp3"
  delete_on_termination = true
  }
  
  # Add tags to build instance for tracking
  run_tags = {
    Name        = "packer-build-nginx-docker"
    Purpose     = "AMI build"
    Temporary   = "true"
  }
  
  # Add tags to final AMI
  tags = {
    Name                = "docker-nginx-ami"
    BuildDate           = timestamp()
    ManagedBy           = "Packer"
    Description         = "Self-contained Docker + Nginx AMI"
    ContainerType       = "production"
    DockerVersion       = "latest"
    NginxVersion        = "latest"
    OperatingSystem     = "Ubuntu 22.04 LTS"
    Architecture        = "x86_64"
    PreConfigured       = "true"
  }
}

build {
  name = "docker-nginx-build"
  sources = [
    "source.amazon-ebs.docker"
  ]

  # ========================================================================
  # Phase 0: Pre-flight Checks
  # Validates environment before starting build
  # ========================================================================
  provisioner "shell" {
    execute_command = "bash -c '{{ .Vars }} {{ .Path }}'"
    inline = [
      "set -eu",
      "",
      "echo '=== Phase 0: Pre-flight Checks ==='",
      "",
      "# Check available disk space (need at least 5GB)",
      "AVAILABLE_KB=$(df /var | tail -1 | awk '{print $4}')",
      "AVAILABLE_GB=$((AVAILABLE_KB / 1048576))",
      "if [ $AVAILABLE_GB -lt 5 ]; then",
      "  echo \"ERROR: Insufficient disk space. Available: $${AVAILABLE_GB}GB, Required: 5GB\"",
      "  exit 1",
      "fi",
      "echo \"✓ Disk space check passed. Available: $${AVAILABLE_GB}GB\"",
      "",
      "# Check Ubuntu version",
      "UBUNTU_VERSION=$(lsb_release -rs)",
      "echo \"✓ Ubuntu version: $UBUNTU_VERSION\"",
      "",
      "# Check internet connectivity",
      "if ! ping -c 1 8.8.8.8 > /dev/null 2>&1; then",
      "  echo \"WARNING: Cannot reach 8.8.8.8 (internet check)\"",
      "fi"
    ]
  }

  # ========================================================================
  # Phase 1: Install Docker Engine
  # ========================================================================
  provisioner "shell" {
    execute_command = "bash -c '{{ .Vars }} {{ .Path }}'"
    inline = [
      "set -eu",
      "",
      "echo '=== Phase 1: Installing Docker Engine ==='",
      "echo 'Updating system packages...'",
      "sudo apt-get update",
      "sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y",
      "",
      "echo 'Installing Docker dependencies...'",
      "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \\",
      "  apt-transport-https ca-certificates curl gnupg lsb-release",
      "",
      "echo 'Adding Docker GPG key...'",
      "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \\",
      "  sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg",
      "",
      "echo 'Adding Docker repository...'",
      "echo \"deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \\",
      "  https://download.docker.com/linux/ubuntu \\",
      "  $(lsb_release -cs) stable\" | \\",
      "  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null",
      "",
      "echo 'Installing Docker runtime...'",
      "sudo apt-get update",
      "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \\",
      "  docker-ce docker-ce-cli containerd.io docker-compose-plugin",
      "",
      "echo 'Starting Docker daemon...'",
      "sudo systemctl start docker",
      "sudo systemctl enable docker",
      "",
      "echo 'Adding ubuntu user to docker group...'",
      "sudo usermod -aG docker ubuntu",
      "newgrp docker",
      "",
      "echo 'Cleaning up apt cache...'",
      "sudo apt-get clean",
      "sudo apt-get autoclean",
      "echo '✓ Docker installation complete'"
    ]
  }

  # ========================================================================
  # Phase 2: Verify Docker Installation
  # ========================================================================
  provisioner "shell" {
    execute_command = "bash -c '{{ .Vars }} {{ .Path }}'"
    inline = [
      "set -eu",
      "",
      "echo '=== Phase 2: Verifying Docker Installation ==='",
      "echo 'Docker version:'",
      "docker --version || exit 1",
      "",
      "echo 'Waiting for Docker daemon to be fully ready...'",
      "MAX_ATTEMPTS=30",
      "for i in $(seq 1 $MAX_ATTEMPTS); do",
      "  if sudo docker info > /dev/null 2>&1; then",
      "    echo \"✓ Docker daemon is ready (attempt $i)\"",
      "    break",
      "  fi",
      "  if [ $i -eq $MAX_ATTEMPTS ]; then",
      "    echo \"ERROR: Docker daemon failed to start after $${MAX_ATTEMPTS} attempts\"",
      "    exit 1",
      "  fi",
      "  echo \"  Waiting for Docker daemon... ($i/$MAX_ATTEMPTS)\"",
      "  sleep 1",
      "done",
      "",
      "echo 'Docker daemon status:'",
      "sudo systemctl status docker --no-pager",
      "",
      "echo 'Docker info (first 20 lines):'",
      "sudo docker info | head -20",
      "echo '✓ Docker verification complete'"
    ]
  }

  # ========================================================================
  # Phase 3: Pull and Cache Nginx Image (with retry logic)
  # ========================================================================
  provisioner "shell" {
    execute_command = "bash -c '{{ .Vars }} {{ .Path }}'"
    inline = [
      "set -eu",
      "",
      "echo '=== Phase 3: Pulling Nginx Docker Image ==='",
      "echo 'Pulling nginx:latest (with retry logic)...'",
      "",
      "MAX_RETRIES=3",
      "RETRY_DELAY=10",
      "for attempt in $(seq 1 $MAX_RETRIES); do",
      "  echo \"Attempt $attempt of $MAX_RETRIES...\"",
      "  if sudo docker pull nginx:latest; then",
      "    echo \"✓ Successfully pulled nginx:latest\"",
      "    break",
      "  else",
      "    if [ $attempt -lt $MAX_RETRIES ]; then",
      "      echo \"Pull failed, waiting $${RETRY_DELAY}s before retry...\"",
      "      sleep $RETRY_DELAY",
      "    else",
      "      echo \"ERROR: Failed to pull image after $MAX_RETRIES attempts\"",
      "      exit 1",
      "    fi",
      "  fi",
      "done",
      "",
      "echo 'Verifying Nginx image...'",
      "IMAGE_ID=$(sudo docker image inspect nginx:latest --format='{{.ID}}' | cut -d: -f2 | cut -c1-12)",
      "IMAGE_SIZE=$(sudo docker image inspect nginx:latest --format='{{.Size}}' | numfmt --to=iec 2>/dev/null || echo 'unknown')",
      "echo \"✓ Nginx image ID: $IMAGE_ID\"",
      "echo \"✓ Nginx image size: $IMAGE_SIZE\"",
      "",
      "sudo docker image ls",
      "echo '✓ Image pull and verification complete'"
    ]
  }

  # ========================================================================
  # Phase 4: Create Dynamic Index Generation Script
  # Script runs at boot to generate index.html with instance metadata
  # ========================================================================
  provisioner "shell" {
    execute_command = "bash -c '{{ .Vars }} {{ .Path }}'"
    inline = [
      "set -eu",
      "",
      "echo '=== Phase 4: Creating Dynamic Index Generation Script ==='",
      "",
      "# Create the script that will run at boot",
      "sudo tee /usr/local/bin/generate-index.sh > /dev/null << 'SCRIPTEOF'",
      "#!/bin/bash",
      "set -eu",
      "",
      "# Generate index.html dynamically with instance metadata",
      "HOSTNAME=$(hostname -f)",
      "BOOT_TIME=$(date '+%Y-%m-%d %H:%M:%S %Z')",
      "",
      "# Try to get EC2 metadata (fail gracefully if not on AWS)",
      "INSTANCE_ID=$(curl -s --connect-timeout 2 http://169.254.169.254/latest/meta-data/instance-id || echo 'N/A')",
      "AVAILABILITY_ZONE=$(curl -s --connect-timeout 2 http://169.254.169.254/latest/meta-data/placement/availability-zone || echo 'N/A')",
      "PRIVATE_IP=$(curl -s --connect-timeout 2 http://169.254.169.254/latest/meta-data/local-ipv4 || echo 'N/A')",
      "",
      "cat > /tmp/index.html << HTMLEOF",
      "<!DOCTYPE html>",
      "<html lang=\"en\">",
      "<head>",
      "    <meta charset=\"UTF-8\">",
      "    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">",
      "    <title>Nginx Docker Instance</title>",
      "    <style>",
      "        * { margin: 0; padding: 0; box-sizing: border-box; }",
      "        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); min-height: 100vh; display: flex; align-items: center; justify-content: center; }",
      "        .container { background: white; border-radius: 10px; box-shadow: 0 20px 60px rgba(0,0,0,0.3); padding: 40px; max-width: 600px; }",
      "        h1 { color: #333; margin-bottom: 10px; }",
      "        .subtitle { color: #666; margin-bottom: 30px; font-size: 14px; }",
      "        .info-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 15px; margin-bottom: 20px; }",
      "        .info-item { background: #f8f9fa; padding: 15px; border-radius: 5px; border-left: 4px solid #667eea; }",
      "        .info-label { color: #666; font-size: 12px; text-transform: uppercase; font-weight: 600; }",
      "        .info-value { color: #333; font-size: 16px; font-family: 'Monaco', 'Courier New', monospace; margin-top: 5px; word-break: break-all; }",
      "        .status { background: #d4edda; border: 1px solid #c3e6cb; color: #155724; padding: 15px; border-radius: 5px; margin-bottom: 20px; }",
      "        .footer { text-align: center; color: #999; font-size: 12px; margin-top: 20px; }",
      "    </style>",
      "</head>",
      "<body>",
      "    <div class=\"container\">",
      "        <h1>🚀 Nginx on Docker</h1>",
      "        <p class=\"subtitle\">Production-ready Docker container, auto-started from AMI</p>",
      "        <div class=\"status\">✅ <strong>Service Status:</strong> Running successfully</div>",
      "        <div class=\"info-grid\">",
      "            <div class=\"info-item\">",
      "                <div class=\"info-label\">Hostname</div>",
      "                <div class=\"info-value\">$HOSTNAME</div>",
      "            </div>",
      "            <div class=\"info-item\">",
      "                <div class=\"info-label\">Instance ID</div>",
      "                <div class=\"info-value\">$INSTANCE_ID</div>",
      "            </div>",
      "            <div class=\"info-item\">",
      "                <div class=\"info-label\">Availability Zone</div>",
      "                <div class=\"info-value\">$AVAILABILITY_ZONE</div>",
      "            </div>",
      "            <div class=\"info-item\">",
      "                <div class=\"info-label\">Private IP</div>",
      "                <div class=\"info-value\">$PRIVATE_IP</div>",
      "            </div>",
      "        </div>",
      "        <div class=\"info-grid\" style=\"grid-template-columns: 1fr;\">",
      "            <div class=\"info-item\">",
      "                <div class=\"info-label\">Boot Time</div>",
      "                <div class=\"info-value\">$BOOT_TIME</div>",
      "            </div>",
      "        </div>",
      "        <div class=\"footer\">",
      "            <p>Generated dynamically on instance boot</p>",
      "        </div>",
      "    </div>",
      "</body>",
      "</html>",
      "HTMLEOF",
      "",
      "# Copy to nginx directory with proper permissions",
      "cp /tmp/index.html /opt/nginx/html/index.html",
      "chown nobody:nogroup /opt/nginx/html/index.html",
      "chmod 644 /opt/nginx/html/index.html",
      "SCRIPTEOF",
      "",
      "# Make the script executable",
      "sudo chmod 755 /usr/local/bin/generate-index.sh",
      "",
      "# Create nginx html directory (will be populated at boot)",
      "sudo mkdir -p /opt/nginx/html",
      "sudo chmod 755 /opt/nginx/html",
      "",
      "# Pre-create a temporary index.html for testing (will be overwritten at boot)",
      "sudo touch /opt/nginx/html/index.html",
      "sudo chmod 644 /opt/nginx/html/index.html",
      "",
      "echo 'Script created at /usr/local/bin/generate-index.sh'",
      "echo 'Directory ready at /opt/nginx/html'",
      "echo '✓ Dynamic index generation script created'"
    ]
  }

  # ========================================================================
  # Phase 4.5: Create generate-index Systemd Service
  # Service runs on boot to generate dynamic index.html from instance metadata
  # Runs BEFORE nginx-docker.service so content is ready
  # ========================================================================
  provisioner "file" {
    content = <<-EOT
[Unit]
Description=Generate Dynamic Nginx Index Page
Before=nginx-docker.service
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/generate-index.sh
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal
SyslogIdentifier=generate-index

[Install]
WantedBy=multi-user.target
EOT
    destination = "/tmp/generate-index.service"
  }

  provisioner "shell" {
    execute_command = "bash -c '{{ .Vars }} {{ .Path }}'"
    inline = [
      "set -eu",
      "",
      "echo '=== Phase 4.5: Installing Generate-Index Service ==='",
      "echo 'Installing generate-index service...'",
      "sudo mv /tmp/generate-index.service /etc/systemd/system/generate-index.service",
      "sudo chmod 644 /etc/systemd/system/generate-index.service",
      "",
      "echo 'Reloading systemd daemon...'",
      "sudo systemctl daemon-reload",
      "",
      "echo 'Enabling service for auto-run on boot...'",
      "sudo systemctl enable generate-index.service",
      "",
      "echo 'Testing the generate-index script...'",
      "sudo /usr/local/bin/generate-index.sh",
      "",
      "echo 'Generated index.html:'",
      "sudo cat /opt/nginx/html/index.html | head -20",
      "",
      "echo '✓ Generate-index service installation complete'"
    ]
  }

  # ========================================================================
  # Phase 5: Create Nginx Docker Container
  # Includes cleanup of previous container if it exists
  # ========================================================================
  provisioner "shell" {
    execute_command = "bash -c '{{ .Vars }} {{ .Path }}'"
    inline = [
      "set -eu",
      "",
      "echo '=== Phase 5: Creating Nginx Docker Container ==='",
      "",
      "# Clean up any existing container from previous builds",
      "if sudo docker container ls -a | grep -q nginx-server; then",
      "  echo 'Removing existing container from previous build...'",
      "  sudo docker container rm -f nginx-server || true",
      "  sleep 2",
      "fi",
      "",
      "# Create container (fixed syntax - single line)",
      "echo 'Creating container with sudo docker create...'",
      "sudo docker create --name nginx-server -p 80:80 -v /opt/nginx/html:/usr/share/nginx/html:ro nginx:latest",
      "",
      "# Verify container was created",
      "echo 'Verifying container creation...'",
      "if ! sudo docker container ls -a | grep -q nginx-server; then",
      "  echo 'ERROR: Container creation failed - container not found'",
      "  exit 1",
      "fi",
      "",
      "CONTAINER_ID=$(sudo docker container ls -a --filter name=nginx-server --format '{{.ID}}')",
      "echo \"✓ Container created successfully: $${CONTAINER_ID}\"",
      "echo 'Container details:'",
      "sudo docker container ls -a | grep nginx-server",
      "echo '✓ Container creation and verification complete'"
    ]
  }


  # ========================================================================
  # Phase 6: Deploy and Configure Systemd Services
  # ========================================================================
  provisioner "file" {
    content = <<-EOT
[Unit]
Description=Nginx Docker Container
After=docker.service generate-index.service
Requires=docker.service
Wants=generate-index.service

[Service]
Type=simple
Restart=always
RestartSec=5

# Start the pre-created container
ExecStart=/usr/bin/docker start -a nginx-server

# Gracefully stop the container
ExecStop=/usr/bin/docker stop -t 10 nginx-server

# Restart on failure
StandardOutput=journal
StandardError=journal
SyslogIdentifier=nginx-docker

[Install]
WantedBy=multi-user.target
EOT
    destination = "/tmp/nginx-docker.service"
  }

  provisioner "shell" {
    execute_command = "bash -c '{{ .Vars }} {{ .Path }}'"
    inline = [
      "set -eu",
      "",
      "echo '=== Phase 6: Installing Systemd Service ==='",
      "echo 'Installing service file...'",
      "sudo mv /tmp/nginx-docker.service /etc/systemd/system/nginx-docker.service",
      "sudo chmod 644 /etc/systemd/system/nginx-docker.service",
      "",
      "echo 'Reloading systemd daemon...'",
      "sudo systemctl daemon-reload",
      "",
      "echo 'Enabling service for auto-start on boot...'",
      "sudo systemctl enable nginx-docker.service",
      "",
      "echo 'Service file installed at /etc/systemd/system/nginx-docker.service'",
      "echo '✓ Systemd service installation complete'"
    ]
  }

  # ========================================================================
  # Phase 7: Test Service Startup (Critical Verification)
  # ========================================================================
  provisioner "shell" {
    execute_command = "bash -c '{{ .Vars }} {{ .Path }}'"
    inline = [
      "set -eu",
      "",
      "echo '=== Phase 7: Testing Systemd Service Startup ==='",
      "echo 'Starting nginx-docker service...'",
      "sudo systemctl start nginx-docker.service",
      "",
      "echo 'Waiting 5 seconds for container to start...'",
      "sleep 5",
      "",
      "echo 'Checking service status...'",
      "if ! sudo systemctl is-active --quiet nginx-docker.service; then",
      "  echo 'ERROR: Service is not active'",
      "  echo 'Service status:'",
      "  sudo systemctl status nginx-docker.service --no-pager || true",
      "  echo 'Service logs:'",
      "  sudo journalctl -u nginx-docker.service -n 50 --no-pager",
      "  exit 1",
      "fi",
      "",
      "echo '✓ Service is active and running'",
      "echo 'Verifying container is running...'",
      "sudo docker ps | grep nginx-server",
      "",
      "echo 'Checking container logs...'",
      "sudo docker logs nginx-server | head -20",
      "",
      "echo 'Testing HTTP connectivity on localhost...'",
      "if ! curl -s http://localhost:80 > /dev/null; then",
      "  echo 'WARNING: HTTP request to localhost failed'",
      "  echo 'Container logs:'",
      "  sudo docker logs nginx-server",
      "  exit 1",
      "fi",
      "",
      "echo '✓ HTTP connectivity test passed'",
      "echo 'Stopping service for AMI snapshot...'",
      "sudo systemctl stop nginx-docker.service",
      "sleep 2",
      "echo '✓ Service startup test complete'"
    ]
  }

  # ========================================================================
  # Phase 8: Final Verification and Cleanup
  # ========================================================================
  provisioner "shell" {
    execute_command = "bash -c '{{ .Vars }} {{ .Path }}'"
    inline = [
      "set -eu",
      "",
      "echo '=== Phase 8: Final Verification ==='",
      "",
      "echo 'Docker version:'",
      "docker --version",
      "",
      "echo 'Available Docker images:'",
      "sudo docker image ls",
      "",
      "echo 'Existing containers:'",
      "sudo docker container ls -a",
      "",
      "echo 'Systemd service status:'",
      "sudo systemctl status nginx-docker.service --no-pager || true",
      "",
      "echo 'Content directory:'",
      "ls -lah /opt/nginx/html/",
      "",
      "echo 'Nginx configuration (from container):'",
      "sudo docker run --rm -v /etc/nginx:/etc/nginx:ro nginx:latest cat /etc/nginx/nginx.conf | head -30",
      "",
      "echo '=== Build Complete ==='",
      "echo '✓ All verifications passed'",
      "echo '✓ AMI is ready for deployment'",
      "echo '✓ Nginx will start automatically on boot'"
    ]
  }
}
