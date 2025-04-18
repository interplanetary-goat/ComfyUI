# Use NVIDIA CUDA base image
FROM nvidia/cuda:12.5.0-base-ubuntu22.04

# Set environment variables
ENV PYTHONUNBUFFERED 1
ENV DEBIAN_FRONTEND=noninteractive
# Set PATH to include python3.12 bin
ENV PATH="/usr/bin/python3.12:${PATH}"

# Install system dependencies in stages

# Stage 1: Base tools and PPA setup
RUN apt-get update && apt-get install -y --no-install-recommends \
    software-properties-common \
    && add-apt-repository -y ppa:deadsnakes/ppa \
    && rm -rf /var/lib/apt/lists/*

# Stage 2: Install Python, Git, SSH, and other specific packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.12 \
    python3.12-dev \
    python3.12-venv \
    python3-pip \
    git \
    openssh-server \
    build-essential \
    ffmpeg libsm6 libxext6 \
    # Add any other system dependencies your project might need here
    && rm -rf /var/lib/apt/lists/*

# Stage 3: Configure Python alternatives and upgrade pip
RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.12 1 \
    && python3.12 -m pip install --no-cache-dir --upgrade pip

# Create a non-root user 'vscode' and add it to the 'sudo' group (no password set)
RUN useradd -m -s /bin/bash vscode \
    && adduser vscode sudo

# Configure SSH server to disable password authentication
RUN mkdir /var/run/sshd \
    && sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config \
    # Ensure PasswordAuthentication is set to no
    && sed -i 's/^#?PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config \
    && sed 's@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g' -i /etc/pam.d/sshd

# VS Code Server requirements
#RUN apt-get update && apt-get install -y curl wget tar

# Set the working directory
WORKDIR /app

# Copy the requirements file first to leverage Docker cache
COPY requirements.txt ./

# Install Python dependencies using python3.12
# Consider using a virtual environment
RUN python3.12 -m pip install --no-cache-dir -r requirements.txt \
    # Install torch separately using the specified CUDA version
    # Note: Base image is CUDA 12.5, installing Torch for cu126. Check compatibility if issues arise.
    && python3.12 -m pip install --no-cache-dir torch torchvision torchaudio --extra-index-url https://download.pytorch.org/whl/cu126

# Copy the rest of the application code
COPY . .

# Grant ownership of the app directory to the vscode user
RUN chown -R vscode:vscode /app

# Switch to the non-root user
USER vscode

# Expose ports (SSH and ComfyUI default)
EXPOSE 22 8188

# Default command to start SSH server and then the Python application using python3.12
# We need to run sshd as root initially to bind to port 22, then switch back
# Using tini or a similar init system is recommended for proper signal handling
CMD service ssh start && python3.12 main.py --listen 0.0.0.0 --port 8188 