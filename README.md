# Apigee AI Model Router (Prompt Complexity Classifier)

This repository contains a reference Apigee X API proxy (`ai-model-router-prompt`) that dynamically routes incoming LLM prompts based on their complexity using **100% out-of-the-box declarative Apigee policies** (with zero custom JavaScript or Python code).

* **Fast & Cost-Effective Short-Circuiting (`SIMPLE`)**: Every incoming prompt is first evaluated by **Gemini 2.5 Flash-Lite** (`gemini-2.5-flash-lite`) via an Apigee `ServiceCallout` using structured JSON output (`responseSchema`). If the prompt is classified as `SIMPLE` (factual lookups, basic math, greetings, simple definitions, or translations), Flash-Lite answers it immediately in the same call and Apigee short-circuits the response back to the client—avoiding a second LLM call.
* **Deep Reasoning Routing (`COMPLEX`)**: If the prompt is classified as `COMPLEX` (multi-step reasoning, system architecture design, complex code debugging, or deep analysis), Apigee routes the request to the **Gemini 2.5 Pro** (`gemini-2.5-pro`) `TargetEndpoint`.
* **Keyless Vertex AI Authentication**: Uses Apigee's native `<GoogleAccessToken>` authentication with a dedicated IAM Service Account (`roles/aiplatform.user`).

---

## Architecture & Policy Flow

| Step | Policy Name | Policy Type | Role in Pipeline |
| :--- | :--- | :--- | :--- |
| **1. Authenticate** | [`verify-api-key-Verify-API-Key`](./apiproxy/policies/verify-api-key-Verify-API-Key.xml) | `VerifyAPIKey` | Validates the consumer API key passed in the `x-api-key` header against the `ai-model-router-prompt-product` API Product. |
| **2. Build Classifier Request** | [`prompt-router-AM-BuildFlashLiteRequest`](./apiproxy/policies/prompt-router-AM-BuildFlashLiteRequest.xml) | `AssignMessage` | Extracts the user prompt (supporting both `{"prompt": "..."}` and standard Gemini `{"contents": [...]}` payloads) and constructs the `gemini-2.5-flash-lite` structured-output classification payload. |
| **3. Classify & Answer (`SIMPLE`)** | [`prompt-router-SC-CallGeminiFlashLite`](./apiproxy/policies/prompt-router-SC-CallGeminiFlashLite.xml) | `ServiceCallout` | Calls Vertex AI `gemini-2.5-flash-lite:generateContent` with a strict JSON `responseSchema` (`{"classification": "SIMPLE" | "COMPLEX", "answer": "..."}`). |
| **4. Parse Classification** | [`prompt-router-EV-ParseFlashResponse`](./apiproxy/policies/prompt-router-EV-ParseFlashResponse.xml) | `ExtractVariables` | Extracts the JSON classification payload from the Flash-Lite response into `flashlite.classification`. |
| **5a. Route `COMPLEX` Prompts** | [`default.xml` (`GeminiProTarget`)](./apiproxy/proxies/default.xml) | `RouteRule` + `TargetEndpoint` | When `classification == "COMPLEX"`, forwards the prompt to Vertex AI `gemini-2.5-pro:generateContent` ([`gemini-pro-target.xml`](./apiproxy/targets/gemini-pro-target.xml)). |
| **5b. Short-Circuit `SIMPLE` Prompts** | [`prompt-router-AM-SetSimpleResponse`](./apiproxy/policies/prompt-router-AM-SetSimpleResponse.xml) | `AssignMessage` | When `classification == "SIMPLE"`, skips the TargetEndpoint (`NoRoute`) and returns the Flash-Lite response directly with `X-Model-Classification: SIMPLE`, `X-Routed-Model: gemini-2.5-flash-lite`, and `X-Short-Circuited: true`. |

---

## Quickstart

### 1. Deploy to Apigee X

Set your GCP Project / Apigee Organization, Environment, Environment Group Hostname, and optional Vertex AI Region (defaults to `europe-west4`), then run [`./deploy.sh`](./deploy.sh):

```bash
export PROJECT_ID="<YOUR_GCP_PROJECT_ID>"
export APIGEE_ENV="<YOUR_APIGEE_ENV>"
export APIGEE_HOST="<YOUR_APIGEE_HOSTNAME>"
export VERTEX_REGION="europe-west4" # Optional (e.g., us-central1, europe-west4)

./deploy.sh
```

`./deploy.sh` automatically:
1. Creates the `llm-proxy@${PROJECT_ID}.iam.gserviceaccount.com` Service Account and grants `roles/aiplatform.user` (if not already present).
2. Substitutes `${PROJECT_ID}` and `${VERTEX_REGION}` in a temporary build copy (keeping your git working tree clean), packages, imports, and deploys the `ai-model-router-prompt` proxy bundle.
3. Configures the API Product (`ai-model-router-prompt-product`) from [`api-product.json`](./api-product.json).
4. Creates the Developer (`admin@example.com`) and Developer App (`ai-model-router-prompt-app`) and prints your **Consumer API Key**.

---

### 2. Verify the Router (`./test-router.sh`)

Run the automated test suite to verify API key enforcement, `SIMPLE` prompt short-circuiting via `gemini-2.5-flash-lite`, and `COMPLEX` prompt routing to `gemini-2.5-pro`:

```bash
export ROUTER_URL="https://${APIGEE_HOST}/ai-model-router-prompt"
export ROUTER_API_KEY="<YOUR_APIGEE_CONSUMER_KEY>"

./test-router.sh
```

---

### 3. Example Requests

#### Example A: `SIMPLE` Prompt (Short-Circuited by `gemini-2.5-flash-lite`)

```bash
curl -i -X POST "https://<YOUR_APIGEE_HOSTNAME>/ai-model-router-prompt" \
  -H "x-api-key: <YOUR_APIGEE_CONSUMER_KEY>" \
  -H "Content-Type: application/json" \
  -d '{"prompt": "What is the capital of France?"}'
```

Response headers include:
```http
HTTP/2 200
x-model-classification: SIMPLE
x-routed-model: gemini-2.5-flash-lite
x-short-circuited: true
```

#### Example B: `COMPLEX` Prompt (Routed to `gemini-2.5-pro`)

```bash
curl -i -X POST "https://<YOUR_APIGEE_HOSTNAME>/ai-model-router-prompt" \
  -H "x-api-key: <YOUR_APIGEE_CONSUMER_KEY>" \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "Design a multi-region active-active microservices architecture on GKE with Cloud Spanner and Apigee X, detailing the failover sequence and CAP theorem trade-offs."
  }'
```
