FROM mcr.microsoft.com/dotnet/sdk:10.0

# --- base linux + dev tooling ---
RUN apt-get update && apt-get install -y --no-install-recommends \
      git curl wget ca-certificates gnupg \
      tmux nano vim less \
      build-essential \
      jq unzip zip \
      openssh-client \
    && rm -rf /var/lib/apt/lists/*

# --- Node.js LTS (Claude Code runtime + your frontend tooling) ---
RUN curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# --- GitHub CLI ---
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y gh \
    && rm -rf /var/lib/apt/lists/*

# --- Claude Code ---
RUN npm install -g @anthropic-ai/claude-code

# --- dotnet tools commonly used by Claude Code on web projects ---
RUN dotnet tool install --global dotnet-ef \
    && dotnet tool install --global dotnet-outdated-tool
ENV PATH="${PATH}:/root/.dotnet/tools"

WORKDIR /workspace

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY rc-supervisor.sh /usr/local/bin/rc-supervisor.sh
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/rc-supervisor.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["tail", "-f", "/dev/null"]
