# ============================================================================
# Production-Ready Packer Template: Docker + Nginx AMI
# 
# This template builds a fully self-contained Ubuntu AMI with:
# - Docker daemon pre-installed and configured
# - Nginx container pre-created (not just an image download)
# - Systemd service to manage the Nginx container lifecycle
#
# Key Improvements:
# 1. Container is created during build (not at first boot)
# 2. Nginx image is pulled and cached in the AMI
# 3. Systemd uses 'docker start' (clean restart) not 'docker run' (new container)
# 4. No internet required after launch - fully self-contained
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
  default     = "t3.micro"
  description = "EC2 instance type for build"
}

variable "ami_prefix" {
  type        = string
  default     = "docker-nginx-ami"
  description = "Prefix for the AMI name"
}

source "amazon-ebs" "docker" {
  ami_name            = "${var.ami_prefix}-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"
  ami_description     = "Production-ready Ubuntu AMI: Docker + pre-configured Nginx container, zero-downtime auto-start"
  instance_type       = var.instance_type
  region              = var.aws_region
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
  tags = {
    Name          = "docker-nginx-ami"
    BuildDate     = timestamp()
    ManagedBy     = "Packer"
    Description   = "Self-contained Docker + Nginx AMI"
    ContainerType = "production"
  }
}

build {
  name = "docker-nginx-build"
  sources = [
    "source.amazon-ebs.docker"
  ]

  # ========================================================================
  # Phase 1: Install Docker Engine
  # ========================================================================
  provisioner "shell" {
    inline = [
      "echo '=== Phase 1: Installing Docker Engine ==='",
      "echo 'Updating system packages...'",
      "sudo apt-get update",
      "sudo apt-get upgrade -y",
      "echo 'Installing Docker dependencies...'",
      "sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release",
      "echo 'Adding Docker GPG key...'",
      "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg",
      "echo 'Adding Docker repository...'",
      "echo \"deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable\" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null",
      "echo 'Installing Docker runtime...'",
      "sudo apt-get update",
      "sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin",
      "echo 'Starting Docker daemon...'",
      "sudo systemctl start docker",
      "sudo systemctl enable docker",
      "echo 'Adding ubuntu user to docker group...'",
      "sudo usermod -aG docker ubuntu",
      "echo 'Cleaning up apt cache...'",
      "sudo apt-get clean",
      "sudo apt-get autoclean"
    ]
  }

  # ========================================================================
  # Phase 2: Verify Docker Installation
  # Ensures Docker is ready before pulling images
  # ========================================================================
  provisioner "shell" {
    inline = [
      "echo '=== Phase 2: Verifying Docker Installation ==='",
      "echo 'Docker version:'",
      "docker --version",
      "echo 'Waiting for Docker daemon to be fully ready...'",
      "sleep 5",
      "echo 'Docker daemon status:'",
      "sudo systemctl status docker",
      "echo 'Docker info:'",
      "docker info | head -20"
    ]
  }

  # ========================================================================
  # Phase 3: Pull and Cache Nginx Image
  # This ensures Nginx is available without internet access after launch
  # ========================================================================
  provisioner "shell" {
    inline = [
      "echo '=== Phase 3: Pulling Nginx Docker Image ==='",
      "echo 'Pulling nginx:latest (this may take a few minutes)...'",
      "docker pull nginx:latest",
      "echo 'Verifying Nginx image download...'",
      "docker image ls",
      "echo 'Nginx image successfully cached in AMI'"
    ]
  }

  # ========================================================================
  # Phase 4: Create HTML Directory and Default Content
  # ========================================================================
  provisioner "shell" {
    inline = [
      "echo '=== Phase 4: Setting up Nginx content directory ==='",
      "sudo mkdir -p /opt/nginx/html",
      "echo '<!DOCTYPE html>' | sudo tee /opt/nginx/html/index.html > /dev/null",
      "echo '<html>' | sudo tee -a /opt/nginx/html/index.html > /dev/null",
      "echo '<head><title>Nginx on Docker</title></head>' | sudo tee -a /opt/nginx/html/index.html > /dev/null",
      "echo '<body><h1>Welcome to Nginx</h1>' | sudo tee -a /opt/nginx/html/index.html > /dev/null",
      "echo '<p>Running on Docker from AMI</p>' | sudo tee -a /opt/nginx/html/index.html > /dev/null",
      "echo '<p>Hostname: ' $(hostname) '</p>' | sudo tee -a /opt/nginx/html/index.html > /dev/null",
      "echo '</body></html>' | sudo tee -a /opt/nginx/html/index.html > /dev/null",
      "echo 'Content directory ready at /opt/nginx/html'"
    ]
  }

  # ========================================================================
  # Phase 5: Create Nginx Docker Container
  # Container is created during build and persisted in the AMI.
  # Systemd will start/stop this container, not create a new one each time.
  # Benefits:
  #  - Faster boot times (no docker run overhead)
  #  - Cleaner lifecycle management
  #  - Container state is preserved across restarts
  # ========================================================================
  provisioner "shell" {
    inline = [
      "echo '=== Phase 5: Creating Nginx Docker Container ==='",
      "echo 'Creating container (docker create)...'",
      "docker create \\",
      "  --name nginx-server \\",
      "  -p 80:80 \\",
      "  -v /opt/nginx/html:/usr/share/nginx/html:ro \\",
      "  nginx:latest",
      "echo 'Container created successfully'",
      "echo 'Verifying container:'",
      "docker container ls -a | grep nginx-server"
    ]
  }

  # ========================================================================
  # Phase 6: Deploy Systemd Service
  # This service manages the Nginx container lifecycle.
  # Key differences from docker run approach:
  #  - Uses 'docker start' to start the pre-created container
  #  - Cleaner error handling and logging
  #  - Compatible with standard systemd operations
  #  - Can restart without needing to re-download images
  # ========================================================================
  provisioner "file" {
    content = <<-EOT
[Unit]
Description=Nginx Docker Container
After=docker.service
Requires=docker.service

[Service]
Type=simple
Restart=always
RestartSec=5

# Start the pre-created container (not docker run)
ExecStart=/usr/bin/docker start -a nginx-server

# Gracefully stop the container
ExecStop=/usr/bin/docker stop nginx-server

[Install]
WantedBy=multi-user.target
EOT
    destination = "/tmp/nginx-docker.service"
  }

  # ========================================================================
  # Phase 7: Install and Enable Systemd Service
  # ========================================================================
  provisioner "shell" {
    inline = [
      "echo '=== Phase 7: Installing Systemd Service ==='",
      "sudo mv /tmp/nginx-docker.service /etc/systemd/system/nginx-docker.service",
      "sudo chmod 644 /etc/systemd/system/nginx-docker.service",
      "sudo systemctl daemon-reload",
      "sudo systemctl enable nginx-docker.service",
      "echo 'Systemd service installed at /etc/systemd/system/nginx-docker.service'",
      "echo 'Service is enabled and will start on boot'"
    ]
  }

  # ========================================================================
  # Phase 8: Final Verification and Cleanup
  # ========================================================================
  provisioner "shell" {
    inline = [
      "echo '=== Phase 8: Final Verification ==='",
      "echo 'Docker version:'",
      "docker --version",
      "echo 'Available Docker images:'",
      "docker image ls",
      "echo 'Existing containers:'",
      "docker container ls -a",
      "echo 'Systemd service status:'",
      "sudo systemctl status nginx-docker.service --no-pager",
      "echo 'Content directory:'",
      "ls -la /opt/nginx/html/",
      "echo '=== Build Complete ==='",
      "echo 'AMI is ready for deployment. Nginx will start automatically on boot.'"
    ]
  }
}
