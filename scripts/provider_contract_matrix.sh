#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
ARTIFACT_DIR="${1:-$ROOT_DIR/.artifacts/provider-contract-matrix/$TIMESTAMP}"
mkdir -p "$ARTIFACT_DIR"

JSON_REPORT="$ARTIFACT_DIR/provider-contract-matrix-report.json"
MARKDOWN_REPORT="$ARTIFACT_DIR/provider-contract-matrix-report.md"

PROVIDER_MATRIX=(
  "anthropic:AnthropicProviderContractTests"
  "openai:OpenAIProviderContractTests"
  "zai:ZAIProviderContractTests"
  "ollama:OllamaProviderContractTests"
  "lmstudio:LMStudioProviderContractTests"
)

overall_passed=true
json_results=""
markdown_rows=""

for entry in "${PROVIDER_MATRIX[@]}"; do
  provider="${entry%%:*}"
  test_class="${entry##*:}"
  log_file="$ARTIFACT_DIR/${provider}.log"

  echo "[provider-contract] Running ${provider} (${test_class})"
  if xcodebuild test \
    -project Dochi.xcodeproj \
    -scheme Dochi \
    -destination 'platform=macOS' \
    -only-testing:"DochiTests/${test_class}" >"$log_file" 2>&1; then
    passed=true
    status_label="PASS"
  else
    passed=false
    status_label="FAIL"
    overall_passed=false
  fi

  summary_line="$(rg "Executed [0-9]+ test" "$log_file" | tail -n 1 || true)"
  if [[ -z "$summary_line" ]]; then
    summary_line="No XCTest summary found"
  fi

  escaped_summary="$(printf '%s' "$summary_line" | sed 's/\\/\\\\/g; s/\"/\\"/g')"
  log_basename="$(basename "$log_file")"

  if [[ -n "$json_results" ]]; then
    json_results+=","
  fi
  json_results+=$'\n'
  json_results+="    {\"provider\":\"${provider}\",\"testClass\":\"${test_class}\",\"passed\":${passed},\"summary\":\"${escaped_summary}\",\"log\":\"${log_basename}\"}"

  markdown_rows+="| ${provider} | ${test_class} | ${status_label} | ${summary_line} | ${log_basename} |"$'\n'
done

generated_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
overall_label="PASS"
if [[ "$overall_passed" != true ]]; then
  overall_label="FAIL"
fi

cat > "$JSON_REPORT" <<EOF
{
  "generatedAt": "${generated_at}",
  "overall": "${overall_label}",
  "results": [${json_results}
  ]
}
EOF

cat > "$MARKDOWN_REPORT" <<EOF
# Provider Contract Matrix Report

- generatedAt: ${generated_at}
- overall: ${overall_label}

| Provider | Test Class | Status | Summary | Log |
| --- | --- | --- | --- | --- |
${markdown_rows}
EOF

echo "Provider contract matrix complete"
echo "- JSON: $JSON_REPORT"
echo "- Markdown: $MARKDOWN_REPORT"

if [[ "$overall_passed" != true ]]; then
  exit 1
fi
