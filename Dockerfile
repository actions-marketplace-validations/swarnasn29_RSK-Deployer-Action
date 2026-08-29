# ============================================================
#  Rootstock Foundry Deployer Action — Docker Image
#  Base: Official Foundry image (Forge + Cast + jq pre-installed)
#
#  PINNING POLICY (Security — H-1):
#  The base image is pinned to an immutable SHA-256 digest to prevent
#  supply-chain attacks from a compromised or silently-updated upstream tag.
#
#  To update the pin:
#    1. Run: docker manifest inspect ghcr.io/foundry-rs/foundry:latest
#    2. Copy the `config.digest` (or multi-arch index digest) value.
#    3. Replace the sha256 hash below and update the date comment.
#    4. Commit and open a PR — renovate-bot can automate this.
#
#  Pinned: 2026-05-27 | ghcr.io/foundry-rs/foundry:latest
#  (multi-arch index digest from `docker buildx imagetools inspect`)
# ============================================================
FROM ghcr.io/foundry-rs/foundry:latest@sha256:8347b728d5d393dac1c018691b36f506d23b9dcd78341d40ea0fcb11c3a19cdd
LABEL org.opencontainers.image.title="Rootstock Foundry Deployer"
LABEL org.opencontainers.image.description="GitHub Action for deploying Foundry smart contracts to Rootstock (Mainnet/Testnet)"
LABEL org.opencontainers.image.source="https://github.com/rsksmart/rootstock-foundry-action"
LABEL org.opencontainers.image.licenses="MIT"

# Install dependencies (jq for JSON parsing, bc for math, bash for script, curl for RPC tests)
USER root
RUN apt-get update && apt-get install -y jq bash curl bc && rm -rf /var/lib/apt/lists/*

# User foundry already exists in the base image

# Copy entrypoint script and make it executable
COPY src/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Switch to the non-privileged user
USER foundry

ENTRYPOINT ["/entrypoint.sh"]
