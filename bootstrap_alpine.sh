#!/bin/sh
set -e

# Configure Alpine v3.24 repositories
echo "https://dl-cdn.alpinelinux.org/alpine/v3.24/main
https://dl-cdn.alpinelinux.org/alpine/v3.24/community" > /etc/apk/repositories

# Install system packages
apk --update --no-cache add \
    curl \
    bash \
    git \
    openssh \
    python3 \
    py3-pip \
    pre-commit \
    xclip \
    ruff \
    nodejs \
    npm \
    deno \
    github-cli \
    git-lfs \
    glab \
    chromium

# Install opencode
curl -fsSL https://opencode.ai/install | bash

# Make opencode available immediately
. /etc/profile
