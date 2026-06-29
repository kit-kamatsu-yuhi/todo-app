FROM node:22-slim

# 1. System dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    git curl jq ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# 2. gh CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update && apt-get install -y gh && rm -rf /var/lib/apt/lists/*

# 3. Claude CLI + Codex CLI + corepack (pnpm/yarn shim respecting package.json "packageManager")
RUN npm install -g @anthropic-ai/claude-code@2.1.159 @openai/codex@0.135.0 \
    && corepack enable

# 5. Non-root user
RUN useradd -m -s /bin/bash autodev

# 6. Directories + npm global prefix
# state / logs / metrics は 0700 で作成し、他ユーザーから読取/書込できないようにする
# (plan.md の「共通」§ / AC-6 の要件)
RUN mkdir -p /var/auto-dev/state /var/auto-dev/logs /var/auto-dev/metrics /workspace /home/autodev/.npm-global \
    && chown -R autodev:autodev /var/auto-dev /workspace /home/autodev/.npm-global \
    && chmod 0700 /var/auto-dev/state /var/auto-dev/logs /var/auto-dev/metrics

ENV NPM_CONFIG_PREFIX=/home/autodev/.npm-global
ENV PATH="/home/autodev/.npm-global/bin:${PATH}"
ENV COREPACK_ENABLE_AUTO_PIN=0
ENV COREPACK_ENABLE_STRICT=0

WORKDIR /workspace

# 7. Scripts
COPY entrypoint.sh /usr/local/bin/auto-dev-entrypoint.sh
COPY lib/ /usr/local/lib/auto-dev/
COPY bin/ /usr/local/bin/
RUN chmod +x /usr/local/bin/auto-dev-entrypoint.sh /usr/local/lib/auto-dev/*.sh /usr/local/bin/auto-dev-status

COPY init-user.sh /usr/local/bin/init-user.sh
RUN chmod +x /usr/local/bin/init-user.sh

ENTRYPOINT ["/usr/local/bin/init-user.sh"]
