# #!/bin/bash
# set -e

# # Determine which scanner to run based on env var
# SCANNER_TYPE=${SCANNER_TYPE:-"block_scanner"}
# CHAIN=${CHAIN:-"eth_mainnet"}

# echo "Starting $SCANNER_TYPE for $CHAIN"

# python -m "ingestion.chains.${CHAIN}.${SCANNER_TYPE}"
