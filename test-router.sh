#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Automated Verification Suite for AI Model Router Prompt Classifier
# ==============================================================================
# Usage:
#   export ROUTER_URL="https://<YOUR_APIGEE_HOSTNAME>/ai-model-router-prompt"
#   export ROUTER_API_KEY="<YOUR_APIGEE_CONSUMER_KEY>"
#   ./test-router.sh
# ==============================================================================

ROUTER_URL="${ROUTER_URL:-https://<YOUR_APIGEE_HOSTNAME>/ai-model-router-prompt}"
API_KEY="${ROUTER_API_KEY:-}"

if [ -z "${API_KEY}" ]; then
  echo "Error: Please export ROUTER_URL and ROUTER_API_KEY before running ./test-router.sh"
  exit 1
fi

echo "=============================================================================="
echo "Testing Apigee AI Model Router: ${ROUTER_URL}"
echo "=============================================================================="

echo ""
echo "==> Test 1: Unauthenticated Request (Expect HTTP 401 from Verify-API-Key)"
CODE_1=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${ROUTER_URL}" \
  -H "Content-Type: application/json" \
  -d '{"prompt":"What is 2 + 2?"}')
echo "    HTTP Status: ${CODE_1}"
if [ "${CODE_1}" = "401" ]; then
  echo "    [PASS] Unauthenticated request rejected with 401."
else
  echo "    [FAIL] Expected 401, got ${CODE_1}."
  exit 1
fi

echo ""
echo "==> Test 2: SIMPLE Prompt Short-Circuit (gemini-2.5-flash-lite)"
HEADERS_2="$(mktemp)"
BODY_2="$(mktemp)"
trap 'rm -f "${HEADERS_2}" "${BODY_2}"' EXIT

curl -s -D "${HEADERS_2}" -o "${BODY_2}" -X POST "${ROUTER_URL}" \
  -H "x-api-key: ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"prompt":"What is the capital of France?"}'

if grep -iq "X-Routed-Model: gemini-2.5-flash-lite" "${HEADERS_2}" && grep -iq "Paris" "${BODY_2}"; then
  echo "    [PASS] SIMPLE prompt short-circuited by gemini-2.5-flash-lite (X-Short-Circuited: true)."
else
  echo "    [FAIL] Expected gemini-2.5-flash-lite short-circuit with Paris, got:"
  cat "${HEADERS_2}"
  cat "${BODY_2}"
  exit 1
fi

echo ""
echo "==> Test 3: COMPLEX Prompt Routing (gemini-2.5-pro)"
RES_3=$(curl -s -X POST "${ROUTER_URL}" \
  -H "x-api-key: ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"prompt":"Design a multi-region active-active microservices architecture on GKE with Cloud Spanner and Apigee X, detailing the failover sequence and CAP theorem trade-offs."}')

if echo "${RES_3}" | grep -iq '"modelVersion".*"gemini-2.5-pro"'; then
  echo "    [PASS] COMPLEX prompt routed to gemini-2.5-pro TargetEndpoint."
else
  echo "    [FAIL] Expected gemini-2.5-pro response, got: ${RES_3}"
  exit 1
fi

echo ""
echo "=============================================================================="
echo "ALL 3 AI MODEL ROUTER TESTS PASSED!"
echo "=============================================================================="
