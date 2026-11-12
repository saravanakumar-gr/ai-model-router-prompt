#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Automated Verification Suite for AI Model Router Prompt Classifier (3-Tier)
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
echo "Testing Apigee AI Model Router (3-Tier): ${ROUTER_URL}"
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

HEADERS_TMP="$(mktemp)"
BODY_TMP="$(mktemp)"
trap 'rm -f "${HEADERS_TMP}" "${BODY_TMP}"' EXIT

echo ""
echo "==> Test 2: SIMPLE Prompt -> Lightweight Classifier & Fast Responder (gemini-3.5-flash-lite)"
curl -s -D "${HEADERS_TMP}" -o "${BODY_TMP}" -X POST "${ROUTER_URL}" \
  -H "x-api-key: ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"prompt":"What is the capital of France?"}'

if grep -iq "X-Routed-Model: gemini-3.5-flash-lite" "${HEADERS_TMP}" && grep -iq "Paris" "${BODY_TMP}"; then
  echo "    [PASS] SIMPLE prompt short-circuited by gemini-3.5-flash-lite (X-Model-Tier: Lightweight-Classifier, X-Short-Circuited: true)."
else
  echo "    [FAIL] Expected gemini-3.5-flash-lite short-circuit with Paris, got:"
  cat "${HEADERS_TMP}"
  cat "${BODY_TMP}"
  exit 1
fi

echo ""
echo "==> Test 3: MEDIUM Prompt -> Mid-Tier Workhorse (gemini-3.8-flash)"
curl -s -D "${HEADERS_TMP}" -o "${BODY_TMP}" -X POST "${ROUTER_URL}" \
  -H "x-api-key: ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"prompt":"Write a Python function to parse a CSV file and return the average of a numeric column using the csv module, including basic error handling."}'

if grep -iq "X-Routed-Model: gemini-3.8-flash" "${HEADERS_TMP}" && grep -iq '"modelVersion".*"gemini-3.8-flash"' "${BODY_TMP}"; then
  echo "    [PASS] MEDIUM prompt routed to gemini-3.8-flash (X-Model-Tier: Mid-Tier-Workhorse)."
else
  echo "    [FAIL] Expected gemini-3.8-flash response, got:"
  cat "${HEADERS_TMP}"
  cat "${BODY_TMP}"
  exit 1
fi

echo ""
echo "==> Test 4: COMPLEX Prompt -> High-Reasoning & Flagship Tier (gemini-4-argon)"
curl -s -D "${HEADERS_TMP}" -o "${BODY_TMP}" -X POST "${ROUTER_URL}" \
  -H "x-api-key: ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"prompt":"Design a multi-region active-active microservices architecture on GKE with Cloud Spanner and Apigee X, detailing the failover sequence and CAP theorem trade-offs."}'

if grep -iq "X-Routed-Model: gemini-4-argon" "${HEADERS_TMP}" && grep -iq '"modelVersion".*"gemini-4-argon"' "${BODY_TMP}"; then
  echo "    [PASS] COMPLEX prompt routed to gemini-4-argon (X-Model-Tier: High-Reasoning-Flagship)."
else
  echo "    [FAIL] Expected gemini-4-argon response, got:"
  cat "${HEADERS_TMP}"
  cat "${BODY_TMP}"
  exit 1
fi

echo ""
echo "=============================================================================="
echo "ALL 4 AI MODEL ROUTER TESTS PASSED!"
echo "=============================================================================="
