#!/bin/bash
# OpenClaw Daily Security Check Script

set -e

OPENCLAW_HOME="${OPENCLAW_HOME:-$HOME/.openclaw}"

echo "=========================================="
echo "  OpenClaw Security Check"
echo "  $(date)"
echo "=========================================="

# Load environment
if [ -f "$OPENCLAW_HOME/credentials/.env" ]; then
    source "$OPENCLAW_HOME/credentials/.env"
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ERRORS=0

# 1. Container Status
echo -e "\n${YELLOW}[1/6] Container Status${NC}"
if docker compose ps openclaw-gateway | grep -q "Up"; then
    echo -e "${GREEN}✓ Gateway container is running${NC}"
else
    echo -e "${RED}✗ Gateway container is NOT running${NC}"
    ((ERRORS++))
fi

# 2. Health Check
echo -e "\n${YELLOW}[2/6] Health Check${NC}"
if docker compose exec -T openclaw-gateway node dist/index.js health 2>/dev/null; then
    echo -e "${GREEN}✓ Gateway health check passed${NC}"
else
    echo -e "${RED}✗ Gateway health check FAILED${NC}"
    ((ERRORS++))
fi

# 3. Security Audit
echo -e "\n${YELLOW}[3/6] Security Audit${NC}"
AUDIT_OUTPUT=$(docker compose exec -T openclaw-gateway node dist/index.js security audit 2>&1 || true)
if echo "$AUDIT_OUTPUT" | grep -q "No issues found"; then
    echo -e "${GREEN}✓ Security audit passed${NC}"
else
    echo -e "${YELLOW}! Security audit findings:${NC}"
    echo "$AUDIT_OUTPUT" | head -20
fi

# 4. Resource Usage
echo -e "\n${YELLOW}[4/6] Resource Usage${NC}"
docker stats --no-stream --format "CPU: {{.CPUPerc}}, Memory: {{.MemUsage}}" openclaw-secure 2>/dev/null || echo "Could not get stats"

# 5. Active Sandboxes
echo -e "\n${YELLOW}[5/6] Active Sandboxes${NC}"
SANDBOX_COUNT=$(docker ps --filter "name=openclaw-sandbox" -q | wc -l)
echo "Active sandbox containers: $SANDBOX_COUNT"

# 6. Disk Usage
echo -e "\n${YELLOW}[6/6] Disk Usage${NC}"
if [ -d "$OPENCLAW_HOME" ]; then
    du -sh "$OPENCLAW_HOME" 2>/dev/null || echo "Could not check disk usage"
fi

# Summary
echo ""
echo "=========================================="
if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}  All checks passed!${NC}"
else
    echo -e "${RED}  $ERRORS check(s) failed!${NC}"
fi
echo "=========================================="

exit $ERRORS
