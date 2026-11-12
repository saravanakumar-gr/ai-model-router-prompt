# Apigee AI Model Router (3-Tier Prompt Complexity Classifier)

This repository demonstrates how to use a **helper model** in Apigee X (`ai-model-router-prompt`) to evaluate incoming LLM prompts and dynamically route them across **three model tiers** based on complexity.

The helper model can be any model, including a custom or self-managed model. This repository uses **Gemini 3.5 Flash-Lite** (`gemini-3.5-flash-lite`) via `SC-CallGeminiFlashLite` as an example helper model to route traffic across three tiers:

| Complexity Tier | Tier Role | Target Model | Gateway Behavior |
| :--- | :--- | :--- | :--- |
| **`SIMPLE`** | **Lightweight Classifier & Fast Responder** | **Gemini 3.5 Flash-Lite** (`gemini-3.5-flash-lite`) | Classifies the prompt as `"SIMPLE"` and **answers it directly in the same call**, allowing Apigee to short-circuit and return the response immediately without invoking a downstream model. |
| **`MEDIUM`** | **Mid-Tier Workhorse** | **Gemini 3.8 Flash** (`gemini-3.8-flash`) | For standard code generation, unit tests, summarization, or SQL/data tasks, the helper model responds only with `"MEDIUM"` (and an empty answer string `""` to **avoid unnecessary response token spend**), routing the prompt to `gemini-3.8-flash`. |
| **`COMPLEX`** | **High-Reasoning & Flagship Tier** | **Gemini 4 Argon** (`gemini-4-argon`) | For multi-step reasoning, distributed architecture design, deep debugging, or cryptographic/algorithmic analysis, the helper model responds only with `"COMPLEX"` (and an empty answer string `""` to **avoid unnecessary response token spend**), routing the prompt to `gemini-4-argon`. |

* **Keyless Vertex AI Authentication**: Uses Apigee's native `<GoogleAccessToken>` authentication with a dedicated IAM Service Account (`roles/aiplatform.user`).

---

## Architecture & Policy Flow

| Step | Policy / Endpoint Name | Type | Role in Pipeline |
| :--- | :--- | :--- | :--- |
| **1. Authenticate** | [`verify-api-key-Verify-API-Key`](./apiproxy/policies/verify-api-key-Verify-API-Key.xml) | `VerifyAPIKey` | Validates the consumer API key passed in the `x-api-key` header against the `ai-model-router-prompt-product` API Product. |
| **2. Build Classifier Request** | [`prompt-router-AM-BuildFlashLiteRequest`](./apiproxy/policies/prompt-router-AM-BuildFlashLiteRequest.xml) | `AssignMessage` | Extracts the user prompt (supporting both `{"prompt": "..."}` and standard Gemini `{"contents": [...]}` payloads) and constructs the `gemini-3.5-flash-lite` structured-output classification payload (`SIMPLE`, `MEDIUM`, `COMPLEX`). |
| **3. Classify & Answer (`SIMPLE`)** | [`prompt-router-SC-CallGeminiFlashLite`](./apiproxy/policies/prompt-router-SC-CallGeminiFlashLite.xml) | `ServiceCallout` | Calls Vertex AI `gemini-3.5-flash-lite:generateContent` with a strict JSON `responseSchema` (`{"classification": "SIMPLE" \| "MEDIUM" \| "COMPLEX", "answer": "..."}`). |
| **4. Parse Classification** | [`prompt-router-EV-ParseFlashResponse`](./apiproxy/policies/prompt-router-EV-ParseFlashResponse.xml) | `ExtractVariables` | Extracts the JSON classification payload from the `gemini-3.5-flash-lite` response into `flashlite.classification`. |
| **5a. Short-Circuit `SIMPLE` Prompts** | [`prompt-router-AM-SetSimpleResponse`](./apiproxy/policies/prompt-router-AM-SetSimpleResponse.xml) | `AssignMessage` (`NoRoute`) | When `classification == "SIMPLE"`, skips TargetEndpoints (`NoRoute`) and returns the `gemini-3.5-flash-lite` response directly with `X-Model-Classification: SIMPLE`, `X-Model-Tier: Lightweight-Classifier`, `X-Routed-Model: gemini-3.5-flash-lite`, and `X-Short-Circuited: true`. |
| **5b. Route `MEDIUM` Prompts** | [`gemini-flash-target.xml`](./apiproxy/targets/gemini-flash-target.xml) | `RouteRule` + `TargetEndpoint` | When `classification == "MEDIUM"`, forwards the prompt to Vertex AI **Gemini 3.8 Flash** (`gemini-3.8-flash:generateContent`) and tags the response with `X-Model-Tier: Mid-Tier-Workhorse` and `X-Routed-Model: gemini-3.8-flash`. |
| **5c. Route `COMPLEX` Prompts** | [`gemini-argon-target.xml`](./apiproxy/targets/gemini-argon-target.xml) | `RouteRule` + `TargetEndpoint` | When `classification == "COMPLEX"`, forwards the prompt to Vertex AI **Gemini 4 Argon** (`gemini-4-argon:generateContent`) and tags the response with `X-Model-Tier: High-Reasoning-Flagship` and `X-Routed-Model: gemini-4-argon`. |

---

## Quickstart

### 1. Deploy to Apigee X

Set your GCP Project / Apigee Organization, Environment, Environment Group Hostname, and optional Vertex AI Location (defaults to `global`), then run [`./deploy.sh`](./deploy.sh):

```bash
export PROJECT_ID="<YOUR_GCP_PROJECT_ID>"
export APIGEE_ENV="<YOUR_APIGEE_ENV>"
export APIGEE_HOST="<YOUR_APIGEE_HOSTNAME>"
export VERTEX_REGION="global" # Optional (defaults to global)

./deploy.sh
```

`./deploy.sh` automatically:
1. Creates the `llm-proxy@${PROJECT_ID}.iam.gserviceaccount.com` Service Account and grants `roles/aiplatform.user` (if not already present).
2. Substitutes `${PROJECT_ID}`, `${VERTEX_REGION}`, and `${VERTEX_ENDPOINT}` in a temporary build copy (keeping your git working tree clean), packages, imports, and deploys the `ai-model-router-prompt` proxy bundle.
3. Configures the API Product (`ai-model-router-prompt-product`) from [`api-product.json`](./api-product.json).
4. Creates the Developer (`admin@example.com`) and Developer App (`ai-model-router-prompt-app`) and prints your **Consumer API Key**.

---

### 2. Verify the 3-Tier Router (`./test-router.sh`)

Run the automated test suite to verify API key enforcement, `SIMPLE` short-circuiting via `gemini-3.5-flash-lite`, `MEDIUM` routing to `gemini-3.8-flash`, and `COMPLEX` routing to `gemini-4-argon`:

```bash
export ROUTER_URL="https://${APIGEE_HOST}/ai-model-router-prompt"
export ROUTER_API_KEY="<YOUR_APIGEE_CONSUMER_KEY>"

./test-router.sh
```

---

### 3. Example Requests

#### Example A: `SIMPLE` Prompt — Lightweight Classifier (`gemini-3.5-flash-lite`)

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
x-model-tier: Lightweight-Classifier
x-routed-model: gemini-3.5-flash-lite
x-short-circuited: true
```

#### Example B: `MEDIUM` Prompt — Mid-Tier Workhorse (`gemini-3.8-flash`)

```bash
curl -i -X POST "https://<YOUR_APIGEE_HOSTNAME>/ai-model-router-prompt" \
  -H "x-api-key: <YOUR_APIGEE_CONSUMER_KEY>" \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "Write a Python function to parse a CSV file and return the average of a numeric column using the csv module, including basic error handling."
  }'
```

Response headers include:
```http
HTTP/2 200
x-model-classification: MEDIUM
x-model-tier: Mid-Tier-Workhorse
x-routed-model: gemini-3.8-flash
x-short-circuited: false
```

#### Example C: `COMPLEX` Prompt — High-Reasoning & Flagship Tier (`gemini-4-argon`)

```bash
curl -i -X POST "https://<YOUR_APIGEE_HOSTNAME>/ai-model-router-prompt" \
  -H "x-api-key: <YOUR_APIGEE_CONSUMER_KEY>" \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "Design a multi-region active-active microservices architecture on GKE with Cloud Spanner and Apigee X, detailing the failover sequence and CAP theorem trade-offs."
  }'
```

Response headers include:
```http
HTTP/2 200
x-model-classification: COMPLEX
x-model-tier: High-Reasoning-Flagship
x-routed-model: gemini-4-argon
x-short-circuited: false
```
